import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/backup_service.dart';
import '../../services/recurring_bills.dart';
import '../../state/ei_providers.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupState();
}

class _BackupState extends ConsumerState<BackupScreen> {
  bool busy = false;
  bool restoreSettings = false;
  String? message;
  BackupData? preview;
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } on Object catch (_) {
      if (mounted) {
        setState(
          () => message = 'Could not complete the operation. Check the file and try again. A partial restore can safely be retried.',
        );
      }
    } finally {
      if (mounted) {
        ref.invalidate(transactionsProvider);
        ref.invalidate(budgetsProvider);
        ref.invalidate(accountsProvider);
        ref.invalidate(rulesProvider);
        ref.invalidate(preferencesProvider);
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Backup and restore')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionCard(
              child: Text(
                'Keep a copy of your transactions, budgets, accounts, category rules, preferences, recurring bills and EI hours. Backups contain readable financial data; save them somewhere private.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt),
              label: const Text('Save backup'),
              onPressed: busy
                  ? null
                  : () => run(() async {
                      final data = ref.read(dataLayerProvider);
                      final bills = await ref.read(billsProvider.future);
                      final eiHours = await ref.read(eiTrackerProvider.future);
                      final backup = await BackupData.capture(
                        data,
                        bills,
                        eiHours: eiHours,
                      );
                      final uri = await FilePicker.saveFile(
                        fileName:
                            'SpendWise-${DateTime.now().toIso8601String().substring(0, 10)}.json',
                        bytes: Uint8List.fromList(utf8.encode(backup.encode())),
                        mimeType: 'application/json',
                      );
                      if (mounted && uri != null) {
                        setState(() => message = 'Backup saved.');
                      }
                    }),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.restore),
              label: const Text('Choose backup to restore'),
              onPressed: busy
                  ? null
                  : () => run(() async {
                      final file = await FilePicker.pickFile(
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                      );
                      if (file?.path == null) return;
                      if (mounted) setState(() => preview = null);
                      final input = File(file!.path!);
                      if (await input.length() > 20000000) {
                        throw const FormatException('File too large');
                      }
                      final result = BackupData.decode(
                        await input.readAsString(),
                      );
                      if (mounted) setState(() => preview = result);
                    }),
            ),
            if (preview case final backup?) ...[
              const SizedBox(height: 16),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready to restore',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${backup.transactions.length} transactions · ${backup.budgets.length} budgets\n${backup.accounts.length} accounts · ${backup.rules.length} category rules\n${backup.bills.length} recurring bills\n${backup.eiHours?.jobs.length ?? 0} EI jobs · ${backup.eiHours?.records.length ?? 0} EI hours entries',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Adds missing records. Existing records and budgets take priority. Nothing is deleted.',
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Also restore reporting preferences'),
                      subtitle: const Text(
                        'Currency, budget period, banks and auto-categorization',
                      ),
                      value: restoreSettings,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => restoreSettings = v!),
                    ),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              final data = ref.read(dataLayerProvider);
                              var count = await backup.restore(data);
                              if (!mounted) return;
                              final bills = List<RecurringBill>.from(
                                await ref.read(billsProvider.future),
                              );
                              if (!mounted) return;
                              for (final bill in backup.bills) {
                                if (!bills.any((b) => b.id == bill.id)) {
                                  bills.add(bill);
                                  count++;
                                }
                              }
                              await ref
                                  .read(billsProvider.notifier)
                                  .save(bills);
                              final eiBackup = backup.eiHours;
                              if (eiBackup != null) {
                                final current = await ref.read(
                                  eiTrackerProvider.future,
                                );
                                if (!mounted) return;
                                final merged = current.mergeMissing(eiBackup);
                                count +=
                                    merged.jobs.length -
                                    current.jobs.length +
                                    merged.records.length -
                                    current.records.length +
                                    merged.breaks.length -
                                    current.breaks.length;
                                await ref
                                    .read(eiTrackerProvider.notifier)
                                    .save(merged);
                              }
                              if (restoreSettings) {
                                final current = await data.preferences.load();
                                await data.preferences.save(
                                  current.copyWith(
                                    currency: backup.preferences.currency,
                                    monthStartDay:
                                        backup.preferences.monthStartDay,
                                    selectedBankIds:
                                        backup.preferences.selectedBankIds,
                                    autoCategorize:
                                        backup.preferences.autoCategorize,
                                  ),
                                );
                              }
                              if (!mounted) return;
                              ref.invalidate(transactionsProvider);
                              ref.invalidate(budgetsProvider);
                              ref.invalidate(accountsProvider);
                              ref.invalidate(rulesProvider);
                              ref.invalidate(preferencesProvider);
                              setState(() {
                                preview = null;
                                message = 'Restored $count missing records.';
                              });
                            }),
                      child: const Text('Restore missing records'),
                    ),
                  ],
                ),
              ),
            ],
            if (busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (message != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(message!)),
          ],
        ),
      ),
    );
  }
}
