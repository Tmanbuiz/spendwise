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
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  _Filter _filter = _Filter.all;
  String _search = '';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
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
                final filtered = all.where(_matches).toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.search_off_rounded,
                    title: all.isEmpty ? 'No transactions yet' : 'Nothing here',
                    message: all.isEmpty
                        ? 'Purchases appear automatically once your bank sends '
                            'an alert.'
                        : 'No transactions match this filter.',
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
