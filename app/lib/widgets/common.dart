import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

import '../core/formatters.dart';
import '../core/theme/app_theme.dart';
import '../data/models/app_transaction.dart';
import '../data/models/budget.dart';
import '../data/month_summary.dart';

/// A padded, rounded surface. Used everywhere instead of raw `Card` so
/// spacing and radius stay consistent across screens.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A titled block with optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// The hero figure on the dashboard: this month's spend.
class SpendHeadline extends StatelessWidget {
  const SpendHeadline({
    super.key,
    required this.comparison,
    required this.monthLabel,
  });

  final MonthComparison comparison;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = comparison.current;
    final change = comparison.percentChange;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Spent in $monthLabel',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          Fmt.money(summary.totalSpentCents, currency: summary.currency),
          style: theme.textTheme.displaySmall,
        ),
        const SizedBox(height: 10),
        if (change != null)
          _ChangePill(comparison: comparison, change: change)
        else
          Text(
            comparison.previous.isEmpty
                ? 'No spending last month to compare with'
                : 'First month of tracking',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _ChangePill extends StatelessWidget {
  const _ChangePill({required this.comparison, required this.change});

  final MonthComparison comparison;
  final double change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Spending more is not an error, so this is amber rather than red — the
    // red is reserved for actually breaching a budget.
    final up = comparison.spentMore;
    final color = up ? AppTheme.warning : AppTheme.positive;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            '${Fmt.percent(change.abs())} ${up ? "more" : "less"} '
            'than last month',
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Donut of spending by category, with a legend.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({super.key, required this.summary});

  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.byCategory.isEmpty) {
      return const EmptyState(
        icon: Icons.pie_chart_outline_rounded,
        title: 'No spending yet',
        message: 'Categories appear here once transactions come in.',
      );
    }

    return Column(
      children: <Widget>[
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 58,
              startDegreeOffset: -90,
              sections: <PieChartSectionData>[
                for (final entry in summary.byCategory)
                  PieChartSectionData(
                    value: entry.amountCents.toDouble(),
                    color: AppTheme.categoryColor(entry.category),
                    radius: 26,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final entry in summary.byCategory)
          _LegendRow(entry: entry, currency: summary.currency),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.entry, required this.currency});

  final CategoryTotal entry;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AppTheme.categoryColor(entry.category),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.category.displayName,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            Fmt.percent(entry.shareOfTotal),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            Fmt.money(entry.amountCents, currency: currency),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Progress bar for one budget.
class BudgetBar extends StatelessWidget {
  const BudgetBar({super.key, required this.progress, this.onTap});

  final BudgetProgress progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final budget = progress.budget;
    final over = progress.isOverBudget;
    final color = over
        ? AppTheme.negative
        : budget.isOverall
            ? theme.colorScheme.primary
            : AppTheme.categoryColor(budget.category!);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (!budget.isOverall) ...<Widget>[
                  Icon(AppTheme.categoryIcon(budget.category!),
                      size: 18, color: color),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    budget.isOverall
                        ? 'Monthly budget'
                        : budget.category!.displayName,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onTap != null) Icon(Icons.edit_outlined, size: 17,
                  color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${Fmt.money(progress.spentCents, currency: budget.currency)}'
              ' / ${Fmt.moneyCompact(budget.amountCents, currency: budget.currency)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 8,
                backgroundColor: color.withValues(alpha: 0.14),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              over
                  ? '${Fmt.money(progress.remainingCents.abs(), currency: budget.currency)} over budget'
                  : '${Fmt.money(progress.remainingCents, currency: budget.currency)} left',
              style: theme.textTheme.labelMedium?.copyWith(
                color: over ? AppTheme.negative : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in a transaction list.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    this.onTap,
  });

  final AppTransaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = transaction.countsAsSpending;
    final color = AppTheme.categoryColor(transaction.category);

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          AppTheme.categoryIcon(transaction.category),
          color: color,
          size: 22,
        ),
      ),
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              transaction.displayMerchant,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (transaction.needsReview) ...<Widget>[
            const SizedBox(width: 6),
            Icon(Icons.error_outline_rounded,
                size: 15, color: AppTheme.warning),
          ],
        ],
      ),
      subtitle: Text(
        _subtitle(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            Fmt.money(transaction.amountCents, currency: transaction.currency),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              // Only spending is rendered in full strength; everything else is
              // context, and is dimmed so the eye skips it.
              color: counts
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              decoration: transaction.excludedByUser
                  ? TextDecoration.lineThrough
                  : null,
            ),
          ),
          if (!counts)
            Text(
              _excludedLabel(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[
      Fmt.relativeDay(transaction.occurredAt),
      transaction.category.displayName,
      if (transaction.accountLast4 != null) '••${transaction.accountLast4}',
    ];
    return parts.join('  ·  ');
  }

  String _excludedLabel() {
    if (transaction.excludedByUser) return 'Excluded';
    switch (transaction.eventType) {
      case TransactionEventType.refund:
        return 'Refund';
      case TransactionEventType.payment:
        return 'Card payment';
      case TransactionEventType.transfer:
        return 'Transfer';
      case TransactionEventType.declined:
        return 'Declined';
      case TransactionEventType.purchase:
      case TransactionEventType.unknown:
        return 'Not counted';
    }
  }
}

/// Shown wherever a list has nothing in it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 30, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(height: 20),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Picker used by the detail screen and the rules editor.
class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final SpendCategory selected;
  final ValueChanged<SpendCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final category in SpendCategory.values)
          ChoiceChip(
            selected: category == selected,
            onSelected: (_) => onChanged(category),
            avatar: Icon(
              AppTheme.categoryIcon(category),
              size: 17,
              color: AppTheme.categoryColor(category),
            ),
            label: Text(category.displayName),
          ),
      ],
    );
  }
}
