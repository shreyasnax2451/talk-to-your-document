import 'package:docchat/services/text_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const chunker = TextChunker(targetChars: 200, overlapChars: 40);

  test('short pages become one chunk each, numbered across the document', () {
    final chunks = chunker.chunkPages(['Page one text.', '', 'Page three text.']);
    expect(chunks.map((c) => c.pageNumber), [1, 3]);
    expect(chunks.map((c) => c.chunkIndex), [0, 1]);
    expect(chunks.first.text, 'Page one text.');
  });

  test('long pages split at sentence boundaries within the target size', () {
    final page = List.generate(30, (i) => 'Sentence number $i is here.').join(' ');
    final chunks = chunker.chunkPages([page]);
    expect(chunks.length, greaterThan(1));
    for (final c in chunks) {
      expect(c.text.length, lessThanOrEqualTo(200));
      expect(c.text, endsWith('.'));
      expect(c.pageNumber, 1);
    }
    // Every sentence survives chunking.
    final joined = chunks.map((c) => c.text).join(' ');
    for (var i = 0; i < 30; i++) {
      expect(joined, contains('Sentence number $i is here.'));
    }
  });

  test('consecutive chunks overlap', () {
    final page = List.generate(30, (i) => 'Sentence number $i is here.').join(' ');
    final chunks = chunker.chunkPages([page]);
    final lastOfFirst = chunks[0].text.split('. ').last;
    expect(chunks[1].text, contains(lastOfFirst.replaceAll('.', '')));
  });

  test('text without spaces still splits and terminates', () {
    final chunks = chunker.chunkPages(['x' * 1000]);
    expect(chunks.map((c) => c.text).join().length, greaterThanOrEqualTo(1000));
  });

  test('splitInHalf keeps all content', () {
    const text = 'Alpha beta. Gamma delta. Epsilon zeta.';
    expect(chunker.splitInHalf(text).join(' '), text);
  });
}
