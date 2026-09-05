import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/models/account.dart';
import 'package:spendwise/data/models/app_transaction.dart';
import 'package:spendwise/data/models/budget.dart';
import 'package:spendwise/data/models/user_preferences.dart';
import 'package:spendwise/data/repositories/repositories.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/state/providers.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

/// Preferences that take a moment to load, like real storage does.
///
/// The delay is the point: an instantly-resolving fake would hide the very bug
/// these tests exist to catch.
class _SlowPreferences implements PreferencesRepository {
  _SlowPreferences(this.value);

  UserPreferences value;

  static const Duration delay = Duration(milliseconds: 50);

  @override
  Future<UserPreferences> load() async {
    await Future<void>.delayed(delay);
    return value;
  }

  @override
  Future<void> save(UserPreferences preferences) async => value = preferences;
}

class _EmptyTransactions implements TransactionRepository {
  @override
  Future<List<AppTransaction>> list({DateTime? from, DateTime? to}) async =>
      const <AppTransaction>[];
  @override
  Future<void> upsert(AppTransaction transaction) async {}
  @override
  Future<void> delete(String id) async {}
}

class _EmptyAccounts implements AccountRepository {
  @override
  Future<List<Account>> list() async => const <Account>[];
  @override
  Future<void> upsert(Account account) async {}
  @override
  Future<void> delete(String id) async {}
}

class _EmptyBudgets implements BudgetRepository {
  @override
  Future<List<Budget>> list() async => const <Budget>[];
  @override
  Future<void> upsert(Budget budget) async {}
  @override
  Future<void> delete(String id) async {}
}

class _EmptyRules implements MerchantRuleRepository {
  @override
  Future<List<MerchantRule>> list() async => const <MerchantRule>[];
  @override
  Future<void> upsert(MerchantRule rule) async {}
  @override
  Future<void> delete(String id) async {}
}

Widget appWith(UserPreferences preferences) {
  return ProviderScope(
    overrides: [
      dataLayerProvider.overrideWith(
        (ref) => DataLayer(
          transactions: _EmptyTransactions(),
          accounts: _EmptyAccounts(),
          budgets: _EmptyBudgets(),
          rules: _EmptyRules(),
          preferences: _SlowPreferences(preferences),
          isRemote: false,
        ),
      ),
    ],
    child: const SpendWiseApp(),
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

  group('startup routing', () {
    testWidgets('leaves the splash screen once preferences load', (tester) async {
      // Regression: the redirect reads providers with `ref.read`, which does
      // not subscribe. Without a refreshListenable the router never
      // re-evaluated and the app sat on the splash screen forever.
      await tester.pumpWidget(appWith(const UserPreferences()));

      // Still loading: splash is correct here.
      await tester.pump();
      expect(find.text('SpendWise'), findsOneWidget);

      await tester.pumpAndSettle();

      expect(
        find.text('Spending tracked automatically'),
        findsNothing,
        reason: 'the app is stranded on the splash screen',
      );
    });

    testWidgets('a new user lands on onboarding', (tester) async {
      await tester.pumpWidget(appWith(const UserPreferences()));
      await tester.pumpAndSettle();

      expect(find.text('Spending tracked as it happens'), findsOneWidget);
    });

    testWidgets('a returning user lands on the dashboard', (tester) async {
      await tester.pumpWidget(appWith(const UserPreferences(
        onboardingComplete: true,
        selectedBankIds: <String>{'cibc'},
      )));
      await tester.pumpAndSettle();

      expect(find.text('Where it went'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Budgets'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('onboarding is not shown again after it is completed',
        (tester) async {
      await tester.pumpWidget(appWith(const UserPreferences(
        onboardingComplete: true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Spending tracked as it happens'), findsNothing);
    });
  });

  group('onboarding flow', () {
    testWidgets('runs through to the dashboard', (tester) async {
      await tester.pumpWidget(appWith(const UserPreferences()));
      await tester.pumpAndSettle();

      // Skip the intro carousel.
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('Your banks'), findsOneWidget);

      // Choose CIBC and continue to the permission screen.
      await tester.tap(find.text('CIBC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Notification access'), findsWidgets);

      // Finish without granting; the app must still become usable.
      await tester.tap(find.text('Continue anyway'));
      await tester.pumpAndSettle();

      expect(find.text('Where it went'), findsOneWidget);
    });

    testWidgets('the intro carousel advances', (tester) async {
      await tester.pumpWidget(appWith(const UserPreferences()));
      await tester.pumpAndSettle();

      expect(find.text('Spending tracked as it happens'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Sorted into categories for you'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Read-only, and only your banks'), findsOneWidget);
      expect(find.text('Choose your banks'), findsOneWidget);
    });
  });

  group('settings can reach setup screens after onboarding', () {
    // Regression: Settings pushed `/onboarding/banks` and
    // `/onboarding/permission`, but the redirect sends every `/onboarding/*`
    // route to the dashboard once setup is complete — so tapping either one
    // bounced the user straight back to Home with no way to change banks.
    testWidgets('Your banks opens bank selection, not the dashboard',
        (tester) async {
      await tester.pumpWidget(appWith(const UserPreferences(
        onboardingComplete: true,
        selectedBankIds: <String>{'cibc'},
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Your banks'));
      await tester.pumpAndSettle();

      expect(
        find.text('Pick every bank whose alerts you want SpendWise to read. '
            'Notifications from any other app are ignored entirely.'),
        findsOneWidget,
        reason: 'tapping Your banks must not bounce back to the dashboard',
      );
      // The onboarding-only wording must not appear here.
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('Notification access opens the permission screen',
        (tester) async {
      await tester.pumpWidget(appWith(const UserPreferences(
        onboardingComplete: true,
        selectedBankIds: <String>{'cibc'},
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notification access'));
      await tester.pumpAndSettle();

      expect(find.text('What SpendWise can and cannot do'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('every bank is offered, including Wealthsimple',
        (tester) async {
      await tester.pumpWidget(appWith(const UserPreferences(
        onboardingComplete: true,
        selectedBankIds: <String>{'cibc'},
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Your banks'));
      await tester.pumpAndSettle();

      for (final name in <String>[
        'CIBC',
        'RBC Royal Bank',
        'TD Canada Trust',
        'Scotiabank',
        'BMO Bank of Montreal',
        'Wealthsimple',
        'Other bank',
      ]) {
        expect(find.text(name), findsOneWidget, reason: '$name is missing');
      }
    });
  });

  group('navigation', () {
    testWidgets('the bottom bar switches tabs', (tester) async {
      await tester.pumpWidget(appWith(const UserPreferences(
        onboardingComplete: true,
        selectedBankIds: <String>{'cibc'},
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(find.text('Search merchant or category'), findsOneWidget);

      await tester.tap(find.text('Budgets'));
      await tester.pumpAndSettle();
      expect(find.text('No budgets yet'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Capture'), findsOneWidget);
      expect(find.text('Test the parser'), findsOneWidget);
    });

    testWidgets('settings reaches the parser debug screen', (tester) async {
      await tester.pumpWidget(appWith(const UserPreferences(
        onboardingComplete: true,
        selectedBankIds: <String>{'cibc'},
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test the parser'));
      await tester.pumpAndSettle();

      expect(find.text('Parser test'), findsOneWidget);
    });
  });
}
