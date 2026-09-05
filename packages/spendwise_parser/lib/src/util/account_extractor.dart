/// The card/account identity carried by a notification.
class AccountHint {
  const AccountHint({this.label, this.last4});

  /// Human-readable product name, e.g. `CIBC Dividend Visa Infinite card`.
  final String? label;

  /// Last four digits only. SpendWise never reads, parses or stores a full
  /// card number, a PIN or a CVV — there is no code path that can.
  final String? last4;

  bool get isEmpty => label == null && last4 == null;
}

abstract final class AccountExtractor {
  /// `ending in 1234`, `ending 1234`, `number ending in 1234`.
  static final RegExp _endingIn = RegExp(
    r'\bending(?:\s+(?:in|with))?\s+(\d{4})\b',
    caseSensitive: false,
  );

  /// Masked forms: `****1234`, `xxxx 1234`, `··1234`.
  static final RegExp _masked = RegExp(
    r'(?:[*x•·]\s*){2,}(\d{4})\b',
    caseSensitive: false,
  );

  /// A long digit run we must NOT treat as a last-4. If a notification ever
  /// contains something card-number shaped, the whole match is refused rather
  /// than four digits being sliced out of it.
  static final RegExp _cardNumberShaped = RegExp(r'\b\d[\d\s-]{12,}\d\b');

  static String? extractLast4(String text) {
    if (_cardNumberShaped.hasMatch(text)) return null;
    final ending = _endingIn.firstMatch(text);
    if (ending != null) return ending.group(1);
    final masked = _masked.firstMatch(text);
    if (masked != null) return masked.group(1);
    return null;
  }

  /// Finds a product label for [bankName], e.g. `CIBC Smart Account`.
  ///
  /// The patterns are assembled from raw-string fragments rather than written
  /// with interpolation, so the regex escapes stay single-escaped and legible.
  // Raw strings cannot interpolate, and interpolating would force every regex
  // escape to be doubled — concatenation keeps the patterns readable.
  // ignore_for_file: prefer_interpolation_to_compose_strings
  static String? extractLabel(String text, String bankName) {
    final bank = RegExp.escape(bankName);

    // `your CIBC Dividend Visa Infinite card ending in 1234`
    final withNoun = RegExp(
      r'\byour\s+(' + bank + r'\b[^,.\n]{0,60}?)\s+'
          r'(card|account|chequing|savings)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (withNoun != null) {
      return _tidy('${withNoun.group(1)} ${withNoun.group(2)}');
    }

    // `to your CIBC Visa ending in 1234`
    final beforeEnding = RegExp(
      r'\byour\s+(' + bank + r'\b[^,.\n]{0,60}?)\s+ending\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (beforeEnding != null) return _tidy(beforeEnding.group(1)!);

    // Bare product mention anywhere: `CIBC Aventura Visa`.
    final bare = RegExp(
      r'\b(' + bank + r'\s+(?:[A-Za-z]+\s+){0,3}?'
          r'(?:Visa|Mastercard|Debit|Chequing|Savings|Credit))\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (bare != null) return _tidy(bare.group(1)!);

    return null;
  }

  static String? _tidy(String input) {
    final out = input.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out.isEmpty ? null : out;
  }
}
