import 'package:spendwise_parser/spendwise_parser.dart';

/// Where a transaction came from.
enum TransactionSource {
  /// Captured from an Android notification and parsed automatically.
  notification,

  /// Entered or corrected by the user.
  manual,

  /// Pulled from a linked bank account via a data aggregator (Plaid, Flinks).
  /// Authoritative over a notification for the same purchase, because it is
  /// the posted transaction rather than the alert.
  aggregator,

  /// Imported from a bank statement file the user downloaded. Authoritative
  /// over a notification for the same purchase, for the same reason an
  /// aggregator row is: it is the posted transaction, not the alert.
  statement,

  /// Reserved for the planned iOS email importer. Declared now so the schema
  /// and the UI do not need changing when it ships.
  email,
}

/// A transaction as stored and displayed by the app.
///
/// Distinct from the parser's `ParsedTransaction`, which knows only what one
/// notification said. This adds identity, category, user edits and the
/// exclusion flag.
class AppTransaction {
  const AppTransaction({
    required this.id,
    required this.eventType,
    required this.amountCents,
    required this.currency,
    required this.occurredAt,
    required this.category,
    required this.source,
    this.merchant,
    this.merchantNormalized,
    this.accountId,
    this.accountLabel,
    this.accountLast4,
    this.bankId,
    this.note,
    this.fingerprint,
    this.needsReview = false,
    this.excludedByUser = false,
    this.categoryWasSetByUser = false,
  });

  final String id;
  final TransactionEventType eventType;

  /// Always positive. Direction is carried by [eventType].
  final int amountCents;
  final String currency;
  final DateTime occurredAt;
  final SpendCategory category;
  final TransactionSource source;

  final String? merchant;
  final String? merchantNormalized;
  final String? accountId;
  final String? accountLabel;
  final String? accountLast4;
  final String? bankId;
  final String? note;
  final String? fingerprint;

  /// The parse was incomplete; the user is asked to confirm the details.
  final bool needsReview;

  /// The user chose to keep this out of their spending totals.
  final bool excludedByUser;

  /// Stops the categoriser from overwriting a category the user picked.
  final bool categoryWasSetByUser;

  double get amount => amountCents / 100.0;

  /// The single rule that decides whether this hits the monthly total.
  ///
  /// Mirrors the parser's rule and adds the user's own override, so a
  /// transaction the user excluded stops counting without being deleted.
  bool get countsAsSpending =>
      eventType.countsAsSpending && amountCents > 0 && !excludedByUser;

  String get displayMerchant {
    final name = merchant?.trim();
    if (name != null && name.isNotEmpty) return name;
    switch (eventType) {
      case TransactionEventType.payment:
        return 'Card payment';
      case TransactionEventType.transfer:
        return 'Transfer';
      case TransactionEventType.refund:
        return 'Refund';
      case TransactionEventType.declined:
        return 'Declined transaction';
      case TransactionEventType.purchase:
      case TransactionEventType.unknown:
        return 'Unknown merchant';
    }
  }

  AppTransaction copyWith({
    TransactionEventType? eventType,
    int? amountCents,
    String? currency,
    DateTime? occurredAt,
    SpendCategory? category,
    TransactionSource? source,
    String? merchant,
    String? merchantNormalized,
    String? accountId,
    String? accountLabel,
    String? accountLast4,
    String? bankId,
    String? note,
    String? fingerprint,
    bool? needsReview,
    bool? excludedByUser,
    bool? categoryWasSetByUser,
  }) {
    return AppTransaction(
      id: id,
      eventType: eventType ?? this.eventType,
      amountCents: amountCents ?? this.amountCents,
      currency: currency ?? this.currency,
      occurredAt: occurredAt ?? this.occurredAt,
      category: category ?? this.category,
      source: source ?? this.source,
      merchant: merchant ?? this.merchant,
      merchantNormalized: merchantNormalized ?? this.merchantNormalized,
      accountId: accountId ?? this.accountId,
      accountLabel: accountLabel ?? this.accountLabel,
      accountLast4: accountLast4 ?? this.accountLast4,
      bankId: bankId ?? this.bankId,
      note: note ?? this.note,
      fingerprint: fingerprint ?? this.fingerprint,
      needsReview: needsReview ?? this.needsReview,
      excludedByUser: excludedByUser ?? this.excludedByUser,
      categoryWasSetByUser:
          categoryWasSetByUser ?? this.categoryWasSetByUser,
    );
  }

  /// Row shape for the Supabase `transactions` table.
  ///
  /// `user_id` is deliberately absent: it is filled by a column default of
  /// `auth.uid()` and enforced by RLS, so the client cannot write a row that
  /// belongs to someone else even if it tried.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'event_type': eventType.wireName,
        'amount_cents': amountCents,
        'currency': currency,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'category': category.slug,
        'source': source.name,
        'merchant': merchant,
        'merchant_normalized': merchantNormalized,
        'account_id': accountId,
        'account_label': accountLabel,
        'account_last4': accountLast4,
        'bank_id': bankId,
        'note': note,
        'fingerprint': fingerprint,
        'needs_review': needsReview,
        'excluded_by_user': excludedByUser,
        'category_set_by_user': categoryWasSetByUser,
      };

  static AppTransaction fromJson(Map<String, Object?> json) {
    return AppTransaction(
      id: (json['id'] as String?) ?? '',
      eventType: TransactionEventType.fromWireName(
        (json['event_type'] as String?) ?? 'unknown',
      ),
      amountCents: (json['amount_cents'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] as String?) ?? 'CAD',
      occurredAt:
          DateTime.tryParse((json['occurred_at'] as String?) ?? '')?.toLocal() ??
              DateTime.now(),
      category: SpendCategory.fromSlug((json['category'] as String?) ?? 'other'),
      source: TransactionSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => TransactionSource.notification,
      ),
      merchant: json['merchant'] as String?,
      merchantNormalized: json['merchant_normalized'] as String?,
      accountId: json['account_id'] as String?,
      accountLabel: json['account_label'] as String?,
      accountLast4: json['account_last4'] as String?,
      bankId: json['bank_id'] as String?,
      note: json['note'] as String?,
      fingerprint: json['fingerprint'] as String?,
      needsReview: (json['needs_review'] as bool?) ?? false,
      excludedByUser: (json['excluded_by_user'] as bool?) ?? false,
      categoryWasSetByUser: (json['category_set_by_user'] as bool?) ?? false,
    );
  }
}
