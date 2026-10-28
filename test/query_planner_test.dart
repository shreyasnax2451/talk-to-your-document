import 'package:docchat/services/fact_extractor.dart';
import 'package:docchat/services/query_planner.dart';
import 'package:flutter_test/flutter_test.dart';

const docs = [
  (id: 'lease', name: 'Lease agreement 2026.pdf'),
  (id: 'hb', name: 'employee-handbook-2026.pdf'),
  (id: 'q3', name: 'Q3 financial report.pdf'),
];

QueryIntent intentOf(String q, {String? previous}) =>
    QueryPlanner.plan(q, previousQuestion: previous, documents: docs).intent;

void expectIntent(QueryIntent intent, List<String> questions) {
  for (final q in questions) {
    expect(intentOf(q), intent, reason: q);
  }
}

void main() {
  test('small talk', () {
    expectIntent(QueryIntent.smallTalk,
        ['hi', 'Hello!', 'thanks', 'Thank you so much', 'ok', 'Great.', 'bye', 'good morning']);
  });

  test('whole-document summaries', () {
    expectIntent(QueryIntent.documentSummary, [
      'Summarize this document',
      'summarise the pdf.',
      'Please summarize',
      'Can you summarize this report?',
      'Give me a summary',
      'Give me a brief overview of this document',
      'Key points',
      'What are the main takeaways?',
      'TL;DR',
      'What is this document about?',
      "What's this about?",
      'Summarize all my documents',
      'Summarize the lease', // names a whole document
    ]);
  });

  test('section summaries carry the topic as the search query', () {
    expectIntent(QueryIntent.sectionSummary, [
      'Summarize the leave policy',
      'Give me a summary of the travel rules',
      'Explain the notice period',
      'Describe the expense reimbursement process',
      'What does the section on resignation say?',
      'What does clause EXP-12 say?', // explaining one clause
    ]);
    expect(QueryPlanner.plan('Summarize the leave policy', documents: docs).searchQuery, 'leave policy');
  });

  test('lists', () {
    expectIntent(QueryIntent.list, [
      'List all the deadlines',
      'List the leave types',
      'What are all the fees?',
      'Show me every clause about termination',
      'What are the allowances?',
      'Which documents mention rent?',
    ]);
  });

  test('comparisons split into two sides', () {
    expectIntent(QueryIntent.compare, [
      'Compare the leave policy and the travel policy',
      'Compare Q2 with Q3',
      'What is the difference between sick leave and earned leave?',
      'How does the Basic plan differ from the Pro plan?',
      'metro hotel cap vs other cities',
    ]);
    final p = QueryPlanner.plan('Compare the leave policy and the travel policy', documents: docs);
    expect(p.compareSides, ['leave policy', 'travel policy']);
  });

  test('numeric questions pick an operation', () {
    NumericOp? op(String q) => QueryPlanner.plan(q, documents: docs).numericOp;
    expect(op('What is the total of all fees?'), NumericOp.sum);
    expect(op('Add up the metro hotel cap and daily allowance'), NumericOp.sum);
    expect(op('What is the average hotel limit?'), NumericOp.average);
    expect(op('How many days between 1 April 2026 and 31 December 2026?'), NumericOp.daysBetween);
    expect(op('How long until the lease expires?'), NumericOp.daysBetween);
    expect(op('How much more is the metro hotel cap than elsewhere?'), NumericOp.difference);
    expect(op('How many clauses are there?'), NumericOp.count);
    expect(QueryPlanner.plan('Total of all fees', documents: docs).factKinds, contains(FactKind.money));
  });

  test('lookups stay lookups', () {
    expectIntent(QueryIntent.lookup, [
      'How many earned leave days can I carry forward?',
      'What is the hotel limit per night in Mumbai?',
      'When does the lease end?',
      'Who is the policy owner?',
      'What does it cost?',
      'Is sick leave paid?',
    ]);
  });

  test('follow-ups merge the previous question into the search', () {
    const prev = 'What is the hotel cap in metro cities?';
    for (final q in ['and in other cities?', 'What about Delhi?', 'for Pune?', 'Is it per night?']) {
      final p = QueryPlanner.plan(q, previousQuestion: prev, documents: docs);
      expect(p.isFollowUp, isTrue, reason: q);
      expect(p.searchQuery, startsWith(prev), reason: q);
    }
    for (final q in ['List all deadlines', 'When does the lease end?', 'How many earned leave days carry forward?']) {
      final p = QueryPlanner.plan(q, previousQuestion: prev, documents: docs);
      expect(p.isFollowUp, isFalse, reason: q);
      expect(p.searchQuery, q, reason: q);
    }
  });

  test('a chain of follow-ups stays on the topic that started it', () {
    final history = [
      'What is the hotel cap in metro cities?',
      'and in other cities?',
      'thanks', // small talk is skipped
    ];
    final context = QueryPlanner.contextOf(history);
    expect(context.previous, 'and in other cities?');
    expect(context.topic, 'What is the hotel cap in metro cities?');

    final p = QueryPlanner.plan('what about Pune?',
        previousQuestion: context.previous, topicQuestion: context.topic, documents: docs);
    expect(p.isFollowUp, isTrue);
    expect(p.searchQuery, 'What is the hotel cap in metro cities? what about Pune?');
  });

  test('a new self-contained question starts a new topic', () {
    final context = QueryPlanner.contextOf([
      'What is the hotel cap in metro cities?',
      'and in other cities?',
      'How many sick leave days do I get?',
    ]);
    expect(context.topic, 'How many sick leave days do I get?');
    final p = QueryPlanner.plan('and is it paid?',
        previousQuestion: context.previous, topicQuestion: context.topic, documents: docs);
    expect(p.searchQuery, startsWith('How many sick leave days'));
  });

  test('no history means no follow-up', () {
    final context = QueryPlanner.contextOf(['hi', 'thanks']);
    expect(context.previous, isNull);
    expect(context.topic, isNull);
    expect(QueryPlanner.plan('and in Delhi?', documents: docs).isFollowUp, isFalse);
  });

  test('a question naming one document narrows to it', () {
    expect(QueryPlanner.plan('When does the lease end?', documents: docs).namedDocId, 'lease');
    expect(QueryPlanner.plan('What is the leave policy in the handbook?', documents: docs).namedDocId, 'hb');
    expect(QueryPlanner.plan('What is the notice period?', documents: docs).namedDocId, isNull);
    // With one document there is nothing to narrow.
    expect(QueryPlanner.plan('When does the lease end?', documents: [docs.first]).namedDocId, isNull);
  });

  test('fact kinds follow the question wording', () {
    Set<FactKind> kinds(String q) => QueryPlanner.plan(q, documents: docs).factKinds;
    expect(kinds('List all the deadlines'), containsAll([FactKind.date, FactKind.duration]));
    expect(kinds('What are all the fees?'), contains(FactKind.money));
    expect(kinds('List every clause ID'), contains(FactKind.id));
  });
}
