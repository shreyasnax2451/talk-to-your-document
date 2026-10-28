import 'package:docchat/services/numeric_calculator.dart';
import 'package:docchat/services/query_planner.dart';
import 'package:flutter_test/flutter_test.dart';

ExtractedValue v(String label, double? value, String unit, int passage, {DateTime? date}) =>
    ExtractedValue(label: label, value: value, unit: unit, passage: passage, date: date);

void main() {
  test('sum with Indian number grouping and citations', () {
    final out = NumericCalculator.compute(NumericOp.sum, [
      v('Hotel cap (metro)', 7000, 'INR', 1),
      v('Daily allowance (metro)', 2500, 'Rs', 2),
      v('Home office allowance', 115500, '₹', 3),
    ])!;
    expect(out, startsWith('Total: INR 1,25,000'));
    expect(out, contains('Hotel cap (metro): INR 7,000 [1]'));
    expect(out, contains('[3]'));
  });

  test('values in different units are totalled separately', () {
    final out = NumericCalculator.compute(NumericOp.sum, [
      v('A', 100, 'USD', 1),
      v('B', 50, 'USD', 1),
      v('C', 2000, 'INR', 2),
    ])!;
    expect(out, contains('Total (USD): USD 150'));
    expect(out, contains('Total (INR): INR 2,000'));
    expect(out, contains('different units'));
  });

  test('average', () {
    expect(
      NumericCalculator.compute(NumericOp.average, [v('a', 7000, 'INR', 1), v('b', 5000, 'INR', 2)]),
      startsWith('Average: INR 6,000'),
    );
  });

  test('difference needs two values in the same unit', () {
    final out = NumericCalculator.compute(
        NumericOp.difference, [v('Metro', 7000, 'INR', 1), v('Other cities', 5000, 'INR', 1)])!;
    expect(out, startsWith('Difference: INR 2,000'));
    expect(NumericCalculator.compute(NumericOp.difference, [v('a', 1, 'INR', 1), v('b', 1, '%', 1)]), isNull);
    expect(NumericCalculator.compute(NumericOp.difference, [v('a', 1, 'INR', 1)]), isNull);
  });

  test('days between two dates', () {
    final out = NumericCalculator.compute(NumericOp.daysBetween, [
      v('Effective date', null, '', 1, date: DateTime(2026, 4, 1)),
      v('Leave lapses', null, '', 2, date: DateTime(2026, 12, 31)),
    ])!;
    expect(out, startsWith('274 days between them (about 39 weeks and 1 day).'));
  });

  test('days until a single date counts from today', () {
    final out = NumericCalculator.compute(
      NumericOp.daysBetween,
      [v('Lease end', null, '', 1, date: DateTime(2027, 3, 31))],
      today: DateTime(2027, 3, 1, 15, 30),
    )!;
    expect(out, contains('which is in 30 days'));
    expect(
      NumericCalculator.compute(NumericOp.daysBetween, [v('x', null, '', 1, date: DateTime(2027, 2, 27))],
          today: DateTime(2027, 3, 1)),
      contains('2 days ago'),
    );
  });

  test('count removes duplicates', () {
    final out = NumericCalculator.compute(
        NumericOp.count, [v('EXP-12', null, '', 1), v('ATT-04', null, '', 2), v('exp-12', null, '', 3)])!;
    expect(out, startsWith('Found 2:'));
  });

  test('nothing usable returns null', () {
    expect(NumericCalculator.compute(NumericOp.sum, [v('a', null, '', 1)]), isNull);
    expect(NumericCalculator.compute(NumericOp.daysBetween, []), isNull);
  });

  test('format', () {
    expect(NumericCalculator.format(15, '%'), '15%');
    expect(NumericCalculator.format(30, 'days'), '30 days');
    expect(NumericCalculator.format(48.2, 'USD'), 'USD 48.2');
    expect(NumericCalculator.format(1234567, 'INR'), 'INR 12,34,567');
  });

  test('values from the question are labelled instead of cited', () {
    final out = NumericCalculator.compute(NumericOp.daysBetween, [
      v('Effective date', null, '', 2, date: DateTime(2026, 4, 1)),
      v('End of year', null, '', 0, date: DateTime(2026, 12, 31)),
    ])!;
    expect(out, contains('1 Apr 2026 [2]'));
    expect(out, contains('31 Dec 2026 (from your question)'));
  });
}
