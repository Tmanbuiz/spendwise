import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/backup_service.dart';
import '../../services/backup_crypto.dart';
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
  bool encryptBackup = true;
  final backupPassword = TextEditingController();
  @override
  void dispose() { backupPassword.dispose(); super.dispose(); }

  Future<String?> requestPassword() => showDialog<String>(context: context,
    builder: (_) => const _BackupPasswordDialog());
  String? message;
  BackupData? preview;
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } on SecretBoxAuthenticationError {
      if (mounted) setState(() => message = 'The password is incorrect or the backup is damaged.');
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
                'Keep a copy of your transactions, budgets, accounts, category rules, preferences and recurring bills. Password protection keeps exported financial data private. Keep the password safe; it cannot be recovered.',
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(title: const Text('Protect backup with a password'), value: encryptBackup,
              onChanged: busy ? null : (v) => setState(() => encryptBackup = v)),
            if (encryptBackup) TextField(controller: backupPassword, obscureText: true,
              enableSuggestions: false, autocorrect: false,
              decoration: const InputDecoration(labelText: 'Backup password (at least 12 characters)')),
            if (!encryptBackup) const Text('Privacy warning: this backup will contain readable financial records. Anyone with the file can read them.'),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt),
              label: const Text('Save backup'),
              onPressed: busy
                  ? null
                  : () => run(() async {
                      if (encryptBackup && (backupPassword.text.length < 12 || backupPassword.text.length > 1024)) {
                        setState(() => message = 'Use a backup password of 12 to 1024 characters.');
                        return;
                      }
                      final data = ref.read(dataLayerProvider);
                      final bills = await ref.read(billsProvider.future);
                      final backup = await BackupData.capture(data, bills);
                      final content = encryptBackup
                        ? await BackupCrypto.encrypt(backup.encode(), backupPassword.text)
                        : backup.encode();
                      final uri = await FilePicker.saveFile(
                        fileName:
                            'SpendWise-${DateTime.now().toIso8601String().substring(0, 10)}.json',
                        bytes: Uint8List.fromList(utf8.encode(content)),
                        type: FileType.custom,
                        allowedExtensions: ['json'],
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
                      final files = await FilePicker.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                      );
                      if (files == null || files.isEmpty || files.single.path == null) return;
                      if (mounted) setState(() => preview = null);
                      final input = File(files.single.path!);
                      if (await input.length() > 30000000) {
                        throw const FormatException('File too large');
                      }
                      var content = await input.readAsString();
                      if (BackupCrypto.isEncrypted(content)) {
                        if (!mounted) return;
                        final password = await requestPassword();
                        if (password == null) return;
                        content = await BackupCrypto.decrypt(content, password);
                      }
                      final result = BackupData.decode(content);
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

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog();
  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}
class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final controller = TextEditingController();
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Backup password'),
    content: TextField(controller: controller, obscureText: true, enableSuggestions: false, autocorrect: false,
      decoration: const InputDecoration(labelText: 'Password used to save this backup')),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Unlock'))]);
}
