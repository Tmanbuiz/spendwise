import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/theme/app_theme.dart';
import 'package:spendwise/data/models/account.dart';
import 'package:spendwise/data/models/app_transaction.dart';
import 'package:spendwise/data/models/budget.dart';
import 'package:spendwise/data/models/user_preferences.dart';
import 'package:spendwise/data/repositories/repositories.dart';
import 'package:spendwise/features/accounts/accounts_screen.dart';
import 'package:spendwise/features/budgets/budgets_screen.dart';
import 'package:spendwise/features/categories/categories_screen.dart';
import 'package:spendwise/features/dashboard/dashboard_screen.dart';
import 'package:spendwise/features/debug/parser_debug_screen.dart';
import 'package:spendwise/features/onboarding/bank_selection_screen.dart';
import 'package:spendwise/features/transactions/transaction_detail_screen.dart';
import 'package:spendwise/features/transactions/transactions_screen.dart';
import 'package:spendwise/state/providers.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

// ------------------------------------------------------------- test doubles

class _FakeTransactions implements TransactionRepository {
  _FakeTransactions(this.rows);
  List<AppTransaction> rows;

  @override
  Future<List<AppTransaction>> list({DateTime? from, DateTime? to}) async =>
      rows;

  @override
  Future<void> upsert(AppTransaction transaction) async {
    rows = <AppTransaction>[
      ...rows.where((r) => r.id != transaction.id),
      transaction,
    ];
  }

  @override
  Future<void> delete(String id) async =>
      rows = rows.where((r) => r.id != id).toList();
}

class _FakeAccounts implements AccountRepository {
  @override
  Future<List<Account>> list() async => const <Account>[];
  @override
  Future<void> upsert(Account account) async {}
  @override
  Future<void> delete(String id) async {}
}

class _FakeBudgets implements BudgetRepository {
  _FakeBudgets(this.rows);
  List<Budget> rows;

  @override
  Future<List<Budget>> list() async => rows;
  @override
  Future<void> upsert(Budget budget) async => rows = <Budget>[...rows, budget];
  @override
  Future<void> delete(String id) async =>
      rows = rows.where((r) => r.id != id).toList();
}

class _FakeRules implements MerchantRuleRepository {
  _FakeRules(this.rows);
  List<MerchantRule> rows;

  @override
  Future<List<MerchantRule>> list() async => rows;
  @override
  Future<void> upsert(MerchantRule rule) async =>
      rows = <MerchantRule>[...rows, rule];
  @override
  Future<void> delete(String id) async =>
      rows = rows.where((r) => r.id != id).toList();
}

class _FakePreferences implements PreferencesRepository {
  _FakePreferences(this.value);
  UserPreferences value;

  @override
  Future<UserPreferences> load() async => value;
  @override
  Future<void> save(UserPreferences preferences) async => value = preferences;
}

AppTransaction sample({
  required String id,
  required int cents,
  required String merchant,
  SpendCategory category = SpendCategory.groceries,
  TransactionEventType type = TransactionEventType.purchase,
  DateTime? when,
  bool needsReview = false,
}) {
  return AppTransaction(
    id: id,
    eventType: type,
    amountCents: cents,
    currency: 'CAD',
    occurredAt: when ?? DateTime.now(),
    category: category,
    source: TransactionSource.notification,
    merchant: merchant,
    merchantNormalized: merchant.toUpperCase(),
    accountLast4: '1234',
    bankId: 'cibc',
    needsReview: needsReview,
  );
}

