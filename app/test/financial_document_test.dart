import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/models/financial_document.dart';

void main() {
  test('FinancialDocument round trips through json', () {
    final original = FinancialDocument(
      id: 'doc-1',
      fileName: 'cibc-july.pdf',
      storagePath: 'user/doc-1/cibc-july.pdf',
      storageKind: DocumentStorageKind.supabase,
      documentType: FinancialDocumentType.bankStatement,
      addedAt: DateTime(2026, 8, 1, 12),
      mimeType: 'application/pdf',
      sizeBytes: 12345,
      institution: 'CIBC',
      ownerLabel: 'Me',
      accountLast4: '1234',
      periodStart: DateTime(2026, 7, 1),
      periodEnd: DateTime(2026, 7, 31),
      importedTransactionCount: 42,
      note: 'Imported statement',
    );

    final decoded = FinancialDocument.fromJson(original.toJson());
    expect(decoded.id, original.id);
    expect(decoded.fileName, original.fileName);
    expect(decoded.storageKind, DocumentStorageKind.supabase);
    expect(decoded.documentType, FinancialDocumentType.bankStatement);
    expect(decoded.institution, 'CIBC');
    expect(decoded.accountLast4, '1234');
    expect(decoded.importedTransactionCount, 42);
    expect(decoded.extension, 'pdf');
  });

  test('extension is empty when the filename has no extension', () {
    final document = FinancialDocument(
      id: 'doc-2',
      fileName: 'statement',
      storagePath: '/private/statement',
      storageKind: DocumentStorageKind.local,
      documentType: FinancialDocumentType.other,
      addedAt: DateTime(2026),
    );

    expect(document.extension, isEmpty);
    expect(document.displayInstitution, 'Financial document');
  });
}
