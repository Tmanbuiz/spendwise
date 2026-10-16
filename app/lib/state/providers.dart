import 'dart:math';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../data/models/account.dart';
import '../data/models/app_transaction.dart';
import '../data/models/bank.dart';
import '../data/models/budget.dart';
import '../data/models/user_preferences.dart';
import '../data/month_summary.dart';
import '../data/monthly_overview.dart';
import '../data/spending_insights.dart';
import '../data/repositories/local_repositories.dart';
import '../data/repositories/repositories.dart';
import '../data/repositories/supabase_repositories.dart';
import '../services/ingest_service.dart';
import '../services/financial_vault_service.dart';
import '../services/notification_access.dart';

/// Set once at startup by `main`, so synchronous providers can read the data
/// layer without every widget awaiting a future.
DataLayer? _bootstrappedDataLayer;

/// Opens Supabase when configured, and falls back to device-local storage
/// otherwise so the app is usable before a backend exists.
Future<DataLayer> bootstrapDataLayer() async {
  if (Env.isConfigured) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
    _bootstrappedDataLayer = SupabaseData.open(Supabase.instance.client);
  } else {
    final local = await LocalStore.open();
    await FinancialVaultService(isRemote: false).migrateLegacyDocuments(await local.documents.list());
    _bootstrappedDataLayer = local;
  }
  return _bootstrappedDataLayer!;
}

final dataLayerProvider = Provider<DataLayer>((ref) {
  final layer = _bootstrappedDataLayer;
  if (layer == null) {
    throw StateError('bootstrapDataLayer() must run before the app starts');
  }
  return layer;
});

/// True when a Supabase project is configured. Drives the honest "stored on
/// this device only" banner in Settings.
final isRemoteProvider = Provider<bool>(
  (ref) => ref.watch(dataLayerProvider).isRemote,
);

// ---------------------------------------------------------------------- auth

/// Who is signed in, or null.
///
/// In local mode there is no account, so a synthetic session stands in and the
/// auth screen is skipped — the app is still fully usable offline.
final authUserProvider = StreamProvider<User?>((ref) {
  if (!Env.isConfigured) return Stream<User?>.value(null);
  final client = Supabase.instance.client;
  return client.auth.onAuthStateChange.map((event) => event.session?.user);
});

final isSignedInProvider = Provider<bool>((ref) {
  if (!Env.isConfigured) return true; // local mode needs no account
  return ref.watch(authUserProvider).value != null;
});

class AuthActions {
  const AuthActions();

  Future<void> signIn({required String email, required String password}) =>
      Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

  Future<void> signUp({required String email, required String password}) =>
      Supabase.instance.client.auth.signUp(email: email, password: password);

  Future<void> signOut() => Supabase.instance.client.auth.signOut();

  Future<void> resetPassword(String email) =>
      Supabase.instance.client.auth.resetPasswordForEmail(email);
}

final authActionsProvider = Provider<AuthActions>((ref) => const AuthActions());

// --------------------------------------------------------------- preferences

final preferencesProvider =
    AsyncNotifierProvider<PreferencesNotifier, UserPreferences>(
      PreferencesNotifier.new,
    );

class PreferencesNotifier extends AsyncNotifier<UserPreferences> {
  @override
  Future<UserPreferences> build() =>
      ref.watch(dataLayerProvider).preferences.load();

  Future<void> _write(UserPreferences next) async {
    state = AsyncData(next);
    await ref.read(dataLayerProvider).preferences.save(next);
  }

  Future<void> setBanks(Set<String> bankIds) async {
    final current = state.value ?? const UserPreferences();
    await _write(current.copyWith(selectedBankIds: bankIds));
  }

  Future<void> setNotificationAccessConfirmed(bool value) async {
    final current = state.value ?? const UserPreferences();
    await _write(current.copyWith(notificationAccessConfirmed: value));
  }

  Future<void> completeOnboarding() async {
    final current = state.value ?? const UserPreferences();
    await _write(current.copyWith(onboardingComplete: true));
  }

  Future<void> setMonthStartDay(int day) async {
    final current = state.value ?? const UserPreferences();
    await _write(current.copyWith(monthStartDay: day));
  }

  Future<void> setAutoCategorize(bool value) async {
    final current = state.value ?? const UserPreferences();
    await _write(current.copyWith(autoCategorize: value));
  }
}

