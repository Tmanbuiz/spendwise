import 'package:spendwise_parser/spendwise_parser.dart';

import 'models/app_transaction.dart';
import 'month_summary.dart';

/// Where a month's money went, or came from.
///
/// Deliberately coarser than [SpendCategory]: this answers "what kind of
/// movement was it", not "what was it for". A month where $700 left the
/// account is a different story depending on whether it was groceries, a
/// transfer into savings or a loan instalment, and the category alone cannot
/// tell those apart.
enum MoneyFlowGroup {
  /// Bought goods or services. The only group that counts as spending.
  spending('Spending', TransactionDirection.outbound),

  /// Moved to another account or another person, including scheduled savings
  /// contributions. Still the user's money, or a gift — either way not
  /// consumption.
  transfersOut('Transfers', TransactionDirection.outbound),

  /// Serviced a debt: a card payment or a loan instalment.
  debtPayments('Loan & card', TransactionDirection.outbound),

  /// Left the account without saying what for.
  otherOut('Other', TransactionDirection.outbound),

  /// Arrived from an employer, a benefit, or someone else.
  deposits('Deposits & pay', TransactionDirection.inbound),

  /// Came back from a merchant.
  refunds('Refunds', TransactionDirection.inbound),

  /// Arrived without saying where from.
  otherIn('Other', TransactionDirection.inbound);

  const MoneyFlowGroup(this.label, this.direction);

  final String label;
  final TransactionDirection direction;

  bool get isOutbound => direction == TransactionDirection.outbound;

  /// Which group [transaction] belongs to.
  ///
  /// Direction is asked first, because it is the one thing the event type
  /// cannot answer: a transfer sent and a transfer received are the same
  /// event type and opposite halves of the report.
  static MoneyFlowGroup of(AppTransaction transaction) {
    if (transaction.isInbound) {
      switch (transaction.eventType) {
        case TransactionEventType.refund:
          return MoneyFlowGroup.refunds;
        case TransactionEventType.transfer:
          return MoneyFlowGroup.deposits;
        case TransactionEventType.purchase:
        case TransactionEventType.payment:
        case TransactionEventType.declined:
        case TransactionEventType.unknown:
          return MoneyFlowGroup.otherIn;
      }
    }

    // Asked through the transaction rather than the event type so a row the
    // user excluded by hand stops being counted as spending here too, exactly
    // as it does everywhere else in the app.
    if (transaction.countsAsSpending) return MoneyFlowGroup.spending;

    switch (transaction.eventType) {
      case TransactionEventType.payment:
        return MoneyFlowGroup.debtPayments;
      case TransactionEventType.transfer:
        return MoneyFlowGroup.transfersOut;
      case TransactionEventType.purchase:
      case TransactionEventType.refund:
      case TransactionEventType.declined:
      case TransactionEventType.unknown:
        return MoneyFlowGroup.otherOut;
    }
  }
}

/// One group's share of a month.
class FlowGroupTotal {
  const FlowGroupTotal({
    required this.group,
    required this.amountCents,
    required this.transactionCount,
  });

  final MoneyFlowGroup group;
  final int amountCents;
  final int transactionCount;
}

/// One month reduced to a single value, for the trend strip.
class MonthPoint {
  const MonthPoint({
    required this.start,
    required this.moneyInCents,
    required this.moneyOutCents,
  });

  /// First day of the window, used both as the label and as the identity.
  final DateTime start;
  final int moneyInCents;
  final int moneyOutCents;

  int valueFor(TransactionDirection direction) =>
      direction == TransactionDirection.inbound
          ? moneyInCents
          : moneyOutCents;
}

/// Everything the Monthly Overview screen shows, computed in one pass.
///
/// The three headline figures reconcile exactly: [netCents] is
/// [moneyInCents] minus [moneyOutCents], and each tab's group totals sum to
/// the figure above them. That is why the headline is "money out" rather than
/// "expenses" — a total labelled expenses that quietly included a transfer
/// into savings would contradict the rule the rest of the app applies.
class MonthlyOverview {
  const MonthlyOverview({
    required this.window,
    required this.moneyInCents,
    required this.moneyOutCents,
    required this.spendingCents,
    required this.groups,
    required this.byCategory,
    required this.trend,
    required this.currency,
    required this.lastTransactionAt,
  });

  final MonthWindow window;

  final int moneyInCents;
  final int moneyOutCents;

  /// The subset of [moneyOutCents] that is actually spending. Shown as a
  /// group rather than as the headline, so the two never disagree.
  final int spendingCents;

