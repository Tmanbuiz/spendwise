/// A source document kept in SpendWise's financial vault.
///
/// The document itself lives either in the app's private documents directory
/// or in a private Supabase Storage bucket. This model stores only metadata and
/// the opaque storage path needed to retrieve it later.
class FinancialDocument {
  const FinancialDocument({
    required this.id,
    required this.fileName,
    required this.storagePath,
    required this.storageKind,
    required this.documentType,
    required this.addedAt,
    this.mimeType,
    this.sizeBytes = 0,
    this.institution,
    this.ownerLabel,
    this.accountLabel,
    this.accountLast4,
    this.periodStart,
    this.periodEnd,
    this.importedTransactionCount = 0,
    this.note,
  });

  final String id;
  final String fileName;

  /// Absolute app-private path for local storage, or a bucket object path for
  /// Supabase Storage. Never contains banking credentials.
  final String storagePath;
  final DocumentStorageKind storageKind;
  final FinancialDocumentType documentType;
  final DateTime addedAt;
  final String? mimeType;
  final int sizeBytes;

  /// Optional metadata used for filtering and household organisation.
  final String? institution;
  final String? ownerLabel;
  final String? accountLabel;
  final String? accountLast4;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  /// Number of transaction rows written when this document was imported.
  /// Zero is valid for documents stored for reference only.
  final int importedTransactionCount;
  final String? note;

  String get extension {
    final index = fileName.lastIndexOf('.');
    if (index < 0 || index == fileName.length - 1) return '';
    return fileName.substring(index + 1).toLowerCase();
  }

  String get displayInstitution {
    final value = institution?.trim();
    return value == null || value.isEmpty ? 'Financial document' : value;
  }

  FinancialDocument copyWith({
    String? fileName,
    String? storagePath,
    DocumentStorageKind? storageKind,
    FinancialDocumentType? documentType,
    DateTime? addedAt,
    String? mimeType,
    int? sizeBytes,
    String? institution,
    String? ownerLabel,
    String? accountLabel,
    String? accountLast4,
    DateTime? periodStart,
    DateTime? periodEnd,
    int? importedTransactionCount,
    String? note,
  }) {
    return FinancialDocument(
      id: id,
      fileName: fileName ?? this.fileName,
      storagePath: storagePath ?? this.storagePath,
      storageKind: storageKind ?? this.storageKind,
      documentType: documentType ?? this.documentType,
      addedAt: addedAt ?? this.addedAt,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      institution: institution ?? this.institution,
      ownerLabel: ownerLabel ?? this.ownerLabel,
      accountLabel: accountLabel ?? this.accountLabel,
      accountLast4: accountLast4 ?? this.accountLast4,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      importedTransactionCount:
          importedTransactionCount ?? this.importedTransactionCount,
      note: note ?? this.note,
    );
  }

  /// `user_id` is deliberately absent. Supabase fills it with `auth.uid()` and
  /// RLS verifies ownership server-side.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'file_name': fileName,
        'storage_path': storagePath,
        'storage_kind': storageKind.name,
        'document_type': documentType.name,
        'added_at': addedAt.toUtc().toIso8601String(),
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'institution': institution,
        'owner_label': ownerLabel,
        'account_label': accountLabel,
        'account_last4': accountLast4,
        'period_start': periodStart?.toIso8601String(),
        'period_end': periodEnd?.toIso8601String(),
        'imported_transaction_count': importedTransactionCount,
        'note': note,
      };

  static FinancialDocument fromJson(Map<String, Object?> json) {
    return FinancialDocument(
      id: (json['id'] as String?) ?? '',
      fileName: (json['file_name'] as String?) ?? 'Document',
      storagePath: (json['storage_path'] as String?) ?? '',
      storageKind: DocumentStorageKind.values.firstWhere(
        (value) => value.name == json['storage_kind'],
        orElse: () => DocumentStorageKind.local,
      ),
      documentType: FinancialDocumentType.values.firstWhere(
        (value) => value.name == json['document_type'],
        orElse: () => FinancialDocumentType.other,
      ),
      addedAt:
          DateTime.tryParse((json['added_at'] as String?) ?? '')?.toLocal() ??
              DateTime.now(),
      mimeType: json['mime_type'] as String?,
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      institution: json['institution'] as String?,
      ownerLabel: json['owner_label'] as String?,
      accountLabel: json['account_label'] as String?,
      accountLast4: json['account_last4'] as String?,
      periodStart:
          DateTime.tryParse((json['period_start'] as String?) ?? '')?.toLocal(),
      periodEnd:
          DateTime.tryParse((json['period_end'] as String?) ?? '')?.toLocal(),
      importedTransactionCount:
          (json['imported_transaction_count'] as num?)?.toInt() ?? 0,
      note: json['note'] as String?,
    );
  }
}

enum DocumentStorageKind { local, supabase }

enum FinancialDocumentType {
  bankStatement('Bank statement'),
  creditCardStatement('Credit card statement'),
  payStub('Pay stub'),
  investmentStatement('Investment statement'),
  taxDocument('Tax document'),
  receipt('Receipt'),
  other('Other');

  const FinancialDocumentType(this.displayName);
  final String displayName;
}
