import 'fact_extractor.dart';

/// What kind of question was asked; decides how passages are gathered and
/// which prompt the answering model gets.
enum QueryIntent {
  /// Greetings and thanks: answered without searching or the model.
  smallTalk,

  /// A specific fact: hybrid search, top passages.
  lookup,

  /// "Summarize the leave policy": the matching passage and its neighbours.
  sectionSummary,

  /// "Summarize this document": passages sampled across the whole document.
  documentSummary,

  /// "List all deadlines": many short matching excerpts plus extracted facts.
  list,

  /// "Compare A and B": a separate search for each side.
  compare,

  /// "Total of all fees", "days between X and Y": values are extracted by the
  /// model and the arithmetic is done in code.
  numeric,
}

enum NumericOp { sum, average, difference, daysBetween, count }

/// How to answer one question.
class QueryPlan {
  final QueryIntent intent;

  /// The question as asked.
  final String question;

  /// What to search for: the question, merged with the previous question for
  /// follow-ups, or the topic for section summaries.
  final String searchQuery;

  /// For [QueryIntent.compare]: the two things being compared.
  final List<String> compareSides;

  /// For [QueryIntent.compare]: a document matching each side by name, if any.
  final List<String?> compareSideDocIds;

  /// A document the question names ("in the lease…"); narrows an
  /// "All documents" chat to it.
  final String? namedDocId;

  /// True when the question continues the previous one ("and for Delhi?").
  final bool isFollowUp;

  final NumericOp? numericOp;

  /// Extracted facts worth adding for list and numeric questions.
  final Set<FactKind> factKinds;

  const QueryPlan({
    required this.intent,
    required this.question,
    required this.searchQuery,
    this.compareSides = const [],
    this.compareSideDocIds = const [],
    this.namedDocId,
    this.isFollowUp = false,
    this.numericOp,
    this.factKinds = const {},
  });
}

/// Works out what a question needs before anything is retrieved.
///
/// Rule-based on purpose: it is instant and predictable on a phone (asking
/// the model to classify would add seconds to every question), and anything
/// it does not recognise is treated as a [QueryIntent.lookup], which is how
/// every question was answered before planning existed.
class QueryPlanner {
  QueryPlanner._();

  static QueryPlan plan(
    String question, {
    String? previousQuestion,
    List<({String id, String name})> documents = const [],
  }) {
    final q = question.trim();
    final lower = q.toLowerCase();

    if (_smallTalk.hasMatch(lower)) {
      return QueryPlan(intent: QueryIntent.smallTalk, question: q, searchQuery: q);
    }

    final namedDocId = _namedDocument(lower, documents);
    final factKinds = _factKinds(lower);

    // Follow-ups continue the previous question: search with both, so
    // "and in other cities?" finds what "hotel cap in metro cities" found.
    final followUp = previousQuestion != null && _isFollowUp(lower);
    final searchBase = followUp ? '${previousQuestion.trim()} $q' : q;

    if (_documentSummary.hasMatch(lower)) {
      return QueryPlan(
        intent: QueryIntent.documentSummary,
        question: q,
        searchQuery: q,
        namedDocId: namedDocId,
      );
    }

    if (_sectionSummary.firstMatch(lower) case final m?) {
      final topic = _cleanTopic(m.namedGroup('topic')!);
      // "Summarize the lease" names a document: that is a document summary.
      final topicDoc = _namedDocument(topic, documents);
      if (topicDoc != null && _isJustDocumentName(topic, documents, topicDoc)) {
        return QueryPlan(
          intent: QueryIntent.documentSummary,
          question: q,
          searchQuery: q,
          namedDocId: topicDoc,
        );
      }
      if (topic.isNotEmpty) {
        return QueryPlan(
          intent: QueryIntent.sectionSummary,
          question: q,
          searchQuery: followUp ? '${previousQuestion.trim()} $topic' : topic,
          namedDocId: namedDocId,
          isFollowUp: followUp,
        );
      }
    }

    final sides = _compareSides(lower);
    if (sides != null) {
      return QueryPlan(
        intent: QueryIntent.compare,
        question: q,
        searchQuery: searchBase,
        compareSides: sides,
        compareSideDocIds: [for (final s in sides) _namedDocument(s, documents)],
        namedDocId: namedDocId,
        isFollowUp: followUp,
      );
    }

    final op = _numericOp(lower);
    if (op != null) {
      return QueryPlan(
        intent: QueryIntent.numeric,
        question: q,
        searchQuery: searchBase,
        numericOp: op,
        namedDocId: namedDocId,
        isFollowUp: followUp,
        factKinds: op == NumericOp.daysBetween
            ? const {FactKind.date}
            : (factKinds.isEmpty ? const {FactKind.money} : factKinds),
      );
    }

    if (_list.hasMatch(lower)) {
      return QueryPlan(
        intent: QueryIntent.list,
        question: q,
        searchQuery: searchBase,
        namedDocId: namedDocId,
        isFollowUp: followUp,
        factKinds: factKinds,
      );
    }

    return QueryPlan(
      intent: QueryIntent.lookup,
      question: q,
      searchQuery: searchBase,
      namedDocId: namedDocId,
      isFollowUp: followUp,
    );
  }

