import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/financial_rule.dart';
import '../../state/financial_providers.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/insight_widgets.dart';

class FinancialRulesScreen extends ConsumerWidget {
  const FinancialRulesScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    FinancialRule? existing,
  ]) async {
    final result = await showModalBottomSheet<FinancialRule>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RuleEditor(existing: existing),
    );
    if (result != null) {
      await ref.read(financialRulesProvider.notifier).upsert(result);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    FinancialRule rule,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this rule?'),
        content: Text(
          '“${rule.pattern}” will stop affecting future SpendWise analysis.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(financialRulesProvider.notifier).delete(rule.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rules = ref.watch(financialRulesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Financial Memory')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add rule'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(financialRulesProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
          children: <Widget>[
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.psychology_alt_outlined,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Teach SpendWise what transactions mean in your household.',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'These rules sit above normal categories. They decide whether a matching transaction is an expense, investment, income, internal household transfer, or ignored item. The longest matching rule wins.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            rules.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => InsightNote(
                title: 'Could not load Financial Memory',
                message: '$error',
                icon: Icons.cloud_off_outlined,
                onTap: () => ref.invalidate(financialRulesProvider),
              ),
              data: (items) => items.isEmpty
                  ? EmptyState(
                      icon: Icons.psychology_alt_outlined,
                      title: 'No rules yet',
                      message:
                          'Add a rule such as “Wealthsimple → Investment / savings” or an employer name → Income.',
                      action: FilledButton.icon(
                        onPressed: () => _edit(context, ref),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add your first rule'),
                      ),
                    )
                  : Column(
                      children: <Widget>[
                        for (final rule in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SectionCard(
                              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                              child: Row(
                                children: <Widget>[
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: _kindColor(rule.kind)
                                          .withValues(alpha: 0.11),
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    child: Icon(
                                      _kindIcon(rule.kind),
                                      color: _kindColor(rule.kind),
                                      size: 21,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Row(
                                          children: <Widget>[
                                            Flexible(
                                              child: Text(
                                                rule.pattern,
                                                style: theme.textTheme.titleSmall,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (!rule.enabled) ...<Widget>[
                                              const SizedBox(width: 6),
                                              Text(
                                                'Off',
                                                style: theme.textTheme.labelSmall
                                                    ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${rule.kind.displayName} · ${rule.match.displayName}'
                                          '${rule.ownerLabel?.trim().isNotEmpty == true ? ' · ${rule.ownerLabel}' : ''}',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        if (rule.note?.trim().isNotEmpty == true)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 3),
                                            child: Text(
                                              rule.note!,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (action) {
                                      if (action == 'edit') {
                                        _edit(context, ref, rule);
                                      } else if (action == 'toggle') {
                                        ref
                                            .read(financialRulesProvider.notifier)
                                            .upsert(
                                              rule.copyWith(enabled: !rule.enabled),
                                            );
                                      } else if (action == 'delete') {
                                        _delete(context, ref, rule);
                                      }
                                    },
                                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit'),
                                      ),
                                      PopupMenuItem(
                                        value: 'toggle',
                                        child: Text(rule.enabled ? 'Turn off' : 'Turn on'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _kindIcon(FinancialRuleKind kind) {
    switch (kind) {
      case FinancialRuleKind.expense:
        return Icons.shopping_bag_outlined;
      case FinancialRuleKind.investment:
        return Icons.savings_outlined;
      case FinancialRuleKind.income:
        return Icons.payments_outlined;
      case FinancialRuleKind.internalTransfer:
        return Icons.swap_horiz_rounded;
      case FinancialRuleKind.exclude:
        return Icons.visibility_off_outlined;
    }
  }

  static Color _kindColor(FinancialRuleKind kind) {
    switch (kind) {
      case FinancialRuleKind.expense:
        return AppTheme.negative;
      case FinancialRuleKind.investment:
        return AppTheme.brand;
      case FinancialRuleKind.income:
        return AppTheme.positive;
      case FinancialRuleKind.internalTransfer:
        return AppTheme.warning;
      case FinancialRuleKind.exclude:
        return const Color(0xFF64748B);
    }
  }
}

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({this.existing});
  final FinancialRule? existing;

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pattern;
  late final TextEditingController _owner;
  late final TextEditingController _note;
  late FinancialRuleKind _kind;
  late FinancialRuleMatch _match;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final rule = widget.existing;
    _pattern = TextEditingController(text: rule?.pattern ?? '');
    _owner = TextEditingController(text: rule?.ownerLabel ?? '');
    _note = TextEditingController(text: rule?.note ?? '');
    _kind = rule?.kind ?? FinancialRuleKind.expense;
    _match = rule?.match ?? FinancialRuleMatch.contains;
    _enabled = rule?.enabled ?? true;
  }

  @override
  void dispose() {
    _pattern.dispose();
    _owner.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existing;
    Navigator.of(context).pop(
      FinancialRule(
        id: existing?.id ?? generateId(),
        pattern: _pattern.text.trim(),
        kind: _kind,
        match: _match,
        ownerLabel: _owner.text.trim().isEmpty ? null : _owner.text.trim(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        enabled: _enabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.existing == null ? 'Add Financial Memory rule' : 'Edit rule',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _pattern,
                  autofocus: widget.existing == null,
                  decoration: const InputDecoration(
                    labelText: 'Transaction text to match',
                    hintText: 'e.g. Wealthsimple or HARMONY FAMILY',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.length < 2) return 'Enter at least 2 characters.';
                    if (_match == FinancialRuleMatch.regex) {
                      try {
                        RegExp(text);
                      } on FormatException {
                        return 'That regular expression is not valid.';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<FinancialRuleKind>(
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Treat it as'),
                  items: <DropdownMenuItem<FinancialRuleKind>>[
                    for (final kind in FinancialRuleKind.values)
                      DropdownMenuItem(value: kind, child: Text(kind.displayName)),
                  ],
                  onChanged: (value) => setState(() => _kind = value ?? _kind),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<FinancialRuleMatch>(
                  initialValue: _match,
                  decoration: const InputDecoration(labelText: 'Matching method'),
                  items: <DropdownMenuItem<FinancialRuleMatch>>[
                    for (final match in FinancialRuleMatch.values)
                      DropdownMenuItem(value: match, child: Text(match.displayName)),
                  ],
                  onChanged: (value) => setState(() => _match = value ?? _match),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _owner,
                  decoration: const InputDecoration(
                    labelText: 'Household member (optional)',
                    hintText: 'e.g. Me, Wife, Child',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'Why this rule exists',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                  title: const Text('Rule enabled'),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _save,
                  child: Text(widget.existing == null ? 'Add rule' : 'Save changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
