import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_transaction.dart';
import '../../features/accounts/accounts_screen.dart';
import '../../features/assistant/ask_spendwise_screen.dart';
import '../../features/assistant/financial_rules_screen.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/budgets/budgets_screen.dart';
import '../../features/categories/categories_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/debug/parser_debug_screen.dart';
import '../../features/import/statement_import_screen.dart';
import '../../features/insights/insights_screen.dart';
import '../../features/onboarding/bank_selection_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/onboarding/permission_screen.dart';
import '../../features/settings/diagnostics_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/home_shell.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/transactions/transaction_detail_screen.dart';
import '../../features/transactions/transactions_screen.dart';
import '../../features/vault/financial_vault_screen.dart';
import '../../state/providers.dart';
import '../config/env.dart';

abstract final class Routes {
  static const splash = '/';
  static const auth = '/auth';
  static const onboarding = '/onboarding';
  // Onboarding-flow versions. These continue to the next step when finished.
  static const bankSelection = '/onboarding/banks';
  static const permission = '/onboarding/permission';

  // Standalone versions, reachable after setup is done.
  //
  // Separate paths rather than reusing the onboarding versions, because the
  // redirect sends every `/onboarding/*` route to the dashboard once
  // onboarding is complete.
  static const banks = '/banks';
  static const notificationAccess = '/notification-access';
  static const dashboard = '/home';
  static const transactions = '/home/transactions';
  static const budgets = '/home/budgets';
  static const insights = '/home/insights';
  static const settings = '/home/settings';
  static const accounts = '/accounts';
  static const categories = '/categories';
  static const debug = '/debug';
  static const diagnostics = '/diagnostics';
  static const importStatement = '/import';
  static const vault = '/vault';
  static const assistant = '/ask';
  static const financialRules = '/financial-rules';
  static const transactionDetail = 'transaction';
}

/// Wakes GoRouter when the state the redirect depends on changes.
///
/// The redirect reads providers with `ref.read`, which does not subscribe. On
/// its own that strands the user on the splash screen forever: the first
/// evaluation sees preferences still loading and returns them to splash, and
/// nothing ever asks the router to look again once loading finishes. This
/// notifier is what asks.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(preferencesProvider, (_, _) => notifyListeners());
    ref.listen(authUserProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => _redirect(ref, state),
    routes: <RouteBase>[
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.auth, builder: (_, _) => const AuthScreen()),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.bankSelection,
        builder: (_, _) => const BankSelectionScreen(isOnboarding: true),
      ),
      GoRoute(
        path: Routes.permission,
        builder: (_, _) => const PermissionScreen(isOnboarding: true),
      ),
      GoRoute(
        path: Routes.banks,
        builder: (_, _) => const BankSelectionScreen(),
      ),
      GoRoute(
        path: Routes.notificationAccess,
        builder: (_, _) => const PermissionScreen(),
      ),
      GoRoute(path: Routes.accounts, builder: (_, _) => const AccountsScreen()),
      GoRoute(
        path: Routes.categories,
        builder: (_, _) => const CategoriesScreen(),
      ),
      GoRoute(path: Routes.debug, builder: (_, _) => const ParserDebugScreen()),
      GoRoute(
        path: Routes.diagnostics,
        builder: (_, _) => const DiagnosticsScreen(),
      ),
      GoRoute(
        path: Routes.importStatement,
        builder: (_, _) => const StatementImportScreen(),
      ),
      GoRoute(
        path: Routes.vault,
        builder: (_, _) => const FinancialVaultScreen(),
      ),
      GoRoute(
        path: Routes.assistant,
        builder: (_, _) => const AskSpendWiseScreen(),
      ),
      GoRoute(
        path: Routes.financialRules,
        builder: (_, _) => const FinancialRulesScreen(),
      ),
      GoRoute(
        path: '/transaction',
        builder: (context, state) => TransactionDetailScreen(
          transaction: state.extra as AppTransaction?,
        ),
      ),
      // The five primary tabs live inside a persistent shell so the bottom bar
      // does not rebuild or animate away when switching between them.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.dashboard,
                builder: (_, _) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.transactions,
                builder: (_, _) => const TransactionsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.budgets,
                builder: (_, _) => const BudgetsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.insights,
                builder: (_, _) => const InsightsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.settings,
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Gate order: signed in, then onboarded. Anything else falls through.
///
/// Preferences are read without blocking: while they are still loading the
/// splash screen stays put rather than flashing onboarding at a user who has
/// already finished it.
String? _redirect(Ref ref, GoRouterState state) {
  final location = state.matchedLocation;
  final preferences = ref.read(preferencesProvider);

  if (preferences.isLoading) {
    return location == Routes.splash ? null : Routes.splash;
  }

  final signedIn = ref.read(isSignedInProvider);
  final onboarded = preferences.value?.onboardingComplete ?? false;

  final isAuthRoute = location == Routes.auth;
  final isOnboardingRoute = location.startsWith('/onboarding');

  if (!signedIn && Env.isConfigured) {
    return isAuthRoute ? null : Routes.auth;
  }

  if (!onboarded) {
    return isOnboardingRoute ? null : Routes.onboarding;
  }

  // Already past the gates: never leave the user sitting on splash or auth.
  if (location == Routes.splash || isAuthRoute || isOnboardingRoute) {
    return Routes.dashboard;
  }

  return null;
}
