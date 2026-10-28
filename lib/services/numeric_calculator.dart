import 'package:intl/intl.dart';

import 'query_planner.dart';

/// A value the answering model found in the passages for a calculation.
class ExtractedValue {
  final String label;
  final double? value;
  final String unit; // "INR", "USD", "%", "days", ... or ""
  final DateTime? date;
  final int passage; // 1-based passage number, for the citation

  const ExtractedValue({
    required this.label,
    required this.passage,
    this.value,
    this.unit = '',
    this.date,
  });

  factory ExtractedValue.fromJson(Map<String, dynamic> json) => ExtractedValue(
        label: (json['label'] as String? ?? '').trim(),
        value: (json['value'] as num?)?.toDouble(),
        unit: (json['unit'] as String? ?? '').trim(),
        date: DateTime.tryParse(json['date'] as String? ?? ''),
        passage: (json['passage'] as num?)?.toInt() ?? 0,
      );
}

/// Does the arithmetic for numeric questions in code, so totals, averages,
/// differences and day counts are exact. Each value keeps its passage
/// citation ([n]), which the chat turns into page citations.
class NumericCalculator {
  NumericCalculator._();

  /// The answer text, or null when the values do not support the operation
  /// (the caller then falls back to a normal written answer).
  static String? compute(NumericOp op, List<ExtractedValue> items, {DateTime? today}) {
    switch (op) {
      case NumericOp.sum:
      case NumericOp.average:
        return _aggregate(op, items);
      case NumericOp.difference:
        return _difference(items);
      case NumericOp.daysBetween:
        return _daysBetween(items, today ?? DateTime.now());
      case NumericOp.count:
        return _count(items);
    }
  }

  static String? _aggregate(NumericOp op, List<ExtractedValue> items) {
    final numbers = items.where((i) => i.value != null).toList();
    if (numbers.isEmpty) return null;
    final byUnit = <String, List<ExtractedValue>>{};
    for (final i in numbers) {
      byUnit.putIfAbsent(_normalizeUnit(i.unit), () => []).add(i);
    }
    final word = op == NumericOp.sum ? 'Total' : 'Average';
    final lines = <String>[];
    for (final entry in byUnit.entries) {
      final values = entry.value.map((i) => i.value!);
      final sum = values.reduce((a, b) => a + b);
      final result = op == NumericOp.sum ? sum : sum / entry.value.length;
      final label = byUnit.length == 1 ? word : '$word (${entry.key.isEmpty ? 'no unit' : entry.key})';
      lines.add('$label: ${format(result, entry.key)}');
    }
    return [
      lines.join('\n'),
      if (byUnit.length > 1) 'These values are in different units, so they are totalled separately.',
      '',
      for (final i in numbers) '- ${_labelOf(i)}: ${format(i.value!, _normalizeUnit(i.unit))}${_cite(i)}',
    ].join('\n');
  }

  static String? _difference(List<ExtractedValue> items) {
    final numbers = items.where((i) => i.value != null).toList();
    if (numbers.length < 2) return null;
    final a = numbers[0];
    final b = numbers[1];
    final unitA = _normalizeUnit(a.unit);
    if (unitA != _normalizeUnit(b.unit)) return null;
    final diff = (a.value! - b.value!).abs();
    final higher = a.value! >= b.value! ? a : b;
    final lower = identical(higher, a) ? b : a;
    return [
      'Difference: ${format(diff, unitA)}',
      '',
      '- ${_labelOf(higher)}: ${format(higher.value!, unitA)}${_cite(higher)}',
      '- ${_labelOf(lower)}: ${format(lower.value!, unitA)}${_cite(lower)}',
      if (numbers.length > 2) '\n(Compared the first two values found.)',
    ].join('\n');
  }

  static String? _daysBetween(List<ExtractedValue> items, DateTime today) {
    final dated = items.where((i) => i.date != null).toList();
    if (dated.isEmpty) return null;
    final day = DateTime(today.year, today.month, today.day);
    if (dated.length == 1) {
      final d = dated.single;
      final days = _dayDiff(day, d.date!);
      final when = days == 0
          ? 'today'
          : days > 0
              ? 'in ${_plural(days, 'day')}'
              : '${_plural(-days, 'day')} ago';
      return '${_labelOf(d)}: ${_formatDate(d.date!)}${_cite(d)}, which is $when '
          '(counting from ${_formatDate(day)}).';
    }
    final a = dated[0];
    final b = dated[1];
    final days = _dayDiff(a.date!, b.date!).abs();
    return [
      '${_plural(days, 'day')} between them${_weeksNote(days)}.',
      '',
      '- ${_labelOf(a)}: ${_formatDate(a.date!)}${_cite(a)}',
      '- ${_labelOf(b)}: ${_formatDate(b.date!)}${_cite(b)}',
    ].join('\n');
  }

  static String? _count(List<ExtractedValue> items) {
    final labels = <String>{};
    final unique = [for (final i in items) if (labels.add(i.label.toLowerCase())) i];
    if (unique.isEmpty) return null;
    return [
      'Found ${unique.length}:',
      '',
      for (final i in unique) '- ${_labelOf(i)}${_cite(i)}',
    ].join('\n');
  }

  // --- Formatting -----------------------------------------------------------

  static String _normalizeUnit(String unit) {
    final u = unit.trim();
    final lower = u.toLowerCase();
    if (const {'inr', 'rs', 'rs.', '₹', 'rupees', 'rupee'}.contains(lower)) return 'INR';
    if (const {'usd', '\$', 'us\$', 'dollars', 'dollar'}.contains(lower)) return 'USD';
    if (const {'eur', '€', 'euros', 'euro'}.contains(lower)) return 'EUR';
    if (const {'gbp', '£', 'pounds', 'pound'}.contains(lower)) return 'GBP';
    if (const {'%', 'percent', 'per cent', 'percentage'}.contains(lower)) return '%';
    if (const {'day', 'days', 'working days', 'calendar days'}.contains(lower)) return 'days';
    return lower;
  }

  /// "INR 9,500", "INR 1,25,000", "USD 48.2", "15%", "30 days".
  static String format(double value, String unit) {
    final rounded = double.parse(value.toStringAsFixed(2));
    final number = unit == 'INR'
        ? NumberFormat('#,##,##0.##', 'en_IN').format(rounded)
        : NumberFormat('#,##0.##', 'en_US').format(rounded);
    if (unit == '%') return '$number%';
    if (const {'INR', 'USD', 'EUR', 'GBP'}.contains(unit)) return '$unit $number';
    return unit.isEmpty ? number : '$number $unit';
  }

  static String _formatDate(DateTime d) => DateFormat('d MMM yyyy', 'en_US').format(d);

  static int _dayDiff(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  static String _plural(int n, String word) => '$n ${n == 1 ? word : '${word}s'}';

  static String _weeksNote(int days) {
    if (days < 14) return '';
    final weeks = days ~/ 7;
    final rest = days % 7;
    return ' (about ${_plural(weeks, 'week')}${rest == 0 ? '' : ' and ${_plural(rest, 'day')}'})';
  }

  static String _labelOf(ExtractedValue i) => i.label.isEmpty ? 'Value' : i.label;

  /// " [n]" for a passage citation; values taken from the question say so.
  static String _cite(ExtractedValue i) => i.passage == 0 ? ' (from your question)' : ' [${i.passage}]';
}