// -------------------------------------------------------------- transactions

final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<AppTransaction>>(
      TransactionsNotifier.new,
    );

class TransactionsNotifier extends AsyncNotifier<List<AppTransaction>> {
  @override
  Future<List<AppTransaction>> build() =>
      ref.watch(dataLayerProvider).transactions.list();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dataLayerProvider).transactions.list(),
    );
  }

  Future<void> upsert(AppTransaction transaction) async {
    await ref.read(dataLayerProvider).transactions.upsert(transaction);
    await refresh();
  }

  Future<void> delete(String id) async {
    await ref.read(dataLayerProvider).transactions.delete(id);
    await refresh();
  }

  /// Re-categorises a transaction and remembers that the user chose it, so
  /// automatic categorisation never overwrites the correction later.
  Future<void> setCategory(
    AppTransaction transaction,
    SpendCategory category,
  ) => upsert(
    transaction.copyWith(
      category: category,
      categoryWasSetByUser: true,
      needsReview: false,
    ),
  );
}

// ------------------------------------------------------------------- budgets

final budgetsProvider = AsyncNotifierProvider<BudgetsNotifier, List<Budget>>(
  BudgetsNotifier.new,
);

class BudgetsNotifier extends AsyncNotifier<List<Budget>> {
  @override
  Future<List<Budget>> build() => ref.watch(dataLayerProvider).budgets.list();

  Future<void> upsert(Budget budget) async {
    await ref.read(dataLayerProvider).budgets.upsert(budget);
    state = await AsyncValue.guard(
      () => ref.read(dataLayerProvider).budgets.list(),
    );
  }

  Future<void> delete(String id) async {
    await ref.read(dataLayerProvider).budgets.delete(id);
    state = await AsyncValue.guard(
      () => ref.read(dataLayerProvider).budgets.list(),
    );
  }
}

// ------------------------------------------------------------------ accounts

final accountsProvider = AsyncNotifierProvider<AccountsNotifier, List<Account>>(
  AccountsNotifier.new,
);

class AccountsNotifier extends AsyncNotifier<List<Account>> {
  @override
  Future<List<Account>> build() => ref.watch(dataLayerProvider).accounts.list();

  Future<void> upsert(Account account) async {
    await ref.read(dataLayerProvider).accounts.upsert(account);
    state = await AsyncValue.guard(
      () => ref.read(dataLayerProvider).accounts.list(),
    );
  }

  Future<void> delete(String id) async {
    await ref.read(dataLayerProvider).accounts.delete(id);
    state = await AsyncValue.guard(
      () => ref.read(dataLayerProvider).accounts.list(),
    );
  }
}

// ------------------------------------------------------------ merchant rules

final rulesProvider = AsyncNotifierProvider<RulesNotifier, List<MerchantRule>>(
  RulesNotifier.new,
);

class RulesNotifier extends AsyncNotifier<List<MerchantRule>> {
  @override
  Future<List<MerchantRule>> build() =>
      ref.watch(dataLayerProvider).rules.list();

  Future<void> upsert(MerchantRule rule) async {
    await ref.read(dataLayerProvider).rules.upsert(rule);
    state = await AsyncValue.guard(
      () => ref.read(dataLayerProvider).rules.list(),
    );
  }

  Future<void> delete(String id) async {
    await ref.read(dataLayerProvider).rules.delete(id);
    state = await AsyncValue.guard(
      () => ref.read(dataLayerProvider).rules.list(),
    );
  }
}

/// The categoriser, rebuilt whenever the user's rules change.
final categorizerProvider = Provider<Categorizer>((ref) {
  final rules = ref.watch(rulesProvider).value ?? const <MerchantRule>[];
  return Categorizer(userRules: rules);
});

// ------------------------------------------------------------------ reporting

final reportingNowProvider = Provider<DateTime>((ref) {
  ref.watch(transactionsProvider);
  final timer = Timer.periodic(
    const Duration(minutes: 1),
    (_) => ref.invalidateSelf(),
  );
  ref.onDispose(timer.cancel);
  return DateTime.now();
});

