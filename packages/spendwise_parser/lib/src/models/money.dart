/// A currency amount held in minor units (cents) to avoid binary float drift.
///
/// Notification amounts are always at most 2 decimal places, so an int of
/// cents is both exact and cheap to compare, sum and fingerprint.
class Money implements Comparable<Money> {
  const Money(this.cents, this.currency);

  /// Signed amount in minor units. Always stored positive by the parser —
  /// direction of money movement is carried by [TransactionEventType], not
  /// by the sign, so that a refund of $10 and a purchase of $10 compare equal
  /// on amount alone during duplicate detection.
  final int cents;

  /// ISO-4217 code, upper case. Defaults to CAD for Canadian banks.
  final String currency;

  static const Money zeroCad = Money(0, 'CAD');

  /// Builds a [Money] from a already-cleaned numeric string such as
  /// `1234.5`, `1,234.56` or `45`. Returns null when the text is not numeric.
  static Money? tryParse(String rawNumber, String currency) {
    final cleaned = rawNumber.replaceAll(',', '').replaceAll(' ', '').trim();
    if (cleaned.isEmpty) return null;
    final asDouble = double.tryParse(cleaned);
    if (asDouble == null || asDouble.isNaN || asDouble.isInfinite) return null;
    if (asDouble < 0) return null;
    // Round rather than truncate so 0.1+0.2 style inputs land on the cent.
    final cents = (asDouble * 100).round();
    return Money(cents, currency.toUpperCase());
  }

  double get amount => cents / 100.0;

  bool get isZero => cents == 0;

  String get formatted {
    final major = cents ~/ 100;
    final minor = (cents % 100).toString().padLeft(2, '0');
    return '\$$major.$minor $currency';
  }

  @override
  int compareTo(Money other) {
    if (currency != other.currency) return currency.compareTo(other.currency);
    return cents.compareTo(other.cents);
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.cents == cents && other.currency == currency;

  @override
  int get hashCode => Object.hash(cents, currency);

  @override
  String toString() => formatted;
}
