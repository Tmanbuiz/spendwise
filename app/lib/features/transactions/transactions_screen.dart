import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

import '../../core/formatters.dart';
import '../../data/models/app_transaction.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Which transactions the list is showing.
enum _Filter {
  all('All'),
  spending('Spending'),
  excluded('Not counted'),
  review('Needs review');

  const _Filter(this.label);
  final String label;
}

/// The full transaction list, grouped by day and filterable.
///
/// Scoped to one month at a time, driven by the same `monthOffsetProvider` the
/// dashboard uses. Sharing that state is the point: stepping back to July on
/// the dashboard and then opening Activity shows July, rather than the two
/// screens quietly disagreeing about which month is being looked at.
///
/// The month can be stepped off entirely, because a couple of questions are
/// genuinely about the whole history — "have I ever shopped here?", "when did
/// this subscription start?" — and month-scoping a search makes those
/// unanswerable.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  _Filter _filter = _Filter.all;
  String _search = '';
  bool _allTime = false;

  bool _matches(AppTransaction transaction) {
    switch (_filter) {
      case _Filter.all:
        break;
      case _Filter.spending:
        if (!transaction.countsAsSpending) return false;
      case _Filter.excluded:
        if (transaction.countsAsSpending) return false;
      case _Filter.review:
        if (!transaction.needsReview) return false;
    }

    if (_search.isEmpty) return true;
    final needle = _search.toLowerCase();
    return transaction.displayMerchant.toLowerCase().contains(needle) ||
        transaction.category.displayName.toLowerCase().contains(needle);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transactions = ref.watch(transactionsProvider);
    final summary = ref.watch(monthComparisonProvider).current;
    final offset = ref.watch(monthOffsetProvider);
    final oldestOffset = ref.watch(oldestMonthOffsetProvider);
    final window = summary.window;

    return Scaffold(
      appBar: AppBar(
        title: Text(_allTime ? 'All activity' : Fmt.monthAndYear(window.start)),
        actions: <Widget>[
          IconButton(
            tooltip: _allTime ? 'Show one month' : 'Show all time',
            onPressed: () => setState(() => _allTime = !_allTime),
            icon: Icon(
              _allTime
                  ? Icons.calendar_month_rounded
                  : Icons.all_inclusive_rounded,
            ),
          ),
          if (!_allTime) ...<Widget>[
            IconButton(
              tooltip: 'Previous month',
              // Stop at the first month that holds anything. Paging into
              // empty months looks like lost data.
              onPressed: offset <= oldestOffset
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
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/transaction'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: (value) => setState(() => _search = value.trim()),
              decoration: const InputDecoration(
                hintText: 'Search merchant or category',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: <Widget>[
                for (final filter in _Filter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filter.label),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (!_allTime)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      summary.isEmpty
                          ? 'Nothing recorded this month'
                          : '${summary.transactionCount} '
                              '${summary.transactionCount == 1 ? "purchase" : "purchases"}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // The same figure the dashboard shows for this month, from
                  // the same summary, so the two can never drift apart.
                  Text(
                    Fmt.money(
                      summary.totalSpentCents,
                      currency: summary.currency,
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: transactions.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load transactions.\n$error',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              data: (all) {
                final inScope = _allTime
                    ? all
                    : all.where((t) => window.contains(t.occurredAt)).toList();
                final filtered = inScope.where(_matches).toList();

                if (filtered.isEmpty) {
                  // Three different nothings, and saying which one it is saves
                  // the user wondering whether the app lost their data: no
                  // history at all, none in this month, or none matching what
                  // they typed.
                  if (all.isEmpty) {
                    return const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No transactions yet',
                      message: 'Purchases appear automatically once your bank '
                          'sends an alert. You can also import a statement.',
                    );
                  }
                  if (!_allTime && inScope.isEmpty) {
                    return EmptyState(
                      icon: Icons.event_busy_rounded,
                      title: 'Nothing in ${Fmt.monthAndYear(window.start)}',
                      message: 'There are transactions in other months.',
                      action: TextButton(
                        onPressed: () => setState(() => _allTime = true),
                        child: const Text('Show all time'),
                      ),
                    );
                  }
                  return EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Nothing here',
                    message: _allTime
                        ? 'No transactions match this filter.'
                        : 'No transactions match this filter in '
                            '${Fmt.monthAndYear(window.start)}.',
                    action: _allTime
                        ? null
                        : TextButton(
                            onPressed: () => setState(() => _allTime = true),
                            child: const Text('Search all time'),
                          ),
                  );
                }
                return _GroupedList(transactions: filtered);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Groups by day with a running daily total, which is how people actually
/// scan a statement.
class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.transactions});

  final List<AppTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <DateTime, List<AppTransaction>>{};

    for (final transaction in transactions) {
      final day = DateTime(
        transaction.occurredAt.year,
        transaction.occurredAt.month,
        transaction.occurredAt.day,
      );
      groups.putIfAbsent(day, () => <AppTransaction>[]).add(transaction);
    }

    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final rows = groups[day]!;
        final dayTotal = rows
            .where((t) => t.countsAsSpending)
            .fold<int>(0, (sum, t) => sum + t.amountCents);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      Fmt.relativeDay(day),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (dayTotal > 0)
                    Text(
                      Fmt.money(dayTotal, currency: rows.first.currency),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            SectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: <Widget>[
                  for (final transaction in rows)
                    TransactionTile(
                      transaction: transaction,
                      onTap: () =>
                          context.push('/transaction', extra: transaction),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Exposed for the detail screen's "similar transactions" hint.
List<AppTransaction> transactionsForMerchant(
  List<AppTransaction> all,
  String? merchantNormalized,
) {
  if (merchantNormalized == null || merchantNormalized.isEmpty) {
    return const <AppTransaction>[];
  }
  return all
      .where((t) => t.merchantNormalized == merchantNormalized)
      .toList();
}

/// Event types the manual-entry form offers, in the order a person would
/// think of them.
const List<TransactionEventType> manualEventTypes = <TransactionEventType>[
  TransactionEventType.purchase,
  TransactionEventType.refund,
  TransactionEventType.payment,
  TransactionEventType.transfer,
];
