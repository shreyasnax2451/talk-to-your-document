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

/// Owns the answering model's engine (the model the user chose) and writes
/// answers grounded in retrieved passages. The model is loaded on the first
/// question, not during indexing, and swapped when the user picks another.
class AnswerService {
  LlamaEngine? _engine;
  ModelSpec? _loadedModel;
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

  bool isLoaded(ModelSpec model) => _engine != null && _loadedModel?.id == model.id;

  Future<LlamaEngine> _ensureLoaded(ModelSpec model) async {
    if (isLoaded(model)) return _engine!;
    if (_loading != null) await _loading;
    if (isLoaded(model)) return _engine!;
    // One answering model in memory at a time.
    await unload();
    final loading = () async {
      final engine = await LlamaEngine.load(
        LlamaModel(await model.resolveSource()),
        params: model.params,
      );
      _engine = engine;
      _loadedModel = model;
      return engine;
    }();
    _loading = loading;
    try {
      return await loading;
    } finally {
      _loading = null;
    }
  }

  /// Loads [model] (already downloaded) if it is not the one in memory.
  Future<void> load(ModelSpec model) => _ensureLoaded(model);

  static List<ContextPassage> toPassages(List<ChunkHit> hits, Map<String, String> docNames) => [
        for (final hit in hits)
          ContextPassage(docName: docNames[hit.docId] ?? 'Document', page: hit.page, text: hit.text),
      ];

  /// Streams [model]'s answer to [question] from [passages].
  Stream<String> answer(ModelSpec model, String question, List<ContextPassage> passages) async* {
    final engine = await _ensureLoaded(model);
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

  /// Frees the memory the model holds (1.5-3 GB); it reloads on the next
  /// question.
  Future<void> unload() async {
    final engine = _engine;
    _engine = null;
    _loadedModel = null;
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
