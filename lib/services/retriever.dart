import 'document_store.dart';
import 'embedding_service.dart';
import 'model_config.dart';

/// Hybrid retrieval: vector search (meaning) + FTS5 keyword search (exact
/// terms), merged with Reciprocal Rank Fusion.
///
/// RRF scores a chunk by its rank in each list rather than its raw score, so
/// cosine similarities and BM25 values never need to be put on one scale.
class Retriever {
  final DocumentStore store;
  final EmbeddingService embeddings;

  /// Candidates fetched from each search before fusion.
  static const _candidates = 20;

  /// Standard RRF damping constant.
  static const _rrfK = 60;

  Retriever({required this.store, required this.embeddings});

  /// Returns the [topK] best chunks for [question], in fused rank order.
  Future<List<ChunkHit>> retrieve(String question, {String? docId, int topK = 5}) async {
    final query = await embeddings.embedQuery(question);
    final vectorHits = store.vectorSearch(
      query,
      embeddingModel: ModelConfig.embedding.id,
      docId: docId,
      limit: _candidates,
    );
    final keywordHits = store.keywordSearch(
      question,
      embeddingModel: ModelConfig.embedding.id,
      docId: docId,
      limit: _candidates,
    );

    final fused = <int, double>{};
    final byId = <int, ChunkHit>{};
    for (final hits in [vectorHits, keywordHits]) {
      for (var rank = 0; rank < hits.length; rank++) {
        final hit = hits[rank];
        byId[hit.id] = hit;
        fused[hit.id] = (fused[hit.id] ?? 0) + 1 / (_rrfK + rank + 1);
      }
    }
    final ranked = fused.keys.toList()..sort((a, b) => fused[b]!.compareTo(fused[a]!));
    return [for (final id in ranked.take(topK)) byId[id]!];
  }
}
