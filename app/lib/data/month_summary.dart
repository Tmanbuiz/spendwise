import 'package:spendwise_parser/spendwise_parser.dart';

import 'models/app_transaction.dart';
import 'models/budget.dart';

/// The month the dashboard is reporting on.
class MonthWindow {
  const MonthWindow(this.start, this.end);

  /// Inclusive start.
  final DateTime start;

  /// Exclusive end.
  final DateTime end;

  bool contains(DateTime when) => !when.isBefore(start) && when.isBefore(end);

  /// The window for the period containing [now], honouring a custom
  /// [monthStartDay] for users whose pay cycle is not the 1st.
  static MonthWindow forDate(DateTime now, {int monthStartDay = 1}) {
    final day = monthStartDay.clamp(1, 28).toInt();
    final start = now.day >= day
        ? DateTime(now.year, now.month, day)
        : DateTime(now.year, now.month - 1, day);
    final end = DateTime(start.year, start.month + 1, day);
    return MonthWindow(start, end);
  }

  /// The window immediately before this one.
  MonthWindow get previous {
    final previousStart = DateTime(start.year, start.month - 1, start.day);
    return MonthWindow(previousStart, start);
  }
}

/// Everything the dashboard needs about one month, computed in one pass.
class MonthSummary {
  const MonthSummary({
    required this.window,
    required this.totalSpentCents,
    required this.byCategory,
    required this.transactionCount,
    required this.currency,
  });

  final MonthWindow window;
  final int totalSpentCents;

  /// Spending per category, highest first. Categories with no spending are
  /// omitted so the chart and legend stay readable.
  final List<CategoryTotal> byCategory;

  final int transactionCount;
  final String currency;

  double get totalSpent => totalSpentCents / 100.0;

  bool get isEmpty => transactionCount == 0;

  /// Aggregates [transactions] over [window].
  ///
  /// Only transactions where `countsAsSpending` is true are included, which is
  /// the single place the product rule is applied to reporting: refunds, card
  /// payments, transfers, declines and user-excluded rows all fall out here.
  static MonthSummary build({
    required List<AppTransaction> transactions,
    required MonthWindow window,
    String currency = 'CAD',
  }) {
    final totals = <SpendCategory, int>{};
    var total = 0;
    var count = 0;

    for (final transaction in transactions) {
      if (!window.contains(transaction.occurredAt)) continue;
      if (!transaction.countsAsSpending) continue;
      if (transaction.currency != currency) continue;
      total += transaction.amountCents;
      count++;
      totals.update(
        transaction.category,
        (value) => value + transaction.amountCents,
        ifAbsent: () => transaction.amountCents,
      );
    }

    final byCategory =
        totals.entries
            .map(
              (e) => CategoryTotal(
                category: e.key,
                amountCents: e.value,
                shareOfTotal: total == 0 ? 0 : e.value / total,
              ),
            )
            .toList()
          ..sort((a, b) => b.amountCents.compareTo(a.amountCents));

    return MonthSummary(
      window: window,
      totalSpentCents: total,
      byCategory: byCategory,
      transactionCount: count,
      currency: currency,
    );
  }
}

class CategoryTotal {
  const CategoryTotal({
    required this.category,
    required this.amountCents,
    required this.shareOfTotal,
  });

  final SpendCategory category;
  final int amountCents;

  /// 0..1 of the month's total spending.
  final double shareOfTotal;

  double get amount => amountCents / 100.0;
}

/// This month measured against last month.
class MonthComparison {
  const MonthComparison({required this.current, required this.previous});

  final MonthSummary current;
  final MonthSummary previous;

  int get differenceCents => current.totalSpentCents - previous.totalSpentCents;

  bool get spentMore => differenceCents > 0;

  /// Null when last month had no spending, because "up 100%" from zero is
  /// meaningless and showing it would be misleading.
  double? get percentChange {
    if (previous.totalSpentCents == 0) return null;
    return differenceCents / previous.totalSpentCents;
  }
}

/// Pairs each budget with what has been spent against it this month.
List<BudgetProgress> buildBudgetProgress({
  required List<Budget> budgets,
  required MonthSummary summary,
}) {
  return budgets.map((budget) {
    if (budget.isOverall) {
      return BudgetProgress(
        budget: budget,
        spentCents: summary.totalSpentCents,
      );
    }
    final match = summary.byCategory
        .where((c) => c.category == budget.category)
        .fold<int>(0, (sum, c) => sum + c.amountCents);
    return BudgetProgress(budget: budget, spentCents: match);
  }).toList();
}
