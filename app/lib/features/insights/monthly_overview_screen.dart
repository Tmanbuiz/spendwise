import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../data/monthly_overview.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// One month, told as where the money came from and where it went.
///
/// The three headline figures are money out, money in and the net of the two,
/// rather than "expenses, income, savings". Expenses would have to include a
/// transfer into savings for the figures to add up, and calling a savings
/// contribution an expense is exactly the reading the rest of the app exists
/// to avoid. Spending still appears — as the first group under Money out,
/// where it can be seen against the transfers and debt payments it sits
/// beside.
class MonthlyOverviewScreen extends ConsumerStatefulWidget {
  const MonthlyOverviewScreen({super.key});

  @override
  ConsumerState<MonthlyOverviewScreen> createState() =>
      _MonthlyOverviewScreenState();
}

class _MonthlyOverviewScreenState
    extends ConsumerState<MonthlyOverviewScreen> {
  TransactionDirection _tab = TransactionDirection.outbound;

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(monthlyOverviewProvider);
    final transactions = ref.watch(transactionsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly Overview')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: <Widget>[
          _MonthChip(start: overview.window.start),
          const SizedBox(height: 14),
          _HeadlineCard(overview: overview),
          if (overview.isEstimated) ...<Widget>[
            const SizedBox(height: 10),
            _EstimateNote(count: overview.guessedRowCount),
          ],
          const SizedBox(height: 14),
          _TrendStrip(overview: overview, direction: _tab),
          if (overview.lastTransactionAt != null) ...<Widget>[
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Data updated through '
                '${Fmt.shortDate(overview.lastTransactionAt!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          _DirectionTabs(
            selected: _tab,
            onChanged: (direction) => setState(() => _tab = direction),
          ),
          const SizedBox(height: 14),
          if (transactions.isLoading && !transactions.hasValue)
            const Center(child: CircularProgressIndicator())
          else ...<Widget>[
            _GroupGrid(overview: overview, direction: _tab),
            const SizedBox(height: 18),
            SectionHeader(
              title: 'Breakdown',
              action: TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('All'),
              ),
            ),
            _Breakdown(overview: overview, direction: _tab),
          ],
        ],
      ),
    );
  }
}

/// Says out loud that some of these figures are guesses.
///
/// Rows imported before the app recorded direction only know which way
/// they went from their wording. A payroll credit says so; an e-Transfer
/// does not, and those default to money out. Without this note the totals
/// look exact, and a reader has no way to tell that their income is
/// understated.
class _EstimateNote extends StatelessWidget {
  const _EstimateNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppTheme.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1
                  ? '1 transaction never recorded which way it went, so it '
                        'is counted as money out. Re-import the statement '
                        'for exact figures.'
                  : '$count transactions never recorded which way they '
                        'went, so they are counted as money out. Re-import '
                        'the statement for exact figures.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// The month being reported on. Tapping it opens the picker.
class _MonthChip extends ConsumerWidget {
  const _MonthChip({required this.start});

  final DateTime start;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        onTap: () => _pickMonth(context, ref, start),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                Fmt.monthAndYear(start),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _pickMonth(
  BuildContext context,
  WidgetRef ref,
  DateTime current,
) async {
  final now = ref.read(reportingNowProvider);
  final picked = await showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    builder: (_) => _MonthPickerSheet(current: current, latest: now),
  );
  if (picked == null) return;

  final preferences = ref.read(preferencesProvider).value;
  ref
      .read(monthOffsetProvider.notifier)
      .jumpTo(
        monthOffsetFor(
          now,
          picked.year,
          picked.month,
          preferences?.monthStartDay ?? 1,
        ),
      );
}

/// Two wheels and a confirm, matching the platform month pickers users
/// already know from their banking apps.
///
/// Nothing is applied until Confirm: scrolling a wheel past a month should
/// not silently reload the report behind the sheet.
class _MonthPickerSheet extends StatefulWidget {
  const _MonthPickerSheet({required this.current, required this.latest});

  final DateTime current;

  /// The newest month worth offering. There is no data after today, and a
  /// report of the future reads as the app having lost the data.
  final DateTime latest;

