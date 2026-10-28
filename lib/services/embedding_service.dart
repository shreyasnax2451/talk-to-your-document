import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';

import 'model_config.dart';

/// Owns the EmbeddingGemma engine. The model is loaded on first use and kept
/// for later indexing jobs and query embedding.
///
/// EmbeddingGemma expects task prefixes: documents are embedded as
/// `title: <title> | text: <chunk>` and queries as
/// `task: search result | query: <question>`. Both sides must use the same
/// model, so vectors stay comparable.
class EmbeddingService {
  LlamaEngine? _engine;
  Future<LlamaEngine>? _loading;

  Future<LlamaEngine> _ensureLoaded({void Function(double? fraction)? onDownloadProgress}) {
    if (_engine != null) return Future.value(_engine);
    return _loading ??= () async {
      try {
        final source = await ModelConfig.embedding.resolveSource();
        final engine = await LlamaEngine.load(
          LlamaModel(source),
          params: ModelConfig.embeddingParams,
          onProgress: onDownloadProgress == null
              ? null
              : (progress) => onDownloadProgress(progress.fraction),
        );
        _engine = engine;
        return engine;
      } finally {
        _loading = null;
      }
    }();
  }

  Future<void> warmUp({void Function(double? fraction)? onDownloadProgress}) =>
      _ensureLoaded(onDownloadProgress: onDownloadProgress);

  static String documentInput(String text, {String? title}) =>
      'title: ${title ?? 'none'} | text: $text';

  static String queryInput(String query) => 'task: search result | query: $query';

  Future<int> tokenCount(String input) async =>
      (await _ensureLoaded()).getTokenCount(input);

  /// Embeds already-prefixed inputs; returns L2-normalized vectors in order.
  Future<List<Float32List>> embedInputs(List<String> inputs) async {
    if (inputs.isEmpty) return const [];
    final engine = await _ensureLoaded();
    final vectors = await engine.embedBatch(inputs);
    return [for (final v in vectors) Float32List.fromList(v)];
  }

  Future<Float32List> embedQuery(String query) async =>
      (await embedInputs([queryInput(query)])).single;

  Future<void> dispose() async {
    final engine = _engine ?? await _loading;
    _engine = null;
    await engine?.dispose();
  }
}
