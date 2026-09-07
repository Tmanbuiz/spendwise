import '../../services/budget_alerts.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/capture_controller.dart';

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

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame so provider writes do not happen
    // during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(captureControllerProvider).start();
    });
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
