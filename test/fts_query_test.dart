import 'package:docchat/services/document_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('drops stop words and quotes each term', () {
    expect(
      DocumentStore.ftsQuery('What is the hotel limit in Mumbai?'),
      '"hotel" OR "limit" OR "mumbai"',
    );
  });

  test('keeps clause IDs and numbers intact', () {
    expect(DocumentStore.ftsQuery('What does clause EXP-12 say?'),
        '"clause" OR "exp-12" OR "say"');
    expect(DocumentStore.ftsQuery('INR 7000 per night'), '"inr" OR "7000" OR "per" OR "night"');
  });

  test('strips trailing punctuation and quotes from terms', () {
    expect(DocumentStore.ftsQuery('notice "period".'), '"notice" OR "period"');
  });

  test('returns null when nothing searchable remains', () {
    expect(DocumentStore.ftsQuery('what is the'), isNull);
    expect(DocumentStore.ftsQuery('???'), isNull);
  });
}
