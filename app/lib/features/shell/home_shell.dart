import '../../services/budget_alerts.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../services/capture_controller.dart';
import '../../services/shared_statements.dart';

/// The four-tab shell holding the main screens.
///
/// Capture is started here rather than in `main` because this is the first
/// point at which the user is definitely past onboarding — starting the
/// listener earlier would attach a stream before any bank has been chosen.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deferred to after the first frame so provider writes do not happen
    // during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(captureControllerProvider).start();
      _openSharedStatements();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A statement shared while the app was already open arrives as a new
  /// intent, which resumes the activity rather than recreating it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _openSharedStatements();
  }

  /// Opens the import screen when another app has handed over a statement.
  ///
  /// Only asks whether anything is waiting; the import screen takes the
  /// queue itself, so a failed navigation cannot swallow the files.
  /// True while the import screen this shell opened is still on top.
  ///
  /// Sharing several statements in quick succession resumes the app once
  /// per file. Without this each resume stacked another import screen, and
  /// only the first one ever saw the files — every screen above it drained
  /// an empty queue and showed nothing.
  bool _importOpen = false;

  Future<void> _openSharedStatements() async {
    if (_importOpen) return;
    if (!await const SharedStatements().hasPending()) return;
    if (!mounted) return;
    _importOpen = true;
    await context.push(Routes.importStatement);
    _importOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(activeBudgetAlertsProvider);
    final enabled = ref.watch(alertsEnabledProvider).value ?? false;
    if (enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(alertDispatcherProvider).send(alerts);
      });
    }
    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.shell.currentIndex,
        onDestinationSelected: (index) => widget.shell.goBranch(
          index,
          // Tapping the active tab returns it to its root, which is the
          // behaviour users expect from a bottom bar.
          initialLocation: index == widget.shell.currentIndex,
        ),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline_rounded),
            selectedIcon: Icon(Icons.pie_chart_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings_rounded),
            label: 'Budgets',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Insights',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
