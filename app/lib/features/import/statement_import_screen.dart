import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

import '../../core/formatters.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_transaction.dart';
import '../../services/shared_statements.dart';
import '../../services/statement_import_service.dart';
import '../../state/financial_providers.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Import downloaded bank statements and retain the source file in the private
/// Financial Vault after the user confirms the preview.
class StatementImportScreen extends ConsumerStatefulWidget {
  const StatementImportScreen({super.key});

  @override
  ConsumerState<StatementImportScreen> createState() =>
      _StatementImportScreenState();
}

class _StatementImportScreenState extends ConsumerState<StatementImportScreen>
    with WidgetsBindingObserver {
  final List<StatementPreview> _previews = <StatementPreview>[];
  List<File> _files = <File>[];
  final Map<String, AmountSign> _signOverrides = <String, AmountSign>{};
  bool _busy = false;
  String? _error;

  /// What the screen is doing right now, while it is doing it.
  ///
  /// Reading a PDF is real work, and a bare spinner over a batch of them
  /// is indistinguishable from a hang.
  String? _progress;

  /// How many statements may be read in one batch.
  ///
  /// Bounded by patience rather than memory: each file is read and
  /// reconciled in turn against everything already loaded, so a batch of a
  /// year's statements is a few thousand rows — small — but the PDF text
  /// extraction behind it is not instant. Twenty covers a full year of
  /// monthly statements in one pass.
  static const int _maxFiles = 20;

  StatementImportService get _service =>
      StatementImportService(idGenerator: generateId);

  /// Guards against two collections overlapping, which would read the same
  /// batch twice and double the preview.
  bool _collecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A statement shared from Files or Gmail lands in a queue on the
    // platform side. Collect it here rather than making the user find the
    // file again through the picker.
    WidgetsBinding.instance.addPostFrameCallback((_) => _collectShared());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Sharing more statements while this screen is open should add them,
  /// not be ignored until it is reopened.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _collectShared();
  }

  /// Collects everything shared, then builds the preview once.
  ///
  /// Sharing several statements at once can deliver them as a burst rather
  /// than in one go, so the queue is drained until it stays empty. Reading
  /// after the first batch and ignoring the rest is how this first went
  /// wrong: files that landed while the previews were being built were
  /// left in the queue with nothing to come back for them.
  Future<void> _collectShared() async {
    if (_collecting) return;
    _collecting = true;
    try {
      const shared = SharedStatements();
      final collected = <File>[];

      var batch = await shared.drain();
      while (batch.isNotEmpty) {
        collected.addAll(batch);
        // Long enough for the tail of a burst to land, short enough not to
        // be felt when a single file was shared.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        batch = await shared.drain();
      }
      if (!mounted || collected.isEmpty) return;

      // Added to whatever is already staged rather than replacing it: a
      // second share is more statements, not a different set.
      final paths = _files.map((file) => file.path).toSet();
      _files = <File>[
        ..._files,
        for (final file in collected)
          if (paths.add(file.path)) file,
      ].take(_maxFiles).toList();
      _signOverrides.clear();
      await _buildPreview();
    } finally {
      _collecting = false;
    }
  }

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Choose up to $_maxFiles statements',
        type: FileType.custom,
        allowedExtensions: <String>['csv', 'pdf', 'txt'],
      );
      if (!mounted) return;
      if (picked.isEmpty) {
        setState(() => _busy = false);
        return;
      }
      if (picked.length > _maxFiles ||
          picked.any((file) => file.path == null)) {
        setState(() {
          _error =
              'Choose up to $_maxFiles files downloaded to your phone.';
          _busy = false;
        });
        return;
      }
      _files = picked.map((file) => File(file.path!)).toList();
      _signOverrides.clear();
      await _buildPreview();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not read that file. $error';
        _busy = false;
      });
    }
  }

  Future<void> _buildPreview() async {
    if (_files.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
      _previews.clear();
    });

    try {
      final existing = List<AppTransaction>.from(
        await ref.read(transactionsProvider.future),
      );
      if (!mounted) return;

      for (var index = 0; index < _files.length; index++) {
        final file = _files[index];
        if (_files.length > 1) {
          setState(
            () => _progress =
                'Reading ${index + 1} of ${_files.length}…',
          );
        }
        final preview = await _service.preview(
          file,
          existing: existing,
          categorizer: ref.read(categorizerProvider),
          signOverride: _signOverrides[file.path],
        );
        if (!mounted) return;
        _previews.add(preview);

        // Grow the preview's working history so files selected in one batch
        // reconcile with each other as well as with already stored data.
        for (final transaction in _service.apply(
          preview.result,
          existing: existing,
          categorizer: ref.read(categorizerProvider),
        )) {
          existing.removeWhere((old) => old.id == transaction.id);
          existing.add(transaction);
        }
      }
      setState(() {
        _busy = false;
        _progress = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _progress = null;
        _previews.clear();
        _error =
            'Could not read all statements. Try selecting unlocked, text-based PDFs or CSV files. $error';
        _busy = false;
      });
    }
  }

  Future<void> _import() async {
    if (_previews.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    var saved = 0;
    var archived = 0;
    var archiveFailures = 0;

    try {
      final existing = List<AppTransaction>.from(
        await ref.read(transactionsProvider.future),
      );
      if (!mounted) return;

      for (var index = 0; index < _previews.length; index++) {
        final preview = _previews[index];
        final file = _files[index];
        final writes = _service.apply(
          preview.result,
          existing: existing,
          categorizer: ref.read(categorizerProvider),
        );

        for (final transaction in writes) {
          await ref.read(transactionsProvider.notifier).upsert(transaction);
          existing.removeWhere((old) => old.id == transaction.id);
          existing.add(transaction);
          saved++;
        }

        // Archiving is deliberately best-effort after transaction writes. A
        // Storage outage must not roll back a correct statement import.
        try {
          if (!await _alreadyArchived(file, preview)) {
            final document = await ref
                .read(financialVaultServiceProvider)
                .archiveStatement(
                  file,
                  preview,
                  documentId: generateId(),
                  importedTransactionCount: writes.length,
                );
            await ref.read(documentsProvider.notifier).upsert(document);
            archived++;
          }
        } on Object {
          archiveFailures++;
        }
      }

      if (!mounted) return;
      setState(() => _busy = false);
      final archiveMessage = archiveFailures > 0
          ? ' $archiveFailures source file${archiveFailures == 1 ? '' : 's'} could not be archived; transactions were still saved.'
          : archived > 0
              ? ' Archived $archived source statement${archived == 1 ? '' : 's'} in Financial Vault.'
              : ' Source statements were already in Financial Vault.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved $saved transactions to history.$archiveMessage'),
        ),
      );
      Navigator.of(context).pop();
    } on Object catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'Saved $saved transactions before the import stopped. You can retry; already imported rows will not be duplicated.';
      });
    }
  }

  Future<bool> _alreadyArchived(File file, StatementPreview preview) async {
    final size = await file.length();
    final existing = await ref.read(documentsProvider.future);
    DateTime? first;
    DateTime? last;
    for (final row in preview.result.rows) {
      if (first == null || row.date.isBefore(first)) first = row.date;
      if (last == null || row.date.isAfter(last)) last = row.date;
    }

    return existing.any((document) {
      if (document.fileName != preview.fileName || document.sizeBytes != size) {
        return false;
      }
      return _sameDay(document.periodStart, first) &&
          _sameDay(document.periodEnd, last);
    });
  }

  bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final newCount = _previews.fold<int>(
      0,
      (sum, preview) => sum + preview.willInsert.length,
    );
    final mergeCount = _previews.fold<int>(
      0,
      (sum, preview) => sum + preview.willMerge.length,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import statements'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Financial Vault',
            onPressed: () => context.push(Routes.vault),
            icon: const Icon(Icons.folder_copy_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: <Widget>[
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Import up to $_maxFiles statements together',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Touch and hold a file in the picker to select several. Review each file below before adding it to history.\n\n'
                  'CIBC online banking → pick an account → Download transactions → CSV.\n'
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
                    'CSV is far more reliable than PDF. A CSV has real columns; a PDF only has text at positions, so the columns have to be guessed back. PDF import works, but check the preview carefully.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.warning,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'After import, the original source file is kept privately in Financial Vault so you do not have to upload it again later.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(
                    _files.isEmpty
                        ? 'Choose statements'
                        : 'Choose different statements',
                  ),
                ),
              ],
            ),
          ),
          if (_busy) ...<Widget>[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
            if (_progress != null) ...<Widget>[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _progress!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            SectionCard(
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
          if (_previews.isNotEmpty && !_busy) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              '${_previews.length} statements · $newCount new · $mergeCount matching',
            ),
            for (var index = 0; index < _previews.length; index++) ...<Widget>[
              const SizedBox(height: 20),
              _PreviewCard(
                preview: _previews[index],
                signOverride: _signOverrides[_files[index].path],
                onFlipSign: () {
                  final preview = _previews[index];
                  setState(() {
                    _signOverrides[_files[index].path] =
                        preview.result.signConvention ==
                                AmountSign.negativeIsSpending
                            ? AmountSign.positiveIsSpending
                            : AmountSign.negativeIsSpending;
                  });
                  _buildPreview();
                },
              ),
              if (_previews[index].isEmpty) ...<Widget>[
                const SizedBox(height: 12),
                SectionCard(
                  child: Text(
                    'No transactions could be read from that file. If it is a PDF, try the CSV export instead.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: newCount + mergeCount == 0 ? null : _import,
              child: Text(
                'Import $newCount new${mergeCount == 0 ? '' : ', update $mergeCount'}',
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
                child: Text(
                  preview.fileName,
                  style: theme.textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _Line(label: 'Rows read', value: '${preview.result.rows.length}'),
          _Line(label: 'New transactions', value: '${preview.willInsert.length}'),
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

          // The statement totals its own sections, so the parse can be
          // measured against them. Showing the result is the point: an import
          // that quietly disagreed with the statement is how every wrong
          // figure got in here in the first place.
          if (preview.result.checks.isNotEmpty) ...<Widget>[
            const Divider(height: 24),
            if (preview.result.verified)
              _Line(
                label: 'Checked against the statement',
                value: 'every total matches',
                emphasise: true,
              )
            else ...<Widget>[
              _Line(
                label: 'Does not match the statement',
                value: '${preview.result.failedChecks.length} of '
                    '${preview.result.checks.length}',
                warn: true,
              ),
              for (final check in preview.result.failedChecks)
                _Line(
                  label: '  ${check.label}',
                  value: '${Fmt.money(check.readCents)} read, '
                      'statement says ${Fmt.money(check.declaredCents)}',
                  warn: true,
                ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Importing this would record figures the statement does not '
                  'agree with. Check the rows below before continuing.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: (emphasise ? theme.textTheme.labelLarge : theme.textTheme.bodySmall)
                ?.copyWith(color: warn ? AppTheme.warning : null),
          ),
        ],
      ),
    );
  }
}
