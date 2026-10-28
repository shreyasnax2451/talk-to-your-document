import 'package:docchat/services/fact_extractor.dart';
import 'package:docchat/services/text_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

List<Fact> facts(String s) => FactExtractor.fromSentence(s, page: 1, chunkIndex: 0);

void main() {
  test('amounts in rupees with Indian and western grouping', () {
    final f = facts('Hotel stays are capped at INR 7,000 per night and Rs. 1,25,000 per year.');
    final money = f.where((x) => x.kind == FactKind.money).toList();
    expect(money.map((x) => x.number), [7000, 125000]);
    expect(money.every((x) => x.unit == 'INR'), isTrue);
  });

  test('amounts with symbols, words and scales', () {
    expect(facts('Revenue reached \$48.2 million.').single.number, closeTo(48.2e6, 1));
    expect(facts('A fee of ₹2,500 applies.').single.unit, 'INR');
    expect(facts('Budget: 3 lakh rupees? No, INR 3 lakh.').where((x) => x.kind == FactKind.money).last.number,
        300000);
    expect(facts('It costs 500 dollars.').single.unit, 'USD');
  });

  test('dates in common formats', () {
    final f = facts('Effective from 1 April 2026, replacing the edition of July 1, 2024 '
        '(signed 2024-07-01, filed 15/08/2024).');
    final dates = f.where((x) => x.kind == FactKind.date).map((x) => x.date).toList();
    expect(dates, [
      DateTime(2026, 4, 1),
      DateTime(2024, 7, 1),
      DateTime(2024, 7, 1),
      DateTime(2024, 8, 15),
    ]);
  });

  test('dates without a year are kept but have no date value', () {
    final f = facts('Any balance above 10 days lapses on 31 December.');
    final date = f.singleWhere((x) => x.kind == FactKind.date);
    expect(date.raw, '31 December');
    expect(date.date, isNull);
  });

  test('durations, percentages and IDs', () {
    final f = facts('Claims within 30 days get a bonus of up to 15% under clause EXP-12.');
    expect(f.map((x) => x.kind).toSet(), {FactKind.duration, FactKind.percent, FactKind.id});
    expect(f.firstWhere((x) => x.kind == FactKind.duration).unit, 'days');
    expect(f.firstWhere((x) => x.kind == FactKind.id).raw, 'EXP-12');
  });

  test('an amount is not also read as a duration or percentage', () {
    final f = facts('Pay INR 30 days later.');
    expect(f.where((x) => x.kind == FactKind.money).length, 1);
    expect(f.where((x) => x.kind == FactKind.duration), isEmpty);
  });

  test('invalid dates are rejected', () {
    expect(facts('Due 31/02/2026.').where((x) => x.kind == FactKind.date), isEmpty);
  });

  test('extract de-duplicates facts repeated by overlapping chunks', () {
    const text = 'Notice period is 60 days. Hotel cap is INR 7,000.';
    final f = FactExtractor.extract([
      const TextChunk(pageNumber: 1, chunkIndex: 0, text: text),
      const TextChunk(pageNumber: 1, chunkIndex: 1, text: text),
    ]);
    expect(f.length, 2);
  });

  test('sentences join wrapped PDF lines but keep list items apart', () {
    final s = FactExtractor.sentences(
        'Final settlement is paid within 45 days of\nthe last working day. Letters follow.\n'
        '• Q1: launch\n• Q2: scale\n\nNew paragraph here');
    expect(s, [
      'Final settlement is paid within 45 days of the last working day.',
      'Letters follow.',
      '• Q1: launch',
      '• Q2: scale',
      'New paragraph here',
    ]);
  });
}
