import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise/core/theme/app_theme.dart';
import 'package:spendwise/data/models/account.dart';
import 'package:spendwise/data/models/app_transaction.dart';
import 'package:spendwise/data/models/budget.dart';
import 'package:spendwise/data/models/user_preferences.dart';
import 'package:spendwise/data/month_summary.dart';
import 'package:spendwise/data/monthly_overview.dart';
import 'package:spendwise/data/repositories/repositories.dart';
import 'package:spendwise/features/insights/monthly_overview_screen.dart';
import 'package:spendwise/state/providers.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

// --------------------------------------------------------------- test doubles

class _Transactions implements TransactionRepository {
  _Transactions(this.rows);
  List<AppTransaction> rows;

  @override
  Future<List<AppTransaction>> list({DateTime? from, DateTime? to}) async =>
      rows;
  @override
  Future<void> upsert(AppTransaction transaction) async {}
  @override
  Future<void> delete(String id) async {}
}

class _Accounts implements AccountRepository {
  @override
  Future<List<Account>> list() async => const <Account>[];
  @override
  Future<void> upsert(Account account) async {}
  @override
  Future<void> delete(String id) async {}
}

class _Budgets implements BudgetRepository {
  @override
  Future<List<Budget>> list() async => const <Budget>[];
  @override
  Future<void> upsert(Budget budget) async {}
  @override
  Future<void> delete(String id) async {}
}

class _Rules implements MerchantRuleRepository {
  @override
  Future<List<MerchantRule>> list() async => const <MerchantRule>[];
  @override
  Future<void> upsert(MerchantRule rule) async {}
  @override
  Future<void> delete(String id) async {}
}

class _Preferences implements PreferencesRepository {
  @override
  Future<UserPreferences> load() async => const UserPreferences(
        onboardingComplete: true,
        selectedBankIds: <String>{'cibc'},
      );
  @override
  Future<void> save(UserPreferences preferences) async {}
}

// --------------------------------------------------------------------- helpers

final DateTime _now = DateTime(2026, 9, 20, 12);

AppTransaction tx({
  required String id,
  required int cents,
  required TransactionEventType type,
  TransactionDirection? direction,
  DateTime? when,
  SpendCategory category = SpendCategory.groceries,
  String merchant = 'SOMETHING',
  bool excluded = false,
}) {
  return AppTransaction(
    id: id,
    eventType: type,
    amountCents: cents,
    currency: 'CAD',
    occurredAt: when ?? DateTime(2026, 9, 4),
    category: category,
    source: TransactionSource.statement,
    merchant: merchant,
    recordedDirection: direction,
    excludedByUser: excluded,
  );
}

MonthlyOverview overviewOf(List<AppTransaction> rows) {
  return MonthlyOverview.build(
    transactions: rows,
    window: MonthWindow.forDate(_now),
  );
}

