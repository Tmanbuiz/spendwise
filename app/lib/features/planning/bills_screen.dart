import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/recurring_bills.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});
  Future<void> edit(
    BuildContext context,
    WidgetRef ref, [
    RecurringBill? old,
  ]) async {
    final result = await showDialog<RecurringBill>(
      context: context,
      builder: (_) => _BillEditor(
        old: old,
        currency: ref.read(preferencesProvider).value?.currency ?? 'CAD',
      ),
    );
    if (result == null || !context.mounted) return;
    await change(
      context,
      ref,
      (bills) => [...bills.where((b) => b.id != result.id), result],
    );
  }

  Future<void> change(
    BuildContext context,
    WidgetRef ref,
    List<RecurringBill> Function(List<RecurringBill>) update,
  ) async {
    try {
      final bills = await ref.read(billsProvider.future);
      if (!context.mounted) return;
      await ref.read(billsProvider.notifier).save(update(bills));
    } on Object catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save bills. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(billsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring bills')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add bill'),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Could not load bills. Please reopen this screen.'),
        ),
        data: (items) {
          final bills = [...items]..sort((a, b) => a.due.compareTo(b.due));
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              const SectionCard(
                child: Text(
                  'Plan bills and subscriptions before they arrive. Marking a bill paid advances its due date; it does not add an expense or make a payment.',
                ),
              ),
              const SizedBox(height: 16),
              if (bills.isEmpty)
                const Text(
                  'Add rent, utilities or subscriptions to see what is coming up.',
                ),
              for (final bill in bills)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bill.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '${bill.currency} ${(bill.cents / 100).toStringAsFixed(2)} · ${bill.frequency}',
                        ),
                        Text(
                          '${bill.due.isBefore(today)
                              ? 'Overdue'
                              : bill.due == today
                              ? 'Due today'
                              : 'Due'} · ${bill.due.toIso8601String().substring(0, 10)}',
                          style: TextStyle(
                            color: bill.due.isBefore(today)
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => edit(context, ref, bill),
                              child: const Text('Edit'),
                            ),
                            TextButton(
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: Text('Mark ${bill.name} paid?'),
                                    content: Text(
                                      'Next due date: ${bill.nextDue.toIso8601String().substring(0, 10)}. Your transaction history stays unchanged.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('Mark paid'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && context.mounted) {
                                  await change(
                                    context,
                                    ref,
                                    (list) => list
                                        .map(
                                          (b) =>
                                              b.id == bill.id ? b.advance() : b,
                                        )
                                        .toList(),
                                  );
                                }
                              },
                              child: const Text('Mark paid'),
                            ),
                            TextButton(
                              onPressed: () async {
                                final yes = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: Text('Remove ${bill.name}?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(c),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                                );
                                if (yes == true && context.mounted) {
                                  await change(
                                    context,
                                    ref,
                                    (list) => list
                                        .where((b) => b.id != bill.id)
                                        .toList(),
                                  );
                                }
                              },
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BillEditor extends StatefulWidget {
  const _BillEditor({this.old, required this.currency});
  final RecurringBill? old;
  final String currency;
  @override
  State<_BillEditor> createState() => _BillEditorState();
}

class _BillEditorState extends State<_BillEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.old?.name);
  late final amount = TextEditingController(
    text: widget.old == null
        ? ''
        : (widget.old!.cents / 100).toStringAsFixed(2),
  );
  late DateTime due =
      widget.old?.due ??
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  late String frequency = widget.old?.frequency ?? 'monthly';
  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.old == null ? 'Add recurring bill' : 'Edit bill'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Bill name'),
              maxLength: 80,
              validator: (s) =>
                  s == null || s.trim().isEmpty ? 'Enter a name' : null,
            ),
            TextFormField(
              controller: amount,
              decoration: InputDecoration(
                labelText:
                    'Amount (${widget.old?.currency ?? widget.currency})',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (s) =>
                  s == null ||
                      !RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(s) ||
                      (double.tryParse(s) ?? 0) <= 0
                  ? 'Enter a positive amount with up to 2 decimals'
                  : null,
            ),
            DropdownButtonFormField<String>(
              initialValue: frequency,
              items: [
                'weekly',
                'monthly',
                'yearly',
              ].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
              onChanged: (v) => setState(() => frequency = v!),
            ),
            TextButton(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: due,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (date != null && mounted) setState(() => due = date);
              },
              child: Text('Due ${due.toIso8601String().substring(0, 10)}'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(
            context,
            RecurringBill(
              id: widget.old?.id ?? generateId(),
              name: name.text.trim(),
              cents: (double.parse(amount.text) * 100).round(),
              currency: widget.old?.currency ?? widget.currency,
              due: due,
              frequency: frequency,
              anchorDay: due == widget.old?.due
                  ? widget.old!.anchorDay
                  : due.day,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}