  /// Replies for [QueryIntent.smallTalk], with no model call.
  static String smallTalkReply(String question) {
    final lower = question.toLowerCase();
    if (RegExp(r'\b(thanks|thank you|thx|ty|cheers)\b').hasMatch(lower)) {
      return "You're welcome! Ask me anything else about your documents.";
    }
    if (RegExp(r'\b(bye|goodbye|see you)\b').hasMatch(lower)) return 'Goodbye!';
    if (RegExp(r'^(ok|okay|cool|great|nice|got it|alright)\b').hasMatch(lower)) {
      return 'Ask me anything else about your documents.';
    }
    return 'Hi! Ask me a question about your documents, or ask me to summarize one.';
  }

  // --- Patterns -----------------------------------------------------------

  static final _smallTalk = RegExp(
    r'^\s*(hi|hii+|hello|hey|hey there|good (morning|afternoon|evening|night)|'
    r'thanks|thank you|thank you so much|thanks a lot|thx|ty|cheers|ok|okay|cool|great|nice|'
    r'got it|alright|bye|goodbye|see you)'
    r'(\s+(there|again|so much|a lot))?\s*[!.\s]*$',
  );

  static const _docWords =
      r'(document|documents|doc|docs|pdf|pdfs|file|files|report|reports|text|paper|this|it)';

  static final _documentSummary = RegExp([
    r'^\s*(please\s+)?((can|could|would) you\s+)?',
    r'(summari[sz]e|give( me)?( a| an)? (short |brief |quick |high[- ]level )?(summary|overview|gist)|',
    r'(short |brief |quick |high[- ]level )?(summary|overview|gist)|tl;?dr|',
    r'((what are|give me|list) )?(the )?(key|main) (points|takeaways|ideas|highlights)|',
    r'what (is|are) (this|these|the|my) ', _docWords, r' (about|for)|',
    r"what'?s (this|the) ", _docWords, r' about|',
    r"what('?s| is) (this|it) about)",
    r'(\s+(of|for|in|from))?',
    r'(\s+(this|the|my|these|all|all the|all my|both|each)\s+', _docWords, r')?',
    r'\s*[.?!]*\s*$',
  ].join());

  static final _sectionSummary = RegExp(
    r'^\s*(please\s+)?((can|could|would) you\s+)?'
    r'(summari[sz]e|give( me)?( a| an)? (short |brief |quick )?(summary|overview|rundown) of|'
    r'(short |brief |quick )?(summary|overview) of|explain|describe|walk me through|'
    r'what does (the |this )?(section|clause|part|chapter|policy)\s*(on |about )?)'
    r'\s+(?<topic>.+?)\s*(say|says|cover|covers|mean|means)?\s*[.?!]*\s*$',
  );

  static final _list = RegExp(
    r'^\s*(please\s+)?(list|enumerate|name|show( me)?|give me( a list of)?)\b|'
    r'\b(all|every|each)\s+(the\s+|of the\s+)?[a-z]+|'
    r'\bwhat are (all )?the [a-z]+s\b|\bwhich [a-z]+s\s+[a-z]+|'
    r'\blist of\b',
  );

  static final _compareA = RegExp(
      r'\b(compare|comparison of|contrast)\s+(?<a>.+?)\s+(and|with|to|vs\.?|versus|against)\s+(?<b>.+?)\s*[.?!]*$');
  static final _compareB =
      RegExp(r'\bdifferences? (between|in)\s+(?<a>.+?)\s+(and|vs\.?|versus)\s+(?<b>.+?)\s*[.?!]*$');
  static final _compareC = RegExp(
      r'^\s*(how (does|do|is|are)\s+)?(?<a>.+?)\s+(differ from|different from|compare (to|with)|compared (to|with)|vs\.?|versus)\s+(?<b>.+?)\s*[.?!]*$');

  static List<String>? _compareSides(String lower) {
    for (final re in [_compareA, _compareB, _compareC]) {
      final m = re.firstMatch(lower);
      if (m == null) continue;
      final a = _cleanTopic(m.namedGroup('a')!);
      final b = _cleanTopic(m.namedGroup('b')!);
      if (a.isNotEmpty && b.isNotEmpty) return [a, b];
    }
    return null;
  }

