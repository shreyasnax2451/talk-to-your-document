/// A passage of a PDF page, the unit that is embedded and retrieved.
class TextChunk {
  final int pageNumber; // 1-based
  final int chunkIndex; // position within the document
  final String text;

  const TextChunk({
    required this.pageNumber,
    required this.chunkIndex,
    required this.text,
  });
}

/// Splits extracted page text into ~400-token passages.
///
/// Chunks never cross a page boundary so every passage can be cited by page.
/// Splits prefer paragraph, then sentence, then word boundaries, and
/// consecutive chunks on a page overlap slightly so a fact cut at a boundary
/// is still found in one piece.
class TextChunker {
  /// ~4 characters per token for English text; 1600 chars ≈ 400 tokens.
  final int targetChars;
  final int overlapChars;

  const TextChunker({this.targetChars = 1600, this.overlapChars = 200});

  List<TextChunk> chunkPages(List<String> pages) {
    final chunks = <TextChunk>[];
    for (var i = 0; i < pages.length; i++) {
      for (final text in _splitPage(_normalize(pages[i]))) {
        chunks.add(TextChunk(
          pageNumber: i + 1,
          chunkIndex: chunks.length,
          text: text,
        ));
      }
    }
    return chunks;
  }

  /// Splits [text] in half at the best boundary; used when a chunk turns out
  /// to have more tokens than the embedding model accepts.
  List<String> splitInHalf(String text) {
    final cut = _findCut(text, text.length ~/ 2, 0);
    return [text.substring(0, cut).trim(), text.substring(cut).trim()]
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String _normalize(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'[ \t ]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  List<String> _splitPage(String text) {
    if (text.isEmpty) return const [];
    if (text.length <= targetChars) return [text];

    final result = <String>[];
    var start = 0;
    while (start < text.length) {
      if (text.length - start <= targetChars) {
        result.add(text.substring(start).trim());
        break;
      }
      final cut = _findCut(text, start + targetChars, start + targetChars ~/ 2);
      result.add(text.substring(start, cut).trim());
      // Step back for overlap, but always move forward.
      final next = _findCut(text, cut - overlapChars, start + 1);
      start = next > start && next < cut ? next : cut;
    }
    return result.where((s) => s.isNotEmpty).toList();
  }

  /// Best split position at or before [limit] and after [minPos].
  int _findCut(String text, int limit, int minPos) {
    limit = limit.clamp(0, text.length);
    for (final boundary in const ['\n\n', '\n', '. ', '? ', '! ', '; ', ' ']) {
      if (limit < boundary.length) continue;
      final idx = text.lastIndexOf(boundary, limit - boundary.length);
      if (idx > minPos) return idx + boundary.length;
    }
    return limit;
  }
}
