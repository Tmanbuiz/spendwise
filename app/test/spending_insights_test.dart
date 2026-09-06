import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/models/app_transaction.dart';
import 'package:spendwise/data/models/budget.dart';
import 'package:spendwise/data/month_summary.dart';
import 'package:spendwise/data/spending_insights.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

AppTransaction purchase(
  DateTime date,
  int cents, {
  String currency = 'CAD',
  bool excluded = false,
  TransactionEventType type = TransactionEventType.purchase,
  String merchant = 'Metro',
}) => AppTransaction(
  id: '$date-$cents',
  eventType: type,
  amountCents: cents,
  currency: currency,
  occurredAt: date,
  category: SpendCategory.groceries,
  source: TransactionSource.manual,
  merchant: merchant,
  excludedByUser: excluded,
);
SpendingInsights insights(
  DateTime now,
  List<AppTransaction> transactions, {
  int offset = 0,
  int startDay = 1,
}) => SpendingInsights(
  window: reportingWindow(now, offset, startDay),
  now: now,
  transactions: transactions,
  currency: 'CAD',
);

void main() {
  test('month navigation does not skip February from March 31', () {
    final window = reportingWindow(DateTime(2026, 3, 31), -1, 1);
    expect(window.start, DateTime(2026, 2, 1));
    expect(window.end, DateTime(2026, 3, 1));
  });
  test('custom pay cycles navigate by their start, including January', () {
    final window = reportingWindow(DateTime(2026, 1, 5), -1, 15);
    expect(window.start, DateTime(2025, 11, 15));
    expect(window.end, DateTime(2025, 12, 15));
  });
  test('calendar day count is independent of DST hours', () {
    expect(calendarDays(DateTime(2026, 3, 1), DateTime(2026, 4, 1)), 31);
    expect(calendarDays(DateTime(2024, 2, 1), DateTime(2024, 3, 1)), 29);
  });
  test('compares matching first days rather than the full previous month', () {
    final data = insights(DateTime(2026, 9, 5, 18), [
      purchase(DateTime(2026, 9, 2), 6000),
      purchase(DateTime(2026, 8, 2), 4000),
      purchase(DateTime(2026, 8, 20), 50000),
    ]);
    expect(data.comparisonDays, 5);
    expect(data.comparable.previous.totalSpentCents, 4000);
    expect(data.comparable.percentChange, 0.5);
  });
  test('comparison clips BOTH periods when prior month is shorter', () {
    final data = insights(DateTime(2026, 3, 31, 18), [
      purchase(DateTime(2026, 3, 28), 1000),
      purchase(DateTime(2026, 3, 30), 9000),
      purchase(DateTime(2026, 2, 28), 1000),
    ]);
    expect(data.comparisonDays, 28);
    expect(data.current.totalSpentCents, 10000);
    expect(data.comparable.current.totalSpentCents, 1000);
    expect(data.comparable.percentChange, 0);
  });
  test(
    'excludes other currencies, non-purchases, exclusions and future dates',
    () {
      final data = insights(DateTime(2026, 9, 5, 18), [
        purchase(DateTime(2026, 9, 1), 1000),
        purchase(DateTime(2026, 9, 2), 2000, currency: 'USD'),
        purchase(DateTime(2026, 9, 2), 3000, excluded: true),
        purchase(DateTime(2026, 9, 2), 4000, type: TransactionEventType.refund),
        purchase(
          DateTime(2026, 9, 2),
          5000,
          type: TransactionEventType.payment,
        ),
        purchase(DateTime(2026, 9, 9), 6000),
      ]);
      expect(data.current.totalSpentCents, 1000);
      expect(data.topMerchants.single.count, 1);
      expect(data.dailyCents.reduce((a, b) => a + b), 1000);
    },
  );
  test('summary does not add dollars in different currencies', () {
    expect(
      MonthSummary.build(
        transactions: [
          purchase(DateTime(2026, 9, 1), 1000),
          purchase(DateTime(2026, 9, 1), 5000, currency: 'USD'),
        ],
        window: reportingWindow(DateTime(2026, 9, 5), 0, 1),
      ).totalSpentCents,
      1000,
    );
  });
  test('daily allowance includes today and floors cents', () {
    final data = insights(DateTime(2026, 9, 5), []);
    expect(data.daysLeft, 26);
    expect(
      data.dailyAllowance(
        const BudgetProgress(
          budget: Budget(id: 'a', amountCents: 10000),
          spentCents: 1000,
        ),
      ),
      346,
    );
    expect(
      data.dailyAllowance(
        const BudgetProgress(
          budget: Budget(id: 'a', amountCents: 10000),
          spentCents: 11000,
        ),
      ),
      0,
    );
    expect(data.dailyAllowance(null), isNull);
  });
  test('past periods have no forward allowance or projection', () {
    final data = insights(DateTime(2026, 9, 5), [], offset: -1);
    expect(data.daysLeft, 0);
    expect(data.projectedCents, isNull);
    expect(
      data.dailyAllowance(
        const BudgetProgress(
          budget: Budget(id: 'a', amountCents: 1000),
          spentCents: 0,
        ),
      ),
      isNull,
    );
  });
  test('projection waits a week and uses unrounded daily spending', () {
    final rows = [purchase(DateTime(2026, 9, 1), 7001)];
    expect(insights(DateTime(2026, 9, 6), rows).projectedCents, isNull);
    expect(insights(DateTime(2026, 9, 7), rows).projectedCents, 30004);
    expect(insights(DateTime(2026, 9, 7), []).projectedCents, isNull);
  });
  test('merchant grouping and trend totals agree with purchases', () {
    final data = insights(DateTime(2026, 9, 5), [
      purchase(DateTime(2026, 9, 1), 1000, merchant: 'Metro'),
      purchase(DateTime(2026, 9, 2), 2000, merchant: 'METRO'),
      purchase(DateTime(2026, 8, 1), 4000),
    ]);
    expect(data.topMerchants.single.amountCents, 3000);
    expect(data.topMerchants.single.count, 2);
    expect(data.history.length, 6);
    expect(data.history.last.totalSpentCents, 3000);
    expect(data.history[4].totalSpentCents, 4000);
  });
}
