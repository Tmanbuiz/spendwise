import '../models/money.dart';

/// One monetary value found in a notification, with where it was found.
class AmountMatch {
  const AmountMatch(this.money, this.start, this.end);

  final Money money;
  final int start;
  final int end;
}

/// Pulls monetary amounts out of free-form notification text.
///
/// The hard part is not finding a number — it is finding the *right* number.
/// Bank alerts routinely quote the running balance, the credit limit, or a
/// card's last four digits in the same sentence as the transaction amount.
abstract final class AmountParser {
  /// Amounts introduced by a symbol or an ISO code. This is the trusted pass.
  static final RegExp _explicit = RegExp(
    r'(?<lead>US\$|CA\$|USD\s*\$?|CAD\s*\$?|EUR\s*|GBP\s*|[$€£])\s*'
    r'(?<num>\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)'
    r'(?:\s*(?<trail>USD|CAD|EUR|GBP))?',
    caseSensitive: false,
  );

  /// Bare two-decimal numbers, optionally followed by a code. Only consulted
  /// when the trusted pass found nothing, because a bare integer is far more
  /// likely to be a card suffix than an amount.
  static final RegExp _bareDecimal = RegExp(
    r'(?<![\d.,])(?<num>\d{1,3}(?:,\d{3})+\.\d{2}|\d+\.\d{2})(?![\d])'
    r'(?:\s*(?<trail>USD|CAD|EUR|GBP))?',
    caseSensitive: false,
  );

  /// Words that mean "this number is not the transaction amount".
  static final RegExp _contextExclusion = RegExp(
    r'\b(?:available|balance|limit|remaining|overdraft|owing|'
    r'statement\s+balance|minimum\s+payment\s+due|credit\s+available)\b',
    caseSensitive: false,
  );

  /// Returns every amount in [text], in document order, already filtered for
  /// balance-style context.
  static List<AmountMatch> extractAll(
    String text, {
    String defaultCurrency = 'CAD',
  }) {
    final explicit = _collect(_explicit, text, defaultCurrency);
    if (explicit.isNotEmpty) return explicit;
    return _collect(_bareDecimal, text, defaultCurrency);
  }

  /// Returns the amount most likely to be the transaction value, or null.
  static Money? extract(String text, {String defaultCurrency = 'CAD'}) {
    final all = extractAll(text, defaultCurrency: defaultCurrency);
    return all.isEmpty ? null : all.first.money;
  }

  static List<AmountMatch> _collect(
    RegExp pattern,
    String text,
    String defaultCurrency,
  ) {
    final results = <AmountMatch>[];
    for (final m in pattern.allMatches(text)) {
      final number = m.namedGroup('num');
      if (number == null) continue;
      if (_isBalanceContext(text, m.start, m.end)) continue;

      final currency = _resolveCurrency(
        lead: _tryNamedGroup(m, 'lead'),
        trail: _tryNamedGroup(m, 'trail'),
        fallback: defaultCurrency,
      );
      final money = Money.tryParse(number, currency);
      if (money == null) continue;
      results.add(AmountMatch(money, m.start, m.end));
    }
    return results;
  }

  /// `namedGroup` throws when the group is absent from the pattern, so the two
  /// passes (which have different group sets) need a tolerant accessor.
  static String? _tryNamedGroup(RegExpMatch m, String name) {
    try {
      return m.namedGroup(name);
    } on ArgumentError {
      return null;
    }
  }

  /// True when the words around the match mark it as a balance or a limit
  /// rather than the amount of the transaction.
  static bool _isBalanceContext(String text, int start, int end) {
    const lookBehind = 34;
    const lookAhead = 26;
    final before = text.substring((start - lookBehind).clamp(0, start), start);
    final after = text.substring(end, (end + lookAhead).clamp(end, text.length));
    return _contextExclusion.hasMatch(before) ||
        _contextExclusion.hasMatch(after);
  }

  static String _resolveCurrency({
    required String? lead,
    required String? trail,
    required String fallback,
  }) {
    final trailCode = trail?.toUpperCase().trim();
    if (trailCode != null && trailCode.isNotEmpty) return trailCode;

    final leadToken = lead?.toUpperCase().trim() ?? '';
    if (leadToken.startsWith('US')) return 'USD';
    if (leadToken.startsWith('CA')) return 'CAD';
    if (leadToken.startsWith('EUR') || leadToken.startsWith('€')) return 'EUR';
    if (leadToken.startsWith('GBP') || leadToken.startsWith('£')) return 'GBP';
    return fallback.toUpperCase();
  }
}
