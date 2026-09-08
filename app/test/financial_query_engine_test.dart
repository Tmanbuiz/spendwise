import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/models/app_transaction.dart';
import 'package:spendwise/data/models/financial_rule.dart';
import 'package:spendwise/services/financial_query_engine.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

void main() {
  const engine = FinancialQueryEngine();

  AppTransaction tx(
    String id,
    int cents,
    DateTime at,
    String merchant, {
    SpendCategory category = SpendCategory.shopping,
    TransactionEventType type = TransactionEventType.purchase,
  }) {
    return AppTransaction(
      id: id,
      eventType: type,
      amountCents: cents,
      currency: 'CAD',
      occurredAt: at,
      category: category,
      source: TransactionSource.statement,
      merchant: merchant,
      merchantNormalized: merchant.toUpperCase(),
    );
  }

  final transactions = <AppTransaction>[
    tx(
      'j1',
      10000,
      DateTime(2026, 7, 5),
      'Walmart',
      category: SpendCategory.groceries,
    ),
    tx(
      'j2',
      5000,
      DateTime(2026, 7, 12),
      'Victory Meat Market',
      category: SpendCategory.groceries,
    ),
    tx('a1', 22000, DateTime(2026, 8, 2), 'Costco', category: SpendCategory.groceries),
    tx('w1', 65000, DateTime(2026, 7, 20), 'Wealthsimple Investments Inc.'),
    tx('s1', 40000, DateTime(2026, 7, 22), 'Spouse transfer'),
  ];

  const rules = <FinancialRule>[
    FinancialRule(
      id: 'r1',
      pattern: 'Wealthsimple',
      kind: FinancialRuleKind.investment,
    ),
    FinancialRule(
      id: 'r2',
      pattern: 'Spouse transfer',
      kind: FinancialRuleKind.internalTransfer,
    ),
  ];

  test('totals a named month after Financial Memory rules', () {
    final answer = engine.answer(
      'How much did I spend in July 2026?',
      transactions: transactions,
      rules: rules,
      currency: 'CAD',
      now: DateTime(2026, 9, 1),
    );

    expect(answer.metrics.first.amountCents, 15000);
  });

  test('filters by category', () {
    final answer = engine.answer(
      'How much did I spend on groceries in July 2026?',
      transactions: transactions,
      rules: rules,
      currency: 'CAD',
      now: DateTime(2026, 9, 1),
    );

    expect(answer.title, 'Groceries');
    expect(answer.metrics.first.amountCents, 15000);
  });

  test('filters by a known merchant', () {
    final answer = engine.answer(
      'How much at Walmart in July 2026?',
      transactions: transactions,
      rules: rules,
      currency: 'CAD',
      now: DateTime(2026, 9, 1),
    );

    expect(answer.title, 'Walmart');
    expect(answer.metrics.first.amountCents, 10000);
  });

  test('investment query uses explicit Financial Memory rules', () {
    final answer = engine.answer(
      'How much did I invest in July 2026?',
      transactions: transactions,
      rules: rules,
      currency: 'CAD',
      now: DateTime(2026, 9, 1),
    );

    expect(answer.title, 'Investments & savings');
    expect(answer.metrics.first.amountCents, 65000);
  });

  test('internal transfers and investments are not counted as spending', () {
    final answer = engine.answer(
      'How much did I spend in July 2026?',
      transactions: transactions,
      rules: rules,
      currency: 'CAD',
      now: DateTime(2026, 9, 1),
    );

    expect(answer.metrics.first.amountCents, 15000);
  });

  test('top merchant ranking is rule-aware', () {
    final answer = engine.answer(
      'What are my top merchants in 2026?',
      transactions: transactions,
      rules: rules,
      currency: 'CAD',
      now: DateTime(2026, 9, 1),
    );

    expect(answer.title, 'Top merchants');
    expect(answer.metrics.first.label, contains('Costco'));
    expect(answer.metrics.first.amountCents, 22000);
  });

  test('compares two months', () {
    final answer = engine.answer(
      'Compare July vs August 2026',
      transactions: transactions,
      rules: rules,
      currency: 'CAD',
      now: DateTime(2026, 9, 1),
    );

    expect(answer.metrics[0].amountCents, 15000);
    expect(answer.metrics[1].amountCents, 22000);
    expect(answer.metrics[2].amountCents, 7000);
  });

  test('mortgage answer refuses to infer approval from spending alone', () {
    final answer = engine.answer(
      'Can I afford a house mortgage?',
      transactions: transactions,
      rules: rules,
      currency: 'CAD',
      now: DateTime(2026, 9, 1),
    );

    expect(answer.title, 'Mortgage readiness');
    expect(answer.body, contains('would be irresponsible'));
  });
}
