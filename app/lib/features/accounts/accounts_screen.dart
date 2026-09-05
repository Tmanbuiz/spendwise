import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/account.dart';
import '../../data/models/app_transaction.dart';
import '../../data/models/bank.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// The cards and accounts SpendWise has seen.
///
/// Accounts are discovered from notifications rather than entered by hand —
/// the user never types card details, and the only card data held is the last
/// four digits.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final transactions =
        ref.watch(transactionsProvider).value ?? const <AppTransaction>[];
    final stored = ref.watch(accountsProvider).value ?? const <Account>[];

    final discovered = _discoverAccounts(transactions, stored);

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: discovered.isEmpty
          ? const EmptyState(
              icon: Icons.credit_card_outlined,
              title: 'No cards seen yet',
              message: 'Cards appear here automatically the first time one of '
                  'your bank alerts names them.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'SpendWise stores at most the last four digits of a card. '
                    'It never holds a full card number, PIN or CVV.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final entry in discovered)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AccountCard(entry: entry),
                  ),
              ],
            ),
    );
  }
}

/// An account plus the activity seen on it.
class _AccountSummary {
  const _AccountSummary({
    required this.label,
    required this.last4,
    required this.bankId,
    required this.type,
    required this.spentCents,
    required this.transactionCount,
    required this.lastSeen,
    required this.currency,
  });

  final String label;
  final String? last4;
  final String bankId;
  final AccountType type;
  final int spentCents;
  final int transactionCount;
  final DateTime? lastSeen;
  final String currency;
}

/// Builds the account list from transaction history, merging in any stored
/// accounts so a renamed one keeps its label.
List<_AccountSummary> _discoverAccounts(
  List<AppTransaction> transactions,
  List<Account> stored,
) {
  final byKey = <String, List<AppTransaction>>{};

  for (final transaction in transactions) {
    final key = transaction.accountLast4 ??
        transaction.accountLabel ??
        transaction.bankId ??
        'unknown';
    byKey.putIfAbsent(key, () => <AppTransaction>[]).add(transaction);
  }

  final results = <_AccountSummary>[];
  byKey.forEach((key, rows) {
    final first = rows.first;
    final override = stored.where((a) => a.last4 == first.accountLast4);
    final label = override.isNotEmpty
        ? override.first.label
        : first.accountLabel ??
            Banks.byId(first.bankId ?? '')?.name ??
            'Account';

    final spent = rows
        .where((t) => t.countsAsSpending)
        .fold<int>(0, (sum, t) => sum + t.amountCents);

    final lastSeen = rows
        .map((t) => t.occurredAt)
        .fold<DateTime?>(null, (latest, when) {
      if (latest == null || when.isAfter(latest)) return when;
      return latest;
    });

    results.add(_AccountSummary(
      label: label,
      last4: first.accountLast4,
      bankId: first.bankId ?? 'other',
      type: AccountType.fromLabel(first.accountLabel),
      spentCents: spent,
      transactionCount: rows.length,
      lastSeen: lastSeen,
      currency: first.currency,
    ));
  });

  results.sort((a, b) => b.spentCents.compareTo(a.spentCents));
  return results;
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.entry});

  final _AccountSummary entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bank = Banks.byId(entry.bankId);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[AppTheme.brand, AppTheme.brandBright],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.credit_card_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        bank?.shortName ?? 'Bank',
                        entry.type.displayName,
                        if (entry.last4 != null) '••${entry.last4}',
                      ].join('  ·  '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          Row(
            children: <Widget>[
              Expanded(
                child: _Stat(
                  label: 'Spent',
                  value: Fmt.money(entry.spentCents, currency: entry.currency),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Transactions',
                  value: '${entry.transactionCount}',
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Last seen',
                  value: entry.lastSeen == null
                      ? '—'
                      : Fmt.shortDate(entry.lastSeen!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
