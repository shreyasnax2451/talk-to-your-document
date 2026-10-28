import 'document_store.dart';
import 'fact_extractor.dart';
import 'query_planner.dart';
import 'retriever.dart';

/// The numbered passages handed to the answering model for one question.
class BuiltContext {
  /// Passages in the order they are numbered for citation ([1], [2], ...).
  final List<ChunkHit> passages;

  /// Shown under the answer, e.g. that a summary covers only some documents.
  final String? note;

  const BuiltContext(this.passages, {this.note});
}

/// Gathers passages according to a [QueryPlan].
///
/// Every intent spends the same reading budget ([budgetChars], about 1,800
/// tokens), so answer time on a phone stays predictable: lookups read a few
/// whole passages, lists read many short excerpts, summaries read a spread
/// of the document.
class ContextBuilder {
  final DocumentStore store;
  final Retriever retriever;

  static const budgetChars = 7000;

  ContextBuilder({required this.store, required this.retriever});

  /// [scopeDocId] is the chat's document (null for "All documents"); a
  /// document named in the question narrows an "All documents" chat.
  Future<BuiltContext> build(QueryPlan plan, {String? scopeDocId}) async {
    final docId = scopeDocId ?? plan.namedDocId;
    switch (plan.intent) {
      case QueryIntent.smallTalk:
        return const BuiltContext([]);
      case QueryIntent.lookup:
        return BuiltContext(await retriever.retrieve(plan.searchQuery, docId: docId, topK: 5));
      case QueryIntent.sectionSummary:
        return _section(plan, docId);
      case QueryIntent.documentSummary:
        return _documentSample(docId);
      case QueryIntent.list:
        return _list(plan, docId);
      case QueryIntent.compare:
        return _compare(plan, docId);
      case QueryIntent.numeric:
        return _numeric(plan, docId);
    }
  }

  /// The best-matching passage plus the ones around it: a section usually
  /// spans a few consecutive chunks.
  Future<BuiltContext> _section(QueryPlan plan, String? docId) async {
    final hits = await retriever.retrieve(plan.searchQuery, docId: docId, topK: 3);
    if (hits.isEmpty) return const BuiltContext([]);
    final section = store.neighborChunks(hits.first.id, radius: 1);
    final ids = {for (final c in section) c.id};
    // A second strong hit elsewhere (sections can be split across pages).
    final extra = hits.skip(1).where((h) => !ids.contains(h.id)).take(1);
    return BuiltContext(_fit([...section, ...extra], budgetChars));
  }

  /// Passages spread evenly from the first page to the last, so the summary
  /// covers the whole document rather than whatever "summary" matches.
  BuiltContext _documentSample(String? docId) {
    final docs = docId != null ? [docId] : [for (final d in store.readyDocuments()) d.id];
    if (docs.isEmpty) return const BuiltContext([]);
    final picked = docs.take(3).toList();
    final perDoc = (6 / picked.length).ceil().clamp(2, 6);
    final samples = [for (final id in picked) ...store.sampleChunks(id, count: perDoc)];
    return BuiltContext(
      _fit(samples, budgetChars),
      note: docs.length > picked.length
          ? 'This covers your ${picked.length} most recent documents. Choose one '
              'document at the top of the chat to summarize it in detail.'
          : null,
    );
  }

  /// Many short excerpts (only the sentences that match), plus every
  /// extracted date/amount/ID of the kind asked for: a list needs breadth.
  Future<BuiltContext> _list(QueryPlan plan, String? docId) async {
    final hits = await retriever.retrieve(plan.searchQuery, docId: docId, topK: 12);
    final terms = _stems(plan.searchQuery);
    final passages = <ChunkHit>[];
    final usedSentences = <String>{};
    var used = 0;
    for (final hit in hits) {
      final excerpt = _matchingSentences(hit.text, terms, maxChars: 450, used: usedSentences);
      if (used + excerpt.length > budgetChars * 0.6) break;
      passages.add(_withText(hit, excerpt));
      used += excerpt.length;
    }
    passages.addAll(_factPassages(plan, docId, terms, budgetChars - used, usedSentences));
    return BuiltContext(passages);
  }