final spendingInsightsProvider = Provider<SpendingInsights>((ref) {
  final preferences =
      ref.watch(preferencesProvider).value ?? const UserPreferences();
  final now = ref.watch(reportingNowProvider);
  return SpendingInsights(
    window: reportingWindow(
      now,
      ref.watch(monthOffsetProvider),
      preferences.monthStartDay,
    ),
    now: now,
    transactions: ref.watch(transactionsProvider).value ?? const [],
    currency: preferences.currency,
  );
});

/// The month currently being viewed, as an offset from this month
/// (0 = current, -1 = last month).
final monthOffsetProvider = NotifierProvider<MonthOffsetNotifier, int>(
  MonthOffsetNotifier.new,
);

class MonthOffsetNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Steps backwards through history but never into the future, because there
  /// is nothing to show there.
  void step(int delta) => state = (state + delta).clamp(-240, 0);

  /// Jumps straight to a month the user picked, rather than stepping.
  /// Clamped the same way [step] is, so a picker cannot land the report
  /// in the future where there is nothing to show.
  void jumpTo(int offset) => state = offset.clamp(-240, 0);

  void reset() => state = 0;

  bool get isCurrentMonth => state == 0;
}

final monthComparisonProvider = Provider<MonthComparison>((ref) {
  final transactions =
      (ref.watch(transactionsProvider).value ?? const <AppTransaction>[])
          .where((t) => !t.occurredAt.isAfter(ref.watch(reportingNowProvider)))
          .toList();
  final preferences =
      ref.watch(preferencesProvider).value ?? const UserPreferences();
  final offset = ref.watch(monthOffsetProvider);

  final now = ref.watch(reportingNowProvider);
  final window = reportingWindow(now, offset, preferences.monthStartDay);

  return MonthComparison(
    current: MonthSummary.build(
      transactions: transactions,
      window: window,
      currency: preferences.currency,
    ),
    previous: MonthSummary.build(
      transactions: transactions,
      window: window.previous,
      currency: preferences.currency,
    ),
  );
});

/// Everything the Monthly Overview screen shows for the month currently
/// selected, including the five months before it for the trend strip.
final monthlyOverviewProvider = Provider<MonthlyOverview>((ref) {
  final now = ref.watch(reportingNowProvider);
  final preferences =
      ref.watch(preferencesProvider).value ?? const UserPreferences();
  final transactions =
      (ref.watch(transactionsProvider).value ?? const <AppTransaction>[])
          .where((t) => !t.occurredAt.isAfter(now))
          .toList();

  return MonthlyOverview.build(
    transactions: transactions,
    window: reportingWindow(
      now,
      ref.watch(monthOffsetProvider),
      preferences.monthStartDay,
    ),
    currency: preferences.currency,
  );
});

/// The offset [MonthOffsetNotifier] needs to land on a calendar month the
/// user picked directly, rather than one they stepped to.
int monthOffsetFor(DateTime now, int year, int month, int startDay) {
  final current = MonthWindow.forDate(now, monthStartDay: startDay).start;
  return (year - current.year) * 12 + (month - current.month);
}

/// How far back month navigation can usefully go: the offset of the oldest
/// month that actually holds a transaction.
///
/// Without it the arrows step endlessly into empty months, which reads as the
/// app having lost the data rather than there being none before that point.
///
/// Computed through [MonthWindow] rather than by subtracting calendar months,
/// because a user whose month starts on the 15th has transactions that fall in
/// the *previous* window from the one their date would suggest.
final oldestMonthOffsetProvider = Provider<int>((ref) {
  final transactions =
      ref.watch(transactionsProvider).value ?? const <AppTransaction>[];
  if (transactions.isEmpty) return 0;

  final preferences =
      ref.watch(preferencesProvider).value ?? const UserPreferences();

  var oldest = transactions.first.occurredAt;
  for (final transaction in transactions) {
    if (transaction.occurredAt.isBefore(oldest)) {
      oldest = transaction.occurredAt;
    }
  }

  final oldestStart = MonthWindow.forDate(
    oldest,
    monthStartDay: preferences.monthStartDay,
  ).start;
  final currentStart = MonthWindow.forDate(
    DateTime.now(),
    monthStartDay: preferences.monthStartDay,
  ).start;

  final months =
      (oldestStart.year - currentStart.year) * 12 +
      (oldestStart.month - currentStart.month);
  return months.clamp(-240, 0);
});

