import 'text_chunker.dart';

enum FactKind { money, percent, date, duration, id }

/// A value found in a document: an amount, percentage, date, duration or
/// reference ID, with the sentence it appears in.
///
/// Facts are extracted with patterns at indexing time (no model involved), so
/// list and calculation questions can collect every date or amount in a
/// document, and arithmetic is done in code instead of by the model.
class Fact {
  final FactKind kind;
  final String raw; // as written, e.g. "INR 7,000", "31 December 2026"
  final double? number; // amounts, percentages, durations
  final String? unit; // currency, "%", "days", ...
  final DateTime? date; // dates that include a year
  final String sentence;
  final int page;
  final int chunkIndex;

  const Fact({
    required this.kind,
    required this.raw,
    required this.sentence,
    required this.page,
    required this.chunkIndex,
    this.number,
    this.unit,
    this.date,
  });
}

class FactExtractor {
  FactExtractor._();

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  static const _month =
      r'(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|June?|July?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)';

  static final _currencyFirst = RegExp(
      r'(INR|Rs\.?|₹|USD|US\$|\$|EUR|€|GBP|£)\s?(\d{1,3}(?:,\d{2,3})+|\d+)(\.\d+)?(\s?(?:lakh|crore|million|billion|k|m|bn)\b)?',
      caseSensitive: false);
  static final _currencyAfter = RegExp(
      r'\b(\d{1,3}(?:,\d{2,3})+|\d+)(\.\d+)?\s?(rupees|dollars|euros|pounds)\b',
      caseSensitive: false);
  static final _percent = RegExp(r'\b(\d+(?:\.\d+)?)\s?(%|per ?cent\b)', caseSensitive: false);
  static final _dayMonthYear = RegExp(
      '\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+$_month\\.?,?\\s+(\\d{4})\\b',
      caseSensitive: false);
  static final _monthDayYear = RegExp(
      '\\b$_month\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})\\b',
      caseSensitive: false);
  static final _dayMonth = RegExp(
      '\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+$_month\\b(?!\\.?,?\\s+\\d{4})',
      caseSensitive: false);
  static final _iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
  // Day-first, as written in India and Europe.
  static final _numericDate = RegExp(r'\b(\d{1,2})[/.](\d{1,2})[/.](\d{4})\b');
  static final _duration = RegExp(
      r'\b(\d+(?:\.\d+)?)\s+(working days|business days|calendar days|days|weeks|months|years|hours|minutes)\b',
      caseSensitive: false);
  static final _id = RegExp(r'\b[A-Z]{2,6}-\d{1,4}\b');
  static final _sentenceEnd = RegExp(r'(?<=[.!?])\s+');
  // A blank line, or a line starting a bullet or numbered item.
  static final _blockBreak = RegExp(r'\n\s*\n|\n(?=\s*([•\-*–▪◦]|\d{1,2}[.)])\s)');

  /// Splits PDF text into sentences. PDF text wraps lines mid-sentence, so
  /// single line breaks are joined; blank lines and list items still separate.
  static List<String> sentences(String text) => [
        for (final block in text.split(_blockBreak))
          for (final s in block.replaceAll(RegExp(r'\s*\n\s*'), ' ').split(_sentenceEnd))
            if (s.trim().isNotEmpty) s.trim(),
      ];

  /// Facts in [chunks], de-duplicated (overlapping chunks repeat text).
  static List<Fact> extract(List<TextChunk> chunks) {
    final facts = <Fact>[];
    final seen = <String>{};
    for (final chunk in chunks) {
      for (final s in sentences(chunk.text)) {
        for (final fact in fromSentence(s, page: chunk.pageNumber, chunkIndex: chunk.chunkIndex)) {
          if (seen.add('${fact.page}|${fact.kind.name}|${fact.raw}|${fact.sentence}')) {
            facts.add(fact);
          }
        }
      }
    }
    return facts;
  }

