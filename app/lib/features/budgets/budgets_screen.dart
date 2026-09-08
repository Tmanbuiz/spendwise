import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/budget.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/insight_widgets.dart';

/// Monthly budgets: one overall, plus any number of per-category limits.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = ref.watch(budgetProgressProvider);
    final summary = ref.watch(monthComparisonProvider).current;
    final insights = ref.watch(spendingInsightsProvider);
    final budgetState = ref.watch(budgetsProvider);
    final transactionState = ref.watch(transactionsProvider);

    final overall = progress.where((p) => p.budget.isOverall).toList();
    final categories = progress.where((p) => !p.budget.isOverall).toList()
      ..sort((a, b) => b.spentCents.compareTo(a.spentCents));
    final allocation = categories.fold<int>(
      0,
      (sum, p) => sum + p.budget.amountCents,
    );
    final allowance = insights.dailyAllowance(overall.firstOrNull);
    final suggestions = ref
        .watch(monthComparisonProvider)
        .previous
        .byCategory
        .where((c) => !categories.any((p) => p.budget.category == c.category))
        .take(3)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editBudget(context, ref, existing: null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New budget'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 104),
        children: <Widget>[
          Text(
            'Give every category a little direction.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          const PeriodSelector(),
          const SizedBox(height: 14),
          if (budgetState.isLoading || transactionState.isLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (budgetState.hasError || transactionState.hasError)
            InsightNote(
              title: 'Could not load your budgets',
              message: 'Tap to reload your budget and spending data.',
              onTap: () {
                ref.invalidate(budgetsProvider);
                ref.invalidate(transactionsProvider);
              },
            )
          else ...[
            if (overall.isEmpty && categories.isEmpty)
              EmptyState(
                icon: Icons.savings_outlined,
                title: 'No budgets yet',
                message:
                    'Set a monthly limit and SpendWise will track how much '
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
                MetricPair(
                  first: MetricCard(
                    label: insights.isCurrent
                        ? 'Daily budget left'
                        : 'Period status',
                    value: insights.isCurrent
                        ? Fmt.money(allowance ?? 0, currency: summary.currency)
                        : overall.first.isOverBudget
                        ? 'Over limit'
                        : 'Within limit',
                    icon: Icons.savings_outlined,
                    detail: insights.isCurrent
                        ? '${insights.daysLeft} days, including today'
                        : 'Using your current budget limits',
                  ),
                  second: MetricCard(
                    label: 'Category allocation',
                    value: Fmt.moneyCompact(
                      allocation,
                      currency: summary.currency,
                    ),
                    icon: Icons.donut_large_outlined,
                    detail: '${categories.length} category limits planned',
                  ),
                ),
                const SizedBox(height: 14),
                InsightNote(
                  title: allocation > overall.first.budget.amountCents
                      ? 'Category limits exceed your total'
                      : 'Your budget at a glance',
                  message: allocation > overall.first.budget.amountCents
                      ? 'Your categories add up to ${Fmt.money(allocation - overall.first.budget.amountCents, currency: summary.currency)} more than your overall limit.'
                      : '${Fmt.percent(overall.first.fraction)} spent · ${Fmt.percent(insights.periodFraction)} of the period elapsed. Category limits sit inside your overall budget.',
                ),
                const SizedBox(height: 16),
              ],
              SectionHeader(
                title: 'By category',
                action: Text(
                  Fmt.money(
                    summary.totalSpentCents,
                    currency: summary.currency,
                  ),
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
                Column(
                  children: <Widget>[
                    for (final entry in categories)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              BudgetBar(
                                progress: entry,
                                onTap: () => _editBudget(
                                  context,
                                  ref,
                                  existing: entry.budget,
                                ),
                              ),
                              Text(
                                entry.isOverBudget
                                    ? 'Over limit'
                                    : entry.fraction >= 0.8
                                    ? 'Approaching limit'
                                    : 'Within limit',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: entry.isOverBudget
                                      ? AppTheme.negative
                                      : theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
            ],
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 14),
              const SectionHeader(title: 'Start from your history'),
              Text(
                'Prior-period spending, rounded up to the next \$10. Review and adjust before saving.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final suggestion in suggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        AppTheme.categoryIcon(suggestion.category),
                        color: AppTheme.categoryColor(suggestion.category),
                      ),
                      title: Text(suggestion.category.displayName),
                      subtitle: Text(
                        Fmt.money(
                          ((suggestion.amountCents + 999) ~/ 1000) * 1000,
                          currency: summary.currency,
                        ),
                      ),
                      trailing: const Icon(Icons.add_circle_outline_rounded),
                      onTap: () => _editBudget(
                        context,
                        ref,
                        existing: null,
                        suggestedCategory: suggestion.category,
                        suggestedCents:
                            ((suggestion.amountCents + 999) ~/ 1000) * 1000,
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 14),
            Text(
              'Limits repeat every period. Editing a limit also changes the comparison shown for past periods. Daily budget left is based on recorded spending, not your bank balance.',
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

/// Opens the create/edit sheet. Shared by every entry point so the form is
/// defined once.
Future<void> _editBudget(
  BuildContext context,
  WidgetRef ref, {
  required Budget? existing,
  SpendCategory? suggestedCategory,
  int? suggestedCents,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: _BudgetForm(
          existing: existing,
          suggestedCategory: suggestedCategory,
          suggestedCents: suggestedCents,
        ),
      ),
    ),
  );
}

class _BudgetForm extends ConsumerStatefulWidget {
  const _BudgetForm({
    required this.existing,
    this.suggestedCategory,
    this.suggestedCents,
  });

  final Budget? existing;
  final SpendCategory? suggestedCategory;
  final int? suggestedCents;

  @override
  ConsumerState<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends ConsumerState<_BudgetForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late SpendCategory? _category;
  late bool _isOverall;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _amount = TextEditingController(
      text: existing == null
          ? widget.suggestedCents == null
                ? ''
                : (widget.suggestedCents! / 100).toStringAsFixed(2)
          : (existing.amountCents / 100).toStringAsFixed(2),
    );
    _isOverall = existing?.isOverall ?? (widget.suggestedCategory == null);
    _category =
        existing?.category ??
        widget.suggestedCategory ??
        SpendCategory.groceries;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? _parseCents(String raw) {
    final cleaned = raw.trim();
    if (!RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(cleaned)) return null;
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
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final cents = _parseCents(_amount.text) ?? 0;
    final category = _isOverall ? null : _category;
    final currency =
        widget.existing?.currency ??
        ref.read(preferencesProvider).value?.currency ??
        'CAD';
    final duplicate = (ref.read(budgetsProvider).value ?? <Budget>[]).any(
      (b) =>
          b.id != widget.existing?.id &&
          b.category == category &&
          b.currency == currency,
    );
    if (duplicate) {
      setState(
        () => _error = 'A budget already exists for this category. Edit that budget instead.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(budgetsProvider.notifier)
          .upsert(
            Budget(
              id: widget.existing?.id ?? generateId(),
              amountCents: cents,
              category: category,
              currency: currency,
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save. Please try again.';
        });
      }
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(budgetsProvider.notifier).delete(existing.id);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not delete. Please try again.';
        });
      }
    }
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
            if (widget.existing != null) ...<Widget>[
              const SizedBox(height: 10),
              TextButton(
                onPressed: _saving ? null : _delete,
                style: TextButton.styleFrom(foregroundColor: AppTheme.negative),
                child: const Text('Delete budget'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
