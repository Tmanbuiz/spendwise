import 'transaction_event_type.dart';

/// Which way the money moved.
///
/// [TransactionEventType] says what a line *means* — a purchase, a transfer, a
/// refund — but not which way the money went, because an Interac e-Transfer
/// sent to a friend and a deposit received from an employer are both
/// `transfer`. Reporting income needs the two told apart, so direction is
/// carried separately.
///
/// It is deliberately not derived from the amount's sign: the app stores every
/// amount as a positive number so a $10 refund and a $10 purchase compare
/// equal during duplicate detection.
enum TransactionDirection {
  /// Money arrived: a deposit, a payroll credit, a refund, an e-Transfer
  /// received.
  inbound,

  /// Money left: a purchase, a bill, an e-Transfer sent, a loan instalment.
  outbound;

  String get wireName => name;

  static TransactionDirection fromWireName(String value) {
    for (final direction in TransactionDirection.values) {
      if (direction.name == value) return direction;
    }
    return TransactionDirection.outbound;
  }

  /// Wording that only ever describes money arriving.
  ///
  /// Kept deliberately narrow. `PAY` as a leading word is how banks label a
  /// payroll credit — "PAY HARMONY FAMILY" — and the word boundary keeps it
  /// from matching PAYMENT, which is usually money going the other way.
  static final RegExp _arriving = RegExp(
    r'^\s*pay\b|\bdirect\s+deposit\b|\bpayroll\b|\bdeposit\b|'
    r'\binterest\s+paid\b|\bcredit\s+memo\b',
    caseSensitive: false,
  );

  /// The direction implied by [type] alone, for rows that predate this field
  /// or come from a source that never knew.
  ///
  /// A refund is the only event type that is inbound by definition.
  /// Everything else is assumed outbound.
  static TransactionDirection inferFrom(TransactionEventType type) =>
      infer(type: type);

  /// The best guess available for a row that never recorded its direction.
  ///
  /// [description] is consulted because assuming outbound for everything is
  /// not the safe default it first appears to be: it files a salary as money
  /// leaving the account, which overstates outflow by the largest single
  /// figure on most statements. Only wording that cannot mean anything else
  /// is treated as inbound — a sent and a received e-Transfer read
  /// identically, and those are settled only by re-importing a statement
  /// whose running balance says which way the money went.
  static TransactionDirection infer({
    required TransactionEventType type,
    String? description,
  }) {
    if (type == TransactionEventType.refund) {
      return TransactionDirection.inbound;
    }
    if (type == TransactionEventType.transfer &&
        description != null &&
        _arriving.hasMatch(description)) {
      return TransactionDirection.inbound;
    }
    return TransactionDirection.outbound;
  }
}
