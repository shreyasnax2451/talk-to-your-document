// End-to-end evaluation of question answering: planning, retrieval and the
// answering model, on real PDFs.
//
// Opt-in, because it needs the model files and takes a few minutes. Run it
// after changing retrieval, prompts or models:
//
//   DOCCHAT_EVAL_DIR=<dir> LLAMADART_NATIVE_LIB_DIR=<repo>/build/native_assets/windows \
//     flutter test test/eval/answer_eval_test.dart
//
// <dir>/models must hold the GGUF files from ModelConfig (the resources pack
// and the answering model to test). sample-docs/employee-handbook-2026.pdf is
// always indexed; put a copy of the architecture guide PDF at <dir>/guide.pdf
// to also run the multi-document cases. Set DOCCHAT_EVAL_MODEL to an answering
// model id (default: the high accuracy model).

import 'dart:io';

import 'package:docchat/models/document.dart';
import 'package:docchat/services/answer_service.dart';
import 'package:docchat/services/context_builder.dart';
import 'package:docchat/services/document_indexer.dart';
import 'package:docchat/services/document_store.dart';
import 'package:docchat/services/embedding_service.dart';
import 'package:docchat/services/model_config.dart';
import 'package:docchat/services/model_manager.dart';
import 'package:docchat/services/numeric_calculator.dart';
import 'package:docchat/services/query_planner.dart';
import 'package:docchat/services/retriever.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdfrx/pdfrx.dart';

final _evalDir = Platform.environment['DOCCHAT_EVAL_DIR'];

class _Paths extends PathProviderPlatform {
  final String root;
  _Paths(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'tmp');
  @override
  Future<String?> getApplicationCachePath() async => p.join(root, 'cache');
}

/// Models are already on disk; nothing to download.
class _LocalModels extends ModelManager {
  @override
  bool isReady(ModelSpec model) => true;
  @override
  Future<void> waitUntilReady(ModelSpec model, {void Function(double progress)? onProgress}) async {}
}

class _Case {
  final String question;
  final String? previous;
  final QueryIntent intent;

  /// Every one of these must appear in the answer (case-insensitive).
  final List<String> mustContain;
  final bool needsGuide;

  const _Case(this.question, this.intent, this.mustContain, {this.previous, this.needsGuide = false});
}

const _cases = [
  _Case('How many earned leave days can I carry forward?', QueryIntent.lookup, ['10']),
  _Case('and in other cities?', QueryIntent.lookup, ['5,000'],
      previous: 'What is the hotel cap per night in metro cities?'),
  _Case('What is the notice period after probation?', QueryIntent.lookup, ['60 days']),
  _Case('Summarize the leave policy', QueryIntent.sectionSummary, ['18', '10']),
  _Case('Summarize this document', QueryIntent.documentSummary, ['Larkspur']),
  _Case('List all the deadlines', QueryIntent.list, ['30 days', '14 days', '4 hours', '45 days']),
  _Case('Compare earned leave and sick leave', QueryIntent.compare, ['18', '8']),
  _Case('What is the total of the metro hotel cap and the metro daily allowance?', QueryIntent.numeric,
      ['Total: INR 9,500']),
  _Case('How much more is the hotel cap in metro cities than in other cities?', QueryIntent.numeric,
      ['Difference: INR 2,000']),
  _Case('How many days from the handbook effective date until 31 December 2026?', QueryIntent.numeric,
      ['274 days']),
  _Case('thanks', QueryIntent.smallTalk, ['welcome']),
  _Case('What is the company policy on pets in the office?', QueryIntent.lookup, [AnswerService.notFoundReply]),
  _Case('Which answering model is recommended for 6 GB phones?', QueryIntent.lookup, ['1.7B'], needsGuide: true),
  _Case('In the handbook, what is the notice period during probation?', QueryIntent.lookup, ['15 days'],
      needsGuide: true),
  _Case('Summarize all my documents', QueryIntent.documentSummary, ['handbook', 'guide'], needsGuide: true),
];

void main() {
  test('answer evaluation', () async {
    final root = p.join(_evalDir!, 'run');
    final dir = Directory(root);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    for (final sub in ['tmp', 'cache']) {
      Directory(p.join(root, sub)).createSync(recursive: true);
    }
    // Model files are looked up in <support>/models.
    Link(p.join(root, 'models')).createSync(p.join(_evalDir!, 'models'));
    PathProviderPlatform.instance = _Paths(root);
    await pdfrxFlutterInitialize();

    final store = await DocumentStore.open();
    final embeddings = EmbeddingService(_LocalModels());
    final indexer = DocumentIndexer(store: store, embeddings: embeddings);
    final guide = File(p.join(_evalDir!, 'guide.pdf'));
    final pdfs = [
      ('hb', 'sample-docs/employee-handbook-2026.pdf', 'employee-handbook-2026.pdf'),
      if (guide.existsSync()) ('guide', guide.path, 'On-device PDF QA guide.pdf'),
    ];
    final names = <String, String>{};
    for (final (id, path, name) in pdfs) {
      final doc = Document(
          id: id, name: name, pageCount: 0, uploadDate: DateTime.now(), status: DocumentStatus.processing);
      doc.filePath = await DocumentIndexer.importFile(path, id);
      store.upsertDocument(doc);
      await indexer.index(docId: id, title: name, filePath: doc.filePath!, onPages: (_) {}, onProgress: (_) {});
      names[id] = name;
      await Future<void>.delayed(const Duration(milliseconds: 5)); // distinct upload order
    }

    final contexts = ContextBuilder(store: store, retriever: Retriever(store: store, embeddings: embeddings));
    final answers = AnswerService();
    final model = ModelConfig.answeringModelById(Platform.environment['DOCCHAT_EVAL_MODEL']) ??
        ModelConfig.qwen3_4b;
    final failures = <String>[];

    for (final c in _cases) {
      if (c.needsGuide && !guide.existsSync()) continue;
      final clock = Stopwatch()..start();
      final plan = QueryPlanner.plan(c.question, previousQuestion: c.previous, documents: store.readyDocuments());
      var answer = '';
      if (plan.intent == QueryIntent.smallTalk) {
        answer = QueryPlanner.smallTalkReply(c.question);
      } else {
        final context = await contexts.build(plan);
        final passages = AnswerService.toPassages(context.passages, names);
        if (passages.isEmpty) {
          answer = AnswerService.notFoundReply;
        } else {
          if (plan.intent == QueryIntent.numeric) {
            final values = await answers.extractValues(model, plan, passages);
            if (values != null) answer = NumericCalculator.compute(plan.numericOp!, values) ?? '';
          }
          if (answer.isEmpty) {
            answer = await answers
                .answer(model, plan, passages,
                    previous: c.previous == null ? null : (question: c.previous!, answer: ''))
                .join();
          }
        }
      }
      final missing = c.mustContain.where((s) => !answer.toLowerCase().contains(s.toLowerCase())).toList();
      final ok = plan.intent == c.intent && missing.isEmpty;
      // ignore: avoid_print
      print('${ok ? 'PASS' : 'FAIL'} ${(clock.elapsedMilliseconds / 1000).toStringAsFixed(1)}s '
          '[${plan.intent.name}] ${c.question}\n     ${answer.trim().replaceAll('\n', ' | ')}');
      if (!ok) {
        failures.add('${c.question}: intent ${plan.intent.name} (want ${c.intent.name}), missing $missing');
      }
    }

    await answers.dispose();
    await embeddings.dispose();
    store.close();
    expect(failures, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 40)), skip: _evalDir == null ? 'Set DOCCHAT_EVAL_DIR to run' : false);
}
