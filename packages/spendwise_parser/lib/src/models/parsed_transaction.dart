import 'money.dart';
import 'raw_retention.dart';
import 'transaction_event_type.dart';

/// Why a parse came out incomplete. Surfaced in the debug screen and used to
/// decide whether a redacted sample is worth keeping.
enum ParseGap {
  noAmount,
  noMerchant,
  noAccount,
  noTimestamp,
  ambiguousType,
  notATransaction,
  emptyMessage,
}

/// The result of running a bank parser over one notification.
///
/// A result is always returned — an unrecognised message comes back as
/// [TransactionEventType.unknown] rather than null, so the caller has one code
/// path and the debug screen can explain *why* nothing was extracted.
class ParsedTransaction {
  ParsedTransaction({
    required this.bankId,
    required this.eventType,
    required this.occurredAt,
    required this.occurredAtIsExact,
    required this.fingerprint,
    required this.rawRetention,
    this.amount,
    this.merchantRaw,
    this.merchantNormalized,
    this.accountLabel,
    this.accountLast4,
    this.redactedRaw,
    List<ParseGap> gaps = const <ParseGap>[],
  }) : gaps = List<ParseGap>.unmodifiable(gaps);

  /// Stable bank identifier, e.g. `cibc`.
  final String bankId;

  final TransactionEventType eventType;

  /// Amount in minor units. Null only when the message carried no amount we
  /// could trust — which for a real transaction means the parse failed.
  final Money? amount;

  /// Merchant exactly as it appeared, for display and user correction.
  final String? merchantRaw;

  /// Upper-cased, store-number-stripped form used for categorisation rules
  /// and duplicate fingerprinting.
  final String? merchantNormalized;

  /// Human label for the card or account, e.g. `CIBC Dividend Visa Infinite`.
  final String? accountLabel;

  /// Last four digits of the card. This is the ONLY part of a card number that
  /// is ever extracted or stored; full numbers, PINs and CVVs are never read.
  final String? accountLast4;

  /// When the transaction happened. Falls back to notification delivery time.
  final DateTime occurredAt;

  /// True when [occurredAt] was read out of the message, false when it is the
  /// notification's delivery time standing in for a missing date.
  final bool occurredAtIsExact;

  /// Deterministic key used for duplicate suppression.
  final String fingerprint;

  final RawRetention rawRetention;

  /// Present only when [rawRetention] is [RawRetention.keepRedactedForReview].
  final String? redactedRaw;

  final List<ParseGap> gaps;

  /// Whether this notification described a real money event we understood.
  bool get isTransaction => eventType != TransactionEventType.unknown;

  /// Whether this event should increase the user's monthly spending.
  ///
  /// Requires both the right event type *and* a usable amount, so a mangled
  /// purchase notification never silently books $0 of spending.
  bool get countsAsSpending =>
      eventType.countsAsSpending && amount != null && !amount!.isZero;

  /// True when every field a transaction row needs was extracted.
  bool get isComplete =>
      isTransaction && amount != null && merchantRaw != null && gaps.isEmpty;

  /// Rough 0..1 quality score, used to rank fallback parses and to drive the
  /// "needs review" flag in the UI.
  double get confidence {
    if (eventType == TransactionEventType.unknown) return 0.0;
    var score = 0.45; // recognised the event type at all
    if (amount != null && !amount!.isZero) score += 0.25;
    if (merchantRaw != null && merchantRaw!.isNotEmpty) score += 0.15;
    if (accountLast4 != null || accountLabel != null) score += 0.10;
    if (occurredAtIsExact) score += 0.05;
    return double.parse(score.clamp(0.0, 1.0).toStringAsFixed(2));
  }

  ParsedTransaction copyWith({
    TransactionEventType? eventType,
    Money? amount,
    String? merchantRaw,
    String? merchantNormalized,
    String? accountLabel,
    String? accountLast4,
    DateTime? occurredAt,
    bool? occurredAtIsExact,
    String? fingerprint,
    RawRetention? rawRetention,
    String? redactedRaw,
    List<ParseGap>? gaps,
  }) {
    return ParsedTransaction(
      bankId: bankId,
      eventType: eventType ?? this.eventType,
      amount: amount ?? this.amount,
      merchantRaw: merchantRaw ?? this.merchantRaw,
      merchantNormalized: merchantNormalized ?? this.merchantNormalized,
      accountLabel: accountLabel ?? this.accountLabel,
      accountLast4: accountLast4 ?? this.accountLast4,
      occurredAt: occurredAt ?? this.occurredAt,
      occurredAtIsExact: occurredAtIsExact ?? this.occurredAtIsExact,
      fingerprint: fingerprint ?? this.fingerprint,
      rawRetention: rawRetention ?? this.rawRetention,
      redactedRaw: redactedRaw ?? this.redactedRaw,
      gaps: gaps ?? this.gaps,
    );
  }

  /// Row shape for the Supabase `transactions` table. Note that the raw
  /// notification text is deliberately absent unless retention allows it.
  Map<String, Object?> toJson() => <String, Object?>{
        'bank_id': bankId,
        'event_type': eventType.wireName,
        'amount_cents': amount?.cents,
        'currency': amount?.currency,
        'merchant_raw': merchantRaw,
        'merchant_normalized': merchantNormalized,
        'account_label': accountLabel,
        'account_last4': accountLast4,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'occurred_at_is_exact': occurredAtIsExact,
        'fingerprint': fingerprint,
        'counts_as_spending': countsAsSpending,
        'confidence': confidence,
        'parse_gaps': gaps.map((g) => g.name).toList(),
        if (rawRetention.keepsAnything) 'redacted_raw': redactedRaw,
      };

  @override
  String toString() =>
      'ParsedTransaction(${eventType.name}, ${amount ?? "no amount"}, '
      '${merchantRaw ?? "no merchant"}, conf=$confidence)';
}
