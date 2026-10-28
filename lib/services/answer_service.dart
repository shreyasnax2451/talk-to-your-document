import 'package:llamadart/llamadart.dart';

import 'document_store.dart';
import 'model_config.dart';

/// A retrieved passage handed to the answering model, numbered for citation.
class ContextPassage {
  final String docName;
  final int page;
  final String text;

  const ContextPassage({required this.docName, required this.page, required this.text});
}

/// Owns the Qwen3-4B engine and writes answers grounded in retrieved
/// passages. The model is loaded on the first question, not during indexing.
class AnswerService {
  LlamaEngine? _engine;
  Future<LlamaEngine>? _loading;

  static const notFoundReply = 'Not found in your documents.';

  static const _systemPrompt = '''
You answer questions using ONLY the numbered document passages provided.
Rules:
- If the passages do not contain the answer, reply exactly: "$notFoundReply"
- Do not use outside knowledge and do not guess.
- Cite the passage(s) you used after each relevant sentence, like [1] or [2][3].
- Quote numbers, dates, amounts and names exactly as written in the passages.
- Be concise: a short paragraph or a few bullet points.''';

  bool get isLoaded => _engine != null;

  Future<LlamaEngine> _ensureLoaded(void Function(double? fraction)? onDownloadProgress) {
    if (_engine != null) return Future.value(_engine);
    return _loading ??= () async {
      try {
        final source = await ModelConfig.answering.resolveSource();
        final engine = await LlamaEngine.load(
          LlamaModel(source),
          params: ModelConfig.answeringParams,
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

  /// Loads the model if needed; [onDownloadProgress] reports the first-run
  /// download (fraction is null while the size is unknown).
  Future<void> warmUp({void Function(double? fraction)? onDownloadProgress}) =>
      _ensureLoaded(onDownloadProgress);

  static List<ContextPassage> toPassages(List<ChunkHit> hits, Map<String, String> docNames) => [
        for (final hit in hits)
          ContextPassage(docName: docNames[hit.docId] ?? 'Document', page: hit.page, text: hit.text),
      ];

  /// Streams the answer text for [question] from [passages].
  Stream<String> answer(String question, List<ContextPassage> passages) async* {
    final engine = await _ensureLoaded(null);
    final context = StringBuffer();
    for (var i = 0; i < passages.length; i++) {
      final p = passages[i];
      context
        ..writeln('[${i + 1}] ${p.docName}, page ${p.page}:')
        ..writeln(p.text)
        ..writeln();
    }
    final messages = [
      const LlamaChatMessage.fromText(role: LlamaChatRole.system, text: _systemPrompt),
      LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'Passages:\n\n$context\nQuestion: $question',
      ),
    ];
    yield* engine
        .create(
          messages,
          // Qwen3's non-thinking mode: thinking is slow and not needed here.
          enableThinking: false,
          params: const GenerationParams(
            maxTokens: 512,
            temp: 0.3,
            topK: 20,
            topP: 0.8,
            penalty: 1.05,
          ),
        )
        .textDeltas();
  }

  void stop() => _engine?.cancelGeneration();

  /// Frees the ~3 GB the model holds; it reloads on the next question.
  Future<void> unload() async {
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }

  Future<void> dispose() async {
    _engine?.cancelGeneration();
    final pending = _loading;
    await unload();
    if (pending != null) {
      try {
        await (await pending).dispose();
      } catch (_) {}
    }
  }
}
