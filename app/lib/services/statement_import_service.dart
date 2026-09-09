import 'dart:io';

import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../data/aggregation/aggregator_models.dart';
import '../data/aggregation/reconciler.dart';
import '../data/models/app_transaction.dart';

/// What a statement file turned into, before anything is written.
class StatementPreview {
  const StatementPreview({
    required this.fileName,
    required this.format,
    required this.result,
    required this.willInsert,
    required this.willMerge,
    required this.willSkip,
  });

  final String fileName;
  final StatementFormat format;
  final StatementImport result;

  /// Rows that would become new transactions.
  final List<StatementRow> willInsert;

  /// Rows that match something already captured from a notification, and would
  /// enrich it rather than add a duplicate.
  final List<StatementRow> willMerge;

  /// Rows that are already recorded, or are not spending events.
  final List<StatementRow> willSkip;

  int get spendingTotalCents => result.spendingTotalCents;

  bool get isEmpty => result.rows.isEmpty;
}

enum StatementFormat { csv, pdf }

/// Reads a downloaded bank statement and merges it with existing data.
///
/// Nothing is written until the user confirms: the preview exists because a
/// statement import is bulk and irreversible in a way notification capture is
/// not. One wrong column guess would add dozens of bad rows at once.
class StatementImportService {
  StatementImportService({
    required this.idGenerator,
    this.reconciler = const CrossSourceReconciler(),
  });

  final String Function() idGenerator;
  final CrossSourceReconciler reconciler;

  /// Extracts text from a PDF.
  ///
  /// A PDF stores positioned glyphs, not columns, so this yields lines whose
  /// former columns are runs of spaces — which is why PDF import is a fallback
  /// and CSV is recommended.
  static String extractPdfText(List<int> bytes) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      return PdfTextExtractor(document).extractText();
    } finally {
      document.dispose();
    }
  }

  /// Reads [file] and works out what importing it would do.
  Future<StatementPreview> preview(
    File file, {
    required List<AppTransaction> existing,
    Categorizer? categorizer,
    AmountSign? signOverride,
    int? year,
  }) async {
    final name = file.path.split(RegExp(r'[\\/]')).last;
    final isPdf = name.toLowerCase().endsWith('.pdf');

    final StatementImport result;
    if (isPdf) {
      final text = extractPdfText(await file.readAsBytes());
      result = TextStatementReader.read(
        text,
        year: year,
        signOverride: signOverride,
      );
    } else {
      result = StatementReader.read(
        await file.readAsString(),
        signOverride: signOverride,
      );
    }

    final insert = <StatementRow>[];
    final merge = <StatementRow>[];
    final skip = <StatementRow>[];

    // Reconcile against a growing copy so two identical rows inside one file
    // do not both insert.
    var working = List<AppTransaction>.from(existing);

    for (final row in result.rows) {
      final outcome = reconciler.reconcile(
        _asAggregatorTransaction(row),
        working,
        idGenerator: idGenerator,
        categorizer: categorizer,
        source: TransactionSource.statement,
      );

      switch (outcome.action) {
        case ReconcileAction.insert:
          insert.add(row);
        case ReconcileAction.mergeIntoExisting:
          merge.add(row);
        case ReconcileAction.updateExisting:
        case ReconcileAction.skip:
          skip.add(row);
      }

      final merged = outcome.merged;
      if (merged != null) {
        working = <AppTransaction>[
          ...working.where((t) => t.id != merged.id),
          merged,
        ];
      }
    }

    return StatementPreview(
      fileName: name,
      format: isPdf ? StatementFormat.pdf : StatementFormat.csv,
      result: result,
      willInsert: insert,
      willMerge: merge,
      willSkip: skip,
    );
  }

  /// Applies an import, returning the rows to write.
  ///
  /// Runs the same reconciliation as [preview] rather than trusting its
  /// output, so the write reflects the data as it is now — the user may have
  /// added or edited transactions while the preview was on screen.
  List<AppTransaction> apply(
    StatementImport statement, {
    required List<AppTransaction> existing,
    Categorizer? categorizer,
  }) {
    final writes = <AppTransaction>[];
    var working = List<AppTransaction>.from(existing);

    for (final row in statement.rows) {
      final outcome = reconciler.reconcile(
        _asAggregatorTransaction(row),
        working,
        idGenerator: idGenerator,
        categorizer: categorizer,
        source: TransactionSource.statement,
      );

      final merged = outcome.merged;
      if (merged == null) continue;

      writes.add(merged);
      working = <AppTransaction>[
        ...working.where((t) => t.id != merged.id),
        merged,
      ];
    }

    return writes;
  }

  /// A statement row is the same shape of fact as an aggregator row — a
  /// posted transaction, authoritative over an alert — so it reuses the same
  /// reconciler rather than duplicating that logic.
  AggregatorTransaction _asAggregatorTransaction(StatementRow row) {
    return AggregatorTransaction(
      providerId: 'stmt:${row.date.toIso8601String().substring(0, 10)}'
          ':${row.amount.cents}:${row.merchantNormalized ?? row.description}',
      amountCents: row.amount.cents,
      currency: row.amount.currency,
      date: row.date,
      eventType: row.eventType,
      merchant: row.description,
      recordedDirection: row.direction,
    );
  }
}
