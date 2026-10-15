import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/backup_service.dart';
import '../../services/recurring_bills.dart';
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
  bool overwrite = false;
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
          () => message = 'Could not complete the operation. Check the file and try again. No restore changes were committed if validation or writing failed.',
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
                'Keep a copy of your transactions, budgets, accounts, category rules, preferences and recurring bills. Backups contain readable financial data; save them somewhere private.',
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
                      final backup = await BackupData.capture(data, bills);
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
              onPressed: busy || ref.watch(dataLayerProvider).atomicWrite == null
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
            if (ref.watch(dataLayerProvider).atomicWrite == null)
              const Text('Restore is available in local mode. Synced restore requires transactional server support.'),
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
                      '${backup.transactions.length} transactions · ${backup.budgets.length} budgets\n${backup.accounts.length} accounts · ${backup.rules.length} category rules\n${backup.bills.length} recurring bills',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Add missing only preserves existing records. Overwrite replaces matching records and conflicting budgets with backup versions.',
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Overwrite matching records'),
                      value: overwrite,
                      onChanged: busy ? null : (v) => setState(() => overwrite = v),
                    ),
                    FutureBuilder<Map<String, int>>(
                      future: backup.previewCounts(ref.read(dataLayerProvider), overwrite: overwrite),
                      builder: (context, snapshot) => Text(snapshot.hasData
                        ? '${snapshot.data!['added']} added · ${snapshot.data!['replaced']} replaced · ${snapshot.data!['unchanged']} kept'
                        : 'Checking conflicts...'),
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
                              final confirmed = await showDialog<bool>(context: context,
                                builder: (context) => AlertDialog(title: const Text('Confirm restore'),
                                  content: Text(overwrite ? 'Matching records and conflicting budgets will be replaced. Recent edits may be lost.' : 'Only missing records will be added. Existing records will be kept.'),
                                  actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore'))]));
                              if (confirmed != true) return;
                              final count = await backup.restore(data, overwrite: overwrite, restoreSettings: restoreSettings);
                              ref.invalidate(billsProvider);
                              if (!mounted) return;
                              ref.invalidate(transactionsProvider);
                              ref.invalidate(budgetsProvider);
                              ref.invalidate(accountsProvider);
                              ref.invalidate(rulesProvider);
                              ref.invalidate(preferencesProvider);
                              setState(() {
                                preview = null;
                                message = 'Restored $count records.';
                              });
                            }),
                      child: const Text('Restore records'),
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
