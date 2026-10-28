import 'package:llamadart/llamadart.dart';

import 'document_store.dart';
import 'model_config.dart';
import 'numeric_calculator.dart';
import 'query_planner.dart';

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

  static const _groundingRules = '''
- Use ONLY the numbered passages. Do not use outside knowledge and do not guess.
- If the passages do not contain what is asked, reply exactly: "$notFoundReply"
- Cite the passage(s) behind each sentence or bullet, like [1] or [2][3].
- Quote numbers, dates, amounts and names exactly as written in the passages.
- Mind qualifiers: when a passage gives different values for different cases
  (during vs after probation, metro vs other cities), answer for the exact
  case asked and never swap them.''';

  static const _lookupPrompt = '''
You answer questions about the user's documents.
Rules:
$_groundingRules
- Be concise: a short paragraph or a few bullet points.''';

  static const _sectionPrompt = '''
You explain one part of the user's documents.
Rules:
$_groundingRules
- Summarize only what the passages say about the requested topic, in at most
  5 plain bullet points (no labels like "Key point:").''';

  static const _documentSummaryPrompt = '''
You summarize the user's documents. The passages are excerpts sampled evenly
from the start to the end of each document, so treat them as an overview.
Several passages usually come from the SAME document; the request says how
many documents there are and how long the summary may be.
Rules:
$_groundingRules
- The first bullet says what the document is and its purpose; the rest give
  the most important facts (numbers, dates, amounts, obligations, deadlines).
- Plain bullets, one sentence each, no labels like "Purpose:".''';

  static const _listPrompt = '''
You list information from the user's documents. Passages are short excerpts
and extracted sentences; together they may hold many separate items.
Rules:
$_groundingRules
- List EVERY distinct item that answers the request, one bullet each, with its
  key detail (amount, date, duration or condition) and citation.
- Do not merge different items and do not stop after the first few.''';

  static const _comparePrompt = '''
You compare two things described in the user's documents. Each passage is
labelled with the side it was found for, like "(About: X)".
Rules:
$_groundingRules
- Give one short bullet per real difference or similarity the passages state
  (amounts, durations, conditions, eligibility). At most 5 bullets; fewer is
  fine. Never pad with points the passages do not make.
- Only attribute a rule to a side if a passage says it applies to that side.
- If a side is not covered by the passages, say so for that side.''';

  static const _extractPrompt = '''
You extract values from the user's documents for a calculation done by code.
Rules:
- Use values from the numbered passages, or values stated in the question
  itself. Never invent or compute values yourself.
- Extract every value the question needs, one item each.
- label: a short description in plain words, like "Hotel cap (metro cities)".
- value: the number only (no currency symbol, no commas); null for dates.
- unit: the currency or unit as written (INR, USD, %, days, ...), or "".
- date: YYYY-MM-DD for dates, otherwise "".
- passage: the number of the passage the value comes from, or 0 if it comes
  from the question.
- If a needed value is not available, leave it out (an empty list is fine).''';

  /// Used when value extraction fails for a numeric question: answer from
  /// the passages but leave arithmetic out, since small models get it wrong.
  static const _numericFallbackPrompt = '''
You answer questions about the user's documents.
Rules:
$_groundingRules
- Do NOT do any arithmetic (no totals, differences or day counts). State the
  relevant values with citations, then say the calculation could not be done
  automatically.''';

  static final _extractOutput = LlamaStructuredOutput<List<Map<String, dynamic>>>.jsonSchema(
    schema: {
      'type': 'object',
      'properties': {
        'items': {
          'type': 'array',
          'maxItems': 20,
          'items': {
            'type': 'object',
            'properties': {
              'label': {'type': 'string'},
              'value': {
                'anyOf': [
                  {'type': 'number'},
                  {'type': 'null'},
                ],
              },
              'unit': {'type': 'string'},
              'date': {'type': 'string'},
              'passage': {'type': 'integer'},
            },
            'required': ['label', 'value', 'unit', 'date', 'passage'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['items'],
      'additionalProperties': false,
    },
    decoder: (json) => [for (final i in json['items'] as List) (i as Map).cast<String, dynamic>()],
  );

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

  /// Streams [model]'s written answer for [plan] from [passages].
  /// [previous] is the last question and answer, passed for follow-ups.
  Stream<String> answer(
    ModelSpec model,
    QueryPlan plan,
    List<ContextPassage> passages, {
    ({String question, String answer})? previous,
  }) {
    final docNames = {for (final p in passages) p.docName}.toList();
    final documents = docNames.length;
    final (system, maxTokens) = switch (plan.intent) {
      QueryIntent.sectionSummary => (_sectionPrompt, 350),
      QueryIntent.documentSummary => (_documentSummaryPrompt, documents <= 1 ? 350 : 250 * documents),
      QueryIntent.list => (_listPrompt, 600),
      QueryIntent.compare => (_comparePrompt, 450),
      QueryIntent.numeric => (_numericFallbackPrompt, 300),
      _ => (_lookupPrompt, 400),
    };
    final request = switch (plan.intent) {
      QueryIntent.documentSummary => documents == 1
          ? 'Summarize the one document "${docNames.single}" in at most 5 short bullets. '
              'Do not repeat its name before each bullet.'
          : 'Summarize these $documents documents: ${docNames.map((n) => '"$n"').join(', ')}. '
              'For each, write its name once on its own line, then at most 3 short bullets.',
      QueryIntent.sectionSummary => 'Request: ${plan.question}\nTopic: ${plan.searchQuery}',
      QueryIntent.compare => 'Request: ${plan.question}\nSides: ${plan.compareSides.join(' | ')}',
      _ => 'Question: ${plan.question}',
    };
    final history = plan.isFollowUp && previous != null
        ? 'Earlier in this conversation (for context only):\n'
            'Q: ${previous.question}\nA: ${_short(previous.answer, 400)}\n\n'
        : '';
    return _generate(
      model,
      system: system,
      user: '${history}Passages:\n\n${_numbered(passages)}\n$request',
      maxTokens: maxTokens,
    );
  }

  /// For numeric questions: the values the calculation needs, as extracted
  /// by [model] with constrained JSON output, or null if none were found.
  Future<List<ExtractedValue>?> extractValues(
    ModelSpec model,
    QueryPlan plan,
    List<ContextPassage> passages,
  ) async {
    final engine = await _ensureLoaded(model);
    final items = await engine.createStructuredJson(
      [
        const LlamaChatMessage.fromText(role: LlamaChatRole.system, text: _extractPrompt),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Passages:\n\n${_numbered(passages)}\nQuestion: ${plan.question}',
        ),
      ],
      output: _extractOutput,
      enableThinking: false,
      // Greedy decoding: extraction should be repeatable, not creative.
      params: const GenerationParams(maxTokens: 500, temp: 0, topK: 1),
    );
    final values = [
      for (final item in items)
        ExtractedValue.fromJson(item),
    ].where((v) => v.passage >= 0 && v.passage <= passages.length).toList();
    return values.isEmpty ? null : values;
  }

  static String _numbered(List<ContextPassage> passages) {
    final context = StringBuffer();
    for (var i = 0; i < passages.length; i++) {
      final p = passages[i];
      context
        ..writeln('[${i + 1}] ${p.docName}, page ${p.page}:')
        ..writeln(p.text)
        ..writeln();
    }
    return context.toString();
  }

  static String _short(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  Stream<String> _generate(
    ModelSpec model, {
    required String system,
    required String user,
    required int maxTokens,
  }) async* {
    final engine = await _ensureLoaded(model);
    yield* engine
        .create(
          [
            LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: user),
          ],
          // Qwen3's non-thinking mode: thinking is slow and not needed here.
          enableThinking: false,
          params: GenerationParams(
            maxTokens: maxTokens,
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
