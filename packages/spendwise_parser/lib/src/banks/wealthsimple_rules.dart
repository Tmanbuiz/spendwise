import '../models/transaction_event_type.dart';

/// Ordered wording rules for Wealthsimple alerts.
///
/// Every pattern here was written against notifications captured from a real
/// device, not from imagination. That distinction cost a day on the CIBC
/// parser: 38 invented fixtures passed 148 tests while the app captured
/// nothing, because the real format was nothing like the guess.
abstract final class WealthsimpleRules {
  static RegExp _re(String pattern) => RegExp(pattern, caseSensitive: false);

  /// Messages that quote a dollar figure but describe no money movement.
  ///
  /// The balance alert is the reason this tier exists and is checked first:
  ///
  ///     Your chequing account balance
  ///     Heads up, you've got $3.17 left in your account.
  ///
  /// It carries an amount and the word "account". Without an explicit rule it
  /// would fall through to a generic tier and invent $3.17 of spending out of
  /// a message that reports the opposite.
  static final List<RegExp> informational = <RegExp>[
    _re(r'\bleft\s+in\s+your\s+account\b'),
    _re(r'\baccount\s+balance\b'),
    _re(r"\bheads\s+up\b[^\n]{0,40}\byou(?:'|’)?ve\s+got\b"),
    _re(r'\byour\s+(?:balance|available\s+balance)\s+is\b'),
    _re(r'\bverification\s+code\b|\bsecurity\s+code\b'),
    _re(r'\bsign[-\s]?in\s+(?:attempt|detected)\b'),
    _re(r'\bmarket\s+(?:open|close)\b'),
    _re(r'\byour\s+statement\s+is\b'),
  ];

  static final List<RegExp> declined = <RegExp>[
    _re(r'\bdeclin(?:e|ed|es)\b'),
    _re(r"\bcould(?:n(?:'|’)?t|\s+not)\s+be\s+(?:completed|processed)\b"),
    _re(r"\bwas(?:n(?:'|’)?t|\s+not)\s+approved\b"),
    _re(r'\binsufficient\s+funds\b'),
  ];

  static final List<RegExp> refund = <RegExp>[
    _re(r'\brefund(?:ed)?\b'),
    _re(r'\breversal\b|\breversed\b'),
    _re(r'\bwe\s+returned\b'),
    _re(r'\bmoney\s+back\b'),
  ];

  /// Movement between accounts, and Interac e-Transfers in either direction.
  ///
  /// Money arriving is still a transfer rather than a refund: nothing was
  /// bought, so nothing is being given back.
  static final List<RegExp> transfer = <RegExp>[
    _re(r'\binterac\b'),
    _re(r'\be-?transfer\b'),
    _re(r'\byou\s+made\s+a\s+transfer\b'),
    _re(r'\btransfer(?:red|s)?\b'),
    _re(r'\bsent\s+you\b'),
    _re(r'\bdeposited\s+the\s+funds\b'),
    _re(r'\bwe\s+moved\b'),
    _re(r'\bdirect\s+deposit\b'),
    _re(r'\badded\s+funds\b'),
  ];

  /// Real outbound spending.
  ///
  /// `You spent $29 at Tel-E-Sim.com with your prepaid card.` is the shape
  /// Wealthsimple actually sends for a card purchase.
  static final List<RegExp> purchase = <RegExp>[
    _re(r'\byou\s+spent\b'),
    _re(r'\bpurchase\b'),
    _re(r'\byou\s+were\s+charged\b|\bwas\s+charged\b'),
    _re(r'\bpaid\s+[$€£\d]'),
    _re(r'\bwithdrew\b|\bwithdrawal\b'),
  ];

  static final List<({List<RegExp> patterns, TransactionEventType type})>
      ruleChain = <({List<RegExp> patterns, TransactionEventType type})>[
    (patterns: declined, type: TransactionEventType.declined),
    (patterns: refund, type: TransactionEventType.refund),
    (patterns: transfer, type: TransactionEventType.transfer),
    (patterns: purchase, type: TransactionEventType.purchase),
  ];

  static TransactionEventType classify(String text) {
    if (text.trim().isEmpty) return TransactionEventType.unknown;

    for (final pattern in informational) {
      if (pattern.hasMatch(text)) return TransactionEventType.unknown;
    }
    for (final tier in ruleChain) {
      for (final pattern in tier.patterns) {
        if (pattern.hasMatch(text)) return tier.type;
      }
    }
    return TransactionEventType.unknown;
  }
}
