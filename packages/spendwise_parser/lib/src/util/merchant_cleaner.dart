/// Extracts and normalises the merchant name from notification text.
abstract final class MerchantExtractor {
  /// Where a merchant name stops. Chosen conservatively: `and` and `in` are
  /// deliberately absent because real merchants contain them
  /// ("BED BATH AND BEYOND", "MADE IN CANADA").
  static final RegExp _terminator = RegExp(
    r'\s+(?:on|with|using|for|was|were|is|has|have|your|at|by'
    r'|could|cannot|will|would|should|did|does|due|than|from)\b'
    r'|\s+[-–—]\s+'
    r'|[,;!?]'
    r'|\.\s'
    r'|\n'
    r'|\s+\d{1,2}:\d{2}',
    caseSensitive: false,
  );

  /// Captures that are grammar or metadata, not merchants. Times matter here:
  /// "... at 8:14 a.m." would otherwise be captured by the `at` anchor.
  static final RegExp _notAMerchant = RegExp(
    r'^(?:your|the|a|an|this|that|our)\b'
    r'|^(?:cibc|rbc|td|scotiabank|bmo)\s+(?:card|account|visa|mastercard)\b'
    r'|^[\d\s#*.\-]+$'
    r'|^\d{1,2}:\d{2}'
    r'|^\d{1,2}\s*(?:a\.?m\.?|p\.?m\.?)\b',
    caseSensitive: false,
  );

  static final RegExp _processorPrefix = RegExp(
    r'^(?:SQ|SP|TST|PP|PAYPAL|IC|POS|PURCHASE)\s*\*+\s*',
    caseSensitive: false,
  );
  static final RegExp _storeNumber = RegExp(r'\s*#\s*\d+');
  static final RegExp _trailingProvince = RegExp(
    r'\s+(?:AB|BC|MB|NB|NL|NS|NT|NU|ON|PE|QC|SK|YT)$',
    caseSensitive: false,
  );
  static final RegExp _trailingDigits = RegExp(r'\s+\d{3,}$');
  static final RegExp _nonAlnum = RegExp(r'[^A-Z0-9 ]');
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _edgePunctuation = RegExp(r'^[\s\-*.,:]+|[\s\-*.,:]+$');

  /// Finds the merchant by trying each anchor in [anchors] in priority order.
  ///
  /// An anchor is a pattern whose *match end* is where the merchant begins,
  /// e.g. `RegExp(r'\bat\s+')`. Every occurrence of an anchor is tried before
  /// moving to the next anchor, so "... at 8:14 a.m. at TIM HORTONS" still
  /// finds the merchant after rejecting the time.
  static String? extract(String text, List<RegExp> anchors) {
    for (final anchor in anchors) {
      for (final m in anchor.allMatches(text)) {
        final candidate = _captureFrom(text, m.end);
        if (candidate != null) return candidate;
      }
    }
    return null;
  }

  static String? _captureFrom(String text, int startIndex) {
    if (startIndex >= text.length) return null;
    final tail = text.substring(startIndex);
    final stop = _terminator.firstMatch(tail);
    final sliced = stop == null ? tail : tail.substring(0, stop.start);
    final cleaned = tidy(sliced);
    if (cleaned == null) return null;
    if (_notAMerchant.hasMatch(cleaned)) return null;
    return cleaned;
  }

  /// Display form: original casing, punctuation trimmed off the edges.
  static String? tidy(String input) {
    final trimmed =
        input.replaceAll(_edgePunctuation, '').replaceAll(_whitespace, ' ');
    if (trimmed.length < 2) return null;
    return trimmed;
  }

  /// Matching form: upper case, store numbers and processor prefixes removed.
  ///
  /// This is what merchant to category rules and duplicate fingerprints key
  /// on, so that `SQ *BLUE DOOR CAFE #12` and `BLUE DOOR CAFE` are recognised
  /// as one merchant.
  static String? normalize(String? input) {
    if (input == null) return null;
    var out = input.toUpperCase();
    out = out.replaceAll(_processorPrefix, '');
    out = out.replaceAll(_storeNumber, ' ');
    out = out.replaceAll(_trailingProvince, '');
    out = out.replaceAll(_trailingDigits, '');
    out = out.replaceAll(_nonAlnum, ' ');
    out = out.replaceAll(_whitespace, ' ').trim();
    return out.isEmpty ? null : out;
  }
}