/// Wraps a screen with an overridden data layer so nothing touches Supabase
/// or device storage.
Widget harness(
  Widget child, {
  List<AppTransaction> transactions = const <AppTransaction>[],
  List<Budget> budgets = const <Budget>[],
  List<MerchantRule> rules = const <MerchantRule>[],
  UserPreferences preferences = const UserPreferences(
    onboardingComplete: true,
    selectedBankIds: <String>{'cibc'},
  ),
}) {
  return ProviderScope(
    overrides: [
      dataLayerProvider.overrideWith(
        (ref) => DataLayer(
          transactions: _FakeTransactions(transactions),
          accounts: _FakeAccounts(),
          budgets: _FakeBudgets(budgets),
          rules: _FakeRules(rules),
          preferences: _FakePreferences(preferences),
          isRemote: false,
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: child,
    ),
  );
}

void main() {
  // The default 800x600 test surface clips long scrolling screens, and a
  // widget that was never built cannot be found. A tall phone-shaped surface
  // lets these render in full.
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

  final transactions = <AppTransaction>[
    sample(id: 't1', cents: 4567, merchant: 'TIM HORTONS',
        category: SpendCategory.dining),
    sample(id: 't2', cents: 12300, merchant: 'LOBLAWS'),
    sample(
      id: 't3',
      cents: 50000,
      merchant: 'CIBC VISA',
      type: TransactionEventType.payment,
    ),
  ];

  group('dashboard', () {
    testWidgets('renders the month total from purchases only', (tester) async {
      await tester.pumpWidget(harness(
        const DashboardScreen(),
        transactions: transactions,
      ));
      await tester.pumpAndSettle();

      // 45.67 + 123.00 = 168.67. The 500.00 card payment must not be counted.
      expect(find.text(r'$168.67'), findsOneWidget);
      expect(find.textContaining(r'$668.67'), findsNothing);
    });

    testWidgets('shows recent activity and the category breakdown',
        (tester) async {
      await tester.pumpWidget(harness(
        const DashboardScreen(),
        transactions: transactions,
      ));
      await tester.pumpAndSettle();

      expect(find.text('TIM HORTONS'), findsOneWidget);
      expect(find.text('LOBLAWS'), findsOneWidget);
      expect(find.text('Where it went'), findsOneWidget);
      expect(find.text('Groceries'), findsWidgets);
    });

    testWidgets('offers to set a budget when none exists', (tester) async {
      await tester.pumpWidget(harness(
        const DashboardScreen(),
        transactions: transactions,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Set a monthly budget'), findsOneWidget);
    });

    testWidgets('shows budget progress when a budget exists', (tester) async {
      await tester.pumpWidget(harness(
        const DashboardScreen(),
        transactions: transactions,
        budgets: <Budget>[const Budget(id: 'b1', amountCents: 100000)],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Monthly budget'), findsOneWidget);
      expect(find.textContaining('left'), findsWidgets);
    });

    testWidgets('renders an empty state with no transactions', (tester) async {
      await tester.pumpWidget(harness(const DashboardScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text(r'$0.00'), findsOneWidget);
    });
  });

  group('transactions', () {
    testWidgets('lists transactions grouped by day', (tester) async {
      await tester.pumpWidget(harness(
        const TransactionsScreen(),
        transactions: transactions,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('TIM HORTONS'), findsOneWidget);
    });

    testWidgets('the "Not counted" filter isolates non-spending rows',
        (tester) async {
      await tester.pumpWidget(harness(
        const TransactionsScreen(),
        transactions: transactions,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not counted'));
      await tester.pumpAndSettle();

      expect(find.text('CIBC VISA'), findsOneWidget);
      expect(find.text('TIM HORTONS'), findsNothing);
    });

    testWidgets('search narrows the list', (tester) async {
      await tester.pumpWidget(harness(
        const TransactionsScreen(),
        transactions: transactions,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'loblaws');
      await tester.pumpAndSettle();

      expect(find.text('LOBLAWS'), findsOneWidget);
      expect(find.text('TIM HORTONS'), findsNothing);
    });
  });

  group('transaction detail', () {
    testWidgets('opens blank for a new manual transaction', (tester) async {
      await tester.pumpWidget(harness(const TransactionDetailScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Add transaction'), findsWidgets);
      expect(find.text('Purchase'), findsOneWidget);
    });

    testWidgets('pre-fills when editing an existing transaction',
        (tester) async {
      await tester.pumpWidget(harness(
        TransactionDetailScreen(transaction: transactions.first),
      ));
      await tester.pumpAndSettle();

      expect(find.text('45.67'), findsOneWidget);
      expect(find.text('TIM HORTONS'), findsOneWidget);
    });

    testWidgets('rejects a zero or empty amount', (tester) async {
      await tester.pumpWidget(harness(const TransactionDetailScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Add transaction'));
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount greater than zero'), findsOneWidget);
    });

    testWidgets('says when the chosen type will not count as spending',
        (tester) async {
      await tester.pumpWidget(harness(const TransactionDetailScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Refund'));
      await tester.pumpAndSettle();

      expect(
        find.text('Recorded for context, but not counted as spending.'),
        findsOneWidget,
      );
    });
  });

  group('budgets', () {
    testWidgets('shows an empty state and an entry point', (tester) async {
      await tester.pumpWidget(harness(const BudgetsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('No budgets yet'), findsOneWidget);
      expect(find.text('Set a budget'), findsOneWidget);
    });

    testWidgets('flags an over-budget category in the negative colour',
        (tester) async {
      await tester.pumpWidget(harness(
        const BudgetsScreen(),
        transactions: transactions,
        budgets: <Budget>[
          const Budget(
            id: 'b1',
            amountCents: 1000,
            category: SpendCategory.dining,
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('over budget'), findsOneWidget);
    });
  });

  group('categories', () {
    testWidgets('lists every category', (tester) async {
      await tester.pumpWidget(harness(const CategoriesScreen()));
      await tester.pumpAndSettle();

      for (final category in SpendCategory.values) {
        expect(
          find.text(category.displayName),
          findsWidgets,
          reason: '${category.displayName} missing from the list',
        );
      }
    });

    testWidgets('shows user rules', (tester) async {
      await tester.pumpWidget(harness(
        const CategoriesScreen(),
        rules: <MerchantRule>[
          const MerchantRule(
            id: 'r1',
            pattern: 'MY CORNER STORE',
            category: SpendCategory.groceries,
            source: RuleSource.user,
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('MY CORNER STORE'), findsOneWidget);
    });
  });

  group('accounts', () {
    testWidgets('discovers cards from transaction history', (tester) async {
      await tester.pumpWidget(harness(
        const AccountsScreen(),
        transactions: transactions,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('••1234'), findsWidgets);
      expect(
        find.textContaining('never holds a full card number'),
        findsOneWidget,
      );
    });

    testWidgets('shows an empty state with no history', (tester) async {
      await tester.pumpWidget(harness(const AccountsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('No cards seen yet'), findsOneWidget);
    });
  });

  group('bank selection', () {
    testWidgets('lists every bank and marks CIBC as fully supported',
        (tester) async {
      await tester.pumpWidget(harness(const BankSelectionScreen()));
      await tester.pumpAndSettle();

      expect(find.text('CIBC'), findsOneWidget);
      expect(find.text('RBC Royal Bank'), findsOneWidget);
      expect(find.text('Wealthsimple'), findsOneWidget);
      expect(find.text('Other bank'), findsOneWidget);
      // CIBC and Wealthsimple both have parsers built from real captured
      // notifications; the rest are capture-only until samples exist.
      expect(
        find.text('Automatic — alerts are read and categorised'),
        findsNWidgets(2),
      );
      expect(
        find.text('Capture only — add these by hand for now'),
        findsNWidgets(5),
      );
    });

    testWidgets('continue is disabled until a bank is chosen', (tester) async {
      await tester.pumpWidget(harness(
        const BankSelectionScreen(isOnboarding: true),
        preferences: const UserPreferences(),
      ));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue'),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.text('CIBC'));
      await tester.pumpAndSettle();

      final enabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue'),
      );
      expect(enabled.onPressed, isNotNull);
    });
  });

  group('parser debug screen', () {
    testWidgets('parses a pasted notification without saving it',
        (tester) async {
      await tester.pumpWidget(harness(const ParserDebugScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        r'You spent $12.50 at STARBUCKS with your CIBC card ending in 4321.',
      );
      await tester.pumpAndSettle();

      expect(find.text('PURCHASE'), findsOneWidget);
      expect(find.text(r'$12.50'), findsOneWidget);
      // Twice: once as the raw capture, once as the normalised form.
      expect(find.text('STARBUCKS'), findsNWidgets(2));
      expect(find.text('Dining'), findsOneWidget);
      expect(find.text('Counts as spending'), findsOneWidget);
    });

    testWidgets('a card payment is shown as not counted', (tester) async {
      await tester.pumpWidget(harness(const ParserDebugScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Card payment'));
      await tester.pumpAndSettle();

      expect(find.text('PAYMENT'), findsOneWidget);
      expect(find.text('Not counted'), findsOneWidget);
    });

    testWidgets('a decline is shown as not counted', (tester) async {
      await tester.pumpWidget(harness(const ParserDebugScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Declined'));
      await tester.pumpAndSettle();

      expect(find.text('DECLINED'), findsOneWidget);
      expect(find.text('Not counted'), findsOneWidget);
    });

    testWidgets('explains retention for an incomplete parse', (tester) async {
      await tester.pumpWidget(harness(const ParserDebugScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        r'A transaction of $18.40 was made on your CIBC card ending in 1234.',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('redacted copy is kept'), findsOneWidget);
      expect(find.text('No merchant could be found'), findsNothing);
      expect(find.textContaining('No merchant could be found'), findsOneWidget);
    });
  });
}