  final Map<MoneyFlowGroup, FlowGroupTotal> groups;

  /// Category totals per direction, largest first.
  final Map<TransactionDirection, List<CategoryTotal>> byCategory;

  /// The window and the five before it, oldest first.
  final List<MonthPoint> trend;

  final String currency;

  /// When the most recent transaction in the whole dataset landed, so the
  /// screen can say how current it is instead of implying the month is
  /// complete.
  final DateTime? lastTransactionAt;

  int get netCents => moneyInCents - moneyOutCents;

  bool get isEmpty => groups.isEmpty;

  List<FlowGroupTotal> groupsFor(TransactionDirection direction) {
    final matching = groups.values
        .where((total) => total.group.direction == direction)
        .toList()
      ..sort((a, b) => b.amountCents.compareTo(a.amountCents));
    return matching;
  }

  List<CategoryTotal> categoriesFor(TransactionDirection direction) =>
      byCategory[direction] ?? const <CategoryTotal>[];

  int totalFor(TransactionDirection direction) =>
      direction == TransactionDirection.inbound
          ? moneyInCents
          : moneyOutCents;

  /// Builds the overview for [window], plus the trend over the five windows
  /// before it.
  ///
  /// Declined events are dropped everywhere: no money moved, so counting them
  /// would overstate both sides of the ledger.
  static MonthlyOverview build({
    required List<AppTransaction> transactions,
    required MonthWindow window,
    String currency = 'CAD',
    int trendMonths = 6,
  }) {
    var moneyIn = 0;
    var moneyOut = 0;
    var spending = 0;
    final groups = <MoneyFlowGroup, FlowGroupTotal>{};
    final categories = <TransactionDirection, Map<SpendCategory, int>>{
      TransactionDirection.inbound: <SpendCategory, int>{},
      TransactionDirection.outbound: <SpendCategory, int>{},
    };
    DateTime? latest;

    final windows = _windowsEndingAt(window, trendMonths);
    final trendIn = List<int>.filled(windows.length, 0);
    final trendOut = List<int>.filled(windows.length, 0);

    for (final transaction in transactions) {
      if (transaction.currency != currency) continue;
      if (!transaction.eventType.isSettled) continue;

      if (latest == null || transaction.occurredAt.isAfter(latest)) {
        latest = transaction.occurredAt;
      }

      for (var i = 0; i < windows.length; i++) {
        if (!windows[i].contains(transaction.occurredAt)) continue;
        if (transaction.isInbound) {
          trendIn[i] += transaction.amountCents;
        } else {
          trendOut[i] += transaction.amountCents;
        }
      }

      if (!window.contains(transaction.occurredAt)) continue;

      final group = MoneyFlowGroup.of(transaction);
      final existing = groups[group];
      groups[group] = FlowGroupTotal(
        group: group,
        amountCents: (existing?.amountCents ?? 0) + transaction.amountCents,
        transactionCount: (existing?.transactionCount ?? 0) + 1,
      );

      if (transaction.isInbound) {
        moneyIn += transaction.amountCents;
      } else {
        moneyOut += transaction.amountCents;
        if (transaction.countsAsSpending) spending += transaction.amountCents;
      }

      categories[transaction.direction]!.update(
        transaction.category,
        (value) => value + transaction.amountCents,
        ifAbsent: () => transaction.amountCents,
      );
    }

    return MonthlyOverview(
      window: window,
      moneyInCents: moneyIn,
      moneyOutCents: moneyOut,
      spendingCents: spending,
      groups: groups,
      byCategory: <TransactionDirection, List<CategoryTotal>>{
        for (final entry in categories.entries)
          entry.key: _rank(
            entry.value,
            entry.key == TransactionDirection.inbound ? moneyIn : moneyOut,
          ),
      },
      trend: <MonthPoint>[
        for (var i = 0; i < windows.length; i++)
          MonthPoint(
            start: windows[i].start,
            moneyInCents: trendIn[i],
            moneyOutCents: trendOut[i],
          ),
      ],
      currency: currency,
      lastTransactionAt: latest,
    );
  }

  /// [count] windows ending with [last], oldest first.
  static List<MonthWindow> _windowsEndingAt(MonthWindow last, int count) {
    final windows = <MonthWindow>[last];
    var cursor = last;
    for (var i = 1; i < count; i++) {
      cursor = cursor.previous;
      windows.insert(0, cursor);
    }
    return windows;
  }

  static List<CategoryTotal> _rank(Map<SpendCategory, int> totals, int total) {
    final ranked =
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
    return ranked;
  }
}
