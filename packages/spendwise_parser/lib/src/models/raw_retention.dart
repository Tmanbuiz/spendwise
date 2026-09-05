/// What the storage layer is allowed to do with the original notification text.
///
/// Requirement: never keep the raw notification longer than necessary once the
/// parsed fields are sufficient. The parser — not the UI and not the database —
/// decides, because only the parser knows whether it got what it needed.
enum RawRetention {
  /// Parse was complete. The raw text must be dropped the moment the
  /// transaction row is written; nothing is gained by keeping it.
  discard,

  /// Parse was incomplete or low confidence. A *redacted* copy may be kept so
  /// the user can correct it and so parser coverage can be improved, but it
  /// expires — see [RawRetention.reviewTtl].
  keepRedactedForReview;

  /// How long a redacted sample may live before it is purged.
  static const Duration reviewTtl = Duration(days: 30);

  bool get keepsAnything => this == RawRetention.keepRedactedForReview;
}

/// Strips values that could be sensitive out of notification text, leaving the
/// *wording* intact so parser coverage can still be improved from the sample.
///
/// Nothing here is a substitute for the hard rule that passwords, PINs, CVVs
/// and full card numbers are never stored at all — this is defence in depth for
/// the one field we may retain.
abstract final class Redactor {
  static final RegExp _longDigitRun = RegExp(r'\d[\d\s-]{10,}\d');
  static final RegExp _money = RegExp(r'[$€£]\s?\d[\d,]*(?:\.\d{1,2})?');
  static final RegExp _mediumDigitRun = RegExp(r'\b\d{4,}\b');
  static final RegExp _shortDigitRun = RegExp(r'\d+');

  /// Returns text safe to persist for a bounded review window.
  static String redact(String input) {
    var out = input;
    // Order matters: longest / most sensitive patterns first, otherwise the
    // short-digit rule would eat the card number before we can label it.
    out = out.replaceAll(_longDigitRun, '<card>');
    out = out.replaceAll(_money, '<amount>');
    out = out.replaceAll(_mediumDigitRun, '<digits>');
    out = out.replaceAll(_shortDigitRun, '<n>');
    return out;
  }
}