  /// A separate search per side, each passage labelled with its side.
  Future<BuiltContext> _compare(QueryPlan plan, String? docId) async {
    final perSide = budgetChars ~/ (plan.compareSides.length * 3);
    final passages = <ChunkHit>[];
    final seen = <int>{};
    for (var i = 0; i < plan.compareSides.length; i++) {
      final side = plan.compareSides[i];
      final sideDoc = plan.compareSideDocIds.elementAtOrNull(i) ?? docId;
      for (final hit in await retriever.retrieve(side, docId: sideDoc, topK: 3)) {
        if (!seen.add(hit.id)) continue;
        passages.add(_withText(hit, '(About: $side)\n${_trim(hit.text, perSide)}'));
      }
    }
    return BuiltContext(passages);
  }

  /// The passages that hold the values, plus extracted values of the right
  /// kind from those pages.
  Future<BuiltContext> _numeric(QueryPlan plan, String? docId) async {
    final hits = _fit(await retriever.retrieve(plan.searchQuery, docId: docId, topK: 6), 5000);
    final used = hits.fold<int>(0, (n, h) => n + h.text.length);
    // Facts only add sentences the trimmed passages no longer contain.
    final sentences = {for (final h in hits) ...FactExtractor.sentences(h.text)};
    final terms = _stems(plan.searchQuery);
    return BuiltContext([
      ...hits,
      ..._factPassages(plan, docId, terms, budgetChars - used, sentences,
          pages: {for (final h in hits) '${h.docId}:${h.page}'}),
    ]);
  }

  /// Extracted facts grouped into one passage per chunk, sentences matching
  /// the question first. [pages] limits them to those document pages.
  List<ChunkHit> _factPassages(
    QueryPlan plan,
    String? docId,
    Set<String> terms,
    int budget,
    Set<String> usedSentences, {
    Set<String>? pages,
  }) {
    if (plan.factKinds.isEmpty || budget <= 200) return const [];
    var facts = store.facts(kinds: plan.factKinds, docId: docId, limit: 120);
    if (pages != null) facts = facts.where((f) => pages.contains('${f.docId}:${f.fact.page}')).toList();
    bool matches(StoredFact f) => terms.any(f.fact.sentence.toLowerCase().contains);
    facts.sort((a, b) => (matches(b) ? 1 : 0) - (matches(a) ? 1 : 0));

    final byChunk = <int, (StoredFact, List<String>)>{};
    var used = 0;
    for (final f in facts) {
      final sentence = f.fact.sentence;
      if (!usedSentences.add(sentence)) continue;
      if (used + sentence.length > budget) break;
      byChunk.putIfAbsent(f.chunkId, () => (f, [])).$2.add(sentence);
      used += sentence.length;
    }
    return [
      for (final (f, sentences) in byChunk.values)
        ChunkHit(id: f.chunkId, docId: f.docId, page: f.fact.page, text: sentences.join(' '), score: 0),
    ];
  }

  // --- Helpers --------------------------------------------------------------

  static const _listWords = {
    'list', 'all', 'every', 'each', 'show', 'give', 'name', 'enumerate', 'total', 'sum', 'average',
    'compare', 'many', 'much', 'between', 'days',
  };

  /// Question words cut to a stem, so "deadlines" also matches "deadline".
  static Set<String> _stems(String text) => {
        for (final t in DocumentStore.queryTerms(text))
          if (!_listWords.contains(t)) t.length > 5 ? t.substring(0, t.length - 2) : t,
      };

  /// The sentences of [text] that mention a term (falls back to its start).
  static String _matchingSentences(String text, Set<String> terms,
      {required int maxChars, required Set<String> used}) {
    final picked = <String>[];
    var length = 0;
    for (final sentence in FactExtractor.sentences(text)) {
      if (!terms.any(sentence.toLowerCase().contains)) continue;
      if (!used.add(sentence)) continue;
      if (length + sentence.length > maxChars) break;
      picked.add(sentence);
      length += sentence.length;
    }
    return picked.isEmpty ? _trim(text, 300) : picked.join(' ');
  }

  /// Keeps [hits] within [budget] characters, trimming each evenly.
  static List<ChunkHit> _fit(List<ChunkHit> hits, int budget) {
    if (hits.isEmpty) return hits;
    final each = budget ~/ hits.length;
    return [for (final h in hits) h.text.length <= each ? h : _withText(h, _trim(h.text, each))];
  }

  static String _trim(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final cut = text.lastIndexOf(RegExp(r'[.!?]\s'), maxChars);
    return cut > maxChars ~/ 2 ? text.substring(0, cut + 1) : '${text.substring(0, maxChars).trimRight()}…';
  }

  static ChunkHit _withText(ChunkHit h, String text) =>
      ChunkHit(id: h.id, docId: h.docId, page: h.page, text: text, score: h.score);
}
