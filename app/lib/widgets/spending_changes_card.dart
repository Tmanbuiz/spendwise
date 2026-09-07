import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../data/spending_changes.dart';
import '../data/spending_insights.dart';
import 'common.dart';

class SpendingChangesCard extends StatelessWidget {
  const SpendingChangesCard({super.key, required this.data});
  final SpendingInsights data;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comparison = data.comparable;
    final difference = comparison.differenceCents;
    final changes = data.categoryChanges;
    final increases = changes
        .where((c) => c.differenceCents > 0)
        .take(3)
        .toList();
    final decreases = changes
        .where((c) => c.differenceCents < 0)
        .take(3)
        .toList();
    String money(int cents) => Fmt.money(cents, currency: data.currency);
    final previousMissing = comparison.previous.isEmpty;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What changed', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            previousMissing
                ? 'Build your comparison'
                : difference == 0
                ? 'Recorded spending is unchanged'
                : '${money(difference.abs())} ${difference > 0 ? 'more' : 'less'} recorded',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Comparing the first ${data.comparisonDays} days of each period. ${data.isCurrent ? 'Today may still be incomplete. ' : ''}Based only on recorded purchases; missing statements can affect the comparison.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (previousMissing)
            const Text(
              'No purchases are recorded in the matching prior period. Import older statements to explain changes over time.',
            )
          else ...[
            Text(
              '${money(comparison.current.totalSpentCents)} this period · ${money(comparison.previous.totalSpentCents)} previously',
            ),
            const SizedBox(height: 8),
            Text(
              '${comparison.current.transactionCount} purchases vs ${comparison.previous.transactionCount} previously',
              style: theme.textTheme.bodySmall,
            ),
            if (increases.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Largest increases', style: theme.textTheme.labelLarge),
              for (final change in increases)
                _ChangeRow(change: change, data: data),
            ],
            if (decreases.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Largest decreases', style: theme.textTheme.labelLarge),
              for (final change in decreases)
                _ChangeRow(change: change, data: data),
            ],
            if (increases.isEmpty && decreases.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Your category totals are unchanged across these matching periods.',
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Tap a category to review the purchases behind its totals.',
            ),
          ],
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change, required this.data});
  final CategoryChange change;
  final SpendingInsights data;
  @override
  Widget build(BuildContext context) {
    final up = change.differenceCents > 0;
    final percent = change.percentChange;
    final description = percent == null
        ? 'No prior recorded spending'
        : '${(percent.abs() * 100).toStringAsFixed(0)}% ${up ? 'increase' : 'decrease'}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(up ? Icons.trending_up : Icons.trending_down),
      title: Text(change.category.displayName),
      subtitle: Text(
        '${Fmt.money(change.differenceCents.abs(), currency: data.currency)} ${up ? 'more' : 'less'} · $description',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .75,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(
                  change.category.displayName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text('First ${data.comparisonDays} days in each period'),
                for (final summary in [
                  data.comparable.current,
                  data.comparable.previous,
                ]) ...[
                  const SizedBox(height: 18),
                  Text(
                    '${summary == data.comparable.current ? 'This period' : 'Previous period'} · ${Fmt.monthName(summary.window.start)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (!data.purchases.any(
                    (t) =>
                        t.category == change.category &&
                        summary.window.contains(t.occurredAt),
                  ))
                    const Text('No recorded purchases.'),
                  for (final transaction
                      in (data.purchases
                          .where(
                            (t) =>
                                t.category == change.category &&
                                summary.window.contains(t.occurredAt),
                          )
                          .toList()
                        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt))))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(transaction.displayMerchant),
                      subtitle: Text(Fmt.shortDate(transaction.occurredAt)),
                      trailing: Text(
                        Fmt.money(
                          transaction.amountCents,
                          currency: data.currency,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
