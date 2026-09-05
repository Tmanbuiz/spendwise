import '../util/merchant_cleaner.dart';

/// The fields of CIBC's terse card-first alert.
class CibcTerseAlert {
  const CibcTerseAlert({
    required this.accountLabel,
    required this.last4,
    required this.merchantRaw,
    required this.amountText,
  });

  final String accountLabel;
  final String last4;
  final String merchantRaw;

  /// The amount exactly as written, e.g. `$28.51`. Parsed by [AmountParser]
  /// so currency handling stays in one place.
  final String amountText;

  String? get merchantNormalized => MerchantExtractor.normalize(merchantRaw);
}

/// Recognises the format CIBC actually ships for card transactions.
///
/// A real alert, captured from a device:
///
/// ```
/// CIBC Adapta Mastercard, 2199 SHEIN $28.51
/// ```
///
/// Note what is *not* there: no verb, no "purchase", no "transaction", no
/// "at". The generic keyword rules cannot classify this, and the generic
/// merchant extractor has no anchor to work from — the merchant simply sits
/// between the card's last four digits and the amount.
///
/// The title and subText are both null on these notifications, and the body is
/// truncated with an ellipsis; the full sentence lives in `EXTRA_BIG_TEXT`,
/// which is why the Android service prefers whichever of the two is longer.
abstract final class CibcTerseFormat {
  /// `CIBC <product>, <last4> <MERCHANT> <amount>`
  ///
  /// The merchant is lazy so it stops at the first amount rather than
  /// swallowing it, which keeps multi-word merchants like `TIM HORTONS #123`
  /// intact. It stays `[^\n]` so the merchant itself cannot run across lines,
  /// while the gap before the amount is plain `\s*` — CIBC puts a line break
  /// there, and the two rules together keep the merchant clean without losing
  /// the amount on the next line.
  static final RegExp _pattern = RegExp(
    r'\b(?<label>CIBC\b[^,\n]{0,48}?)\s*,\s*(?<last4>\d{4})\b'
    r'\s+(?<merchant>[^\n]{1,60}?)\s*'
    r'(?<amount>(?:US\$|CA\$|[$€£])\s?\d[\d,]*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  /// True when [text] is this template. Used by the rules chain so a terse
  /// alert is classified as a purchase despite carrying no verb.
  static bool matches(String text) => _pattern.hasMatch(text);

  static CibcTerseAlert? tryParse(String text) {
    final match = _pattern.firstMatch(text);
    if (match == null) return null;

    final merchant = MerchantExtractor.tidy(match.namedGroup('merchant') ?? '');
    if (merchant == null) return null;

    final label = match.namedGroup('label')?.trim();
    final last4 = match.namedGroup('last4');
    final amount = match.namedGroup('amount');
    if (label == null || last4 == null || amount == null) return null;

    return CibcTerseAlert(
      accountLabel: label,
      last4: last4,
      merchantRaw: merchant,
      amountText: amount,
    );
  }
}
