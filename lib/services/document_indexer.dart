import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'document_store.dart';
import 'embedding_service.dart';
import 'fact_extractor.dart';
import 'model_config.dart';
import 'text_chunker.dart';

class IndexingException implements Exception {
  final String message;
  IndexingException(this.message);

  @override
  String toString() => message;
}

/// Turns an uploaded PDF into stored chunks + embeddings:
/// copy into app storage → extract text per page → chunk → embed → save.
///
/// Jobs run one at a time; indexing only needs the embedding model, never the
/// answering model.
class DocumentIndexer {
  final DocumentStore store;
  final EmbeddingService embeddings;
  final TextChunker chunker;

  /// Chunks per embedding call; also how often progress is reported.
  static const _embedBatchSize = 8;

  Future<void> _queue = Future.value();

  DocumentIndexer({
    required this.store,
    required this.embeddings,
    this.chunker = const TextChunker(),
  });

  /// Copies a picked file into the app's private documents folder, since the
  /// picker may hand back a temporary cache path.
  static Future<String> importFile(String sourcePath, String docId) async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'documents'));
    await dir.create(recursive: true);
    final target = p.join(dir.path, '$docId.pdf');
    await File(sourcePath).copy(target);
    return target;
  }

  static Future<void> deleteFile(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// Opens the PDF and returns its page texts. Throws [IndexingException] if
  /// it has no extractable text (e.g. a scanned PDF; OCR is not supported).
  Future<List<String>> extractPages(String filePath) async {
    final PdfDocument pdf;
    try {
      pdf = await PdfDocument.openFile(filePath);
    } catch (e) {
      throw IndexingException('Could not open this PDF.');
    }
    try {
      final pages = <String>[];
      for (final page in pdf.pages) {
        pages.add((await page.loadText())?.fullText ?? '');
      }
      if (pages.every((t) => t.trim().isEmpty)) {
        throw IndexingException('No text found. Scanned PDFs are not supported yet.');
      }
      return pages;
    } finally {
      await pdf.dispose();
    }
  }

  /// Queues indexing of [docId]. [onPages] is called once the page texts are
  /// known; [onProgress] reports 0..1 across the whole job.
  Future<void> index({
    required String docId,
    required String title,
    required String filePath,
    required void Function(List<String> pages) onPages,
    required void Function(double progress) onProgress,
  }) {
    final job = _queue.then((_) => _run(docId, title, filePath, onPages, onProgress));
    _queue = job.catchError((_) {});
    return job;
  }

  Future<void> _run(
    String docId,
    String title,
    String filePath,
    void Function(List<String> pages) onPages,
    void Function(double progress) onProgress,
  ) async {
    onProgress(0.02);
    await embeddings.warmUp(
      onDownloadProgress: (f) => onProgress(0.02 + 0.08 * f),
    );

    final pages = await extractPages(filePath);
    onPages(pages);
    onProgress(0.15);

    final chunks = await _fitToEmbeddingLimit(chunker.chunkPages(pages), title);
    final vectors = <Float32List>[];
    for (var i = 0; i < chunks.length; i += _embedBatchSize) {
      final batch = chunks.skip(i).take(_embedBatchSize);
      vectors.addAll(await embeddings.embedInputs([
        for (final c in batch) EmbeddingService.documentInput(c.text, title: title),
      ]));
      onProgress(0.15 + 0.8 * (vectors.length / chunks.length));
    }

    for (final v in vectors) {
      if (v.length != ModelConfig.embeddingDimensions) {
        throw IndexingException(
            'Embedding model returned ${v.length}-dim vectors, '
            'expected ${ModelConfig.embeddingDimensions}.');
      }
    }

    store.saveIndex(
      docId: docId,
      pages: pages,
      chunks: chunks,
      embeddings: vectors,
      facts: FactExtractor.extract(chunks),
      embeddingModel: ModelConfig.embedding.id,
      embeddingDim: ModelConfig.embeddingDimensions,
    );
    onProgress(1.0);
  }

  /// The chunker sizes by characters; dense text (tables, numbers, non-Latin
  /// scripts) can exceed the model's one-pass token limit, so those chunks
  /// are split further.
  Future<List<TextChunk>> _fitToEmbeddingLimit(List<TextChunk> chunks, String title) async {
    final result = <TextChunk>[];
    for (final chunk in chunks) {
      final pending = [chunk.text];
      while (pending.isNotEmpty) {
        final text = pending.removeAt(0);
        final tokens = await embeddings.tokenCount(
            EmbeddingService.documentInput(text, title: title));
        if (tokens > ModelConfig.embeddingMaxInputTokens && text.length > 1) {
          pending.insertAll(0, chunker.splitInHalf(text));
          continue;
        }
        result.add(TextChunk(
          pageNumber: chunk.pageNumber,
          chunkIndex: result.length,
          text: text,
        ));
      }
    }
    return result;
  }
}