  static NumericOp? _numericOp(String lower) {
    if (RegExp(r'\b(days|weeks|months) (between|from)\b.*\b(and|to|until|till)\b|'
            r'\bhow (many|long) (days|weeks|months)? ?(between|from|until|till|before)\b|'
            r'\bhow long (between|from|until|till)\b')
        .hasMatch(lower)) {
      return NumericOp.daysBetween;
    }
    if (RegExp(r'\b(average|mean)\b').hasMatch(lower)) return NumericOp.average;
    if (RegExp(r'\b(total|sum|add up|added up|altogether|combined|in all)\b').hasMatch(lower)) {
      return NumericOp.sum;
    }
    if (RegExp(r'\bhow much (more|less|higher|lower|cheaper|costlier)\b|'
            r'\b(difference|gap) (between|in) (the )?(amount|cost|price|fee|salary|rent|limit|value)')
        .hasMatch(lower)) {
      return NumericOp.difference;
    }
    if (RegExp(r'\bhow many (different |separate |distinct )?'
            r'(items|documents|clauses|sections|deadlines|dates|fees|types|kinds|times|rules|policies)\b|'
            r'\bnumber of (items|clauses|sections|deadlines|fees|types|kinds|rules)\b')
        .hasMatch(lower)) {
      return NumericOp.count;
    }
    return null;
  }

  static final _followUpStart = RegExp(
      r'^\s*(and|also|what about|how about|same for|same with|but|then|or|'
      r'what if|is that|is it|are they|does it|does that|do they)\b');
  static final _pronoun = RegExp(r'\b(it|its|that|they|them|their|those|these|there|he|she)\b');
  // Questions starting like this stand on their own even when short
  // ("List all deadlines", "When is renewal?").
  static final _selfContainedStart = RegExp(
      r'^\s*(what|who|when|where|which|how|list|show|name|give|summari[sz]e|compare|explain|'
      r'describe|define|tell|find|is|are|does|do|can|should|will)\b');

  static bool _isFollowUp(String lower) {
    if (_followUpStart.hasMatch(lower)) return true;
    final words = lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (words <= 3 && !_selfContainedStart.hasMatch(lower)) return true; // "for Delhi?", "in 2027?"
    return words <= 6 && _pronoun.hasMatch(lower);
  }

  static Set<FactKind> _factKinds(String lower) => {
        if (RegExp(r'\b(dates?|deadlines?|due|when|expir\w*|timelines?|schedule|milestones?|renewal)\b')
            .hasMatch(lower)) ...[FactKind.date, FactKind.duration],
        if (RegExp(r'\b(notice|period|durations?|how long|days|weeks|months|within)\b').hasMatch(lower))
          FactKind.duration,
        if (RegExp(r'\b(fees?|costs?|prices?|amounts?|money|charges?|limits?|caps?|allowances?|salary|'
                r'pay|payments?|rent|budget|expenses?|spend|revenue|totals?|inr|rupees|dollars)\b')
            .hasMatch(lower))
          FactKind.money,
        if (RegExp(r'\b(percent|percentage|rates?|%|growth|interest)\b').hasMatch(lower)) FactKind.percent,
        if (RegExp(r'\b(clauses?|sections?|ids?|references?|codes?)\b').hasMatch(lower)) FactKind.id,
      };

  static String _cleanTopic(String topic) => topic
      .replaceAll(RegExp(r'^(the|a|an|this|that|our|my)\s+'), '')
      .replaceAll(RegExp(r'\s+(in|from|of) (the|this|my) (document|doc|pdf|file|report)$'), '')
      .replaceAll(RegExp(r'[.?!]+$'), '')
      .trim();

  // --- Document names -------------------------------------------------------

  static const _nameStopWords = {
    'pdf', 'document', 'doc', 'docs', 'file', 'final', 'draft', 'copy', 'scan', 'scanned',
    'version', 'the', 'and', 'for', 'with', 'from', 'new', 'old', 'signed', 'updated',
  };

  /// Distinctive words of a file name: "Lease agreement 2026.pdf" -> {lease, agreement}.
  static Set<String> nameWords(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'\.[a-z0-9]{2,5}$'), '')
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length >= 4 && !_nameStopWords.contains(w) && !RegExp(r'^\d+$').hasMatch(w))
      .toSet();

  /// The one document whose name the text mentions, if exactly one matches.
  static String? _namedDocument(String lower, List<({String id, String name})> documents) {
    if (documents.length < 2) return null; // nothing to narrow
    final words = lower.split(RegExp(r'[^a-z0-9]+')).toSet();
    String? best;
    var bestScore = 0;
    var tie = false;
    for (final doc in documents) {
      final score = nameWords(doc.name).where(words.contains).length;
      if (score > bestScore) {
        best = doc.id;
        bestScore = score;
        tie = false;
      } else if (score == bestScore && score > 0) {
        tie = true;
      }
    }
    return bestScore > 0 && !tie ? best : null;
  }

  static bool _isJustDocumentName(String topic, List<({String id, String name})> documents, String docId) {
    final name = documents.firstWhere((d) => d.id == docId).name;
    final topicWords = topic.split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 4).toSet();
    final docWords = {...nameWords(name), 'document', 'report', 'file', 'agreement', 'contract'};
    return topicWords.isNotEmpty && topicWords.every(docWords.contains);
  }
}
