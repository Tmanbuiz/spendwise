import 'dart:math' as math;

import 'models/app_transaction.dart';
import 'models/budget.dart';
import 'month_summary.dart';

/// Calendar arithmetic deliberately ignores DST and month-end overflow.
int calendarDays(DateTime start, DateTime end) => DateTime.utc(
  end.year,
  end.month,
  end.day,
).difference(DateTime.utc(start.year, start.month, start.day)).inDays;

MonthWindow reportingWindow(DateTime now, int offset, int startDay) {
  final current = MonthWindow.forDate(now, monthStartDay: startDay);
  final start = DateTime(
    current.start.year,
    current.start.month + offset,
    current.start.day,
  );
  return MonthWindow(start, DateTime(start.year, start.month + 1, start.day));
}

class MerchantTotal {
  const MerchantTotal(this.name, this.amountCents, this.count);
  final String name;
  final int amountCents;
  final int count;
}

/// Read-only insights derived from recorded purchases; never changes storage.
class SpendingInsights {
  SpendingInsights({
    required this.window,
    required this.now,
    required List<AppTransaction> transactions,
    required this.currency,
  }) {
    purchases = transactions
        .where(
          (t) =>
              t.countsAsSpending &&
              t.currency == currency &&
              !t.occurredAt.isAfter(now),
        )
        .toList();
    current = MonthSummary.build(
      transactions: purchases,
      window: window,
      currency: currency,
    );
    final previous = window.previous;
    final previousDays = calendarDays(previous.start, previous.end);
    comparisonDays = math.min(elapsedDays, previousDays);
    final currentComparableEnd = DateTime(
      window.start.year,
      window.start.month,
      window.start.day + comparisonDays,
    );
    final previousComparableEnd = DateTime(
      previous.start.year,
      previous.start.month,
      previous.start.day + comparisonDays,
    );
    comparable = MonthComparison(
      current: MonthSummary.build(
        transactions: purchases,
        window: MonthWindow(window.start, currentComparableEnd),
        currency: currency,
      ),
      previous: MonthSummary.build(
        transactions: purchases,
        window: MonthWindow(previous.start, previousComparableEnd),
        currency: currency,
      ),
    );
    dailyCents = List<int>.filled(totalDays, 0);
    final merchants = <String, List<AppTransaction>>{};
    for (final t in purchases.where((t) => window.contains(t.occurredAt))) {
      final day = calendarDays(window.start, t.occurredAt);
      if (day >= 0 && day < totalDays) dailyCents[day] += t.amountCents;
      final key = (t.merchantNormalized ?? t.displayMerchant)
          .trim()
          .toLowerCase();
      merchants.putIfAbsent(key, () => []).add(t);
    }
    topMerchants =
        merchants.values
            .map(
              (items) => MerchantTotal(
                items.first.displayMerchant,
                items.fold<int>(0, (sum, t) => sum + t.amountCents),
                items.length,
              ),
            )
            .toList()
          ..sort((a, b) => b.amountCents.compareTo(a.amountCents));
    history = List.generate(6, (i) {
      final start = DateTime(
        window.start.year,
        window.start.month - 5 + i,
        window.start.day,
      );
      return MonthSummary.build(
        transactions: purchases,
        window: MonthWindow(
          start,
          DateTime(start.year, start.month + 1, start.day),
        ),
        currency: currency,
      );
    });
  }

  final MonthWindow window;
  final DateTime now;
  final String currency;
  late final List<AppTransaction> purchases;
  late final MonthSummary current;
  late final MonthComparison comparable;
  late final int comparisonDays;
  late final List<int> dailyCents;
  late final List<MerchantTotal> topMerchants;
  late final List<MonthSummary> history;

  int get totalDays => calendarDays(window.start, window.end);
  bool get isCurrent => window.contains(now);
  int get elapsedDays => now.isBefore(window.start)
      ? 0
      : (calendarDays(window.start, now) + 1).clamp(0, totalDays);
  int get daysLeft => isCurrent ? totalDays - elapsedDays + 1 : 0;
  int get dailyAverageCents =>
      elapsedDays == 0 ? 0 : (current.totalSpentCents / elapsedDays).round();
  int get averagePurchaseCents => current.transactionCount == 0
      ? 0
      : (current.totalSpentCents / current.transactionCount).round();

  /// At least a week of dates is needed before exposing a linear estimate.
  int? get projectedCents => !isCurrent || elapsedDays < 7 || current.isEmpty
      ? null
      : (current.totalSpentCents * totalDays / elapsedDays).round();
  int? dailyAllowance(BudgetProgress? budget) =>
      !isCurrent ||
          budget == null ||
          budget.budget.currency != currency ||
          daysLeft == 0
      ? null
      : math.max(0, budget.remainingCents) ~/ daysLeft;
  double get periodFraction => elapsedDays / totalDays;
}
