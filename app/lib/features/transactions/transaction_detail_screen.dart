import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_transaction.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import 'transactions_screen.dart';

/// Add, edit or delete one transaction.
///
/// The same screen serves manual entry and correction of an automatic capture,
/// because the fields are identical — only the title and the delete action
/// differ.
class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, this.transaction});

  /// Null when adding a new transaction by hand.
  final AppTransaction? transaction;

  @override
  ConsumerState<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState
    extends ConsumerState<TransactionDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _merchant;
  late final TextEditingController _amount;
  late final TextEditingController _note;

  late TransactionEventType _eventType;
  late SpendCategory _category;
  late DateTime _occurredAt;
  late bool _excluded;
  bool _saving = false;

  bool get _isNew => widget.transaction == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.transaction;
    _merchant = TextEditingController(text: existing?.merchant ?? '');
    _amount = TextEditingController(
      text: existing == null ? '' : (existing.amountCents / 100).toStringAsFixed(2),
    );
    _note = TextEditingController(text: existing?.note ?? '');
    _eventType = existing?.eventType ?? TransactionEventType.purchase;
    _category = existing?.category ?? SpendCategory.other;
    _occurredAt = existing?.occurredAt ?? DateTime.now();
    _excluded = existing?.excludedByUser ?? false;
  }

  @override
  void dispose() {
    _merchant.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Parses the amount field into cents without going through a double, so
  /// `19.99` cannot land as 1998.
  int? _parseCents(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d.]'), '');
    if (cleaned.isEmpty) return null;
    final parts = cleaned.split('.');
    if (parts.length > 2) return null;
    final dollars = int.tryParse(parts.first.isEmpty ? '0' : parts.first);
    if (dollars == null) return null;
    var cents = 0;
    if (parts.length == 2) {
      final fraction = parts[1].padRight(2, '0').substring(0, 2);
      cents = int.tryParse(fraction) ?? 0;
    }
    return dollars * 100 + cents;
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (!mounted) return;

    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _occurredAt.hour,
        time?.minute ?? _occurredAt.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final cents = _parseCents(_amount.text) ?? 0;
    final merchant = _merchant.text.trim();
    final existing = widget.transaction;

    final transaction = (existing ??
            AppTransaction(
              id: generateId(),
              eventType: _eventType,
              amountCents: cents,
              currency: 'CAD',
              occurredAt: _occurredAt,
              category: _category,
              source: TransactionSource.manual,
            ))
        .copyWith(
      eventType: _eventType,
      amountCents: cents,
      occurredAt: _occurredAt,
      category: _category,
      merchant: merchant.isEmpty ? null : merchant,
      merchantNormalized: MerchantExtractor.normalize(merchant),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      excludedByUser: _excluded,
      // Saving is the user's confirmation, so the review flag clears and the
      // category is now theirs, not a guess.
      needsReview: false,
      categoryWasSetByUser: true,
    );

    await ref.read(transactionsProvider.notifier).upsert(transaction);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.transaction;
    if (existing == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: const Text(
          'It will be removed from your totals. This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.negative),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await ref.read(transactionsProvider.notifier).delete(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _createRule() async {
    final merchant = MerchantExtractor.normalize(_merchant.text.trim());
    if (merchant == null) return;

    await ref.read(rulesProvider.notifier).upsert(
          MerchantRule(
            id: generateId(),
            pattern: merchant,
            category: _category,
            source: RuleSource.user,
          ),
        );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$merchant will be filed under ${_category.displayName} from now on.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = widget.transaction;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Add transaction' : 'Transaction'),
        actions: <Widget>[
          if (!_isNew)
            IconButton(
              tooltip: 'Delete',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: <Widget>[
            if (existing?.needsReview ?? false)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.error_outline_rounded,
                          size: 18, color: AppTheme.warning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Some details could not be read from the alert. '
                          'Check them and save.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextFormField(
                    controller: _amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: r'$ ',
                    ),
                    validator: (value) {
                      final cents = _parseCents(value ?? '');
                      if (cents == null || cents <= 0) {
                        return 'Enter an amount greater than zero';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _merchant,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Merchant',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'When',
                        prefixIcon: Icon(Icons.event_outlined),
                      ),
                      child: Text(
                        '${Fmt.shortDate(_occurredAt)} at '
                        '${Fmt.time(_occurredAt)}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'Type'),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final type in manualEventTypes)
                        ChoiceChip(
                          label: Text(_typeLabel(type)),
                          selected: _eventType == type,
                          onSelected: (_) =>
                              setState(() => _eventType = type),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _eventType.countsAsSpending
                        ? 'Counts towards this month\'s spending.'
                        : 'Recorded for context, but not counted as spending.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _eventType.countsAsSpending
                          ? theme.colorScheme.onSurfaceVariant
                          : AppTheme.positive,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'Category'),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CategoryPicker(
                    selected: _category,
                    onChanged: (category) =>
                        setState(() => _category = category),
                  ),
                  if (_merchant.text.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _createRule,
                      icon: const Icon(Icons.rule_rounded, size: 18),
                      label: Text(
                        'Always file ${_merchant.text.trim()} here',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            SectionCard(
              child: Column(
                children: <Widget>[
                  TextFormField(
                    controller: _note,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _excluded,
                    onChanged: (value) => setState(() => _excluded = value),
                    title: const Text('Exclude from spending'),
                    subtitle: const Text(
                      'Keeps the record but leaves it out of your totals.',
                    ),
                  ),
                ],
              ),
            ),
            if (existing != null && existing.accountLabel != null) ...<Widget>[
              const SizedBox(height: 20),
              SectionCard(
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.credit_card_outlined, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        existing.accountLast4 == null
                            ? existing.accountLabel!
                            : '${existing.accountLabel} ••${existing.accountLast4}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_isNew ? 'Add transaction' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(TransactionEventType type) {
    switch (type) {
      case TransactionEventType.purchase:
        return 'Purchase';
      case TransactionEventType.refund:
        return 'Refund';
      case TransactionEventType.payment:
        return 'Card payment';
      case TransactionEventType.transfer:
        return 'Transfer';
      case TransactionEventType.declined:
        return 'Declined';
      case TransactionEventType.unknown:
        return 'Unknown';
    }
  }
}
