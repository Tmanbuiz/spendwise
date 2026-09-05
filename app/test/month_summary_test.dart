import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/models/app_transaction.dart';
import 'package:spendwise/data/models/budget.dart';
import 'package:spendwise/data/month_summary.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

AppTransaction tx({
  required int cents,
  required DateTime when,
  TransactionEventType type = TransactionEventType.purchase,
  SpendCategory category = SpendCategory.groceries,
  bool excluded = false,
}) {
  return AppTransaction(
    id: '${when.microsecondsSinceEpoch}-$cents',
    eventType: type,
    amountCents: cents,
    currency: 'CAD',
    occurredAt: when,
    category: category,
    source: TransactionSource.notification,
    excludedByUser: excluded,
  );
}

void main() {
  final september = MonthWindow(DateTime(2026, 9), DateTime(2026, 10));

  group('only purchases reach the monthly total', () {
    test('purchases are summed', () {
      final summary = MonthSummary.build(
        transactions: <AppTransaction>[
          tx(cents: 1000, when: DateTime(2026, 9, 2)),
          tx(cents: 2500, when: DateTime(2026, 9, 15)),
        ],
        window: september,
      );

      expect(summary.totalSpentCents, 3500);
      expect(summary.transactionCount, 2);
    });

    test('refunds, payments, transfers and declines are all excluded', () {
      final summary = MonthSummary.build(
        transactions: <AppTransaction>[
          tx(cents: 1000, when: DateTime(2026, 9, 2)),
          tx(
            cents: 5000,
            when: DateTime(2026, 9, 3),
            type: TransactionEventType.refund,
          ),
          tx(
            cents: 50000,
            when: DateTime(2026, 9, 4),
            type: TransactionEventType.payment,
          ),
          tx(
            cents: 30000,
            when: DateTime(2026, 9, 5),
            type: TransactionEventType.transfer,
          ),
          tx(
            cents: 8999,
            when: DateTime(2026, 9, 6),
            type: TransactionEventType.declined,
          ),
        ],
        window: september,
      );

      expect(summary.totalSpentCents, 1000);
      expect(summary.transactionCount, 1);
    });

    test('a user-excluded purchase is left out', () {
      final summary = MonthSummary.build(
        transactions: <AppTransaction>[
          tx(cents: 1000, when: DateTime(2026, 9, 2)),
          tx(cents: 9999, when: DateTime(2026, 9, 3), excluded: true),
        ],
        window: september,
      );

      expect(summary.totalSpentCents, 1000);
    });

    test('transactions outside the window are ignored', () {
      final summary = MonthSummary.build(
        transactions: <AppTransaction>[
          tx(cents: 1000, when: DateTime(2026, 8, 31, 23, 59)),
          tx(cents: 2000, when: DateTime(2026, 9, 1)),
          tx(cents: 4000, when: DateTime(2026, 10, 1)),
        ],
        window: september,
      );

      expect(summary.totalSpentCents, 2000);
    });
  });

  group('category breakdown', () {
    test('groups and sorts by amount, largest first', () {
      final summary = MonthSummary.build(
        transactions: <AppTransaction>[
          tx(cents: 1000, when: DateTime(2026, 9, 2)),
          tx(cents: 500, when: DateTime(2026, 9, 3)),
          tx(
            cents: 4000,
            when: DateTime(2026, 9, 4),
            category: SpendCategory.dining,
          ),
        ],
        window: september,
      );

      expect(summary.byCategory.first.category, SpendCategory.dining);
      expect(summary.byCategory.first.amountCents, 4000);
      expect(summary.byCategory[1].category, SpendCategory.groceries);
      expect(summary.byCategory[1].amountCents, 1500);
    });

    test('shares sum to one', () {
      final summary = MonthSummary.build(
        transactions: <AppTransaction>[
          tx(cents: 2500, when: DateTime(2026, 9, 2)),
          tx(
            cents: 7500,
            when: DateTime(2026, 9, 3),
            category: SpendCategory.dining,
          ),
        ],
        window: september,
      );

      final total = summary.byCategory
          .fold<double>(0, (sum, c) => sum + c.shareOfTotal);
      expect(total, closeTo(1.0, 0.0001));
    });

    test('categories with no spending are omitted', () {
      final summary = MonthSummary.build(
        transactions: <AppTransaction>[
          tx(cents: 1000, when: DateTime(2026, 9, 2)),
        ],
        window: september,
      );

      expect(summary.byCategory, hasLength(1));
    });
  });

  group('month window', () {
    test('defaults to calendar months', () {
      final window = MonthWindow.forDate(DateTime(2026, 9, 15));
      expect(window.start, DateTime(2026, 9));
      expect(window.end, DateTime(2026, 10));
    });

    test('honours a custom start day', () {
      final window =
          MonthWindow.forDate(DateTime(2026, 9, 20), monthStartDay: 15);
      expect(window.start, DateTime(2026, 9, 15));
      expect(window.end, DateTime(2026, 10, 15));
    });

    test('a date before the start day belongs to the previous period', () {
      final window =
          MonthWindow.forDate(DateTime(2026, 9, 10), monthStartDay: 15);
      expect(window.start, DateTime(2026, 8, 15));
      expect(window.end, DateTime(2026, 9, 15));
    });

    test('the previous window abuts this one exactly', () {
      final window = MonthWindow.forDate(DateTime(2026, 9, 15));
      expect(window.previous.end, window.start);
    });
  });

  group('month comparison', () {
    test('reports the difference against last month', () {
      final transactions = <AppTransaction>[
        tx(cents: 10000, when: DateTime(2026, 9, 2)),
        tx(cents: 8000, when: DateTime(2026, 8, 2)),
      ];

      final comparison = MonthComparison(
        current: MonthSummary.build(
          transactions: transactions,
          window: september,
        ),
        previous: MonthSummary.build(
          transactions: transactions,
          window: september.previous,
        ),
      );

      expect(comparison.differenceCents, 2000);
      expect(comparison.spentMore, isTrue);
      expect(comparison.percentChange, closeTo(0.25, 0.0001));
    });

    test('percent change is null when last month was empty', () {
      final comparison = MonthComparison(
        current: MonthSummary.build(
          transactions: <AppTransaction>[
            tx(cents: 10000, when: DateTime(2026, 9, 2)),
          ],
          window: september,
        ),
        previous: MonthSummary.build(
          transactions: const <AppTransaction>[],
          window: september.previous,
        ),
      );

      // "Up 100% from nothing" would be misleading, so it is not shown.
      expect(comparison.percentChange, isNull);
    });
  });

  group('budget progress', () {
    test('the overall budget measures total spending', () {
      final summary = MonthSummary.build(
        transactions: <AppTransaction>[
          tx(cents: 30000, when: DateTime(2026, 9, 2)),
        ],
        window: september,
      );

      final progress = buildBudgetProgress(
        budgets: <Budget>[const Budget(id: 'b1', amountCents: 100000)],
        summary: summary,
      );

      expect(progress.single.spentCents, 30000);
      expect(progress.single.remainingCents, 70000);
      expect(progress.single.isOverBudget, isFalse);
      expect(progress.single.fraction, closeTo(0.3, 0.0001));
    });

    test('a category budget measures only that category', () {
      final summary = MonthSummary.build(
        transactions: <AppTransaction>[
          tx(cents: 30000, when: DateTime(2026, 9, 2)),
          tx(
            cents: 9000,
            when: DateTime(2026, 9, 3),
            category: SpendCategory.dining,
          ),
        ],
        window: september,
      );

      final progress = buildBudgetProgress(
        budgets: <Budget>[
          const Budget(
            id: 'b2',
            amountCents: 20000,
            category: SpendCategory.dining,
          ),
        ],
        summary: summary,
      );

      expect(progress.single.spentCents, 9000);
    });

    test('going over budget is flagged and the bar stays clamped', () {
      final summary = MonthSummary.build(
        transactions: <AppTransaction>[
          tx(cents: 150000, when: DateTime(2026, 9, 2)),
        ],
        window: september,
      );

      final progress = buildBudgetProgress(
        budgets: <Budget>[const Budget(id: 'b3', amountCents: 100000)],
        summary: summary,
      ).single;

      expect(progress.isOverBudget, isTrue);
      expect(progress.remainingCents, -50000);
      expect(progress.fraction, 1.0);
    });
  });
}
