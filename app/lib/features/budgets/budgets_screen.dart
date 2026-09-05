import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/budget.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Monthly budgets: one overall, plus any number of per-category limits.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = ref.watch(budgetProgressProvider);
    final summary = ref.watch(monthComparisonProvider).current;

    final overall = progress.where((p) => p.budget.isOverall).toList();
    final categories = progress.where((p) => !p.budget.isOverall).toList()
      ..sort((a, b) => b.spentCents.compareTo(a.spentCents));

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editBudget(context, ref, existing: null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New budget'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: <Widget>[
          if (overall.isEmpty && categories.isEmpty)
            EmptyState(
              icon: Icons.savings_outlined,
              title: 'No budgets yet',
              message: 'Set a monthly limit and SpendWise will track how much '
                  'is left as purchases come in.',
              action: FilledButton(
                onPressed: () => _editBudget(context, ref, existing: null),
                child: const Text('Set a budget'),
              ),
            )
          else ...<Widget>[
            if (overall.isNotEmpty) ...<Widget>[
              const SectionHeader(title: 'Overall'),
              SectionCard(
                child: BudgetBar(
                  progress: overall.first,
                  onTap: () => _editBudget(
                    context,
                    ref,
                    existing: overall.first.budget,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            SectionHeader(
              title: 'By category',
              action: Text(
                Fmt.money(summary.totalSpentCents, currency: summary.currency),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (categories.isEmpty)
              SectionCard(
                child: Text(
                  'No category budgets yet. Add one to keep an eye on a '
                  'specific kind of spending.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              SectionCard(
                child: Column(
                  children: <Widget>[
                    for (final entry in categories)
                      BudgetBar(
                        progress: entry,
                        onTap: () =>
                            _editBudget(context, ref, existing: entry.budget),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Opens the create/edit sheet. Shared by every entry point so the form is
/// defined once.
Future<void> _editBudget(
  BuildContext context,
  WidgetRef ref, {
  required Budget? existing,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _BudgetForm(existing: existing),
    ),
  );
}

class _BudgetForm extends ConsumerStatefulWidget {
  const _BudgetForm({required this.existing});

  final Budget? existing;

  @override
  ConsumerState<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends ConsumerState<_BudgetForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late SpendCategory? _category;
  late bool _isOverall;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _amount = TextEditingController(
      text: existing == null
          ? ''
          : (existing.amountCents / 100).toStringAsFixed(0),
    );
    _isOverall = existing?.isOverall ?? true;
    _category = existing?.category ?? SpendCategory.groceries;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? _parseCents(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d.]'), '');
    if (cleaned.isEmpty) return null;
    final parts = cleaned.split('.');
    final dollars = int.tryParse(parts.first.isEmpty ? '0' : parts.first);
    if (dollars == null) return null;
    final cents = parts.length == 2
        ? int.tryParse(parts[1].padRight(2, '0').substring(0, 2)) ?? 0
        : 0;
    return dollars * 100 + cents;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final cents = _parseCents(_amount.text) ?? 0;

    await ref.read(budgetsProvider.notifier).upsert(
          Budget(
            id: widget.existing?.id ?? generateId(),
            amountCents: cents,
            category: _isOverall ? null : _category,
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    await ref.read(budgetsProvider.notifier).delete(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.existing == null ? 'New budget' : 'Edit budget',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: true, label: Text('Overall')),
                ButtonSegment<bool>(value: false, label: Text('One category')),
              ],
              selected: <bool>{_isOverall},
              onSelectionChanged: (selection) =>
                  setState(() => _isOverall = selection.first),
            ),
            const SizedBox(height: 20),
            if (!_isOverall) ...<Widget>[
              CategoryPicker(
                selected: _category ?? SpendCategory.groceries,
                onChanged: (category) => setState(() => _category = category),
              ),
              const SizedBox(height: 20),
            ],
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Monthly limit',
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
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Save')),
            if (widget.existing != null) ...<Widget>[
              const SizedBox(height: 10),
              TextButton(
                onPressed: _delete,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.negative,
                ),
                child: const Text('Delete budget'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
