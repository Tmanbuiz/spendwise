import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_transaction.dart';
import '../../services/statement_import_service.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Import a downloaded bank statement.
///
/// Always previews before writing. A statement import is bulk: one wrong
/// column guess would add dozens of wrong rows at once, which is a very
/// different risk profile from a single mis-read notification.
class StatementImportScreen extends ConsumerStatefulWidget {
  const StatementImportScreen({super.key});

  @override
  ConsumerState<StatementImportScreen> createState() =>
      _StatementImportScreenState();
}

class _StatementImportScreenState
    extends ConsumerState<StatementImportScreen> {
  StatementPreview? _preview;
  File? _file;
  AmountSign? _signOverride;
  bool _busy = false;
  String? _error;

  StatementImportService get _service =>
      StatementImportService(idGenerator: generateId);

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Choose a statement',
        type: FileType.custom,
        allowedExtensions: <String>['csv', 'pdf', 'txt'],
      );
      final path = picked?.path;
      if (path == null) {
        setState(() => _busy = false);
        return;
      }
      _file = File(path);
      await _buildPreview();
    } on Object catch (error) {
      setState(() {
        _error = 'Could not read that file. $error';
        _busy = false;
      });
    }
  }

  Future<void> _buildPreview() async {
    final file = _file;
    if (file == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final existing =
          ref.read(transactionsProvider).value ?? const <AppTransaction>[];
      final preview = await _service.preview(
        file,
        existing: existing,
        categorizer: ref.read(categorizerProvider),
        signOverride: _signOverride,
      );
      setState(() {
        _preview = preview;
        _busy = false;
      });
    } on Object catch (error) {
      setState(() {
        _error = 'Could not read that file. $error';
        _busy = false;
      });
    }
  }

  Future<void> _import() async {
    final preview = _preview;
    if (preview == null) return;

    setState(() => _busy = true);

    final existing =
        ref.read(transactionsProvider).value ?? const <AppTransaction>[];
    final writes = _service.apply(
      preview.result,
      existing: existing,
      categorizer: ref.read(categorizerProvider),
    );

    for (final transaction in writes) {
      await ref.read(transactionsProvider.notifier).upsert(transaction);
    }

    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported ${writes.length} transactions.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;

    return Scaffold(
      appBar: AppBar(title: const Text('Import a statement')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: <Widget>[
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Where to get the file',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'CIBC online banking → pick an account → Download '
                  'transactions → CSV.\n'
                  'Wealthsimple → Activity → export.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Text(
                    'CSV is far more reliable than PDF. A CSV has real '
                    'columns; a PDF only has text at positions, so the '
                    'columns have to be guessed back. PDF import works, but '
                    'check the preview carefully.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.warning,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(
                    _file == null ? 'Choose a file' : 'Choose a different file',
                  ),
                ),
              ],
            ),
          ),
          if (_busy) ...<Widget>[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            SectionCard(
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          ],
          if (preview != null && !_busy) ...<Widget>[
            const SizedBox(height: 20),
            _PreviewCard(
              preview: preview,
              signOverride: _signOverride,
              onFlipSign: () {
                setState(() {
                  _signOverride =
                      preview.result.signConvention == AmountSign.negativeIsSpending
                          ? AmountSign.positiveIsSpending
                          : AmountSign.negativeIsSpending;
                });
                _buildPreview();
              },
            ),
            const SizedBox(height: 20),
            if (preview.isEmpty)
              SectionCard(
                child: Text(
                  'No transactions could be read from that file. If it is a '
                  'PDF, try the CSV export instead.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              FilledButton(
                onPressed: _import,
                child: Text(
                  'Import ${preview.willInsert.length} new'
                  '${preview.willMerge.isEmpty ? '' : ', update ${preview.willMerge.length}'}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.preview,
    required this.signOverride,
    required this.onFlipSign,
  });

  final StatementPreview preview;
  final AmountSign? signOverride;
  final VoidCallback onFlipSign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = preview.result.rows.take(12).toList();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                preview.format == StatementFormat.pdf
                    ? Icons.picture_as_pdf_outlined
                    : Icons.table_chart_outlined,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(preview.fileName,
                    style: theme.textTheme.labelLarge,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const Divider(height: 24),
          _Line(
            label: 'Rows read',
            value: '${preview.result.rows.length}',
          ),
          _Line(
            label: 'New transactions',
            value: '${preview.willInsert.length}',
          ),
          _Line(
            label: 'Match something already captured',
            value: '${preview.willMerge.length}',
          ),
          _Line(
            label: 'Spending in this file',
            value: Fmt.money(preview.spendingTotalCents),
            emphasise: true,
          ),
          if (preview.result.problems.isNotEmpty)
            _Line(
              label: 'Lines skipped',
              value: '${preview.result.problems.length}',
              warn: true,
            ),
          if (preview.format == StatementFormat.csv &&
              preview.result.layout?.usesDebitCredit == false) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              preview.result.signConvention == AmountSign.negativeIsSpending
                  ? 'Reading negative amounts as money out.'
                  : 'Reading positive amounts as money out.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextButton(
              onPressed: onFlipSign,
              child: const Text('That is backwards — flip it'),
            ),
          ],
          const Divider(height: 24),
          Text('First rows', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 62,
                    child: Text(
                      Fmt.shortDate(row.date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    Fmt.money(row.amount.cents),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: row.countsAsSpending
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          if (preview.result.rows.length > rows.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '…and ${preview.result.rows.length - rows.length} more',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.emphasise = false,
    this.warn = false,
  });

  final String label;
  final String value;
  final bool emphasise;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: warn
                    ? AppTheme.warning
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: (emphasise
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.bodyMedium)
                ?.copyWith(
              fontWeight: FontWeight.w600,
              color: warn ? AppTheme.warning : null,
            ),
          ),
        ],
      ),
    );
  }
}