  static List<Fact> fromSentence(String sentence, {required int page, required int chunkIndex}) {
    final text = sentence.length > 400 ? '${sentence.substring(0, 400)}…' : sentence;
    final out = <Fact>[];
    Fact make(FactKind kind, String raw, {double? number, String? unit, DateTime? date}) => Fact(
          kind: kind,
          raw: raw.trim(),
          number: number,
          unit: unit,
          date: date,
          sentence: text,
          page: page,
          chunkIndex: chunkIndex,
        );
    // Character ranges already claimed, so "7,000 rupees" is not also read
    // as a duration or percentage.
    final claimed = <(int, int)>[];
    bool free(Match m) => !claimed.any((c) => m.start < c.$2 && m.end > c.$1);
    void claim(Match m) => claimed.add((m.start, m.end));

    for (final m in _currencyFirst.allMatches(sentence)) {
      final value = _amount(m.group(2)!, m.group(3), m.group(4));
      if (value == null) continue;
      out.add(make(FactKind.money, m.group(0)!, number: value, unit: _currency(m.group(1)!)));
      claim(m);
    }
    for (final m in _currencyAfter.allMatches(sentence)) {
      if (!free(m)) continue;
      final value = _amount(m.group(1)!, m.group(2), null);
      if (value == null) continue;
      out.add(make(FactKind.money, m.group(0)!, number: value, unit: _currency(m.group(3)!)));
      claim(m);
    }
    for (final m in _percent.allMatches(sentence)) {
      if (!free(m)) continue;
      out.add(make(FactKind.percent, m.group(0)!, number: double.parse(m.group(1)!), unit: '%'));
      claim(m);
    }
    for (final m in _dayMonthYear.allMatches(sentence)) {
      final date = _date(int.parse(m.group(3)!), _monthNumber(m.group(2)!), int.parse(m.group(1)!));
      out.add(make(FactKind.date, m.group(0)!, date: date));
      claim(m);
    }
    for (final m in _monthDayYear.allMatches(sentence)) {
      if (!free(m)) continue;
      final date = _date(int.parse(m.group(3)!), _monthNumber(m.group(1)!), int.parse(m.group(2)!));
      out.add(make(FactKind.date, m.group(0)!, date: date));
      claim(m);
    }
    for (final m in _iso.allMatches(sentence)) {
      if (!free(m)) continue;
      final date = _date(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
      out.add(make(FactKind.date, m.group(0)!, date: date));
      claim(m);
    }
    for (final m in _numericDate.allMatches(sentence)) {
      if (!free(m)) continue;
      final date = _date(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
      if (date == null) continue;
      out.add(make(FactKind.date, m.group(0)!, date: date));
      claim(m);
    }
    for (final m in _dayMonth.allMatches(sentence)) {
      if (!free(m)) continue;
      out.add(make(FactKind.date, m.group(0)!)); // no year: kept for lists only
      claim(m);
    }
    for (final m in _duration.allMatches(sentence)) {
      if (!free(m)) continue;
      out.add(make(FactKind.duration, m.group(0)!,
          number: double.parse(m.group(1)!), unit: m.group(2)!.toLowerCase()));
      claim(m);
    }
    for (final m in _id.allMatches(sentence)) {
      if (!free(m)) continue;
      out.add(make(FactKind.id, m.group(0)!));
      claim(m);
    }
    return out;
  }

  static int _monthNumber(String name) => _months[name.substring(0, 3).toLowerCase()]!;

  static DateTime? _date(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    return date.month == month ? date : null; // rejects 31 February
  }

  static double? _amount(String digits, String? decimals, String? scale) {
    final base = double.tryParse('${digits.replaceAll(',', '')}${decimals ?? ''}');
    if (base == null) return null;
    final multiplier = switch (scale?.trim().toLowerCase()) {
      'lakh' => 1e5,
      'crore' => 1e7,
      'k' => 1e3,
      'million' || 'm' => 1e6,
      'billion' || 'bn' => 1e9,
      _ => 1.0,
    };
    return base * multiplier;
  }

  static String _currency(String symbol) {
    final s = symbol.toLowerCase().replaceAll('.', '');
    if (s == 'inr' || s == 'rs' || s == '₹' || s == 'rupees') return 'INR';
    if (s == 'usd' || s == 'us\$' || s == '\$' || s == 'dollars') return 'USD';
    if (s == 'eur' || s == '€' || s == 'euros') return 'EUR';
    if (s == 'gbp' || s == '£' || s == 'pounds') return 'GBP';
    return symbol.toUpperCase();
  }
}
