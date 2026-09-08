import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/financial_document.dart';
import '../../services/financial_vault_service.dart';
import '../../state/financial_providers.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

class FinancialVaultScreen extends ConsumerStatefulWidget {
  const FinancialVaultScreen({super.key});

  @override
  ConsumerState<FinancialVaultScreen> createState() => _FinancialVaultScreenState();
}

class _FinancialVaultScreenState extends ConsumerState<FinancialVaultScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _addDocuments() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Choose financial documents',
        type: FileType.custom,
        allowedExtensions: <String>['pdf', 'csv', 'txt', 'jpg', 'jpeg', 'png'],
      );
      if (!mounted) return;
      if (picked.isEmpty) {
        setState(() => _busy = false);
        return;
      }
      if (picked.length > 12 || picked.any((entry) => entry.path == null)) {
        setState(() {
          _busy = false;
          _error = 'Choose up to 12 files that are stored on this device.';
        });
        return;
      }

      var stored = 0;
      for (final selected in picked) {
        final file = File(selected.path!);
        final document = await ref.read(financialVaultServiceProvider).storeFile(
              file,
              documentId: generateId(),
              documentType: FinancialVaultService.inferDocumentType(selected.name),
            );
        await ref.read(documentsProvider.notifier).upsert(document);
        stored++;
      }

      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Stored $stored document${stored == 1 ? '' : 's'} in your vault.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not store every selected document. $error';
      });
    }
  }

  Future<void> _delete(FinancialDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this document?'),
        content: Text(
          'This removes “${document.fileName}” from the vault. Imported transaction history is not deleted.',
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
    if (confirmed != true) return;

    try {
      await ref.read(financialVaultServiceProvider).deleteStoredFile(document);
      await ref.read(documentsProvider.notifier).delete(document.id);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the document. $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final documents = ref.watch(documentsProvider);
    final remote = ref.watch(isRemoteProvider);
    final items = documents.value ?? const <FinancialDocument>[];
    final coveredMonths = <String>{
      for (final document in items)
        if (document.periodStart != null)
          '${document.periodStart!.year}-${document.periodStart!.month}',
    }.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Vault'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Import a statement',
            onPressed: () => context.push(Routes.importStatement),
            icon: const Icon(Icons.upload_file_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addDocuments,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add documents'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(documentsProvider.notifier).refresh(),
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
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          Icons.folder_copy_outlined,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('Your financial history, kept together', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 3),
                            Text(
                              remote
                                  ? 'Files are private and synced to your account.'
                                  : 'Files are stored privately on this device.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _VaultMetric(
                          label: 'Documents',
                          value: '${items.length}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _VaultMetric(
                          label: 'Months indexed',
                          value: '$coveredMonths',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Statements imported through SpendWise are archived here automatically. You can also keep pay stubs, investment statements, tax documents and receipts for later reference.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            if (_busy) ...<Widget>[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 14),
              InsightNote(
                title: 'Vault action needs attention',
                message: _error!,
                icon: Icons.error_outline_rounded,
              ),
            ],
            const SizedBox(height: 18),
            SectionHeader(
              title: 'Documents',
              action: TextButton.icon(
                onPressed: () => context.push(Routes.importStatement),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Import statement'),
              ),
            ),
            documents.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => InsightNote(
                title: 'Could not load your vault',
                message: '$error',
                icon: Icons.cloud_off_outlined,
                onTap: () => ref.read(documentsProvider.notifier).refresh(),
              ),
              data: (docs) => docs.isEmpty
                  ? EmptyState(
                      icon: Icons.folder_open_outlined,
                      title: 'Your vault is empty',
                      message:
                          'Import a statement or add financial documents. Source files stay available after their transactions are analysed.',
                      action: FilledButton.icon(
                        onPressed: _addDocuments,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add documents'),
                      ),
                    )
                  : Column(
                      children: <Widget>[
                        for (final document in docs)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _DocumentCard(
                              document: document,
                              onDelete: () => _delete(document),
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
}

class _VaultMetric extends StatelessWidget {
  const _VaultMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document, required this.onDelete});
  final FinancialDocument document;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final period = _periodLabel(document);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _documentColor(document.documentType).withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _documentIcon(document),
              color: _documentColor(document.documentType),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  document.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  <String>[
                    document.documentType.displayName,
                    if (document.institution != null) document.institution!,
                    if (period != null) period,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: <Widget>[
                    _MiniBadge(
                      text: document.storageKind == DocumentStorageKind.supabase
                          ? 'Synced'
                          : 'On device',
                      icon: document.storageKind == DocumentStorageKind.supabase
                          ? Icons.cloud_done_outlined
                          : Icons.phone_android_outlined,
                    ),
                    _MiniBadge(
                      text: _fileSize(document.sizeBytes),
                      icon: Icons.data_usage_outlined,
                    ),
                    if (document.importedTransactionCount > 0)
                      _MiniBadge(
                        text: '${document.importedTransactionCount} transactions',
                        icon: Icons.receipt_long_outlined,
                      ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'delete', child: Text('Delete from vault')),
            ],
          ),
        ],
      ),
    );
  }

  static IconData _documentIcon(FinancialDocument document) {
    if (document.extension == 'pdf') return Icons.picture_as_pdf_outlined;
    switch (document.documentType) {
      case FinancialDocumentType.bankStatement:
      case FinancialDocumentType.creditCardStatement:
        return Icons.account_balance_outlined;
      case FinancialDocumentType.payStub:
        return Icons.payments_outlined;
      case FinancialDocumentType.investmentStatement:
        return Icons.savings_outlined;
      case FinancialDocumentType.taxDocument:
        return Icons.description_outlined;
      case FinancialDocumentType.receipt:
        return Icons.receipt_long_outlined;
      case FinancialDocumentType.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  static Color _documentColor(FinancialDocumentType type) {
    switch (type) {
      case FinancialDocumentType.bankStatement:
      case FinancialDocumentType.creditCardStatement:
        return AppTheme.brand;
      case FinancialDocumentType.payStub:
        return AppTheme.positive;
      case FinancialDocumentType.investmentStatement:
        return const Color(0xFF2563EB);
      case FinancialDocumentType.taxDocument:
        return AppTheme.warning;
      case FinancialDocumentType.receipt:
        return const Color(0xFF7C3AED);
      case FinancialDocumentType.other:
        return const Color(0xFF64748B);
    }
  }

  static String? _periodLabel(FinancialDocument document) {
    final start = document.periodStart;
    final end = document.periodEnd;
    if (start == null && end == null) return null;
    if (start != null && end != null) {
      if (start.year == end.year && start.month == end.month) {
        return Fmt.monthName(start);
      }
      return '${Fmt.monthName(start)}–${Fmt.monthName(end)}';
    }
    return Fmt.monthName(start ?? end!);
  }

  static String _fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.text, required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
