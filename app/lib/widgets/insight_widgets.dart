import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters.dart';
import '../core/theme/app_theme.dart';
import '../data/models/budget.dart';
import '../data/spending_insights.dart';
import '../state/providers.dart';
import 'common.dart';

class PeriodSelector extends ConsumerWidget {
  const PeriodSelector({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(spendingInsightsProvider).window;
    final offset = ref.watch(monthOffsetProvider);
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Fmt.monthAndYear(window.start),
                style: theme.textTheme.titleMedium,
              ),
              if (window.start.day != 1)
                Text(
                  '${Fmt.shortDate(window.start)} – ${Fmt.shortDate(window.end.subtract(const Duration(days: 1)))}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
        if (offset != 0)
          TextButton(
            onPressed: () => ref.read(monthOffsetProvider.notifier).reset(),
            child: const Text('Today'),
          ),
        IconButton(
          tooltip: 'Previous month',
          onPressed: offset <= ref.watch(oldestMonthOffsetProvider)
              ? null
              : () => ref.read(monthOffsetProvider.notifier).step(-1),
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
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.detail,
  });
  final String label, value, detail;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: theme.colorScheme.primary),
          const SizedBox(height: 14),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class MetricPair extends StatelessWidget {
  const MetricPair({super.key, required this.first, required this.second});
  final Widget first, second;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.4) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 12), second],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        ),
      );
    },
  );
}

class SpendingHero extends StatelessWidget {
  const SpendingHero({
    super.key,
    required this.insights,
    required this.budget,
    required this.onBudget,
  });
  final SpendingInsights insights;
  final BudgetProgress? budget;
  final VoidCallback onBudget;
  @override
  Widget build(BuildContext context) {
    final change = insights.comparable.percentChange;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.navy, Color(0xFF174A54)],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: AppTheme.brandBright,
                size: 20,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'TOTAL SPENT',
                  style: TextStyle(
                    color: Color(0xFFB9D2DA),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
              Text(
                insights.currency,
                style: const TextStyle(color: Color(0xFFB9D2DA), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            Fmt.money(
              insights.current.totalSpentCents,
              currency: insights.currency,
            ),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.8,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            change == null
                ? 'Your spending story starts here'
                : '${Fmt.percent(change.abs())} ${change > 0
                      ? 'more'
                      : change < 0
                      ? 'less'
                      : 'change'} · first ${insights.comparisonDays} days vs prior period',
            style: const TextStyle(
              color: Color(0xFFC8E4E8),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          if (budget != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: budget!.fraction,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                color: budget!.isOverBudget
                    ? const Color(0xFFFFB8A8)
                    : AppTheme.brandBright,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Text(
                  '${Fmt.money(budget!.remainingCents.abs(), currency: insights.currency)} ${budget!.isOverBudget ? 'over budget' : 'left'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'of ${Fmt.moneyCompact(budget!.budget.amountCents, currency: insights.currency)} budget',
                  style: const TextStyle(color: Color(0xFFB9D2DA)),
                ),
              ],
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF66949D)),
                  minimumSize: const Size(0, 46),
                ),
                onPressed: onBudget,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Set a monthly budget'),
              ),
            ),
        ],
      ),
    );
  }
}

class InsightNote extends StatelessWidget {
  const InsightNote({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.auto_awesome_outlined,
    this.onTap,
  });
  final String title, message;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 23),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 20),
        ],
      ),
    );
  }
}

/// Native, tappable daily chart with a text readout for exact values.
class DailySpendingChart extends StatefulWidget {
  const DailySpendingChart({super.key, required this.insights});
  final SpendingInsights insights;
  @override
  State<DailySpendingChart> createState() => _DailySpendingChartState();
}

class _DailySpendingChartState extends State<DailySpendingChart> {
  int? selected;
  @override
  void didUpdateWidget(covariant DailySpendingChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.insights.window.start != widget.insights.window.start) {
      selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.insights;
    final theme = Theme.of(context);
    final values = data.dailyCents;
    final maximum = math.max(1, values.fold<int>(0, math.max));
    final index =
        selected ?? (data.elapsedDays - 1).clamp(0, values.length - 1);
    final date = DateTime(
      data.window.start.year,
      data.window.start.month,
      data.window.start.day + index,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                Fmt.shortDate(date),
                style: theme.textTheme.bodySmall,
              ),
            ),
            Text(
              Fmt.money(values[index], currency: data.currency),
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Semantics(
                    label:
                        'Day ${i + 1}, ${Fmt.money(values[i], currency: data.currency)}',
                    button: true,
                    selected: index == i,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => selected = i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: math.max(3.0, values[i] / maximum * 100),
                            decoration: BoxDecoration(
                              color: i >= data.elapsedDays
                                  ? theme.colorScheme.outlineVariant
                                  : index == i
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.primary.withValues(
                                      alpha: 0.35,
                                    ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              Fmt.shortDate(data.window.start),
              style: theme.textTheme.labelSmall,
            ),
            Text(
              'Tap a day',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              Fmt.shortDate(data.window.end.subtract(const Duration(days: 1))),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ],
    );
  }
}