final budgetProgressProvider = Provider<List<BudgetProgress>>((ref) {
  final budgets = ref.watch(budgetsProvider).value ?? const <Budget>[];
  final summary = ref.watch(monthComparisonProvider).current;
  return buildBudgetProgress(
    budgets: budgets.where((b) => b.currency == summary.currency).toList(),
    summary: summary,
  );
});

/// The overall monthly budget, if the user set one.
final overallBudgetProvider = Provider<BudgetProgress?>((ref) {
  final progress = ref.watch(budgetProgressProvider);
  for (final entry in progress) {
    if (entry.budget.isOverall) return entry;
  }
  return null;
});

// ------------------------------------------------------------------- capture

final notificationAccessProvider = Provider<NotificationAccess>(
  (ref) => NotificationAccess(),
);

/// Live permission state, re-read from Android rather than cached.
final notificationPermissionProvider = FutureProvider<bool>(
  (ref) => ref.watch(notificationAccessProvider).isGranted(),
);

/// Counters describing what the Android capture path has actually done.
///
/// Without these, "no transactions" and "capture is broken" look identical.
final captureStatsProvider = FutureProvider<CaptureStats>(
  (ref) => ref.watch(notificationAccessProvider).stats(),
);

/// Which bank apps are actually installed, keyed by package name.
///
/// Turns "we assume CIBC ships as com.cibc.android.mobi" into something the
/// user can see. A bank whose app is not detected cannot deliver alerts, and
/// saying so beats letting the user wonder why nothing appears.
final installedBankAppsProvider = FutureProvider<Map<String, String>>((ref) {
  final candidates = <String>{
    for (final bank in Banks.all) ...bank.packageNames,
  };
  return ref.watch(notificationAccessProvider).findInstalledApps(candidates);
});

/// Whether a specific bank's app was found on this device.
final bankDetectionProvider = Provider.family<BankDetection, String>((
  ref,
  bankId,
) {
  final bank = Banks.byId(bankId);
  if (bank == null || bank.packageNames.isEmpty) {
    return BankDetection.notApplicable;
  }

  final installed = ref.watch(installedBankAppsProvider);
  if (installed.isLoading) return BankDetection.checking;
  final found = installed.value;
  if (found == null || found.isEmpty) return BankDetection.unknown;

  for (final packageName in bank.packageNames) {
    if (found.containsKey(packageName)) return BankDetection.installed;
  }
  return BankDetection.notInstalled;
});

enum BankDetection {
  checking,
  installed,
  notInstalled,

  /// The platform could not answer — off Android, or the channel is absent.
  /// Deliberately distinct from [notInstalled]: claiming an app is missing
  /// when we simply could not look would be worse than saying nothing.
  unknown,

  /// The bank has no app to detect, e.g. "Other".
  notApplicable,
}

/// Generates transaction ids. Time-ordered so a list sorts sensibly even
/// before the server sees the row.
String generateId() {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = Random().nextInt(1 << 32).toRadixString(36);
  return '$now-$salt';
}

/// Adapts the transaction repository to the ingest pipeline's narrower need.
class _RepositorySink implements TransactionSink {
  _RepositorySink(this._repository);
  final TransactionRepository _repository;

  @override
  Future<void> save(AppTransaction transaction) =>
      _repository.upsert(transaction);

  @override
  Future<List<AppTransaction>> recent({required Duration window}) =>
      _repository.list(from: DateTime.now().subtract(window));

  @override
  Future<bool> existsNear(
    String fingerprint,
    DateTime at,
    Duration window,
  ) async {
    final nearby = await _repository.list(
      from: at.subtract(window),
      to: at.add(window),
    );
    return nearby.any((t) => t.fingerprint == fingerprint);
  }
}

final ingestServiceProvider = Provider<IngestService>((ref) {
  final service = IngestService(
    sink: _RepositorySink(ref.watch(dataLayerProvider).transactions),
    idGenerator: generateId,
    categorizer: ref.watch(categorizerProvider),
    duplicateWindow: Env.duplicateWindow,
  );
  return service;
});

/// The Android package names to watch, derived from the banks the user picked.
final watchedPackagesProvider = Provider<Set<String>>((ref) {
  final selected =
      ref.watch(preferencesProvider).value?.selectedBankIds ?? const <String>{};
  return <String>{for (final id in selected) ...?Banks.byId(id)?.packageNames};
});
