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

  /// The direction implied by [type] alone, for rows that predate this field
  /// or come from a source that never knew.
  ///
  /// A refund is the only event type that is inbound by definition. Everything
  /// else — transfers most of all — is assumed outbound, because that is the
  /// reading that cannot silently inflate someone's income.
  static TransactionDirection inferFrom(TransactionEventType type) {
    return type == TransactionEventType.refund
        ? TransactionDirection.inbound
        : TransactionDirection.outbound;
  }
}
