import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/financial_document.dart';
import 'statement_import_service.dart';

/// Stores source financial documents without ever making them public.
///
/// In local mode files are copied into the application's private documents
/// directory. In synced mode they are uploaded to a private Supabase Storage
/// bucket under `<auth.uid()>/<document-id>/...`; Storage RLS verifies that
/// prefix server-side.
class FinancialVaultService {
  FinancialVaultService({
    required this.isRemote,
    this.client,
  });

  static const bucket = 'financial-documents';

  final bool isRemote;
  final SupabaseClient? client;

  Future<FinancialDocument> storeFile(
    File file, {
    required String documentId,
    FinancialDocumentType documentType = FinancialDocumentType.other,
    String? institution,
    String? ownerLabel,
    String? accountLabel,
    String? accountLast4,
    DateTime? periodStart,
    DateTime? periodEnd,
    int importedTransactionCount = 0,
    String? note,
  }) async {
    final sourceName = _basename(file.path);
    final safeName = _safeFileName(sourceName);
    final size = await file.length();
    final mime = _mimeType(sourceName);

    if (isRemote) {
      final supabase = client;
      final userId = supabase?.auth.currentUser?.id;
      if (supabase == null || userId == null) {
        throw StateError('Sign in before storing a synced financial document.');
      }

      final objectPath = '$userId/$documentId/$safeName';
      await supabase.storage.from(bucket).upload(
            objectPath,
            file,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );

      return FinancialDocument(
        id: documentId,
        fileName: sourceName,
        storagePath: objectPath,
        storageKind: DocumentStorageKind.supabase,
        documentType: documentType,
        addedAt: DateTime.now(),
        mimeType: mime,
        sizeBytes: size,
        institution: institution,
        ownerLabel: ownerLabel,
        accountLabel: accountLabel,
        accountLast4: accountLast4,
        periodStart: periodStart,
        periodEnd: periodEnd,
        importedTransactionCount: importedTransactionCount,
        note: note,
      );
    }

    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}financial_documents');
    if (!await directory.exists()) await directory.create(recursive: true);

    final storedName = '${documentId}_$safeName';
    final destination = File('${directory.path}${Platform.pathSeparator}$storedName');
    await file.copy(destination.path);

    return FinancialDocument(
      id: documentId,
      fileName: sourceName,
      storagePath: destination.path,
      storageKind: DocumentStorageKind.local,
      documentType: documentType,
      addedAt: DateTime.now(),
      mimeType: mime,
      sizeBytes: size,
      institution: institution,
      ownerLabel: ownerLabel,
      accountLabel: accountLabel,
      accountLast4: accountLast4,
      periodStart: periodStart,
      periodEnd: periodEnd,
      importedTransactionCount: importedTransactionCount,
      note: note,
    );
  }

  /// Archives a statement with the date coverage recovered by its parser.
  Future<FinancialDocument> archiveStatement(
    File file,
    StatementPreview preview, {
    required String documentId,
    int importedTransactionCount = 0,
    String? ownerLabel,
    String? accountLabel,
    String? accountLast4,
  }) {
    DateTime? first;
    DateTime? last;
    for (final row in preview.result.rows) {
      if (first == null || row.date.isBefore(first)) first = row.date;
      if (last == null || row.date.isAfter(last)) last = row.date;
    }

    return storeFile(
      file,
      documentId: documentId,
      documentType: _statementType(preview.fileName),
      institution: _inferInstitution(preview.fileName),
      ownerLabel: ownerLabel,
      accountLabel: accountLabel,
      accountLast4: accountLast4,
      periodStart: first,
      periodEnd: last,
      importedTransactionCount: importedTransactionCount,
      note: 'Archived when statement transactions were imported.',
    );
  }

  Future<void> deleteStoredFile(FinancialDocument document) async {
    if (document.storageKind == DocumentStorageKind.supabase) {
      final supabase = client;
      if (supabase == null) {
        throw StateError('Synced storage is unavailable.');
      }
      await supabase.storage.from(bucket).remove(<String>[document.storagePath]);
      return;
    }

    final file = File(document.storagePath);
    if (await file.exists()) await file.delete();
  }

  Future<List<int>> readBytes(FinancialDocument document) async {
    if (document.storageKind == DocumentStorageKind.supabase) {
      final supabase = client;
      if (supabase == null) {
        throw StateError('Synced storage is unavailable.');
      }
      return supabase.storage.from(bucket).download(document.storagePath);
    }
    return File(document.storagePath).readAsBytes();
  }

  static FinancialDocumentType inferDocumentType(String fileName) {
    final name = fileName.toLowerCase();
    if (name.contains('paystub') || name.contains('pay stub') || name.contains('payslip')) {
      return FinancialDocumentType.payStub;
    }
    if (name.contains('investment') ||
        name.contains('tfsa') ||
        name.contains('fhsa') ||
        name.contains('rrsp') ||
        name.contains('wealthsimple')) {
      return FinancialDocumentType.investmentStatement;
    }
    if (name.contains('tax') || name.contains('t4') || name.contains('notice of assessment')) {
      return FinancialDocumentType.taxDocument;
    }
    if (name.contains('visa') ||
        name.contains('mastercard') ||
        name.contains('credit card')) {
      return FinancialDocumentType.creditCardStatement;
    }
    if (name.endsWith('.csv') || name.endsWith('.pdf') || name.endsWith('.txt')) {
      return FinancialDocumentType.bankStatement;
    }
    return FinancialDocumentType.other;
  }

  static FinancialDocumentType _statementType(String name) {
    final inferred = inferDocumentType(name);
    return inferred == FinancialDocumentType.other
        ? FinancialDocumentType.bankStatement
        : inferred;
  }

  static String? _inferInstitution(String fileName) {
    final name = fileName.toLowerCase();
    if (name.contains('cibc')) return 'CIBC';
    if (name.contains('wealthsimple')) return 'Wealthsimple';
    if (name.contains('scotia')) return 'Scotiabank';
    if (name.contains('td')) return 'TD';
    if (name.contains('rbc')) return 'RBC';
    if (name.contains('bmo')) return 'BMO';
    return null;
  }

  static String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

  static String _safeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'document' : cleaned;
  }

  static String _mimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    return 'application/octet-stream';
  }
}
