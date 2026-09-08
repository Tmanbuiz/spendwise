import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/insight_widgets.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final insights = ref.watch(spendingInsightsProvider);
    final overall = ref.watch(overallBudgetProvider);
    final transactions = ref.watch(transactionsProvider);
    final allowance = insights.dailyAllowance(overall);
    final permission = ref.watch(notificationPermissionProvider);
    final supportsCapture = ref.watch(notificationAccessProvider).isSupportedPlatform;
    final recent =
        (transactions.value ?? [])
            .where((t) => insights.window.contains(t.occurredAt))
            .toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final categories = insights.current.byCategory;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.stacked_line_chart_rounded,
                color: theme.colorScheme.onPrimary,
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            const Text('SpendWise'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ask SpendWise',
            onPressed: () => context.push(Routes.assistant),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.go(Routes.settings),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/transaction'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add expense'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(reportingNowProvider);
          ref.invalidate(notificationPermissionProvider);
          await ref.read(transactionsProvider.notifier).refresh();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 104),
          children: [
            Text(
              'A little clarity. A lot more control.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            const PeriodSelector(),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _QuickAction(
                    icon: Icons.auto_awesome_outlined,
                    label: 'Ask',
                    detail: 'Your data',
                    onTap: () => context.push(Routes.assistant),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.folder_copy_outlined,
                    label: 'Vault',
                    detail: 'Documents',
                    onTap: () => context.push(Routes.vault),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.upload_file_outlined,
                    label: 'Import',
                    detail: 'Statement',
                    onTap: () => context.push(Routes.importStatement),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (supportsCapture && permission.value == false) ...[
              InsightNote(
                title: 'Notification access is off',
                message: 'Turn it on to capture new bank purchase alerts.',
                icon: Icons.notifications_off_outlined,
                onTap: () => context.push(Routes.notificationAccess),
              ),
              const SizedBox(height: 12),
            ],
            if (transactions.isLoading && !transactions.hasValue)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (transactions.hasError)
              const InsightNote(
                title: 'Could not load your spending',
                message: 'Pull down to try again.',
                icon: Icons.cloud_off_outlined,
              )
            else ...[
              SpendingHero(
                insights: insights,
                budget: overall,
                onBudget: () => context.go(Routes.budgets),
              ),
              const SizedBox(height: 14),
              MetricPair(
                first: MetricCard(
                  label: allowance == null ? 'Purchases' : 'Daily budget left',
                  value: allowance == null
                      ? '${insights.current.transactionCount}'
                      : Fmt.money(allowance, currency: insights.currency),
                  icon: Icons.savings_outlined,
                  detail: allowance == null
                      ? 'Recorded this period'
                      : 'Across ${insights.daysLeft} days, including today',
                ),
                second: MetricCard(
                  label: 'Daily average',
                  value: insights.current.isEmpty
                      ? '—'
                      : Fmt.money(
                          insights.dailyAverageCents,
                          currency: insights.currency,
                        ),
                  icon: Icons.show_chart_rounded,
                  detail: '${insights.elapsedDays} days in this period',
                ),
              ),
              const SizedBox(height: 16),
              if (overall != null)
                InsightNote(
                  title: 'Monthly budget',
                  message: overall.isOverBudget
                      ? 'You are ${Fmt.money(overall.remainingCents.abs(), currency: insights.currency)} over your limit. Review your category budgets to adjust your plan.'
                      : '${Fmt.percent(overall.fraction)} used · ${Fmt.percent(insights.periodFraction)} of the period elapsed.',
                  onTap: () => context.go(Routes.budgets),
                )
              else
                InsightNote(
                  title: 'Bring your history into focus',
                  message: 'Import a bank statement to see earlier spending and more useful trends.',
                  icon: Icons.file_upload_outlined,
                  onTap: () => context.push(Routes.importStatement),
                ),
              const SizedBox(height: 14),
              SectionHeader(
                title: 'Where it went',
                action: TextButton(
                  onPressed: () => context.go(Routes.insights),
                  child: const Text('Insights'),
                ),
              ),
              SectionCard(
                child: categories.isEmpty
                    ? const EmptyState(
                        icon: Icons.donut_large_rounded,
                        title: 'No spending yet',
                        message: 'Your category breakdown will appear here.',
                      )
                    : Column(
                        children: [
                          for (final entry in categories.take(3))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        AppTheme.categoryIcon(entry.category),
                                        color: AppTheme.categoryColor(entry.category),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          entry.category.displayName,
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ),
                                      Text(
                                        Fmt.money(
                                          entry.amountCents,
                                          currency: insights.currency,
                                        ),
                                        style: theme.textTheme.labelLarge,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(9),
                                    child: LinearProgressIndicator(
                                      value: entry.shareOfTotal,
                                      minHeight: 5,
                                      color: AppTheme.categoryColor(entry.category),
                                      backgroundColor:
                                          theme.colorScheme.surfaceContainerHighest,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              SectionHeader(
                title: 'Recent activity',
                action: TextButton(
                  onPressed: () => context.go(Routes.transactions),
                  child: const Text('See all'),
                ),
              ),
              SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: recent.isEmpty
                    ? const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'Nothing here yet',
                        message: 'Add an expense, import a statement, or capture a new bank alert.',
                      )
                    : Column(
                        children: [
                          for (final t in recent.take(5))
                            TransactionTile(
                              transaction: t,
                              onTap: () => context.push('/transaction', extra: t),
                            ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            children: <Widget>[
              Icon(icon, color: theme.colorScheme.primary, size: 22),
              const SizedBox(height: 6),
              Text(label, style: theme.textTheme.labelLarge),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
