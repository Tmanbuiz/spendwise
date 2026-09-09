import '../../widgets/spending_changes_card.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/router/app_router.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/insight_widgets.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(spendingInsightsProvider);
    final transactions = ref.watch(transactionsProvider);
    final theme = Theme.of(context);
    final projection = data.projectedCents;
    final largestMonth = data.history.fold<int>(
      1,
      (max, month) => month.totalSpentCents > max ? month.totalSpentCents : max,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Monthly overview',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => context.push(Routes.monthlyOverview),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
            'Understand the patterns behind your spending.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          const PeriodSelector(),
          const SizedBox(height: 14),
          if (transactions.isLoading && !transactions.hasValue)
            const Center(child: CircularProgressIndicator())
          else if (transactions.hasError)
            InsightNote(
              title: 'Insights are unavailable',
              message: 'Tap to reload your transactions.',
              onTap: () => ref.read(transactionsProvider.notifier).refresh(),
            )
          else ...[
            MetricPair(
              first: MetricCard(
                label: 'Average purchase',
                value: data.current.isEmpty
                    ? '—'
                    : Fmt.money(
                        data.averagePurchaseCents,
                        currency: data.currency,
                      ),
                icon: Icons.receipt_long_outlined,
                detail: '${data.current.transactionCount} recorded purchases',
              ),
              second: MetricCard(
                label: data.isCurrent ? 'Period-end estimate' : 'Period total',
                value: data.isCurrent
                    ? projection == null
                          ? '—'
                          : Fmt.moneyCompact(
                              projection,
                              currency: data.currency,
                            )
                    : Fmt.moneyCompact(
                        data.current.totalSpentCents,
                        currency: data.currency,
                      ),
                icon: Icons.trending_up_rounded,
                detail: data.isCurrent
                    ? projection == null
                          ? 'Available after 7 days with spending'
                          : 'If the recorded daily pace continues'
                    : 'Recorded spending',
              ),
            ),
            const SizedBox(height: 16),
            InsightNote(
              title: 'Compare like with like',
              message: data.comparable.percentChange == null
                  ? 'No spending recorded in the matching prior period. Add older statements to build a useful comparison.'
                  : 'First ${data.comparisonDays} days: ${Fmt.money(data.comparable.current.totalSpentCents, currency: data.currency)} this period vs ${Fmt.money(data.comparable.previous.totalSpentCents, currency: data.currency)} in the prior period. Today may still be incomplete.',
            ),
            const SizedBox(height: 14),
            SpendingChangesCard(data: data),
            const SizedBox(height: 14),
            const SectionHeader(title: 'Daily spending'),
            SectionCard(
              child: data.current.isEmpty
                  ? const EmptyState(
                      icon: Icons.bar_chart_rounded,
                      title: 'Your next purchase starts the chart',
                      message: 'Only recorded purchases count toward spending.',
                    )
                  : DailySpendingChart(insights: data),
            ),
            const SizedBox(height: 14),
            const SectionHeader(title: 'Six-period trend'),
            SectionCard(
              child: Column(
                children: [
                  for (final month in data.history)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${Fmt.monthName(month.window.start)}${month.window.start == data.window.start && data.isCurrent ? ' · so far' : ''}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              Text(
                                Fmt.money(
                                  month.totalSpentCents,
                                  currency: data.currency,
                                ),
                                style: theme.textTheme.labelLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: month.totalSpentCents / largestMonth,
                              minHeight: 8,
                              color: month.window.start == data.window.start
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.primary.withValues(
                                      alpha: 0.35,
                                    ),
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
            const SectionHeader(title: 'Category breakdown'),
            SectionCard(child: CategoryBreakdown(summary: data.current)),
            const SizedBox(height: 14),
            const SectionHeader(title: 'Top merchants'),
            SectionCard(
              child: data.topMerchants.isEmpty
                  ? const Text(
                      'Merchant totals appear as you record purchases.',
                    )
                  : Column(
                      children: [
                        for (final merchant in data.topMerchants.take(5))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.09,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.storefront_outlined,
                                    color: theme.colorScheme.primary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        merchant.name,
                                        style: theme.textTheme.titleSmall,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${merchant.count} purchases',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  Fmt.money(
                                    merchant.amountCents,
                                    currency: data.currency,
                                  ),
                                  style: theme.textTheme.labelLarge,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            Text(
              'Based on recorded ${data.currency} purchases only. Refunds, transfers, card payments and excluded items are not spending. Estimates are not account balances and may be incomplete when history is missing.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
