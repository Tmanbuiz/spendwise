/// What a bank notification actually represents.
///
/// The single most important product rule in SpendWise lives here: only
/// [TransactionEventType.purchase] events increase the user's spending totals.
/// Everything else is recorded for context but is excluded from budgets.
enum TransactionEventType {
  /// Money left the account for goods or services. Counts as spending.
  purchase,

  /// Money came back from a merchant (return, reversal, chargeback).
  refund,

  /// A payment toward a credit card or line of credit. Moves debt around,
  /// it is not new spending — the original purchases were already counted.
  payment,

  /// Movement between the user's own accounts, or an Interac e-Transfer.
  transfer,

  /// The card was refused. No money moved at all.
  declined,

  /// Recognised as coming from the bank, but not a transaction we understand
  /// (statement ready, balance alert, marketing, or an unparseable message).
  unknown;

  /// Whether an event of this type should increase monthly spending totals.
  ///
  /// Deliberately expressed as a whitelist: a future event type added to this
  /// enum defaults to *not* counting, which is the safe direction to fail.
  bool get countsAsSpending => this == TransactionEventType.purchase;

  /// Whether the event moved money at all. Declined events did not.
  bool get isSettled => this != TransactionEventType.declined &&
      this != TransactionEventType.unknown;

  String get wireName => name;

  static TransactionEventType fromWireName(String value) {
    for (final type in TransactionEventType.values) {
      if (type.name == value) return type;
    }
    return TransactionEventType.unknown;
  }
}
