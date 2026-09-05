import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Categories and the merchant rules that feed them.
///
/// The category set itself is fixed — budgets and reporting key on it — so
/// this screen is about *rules*: teaching SpendWise where a merchant belongs.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = ref.watch(monthComparisonProvider).current;
    final rules = ref.watch(rulesProvider);

    final spendByCategory = <SpendCategory, int>{
      for (final entry in summary.byCategory) entry.category: entry.amountCents,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editRule(context, ref, existing: null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New rule'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: <Widget>[
          const SectionHeader(title: 'This month'),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              children: <Widget>[
                for (final category in SpendCategory.values)
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.categoryColor(category)
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        AppTheme.categoryIcon(category),
                        size: 19,
                        color: AppTheme.categoryColor(category),
                      ),
                    ),
                    title: Text(category.displayName),
                    trailing: Text(
                      Fmt.money(
                        spendByCategory[category] ?? 0,
                        currency: summary.currency,
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: (spendByCategory[category] ?? 0) == 0
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Your rules'),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'A rule sends every matching merchant to the category you pick, '
              'and always beats SpendWise\'s own guess.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          rules.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('Could not load rules.\n$error'),
            data: (all) {
              if (all.isEmpty) {
                return const SectionCard(
                  child: EmptyState(
                    icon: Icons.rule_rounded,
                    title: 'No rules yet',
                    message: 'Change a transaction\'s category and choose '
                        '"always file here" to create one.',
                  ),
                );
              }
              return SectionCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  children: <Widget>[
                    for (final rule in all)
                      ListTile(
                        onTap: () => _editRule(context, ref, existing: rule),
                        leading: Icon(
                          AppTheme.categoryIcon(rule.category),
                          color: AppTheme.categoryColor(rule.category),
                        ),
                        title: Text(rule.pattern),
                        subtitle: Text(
                          '${_matchLabel(rule.match)} → '
                          '${rule.category.displayName}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Delete rule',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: rule.id == null
                              ? null
                              : () => ref
                                  .read(rulesProvider.notifier)
                                  .delete(rule.id!),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

String _matchLabel(RuleMatch match) {
  switch (match) {
    case RuleMatch.exact:
      return 'Exactly';
    case RuleMatch.contains:
      return 'Contains';
    case RuleMatch.startsWith:
      return 'Starts with';
    case RuleMatch.regex:
      return 'Pattern';
  }
}

Future<void> _editRule(
  BuildContext context,
  WidgetRef ref, {
  required MerchantRule? existing,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _RuleForm(existing: existing),
    ),
  );
}

class _RuleForm extends ConsumerStatefulWidget {
  const _RuleForm({required this.existing});
  final MerchantRule? existing;

  @override
  ConsumerState<_RuleForm> createState() => _RuleFormState();
}

class _RuleFormState extends ConsumerState<_RuleForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pattern;
  late SpendCategory _category;
  late RuleMatch _match;

  @override
  void initState() {
    super.initState();
    _pattern = TextEditingController(text: widget.existing?.pattern ?? '');
    _category = widget.existing?.category ?? SpendCategory.other;
    _match = widget.existing?.match ?? RuleMatch.contains;
  }

  @override
  void dispose() {
    _pattern.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(rulesProvider.notifier).upsert(
          MerchantRule(
            id: widget.existing?.id ?? generateId(),
            pattern: _pattern.text.trim().toUpperCase(),
            category: _category,
            match: _match,
            source: RuleSource.user,
          ),
        );
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
              widget.existing == null ? 'New rule' : 'Edit rule',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _pattern,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Merchant text',
                hintText: 'e.g. TIM HORTONS',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.length < 2) return 'Enter at least two characters';
                if (_match == RuleMatch.regex) {
                  try {
                    RegExp(text);
                  } on FormatException {
                    return 'That is not a valid pattern';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<RuleMatch>(
              initialValue: _match,
              decoration: const InputDecoration(labelText: 'Match'),
              items: <DropdownMenuItem<RuleMatch>>[
                for (final match in RuleMatch.values)
                  DropdownMenuItem<RuleMatch>(
                    value: match,
                    child: Text(_matchLabel(match)),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _match = value ?? RuleMatch.contains),
            ),
            const SizedBox(height: 20),
            CategoryPicker(
              selected: _category,
              onChanged: (category) => setState(() => _category = category),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Save rule')),
          ],
        ),
      ),
    );
  }
}