Widget harness(List<AppTransaction> rows) {
  return ProviderScope(
    overrides: [
      reportingNowProvider.overrideWithValue(_now),
      dataLayerProvider.overrideWith(
        (ref) => DataLayer(
          transactions: _Transactions(rows),
          accounts: _Accounts(),
          budgets: _Budgets(),
          rules: _Rules(),
          preferences: _Preferences(),
          isRemote: false,
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const MonthlyOverviewScreen(),
    ),
  );
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!
      ..physicalSize = const Size(1000, 3200)
      ..devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  group('which group a transaction belongs to', () {
    test('a purchase is spending', () {
      expect(
        MoneyFlowGroup.of(
          tx(id: 'a', cents: 100, type: TransactionEventType.purchase),
        ),
        MoneyFlowGroup.spending,
      );
    });

    // The whole reason direction exists: these two are the same event type
    // and belong on opposite sides of the report.
    test('a transfer is grouped by direction, not by type', () {
      final sent = tx(
        id: 'a',
        cents: 100,
        type: TransactionEventType.transfer,
        direction: TransactionDirection.outbound,
      );
      final received = tx(
        id: 'b',
        cents: 100,
        type: TransactionEventType.transfer,
        direction: TransactionDirection.inbound,
      );

      expect(MoneyFlowGroup.of(sent), MoneyFlowGroup.transfersOut);
      expect(MoneyFlowGroup.of(received), MoneyFlowGroup.deposits);
    });

    test('a loan or card payment is debt service', () {
      expect(
        MoneyFlowGroup.of(
          tx(id: 'a', cents: 100, type: TransactionEventType.payment),
        ),
        MoneyFlowGroup.debtPayments,
      );
    });

    // A row the user excluded by hand must stop counting as spending here for
    // the same reason it does everywhere else.
    test('a purchase the user excluded is no longer spending', () {
      expect(
        MoneyFlowGroup.of(
          tx(
            id: 'a',
            cents: 100,
            type: TransactionEventType.purchase,
            excluded: true,
          ),
        ),
        MoneyFlowGroup.otherOut,
      );
    });
  });

  group('the month adds up', () {
    final rows = <AppTransaction>[
      tx(id: 'a', cents: 5000, type: TransactionEventType.purchase),
      tx(
        id: 'b',
        cents: 20000,
        type: TransactionEventType.transfer,
        direction: TransactionDirection.outbound,
      ),
      tx(id: 'c', cents: 24112, type: TransactionEventType.payment),
      tx(
        id: 'd',
        cents: 300000,
        type: TransactionEventType.transfer,
        direction: TransactionDirection.inbound,
      ),
    ];

    test('money out is every outbound movement, not just spending', () {
      final overview = overviewOf(rows);
      expect(overview.moneyOutCents, 5000 + 20000 + 24112);
      expect(overview.spendingCents, 5000);
    });

    test('money in is what arrived', () {
      expect(overviewOf(rows).moneyInCents, 300000);
    });

    test('net is money in less money out', () {
      final overview = overviewOf(rows);
      expect(
        overview.netCents,
        overview.moneyInCents - overview.moneyOutCents,
      );
    });

    // If a tab's tiles did not sum to the figure above them the screen would
    // be quietly lying about one of the two.
    test('each tab reconciles with its headline', () {
      final overview = overviewOf(rows);
      for (final direction in TransactionDirection.values) {
        final summed = overview
            .groupsFor(direction)
            .fold<int>(0, (sum, group) => sum + group.amountCents);
        expect(summed, overview.totalFor(direction), reason: '$direction');
      }
    });

    test('a declined card never moved money, so it counts nowhere', () {
      final overview = overviewOf(<AppTransaction>[
        ...rows,
        tx(id: 'e', cents: 99900, type: TransactionEventType.declined),
      ]);
      expect(overview.moneyOutCents, 5000 + 20000 + 24112);
      expect(overview.moneyInCents, 300000);
    });

    test('another month is left out of this one', () {
      final overview = overviewOf(<AppTransaction>[
        ...rows,
        tx(
          id: 'old',
          cents: 777,
          type: TransactionEventType.purchase,
          when: DateTime(2026, 7, 4),
        ),
      ]);
      expect(overview.spendingCents, 5000);
    });

    test('the trend covers six months ending with the one on screen', () {
      final overview = overviewOf(rows);
      expect(overview.trend, hasLength(6));
      expect(overview.trend.last.start, overview.window.start);
      expect(overview.trend.first.start, DateTime(2026, 4));
    });

    // A month outside the window still belongs on the trend strip; that is
    // the whole point of showing five months of context.
    test('the trend counts months the headline excludes', () {
      final overview = overviewOf(<AppTransaction>[
        ...rows,
        tx(
          id: 'old',
          cents: 777,
          type: TransactionEventType.purchase,
          when: DateTime(2026, 7, 4),
        ),
      ]);
      final july = overview.trend.firstWhere(
        (point) => point.start.month == 7,
      );
      expect(july.moneyOutCents, 777);
    });
  });

  group('picking a month by hand', () {
    test('last month is one step back', () {
      expect(monthOffsetFor(_now, 2026, 8, 1), -1);
    });

    test('the same month a year ago is twelve steps back', () {
      expect(monthOffsetFor(_now, 2025, 9, 1), -12);
    });

    test('the month on screen is no step at all', () {
      expect(monthOffsetFor(_now, 2026, 9, 1), 0);
    });

    // A future month has nothing to report, and a report of the future
    // reads as the app having lost the data rather than as it not
    // existing yet.
    test('a future month is refused by the notifier', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(monthOffsetProvider.notifier)
          .jumpTo(monthOffsetFor(_now, 2027, 3, 1));
      expect(container.read(monthOffsetProvider), 0);
    });
  });

  group('the screen', () {
    final rows = <AppTransaction>[
      tx(id: 'a', cents: 5000, type: TransactionEventType.purchase),
      tx(
        id: 'b',
        cents: 300000,
        type: TransactionEventType.transfer,
        direction: TransactionDirection.inbound,
        merchant: 'PAY PROV OF NEW BRUNSWICK',
      ),
    ];

    testWidgets('shows the month being reported on', (tester) async {
      await tester.pumpWidget(harness(rows));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);
    });

    testWidgets('shows money out, money in and the net', (tester) async {
      await tester.pumpWidget(harness(rows));
      await tester.pumpAndSettle();

      expect(find.text('Money out'), findsWidgets);
      expect(find.text('Money in'), findsWidgets);
      expect(find.text('Net'), findsOneWidget);
      expect(find.text(r'$50.00'), findsWidgets);
      expect(find.text(r'+$2,950.00'), findsOneWidget);
    });

    testWidgets('opens on money out and switches to money in', (
      tester,
    ) async {
      await tester.pumpWidget(harness(rows));
      await tester.pumpAndSettle();

      expect(find.text('Spending'), findsOneWidget);
      expect(find.text('Deposits & pay'), findsNothing);

      await tester.tap(find.text('Money in').last);
      await tester.pumpAndSettle();

      expect(find.text('Deposits & pay'), findsOneWidget);
      expect(find.text('Spending'), findsNothing);
    });

    testWidgets('the month picker changes the month on confirm', (
      tester,
    ) async {
      await tester.pumpWidget(harness(rows));
      await tester.pumpAndSettle();

      await tester.tap(find.text('September 2026'));
      await tester.pumpAndSettle();
      expect(find.text('Select Month'), findsOneWidget);

      // Asserted as "no longer September" rather than as a specific month:
      // exactly how far one drag scrolls a wheel is Flutter's business, and
      // pinning it would make this a test of scroll physics. What matters is
      // that the wheel moves at all — with the controller rebuilt on every
      // setState it snapped back, and the month never changed.
      await tester.drag(
        find.byType(ListWheelScrollView).first,
        const Offset(0, 100),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('September 2026'), findsNothing);
      expect(find.textContaining('2026'), findsWidgets);
    });

    testWidgets('confirming without scrolling keeps the month', (
      tester,
    ) async {
      await tester.pumpWidget(harness(rows));
      await tester.pumpAndSettle();

      await tester.tap(find.text('September 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('Select Month'), findsNothing);
      expect(find.text('September 2026'), findsOneWidget);
    });

    testWidgets('cancelling the picker leaves the month alone', (
      tester,
    ) async {
      await tester.pumpWidget(harness(rows));
      await tester.pumpAndSettle();

      await tester.tap(find.text('September 2026'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListWheelScrollView).first, const Offset(0, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('September 2026'), findsOneWidget);
    });

    testWidgets('an empty side says which side is empty', (tester) async {
      await tester.pumpWidget(
        harness(<AppTransaction>[
          tx(id: 'a', cents: 5000, type: TransactionEventType.purchase),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Money in').last);
      await tester.pumpAndSettle();

      expect(find.text('No money in for September 2026'), findsWidgets);
    });
  });
}
