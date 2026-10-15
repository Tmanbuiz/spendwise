import 'dart:io';
import 'dart:convert';
import 'local_cipher.dart';

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
    this.cipherOverride,
    this.documentsDirectory,
  });

  static const bucket = 'financial-documents';

  final bool isRemote;
  final SupabaseClient? client;
  final LocalCipher? cipherOverride;
  final Directory? documentsDirectory;
  Future<Directory> get _root async => documentsDirectory ?? await getApplicationDocumentsDirectory();
  Future<LocalCipher> get _cipher async => cipherOverride ?? await LocalCipher.open();

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
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(documentId)) throw const FormatException('Invalid document ID');
    if (await file.length() > 30000000) throw const FormatException('Document too large');
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

    final root = await _root;
    final directory = Directory('${root.path}${Platform.pathSeparator}financial_documents');
    if (!await directory.exists()) await directory.create(recursive: true);

    final storedName = '${documentId}_$safeName';
    final destination = File('${directory.path}${Platform.pathSeparator}$storedName');
    await _writeEncrypted(destination, await file.readAsBytes(), documentId);

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

    if (!await File(document.storagePath).exists()) return;
    final file = await _localFile(document);
    await file.delete();
  }

  Future<List<int>> readBytes(FinancialDocument document) async {
    if (document.storageKind == DocumentStorageKind.supabase) {
      final supabase = client;
      if (supabase == null) {
        throw StateError('Synced storage is unavailable.');
      }
      return supabase.storage.from(bucket).download(document.storagePath);
    }
    final file = await _localFile(document);
    final bytes = await file.readAsBytes();
    final cipher = await _cipher;
    const prefix = [83, 87, 69, 78, 67, 49, 10]; // SWENC1 newline
    if (bytes.length >= prefix.length && List.generate(prefix.length, (i) => bytes[i] == prefix[i]).every((v) => v)) {
      return cipher.decrypt(utf8.decode(bytes.sublist(prefix.length)), 'vault:${document.id}');
    }
    // Upgrade a legacy document in place; no plaintext temporary file is made.
    await _writeEncrypted(file, bytes, document.id);
    return bytes;
  }

  /// Upgrade every available legacy document before the normal UI starts.
  /// Missing source files keep their metadata; no replacement is invented.
  Future<int> migrateLegacyDocuments(Iterable<FinancialDocument> documents) async {
    var checked = 0;
    for (final document in documents) {
      if (document.storageKind != DocumentStorageKind.local) continue;
      if (!await File(document.storagePath).exists()) continue;
      await readBytes(document);
      checked++;
    }
    return checked;
  }

  Future<void> _writeEncrypted(File destination, List<int> bytes, String id) async {
    final cipher = await _cipher;
    final encrypted = await cipher.encrypt(bytes, 'vault:$id');
    final staged = File('${destination.path}.encrypting');
    await staged.writeAsString('SWENC1\n$encrypted', flush: true);
    final stored = await staged.readAsString();
    final verified = await cipher.decrypt(stored.substring(7), 'vault:$id');
    if (verified.length != bytes.length || Iterable<int>.generate(bytes.length).any((i) => bytes[i] != verified[i])) {
      throw StateError('Document verification failed');
    }
    await staged.rename(destination.path);
  }

  Future<File> _localFile(FinancialDocument document) async {
    final root = await _root;
    final directory = Directory('${root.path}${Platform.pathSeparator}financial_documents');
    final file = File(document.storagePath);
    if (!await directory.exists() || !await file.exists()) throw StateError('Document unavailable');
    final parent = await directory.resolveSymbolicLinks();
    final actual = await file.resolveSymbolicLinks();
    if (!actual.startsWith('$parent${Platform.pathSeparator}')) throw StateError('Invalid document path');
    return File(actual);
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