  @override
  State<_MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<_MonthPickerSheet> {
  static const int _yearsBack = 6;

  late int _month = widget.current.month;
  late int _year = widget.current.year;
  late final List<int> _years = <int>[
    for (var i = _yearsBack - 1; i >= 0; i--) widget.latest.year - i,
  ];

  bool get _isInFuture =>
      _year > widget.latest.year ||
      (_year == widget.latest.year && _month > widget.latest.month);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Select Month', style: theme.textTheme.titleLarge),
          ),
          SizedBox(
            height: 200,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _Wheel<int>(
                    values: const <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
                    selected: _month,
                    label: (month) => Fmt.monthAbbreviation(month),
                    onChanged: (month) => setState(() => _month = month),
                  ),
                ),
                Expanded(
                  child: _Wheel<int>(
                    values: _years,
                    selected: _year,
                    label: (year) => '$year',
                    onChanged: (year) => setState(() => _year = year),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Row(
            children: <Widget>[
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              Container(width: 1, height: 44, color: theme.dividerColor),
              Expanded(
                child: TextButton(
                  onPressed: _isInFuture
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(DateTime(_year, _month)),
                  child: const Text('Confirm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One scrolling column of the month picker.
///
/// Stateful only to own its controller. Built as a stateless widget it made a
/// fresh [FixedExtentScrollController] on every rebuild, and because selecting
/// an item rebuilds the sheet, every wheel snapped straight back to where it
/// started — the picker could be scrolled but never actually moved.
class _Wheel<T> extends StatefulWidget {
  const _Wheel({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final ValueChanged<T> onChanged;

  @override
  State<_Wheel<T>> createState() => _WheelState<T>();
}

class _WheelState<T> extends State<_Wheel<T>> {
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(
        initialItem: widget.values.indexOf(widget.selected).clamp(
          0,
          widget.values.length - 1,
        ),
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListWheelScrollView.useDelegate(
      itemExtent: 48,
      diameterRatio: 1.6,
      physics: const FixedExtentScrollPhysics(),
      controller: _controller,
      onSelectedItemChanged: (index) => widget.onChanged(widget.values[index]),
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: widget.values.length,
        builder: (context, index) {
          final value = widget.values[index];
          final isSelected = value == widget.selected;
          return Center(
            child: Text(
              widget.label(value),
              style: (isSelected
                  ? theme.textTheme.headlineSmall
                  : theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    )),
            ),
          );
        },
      ),
    );
  }
}

/// Money out, money in, and what the month actually left behind.
class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({required this.overview});

  final MonthlyOverview overview;

  @override
  Widget build(BuildContext context) {
    final net = overview.netCents;
    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _Figure(
              label: 'Money out',
              cents: overview.moneyOutCents,
              currency: overview.currency,
              color: AppTheme.negative,
            ),
          ),
          Expanded(
            child: _Figure(
              label: 'Money in',
              cents: overview.moneyInCents,
              currency: overview.currency,
              color: AppTheme.positive,
            ),
          ),
          Expanded(
            child: _Figure(
              label: 'Net',
              cents: net,
              currency: overview.currency,
              // Colourless at zero: an empty month is neither good nor bad,
              // and painting it green would suggest it went well.
              color: net == 0
                  ? null
                  : (net > 0 ? AppTheme.positive : AppTheme.negative),
              signed: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.cents,
    required this.currency,
    this.color,
    this.signed = false,
  });

  final String label;
  final int cents;
  final String currency;
  final Color? color;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          child: Text(
            Fmt.money(cents, currency: currency, sign: signed),
            style: theme.textTheme.titleLarge?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Six months at a glance, so one month is read against the ones around it.
class _TrendStrip extends StatelessWidget {
  const _TrendStrip({required this.overview, required this.direction});

  final MonthlyOverview overview;
  final TransactionDirection direction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = overview.trend;
    final largest = points.fold<int>(
      0,
      (max, point) =>
          point.valueFor(direction) > max ? point.valueFor(direction) : max,
    );

    return SizedBox(
      height: 132,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final point in points)
            Expanded(
              child: _TrendBar(
                point: point,
                direction: direction,
                largest: largest,
                isSelected: point.start == overview.window.start,
                currency: overview.currency,
                theme: theme,
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendBar extends StatelessWidget {
  const _TrendBar({
    required this.point,
    required this.direction,
    required this.largest,
    required this.isSelected,
    required this.currency,
    required this.theme,
  });

  final MonthPoint point;
  final TransactionDirection direction;
  final int largest;
  final bool isSelected;
  final String currency;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final value = point.valueFor(direction);
    // A zero month still gets a sliver, so the strip reads as six months with
    // nothing in one rather than as five months and a gap.
    final fraction = largest == 0 ? 0.0 : value / largest;
    final colour = direction == TransactionDirection.inbound
        ? AppTheme.positive
        : theme.colorScheme.primary;

    return Semantics(
      label:
          '${Fmt.monthAbbreviation(point.start.month)}: '
          '${Fmt.money(value, currency: currency)}',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: fraction.clamp(0.02, 1.0),
                widthFactor: 0.44,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: isSelected ? 1 : 0.28),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.navy : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              Fmt.monthAbbreviation(point.start.month),
              style: theme.textTheme.bodySmall?.copyWith(
                color: isSelected
                    ? Colors.white
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectionTabs extends StatelessWidget {
  const _DirectionTabs({required this.selected, required this.onChanged});

  final TransactionDirection selected;
  final ValueChanged<TransactionDirection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _Tab(
            label: 'Money out',
            isSelected: selected == TransactionDirection.outbound,
            onTap: () => onChanged(TransactionDirection.outbound),
          ),
        ),
        Expanded(
          child: _Tab(
            label: 'Money in',
            isSelected: selected == TransactionDirection.inbound,
            onTap: () => onChanged(TransactionDirection.inbound),
          ),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primary
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tab's total, split into the kinds of movement that made it up.
class _GroupGrid extends StatelessWidget {
  const _GroupGrid({required this.overview, required this.direction});

  final MonthlyOverview overview;
  final TransactionDirection direction;

  @override
  Widget build(BuildContext context) {
    final groups = overview.groupsFor(direction);
    if (groups.isEmpty) {
      return _NothingYet(
        direction: direction,
        month: overview.window.start,
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.9,
      children: <Widget>[
        for (final total in groups)
          _GroupTile(total: total, currency: overview.currency),
      ],
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.total, required this.currency});

  final FlowGroupTotal total;
  final String currency;

  static IconData _iconFor(MoneyFlowGroup group) {
    switch (group) {
      case MoneyFlowGroup.spending:
        return Icons.shopping_bag_outlined;
      case MoneyFlowGroup.transfersOut:
        return Icons.swap_horiz_rounded;
      case MoneyFlowGroup.debtPayments:
        return Icons.credit_card_outlined;
      case MoneyFlowGroup.deposits:
        return Icons.account_balance_outlined;
      case MoneyFlowGroup.refunds:
        return Icons.undo_rounded;
      case MoneyFlowGroup.otherOut:
      case MoneyFlowGroup.otherIn:
        return Icons.more_horiz_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = total.group.isOutbound
        ? theme.colorScheme.primary
        : AppTheme.positive;

    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_iconFor(total.group), size: 17, color: colour),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  total.group.label,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            child: Text(
              Fmt.money(total.amountCents, currency: currency),
              style: theme.textTheme.titleLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.overview, required this.direction});

  final MonthlyOverview overview;
  final TransactionDirection direction;

  @override
  Widget build(BuildContext context) {
    final categories = overview.categoriesFor(direction);
    if (categories.isEmpty) {
      return _NothingYet(
        direction: direction,
        month: overview.window.start,
      );
    }

    final theme = Theme.of(context);
    return SectionCard(
      child: Column(
        children: <Widget>[
          for (final entry in categories) ...<Widget>[
            if (entry != categories.first) const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppTheme.categoryColor(entry.category),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
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
                  Fmt.money(entry.amountCents, currency: overview.currency),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Says which half of the ledger is empty, rather than a generic "no data".
///
/// An empty Money in tab usually means income was never captured, which is a
/// different problem from a month with no transactions at all.
class _NothingYet extends StatelessWidget {
  const _NothingYet({required this.direction, required this.month});

  final TransactionDirection direction;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final isIncome = direction == TransactionDirection.inbound;
    return EmptyState(
      icon: isIncome
          ? Icons.savings_outlined
          : Icons.receipt_long_outlined,
      title: isIncome
          ? 'No money in for ${Fmt.monthAndYear(month)}'
          : 'No money out for ${Fmt.monthAndYear(month)}',
      message: isIncome
          ? 'Deposits show up here once a statement or alert records one.'
          : 'Import a statement or capture an alert to see this month.',
    );
  }
}
