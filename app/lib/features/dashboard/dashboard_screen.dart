import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_transaction.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// The home dashboard: this month's total, budget remaining, category
/// breakdown, recent activity and a comparison with last month.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final comparison = ref.watch(monthComparisonProvider);
    final overall = ref.watch(overallBudgetProvider);
    final transactions = ref.watch(transactionsProvider);
    final offset = ref.watch(monthOffsetProvider);
    final permission = ref.watch(notificationPermissionProvider);
    final accessGranted = permission.value ?? false;
    final supportsCapture =
        ref.watch(notificationAccessProvider).isSupportedPlatform;

    return Scaffold(
      appBar: AppBar(
        title: Text(Fmt.monthAndYear(comparison.current.window.start)),
        actions: <Widget>[
          IconButton(
            tooltip: 'Previous month',
            onPressed: () => ref.read(monthOffsetProvider.notifier).step(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: 'Next month',
            onPressed: offset >= 0
                ? null
                : () => ref.read(monthOffsetProvider.notifier).step(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/transaction'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(transactionsProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: <Widget>[
            if (supportsCapture && !accessGranted)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AlertBanner(
                  icon: Icons.notifications_off_outlined,
                  title: 'Notification access is off',
                  body: 'Purchases will not be recorded automatically.',
                  actionLabel: 'Turn on',
                  onAction: () => context.push(Routes.notificationAccess),
                ),
              ),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SpendHeadline(
                    comparison: comparison,
                    monthLabel: Fmt.monthName(comparison.current.window.start),
                  ),
                  if (overall != null) ...<Widget>[
                    const Divider(height: 32),
                    BudgetBar(
                      progress: overall,
                      onTap: () => context.go(Routes.budgets),
                    ),
                  ] else ...<Widget>[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => context.go(Routes.budgets),
                      icon: const Icon(Icons.savings_outlined),
                      label: const Text('Set a monthly budget'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'Where it went'),
            SectionCard(
              child: CategoryBreakdown(summary: comparison.current),
            ),
            const SizedBox(height: 20),
            SectionHeader(
              title: 'Recent activity',
              action: TextButton(
                onPressed: () => context.go(Routes.transactions),
                child: const Text('See all'),
              ),
            ),
            SectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: transactions.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load transactions.\n$error',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                data: (all) => _RecentList(transactions: all),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.transactions});

  final List<AppTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Nothing here yet',
        message: 'Your next card purchase will show up automatically, or you '
            'can add one by hand.',
      );
    }

    final recent = transactions.take(6).toList();
    return Column(
      children: <Widget>[
        for (final transaction in recent)
          TransactionTile(
            transaction: transaction,
            onTap: () => context.push('/transaction', extra: transaction),
          ),
      ],
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: AppTheme.warning, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.labelLarge),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
