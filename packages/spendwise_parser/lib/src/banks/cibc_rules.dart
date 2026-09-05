import '../models/transaction_event_type.dart';

/// One tier of the classification chain: a set of wordings and the verdict
/// they produce.
typedef CibcRuleTier = ({List<RegExp> patterns, TransactionEventType type});

/// Wording rules for CIBC alerts, in the order they must be tested.
///
/// Order is the whole design. A single notification often contains several
/// keywords at once — "a purchase of $200.00 at CANADIAN TIRE could not be
/// completed" is a purchase *and* a decline — so the tiers are evaluated
/// most-specific first and the first match wins.
abstract final class CibcRules {
  static RegExp _re(String pattern) => RegExp(pattern, caseSensitive: false);

  /// Messages that describe no money movement, whatever else they contain.
  ///
  /// Checked before every transaction tier, so a fraud-confirmation prompt
  /// ("Did you make a $620.00 purchase at NEWEGG?") is never booked as one.
  ///
  /// Note what is deliberately absent: "your available balance is". That
  /// phrase is a *trailing clause* on many genuine purchase alerts, so making
  /// it informational would suppress real spending. A pure balance alert
  /// matches no transaction tier and falls through to unknown on its own.
  static final List<RegExp> informational = <RegExp>[
    _re(r'\byour\s+(?:e?-?statement|statement)\s+is\s+(?:ready|available)\b'),
    _re(r'\bstatement\s+is\s+now\s+available\b'),
    _re(r'\bminimum\s+payment\s+(?:of\s+[^\n]{0,20})?is\s+due\b'),
    _re(r'\bpayment\s+due\s+(?:date|on|in)\b'),
    _re(r'\byour\s+(?:security|verification|one[-\s]?time)\s+code\b'),
    _re(r'\bsign[-\s]?in\s+(?:attempt|detected)\b'),
    _re(r'\bdid\s+you\s+(?:make|try|authorize)\b'),
    _re(r'\bcredit\s+limit\s+(?:has\s+been\s+)?(?:increased|changed)\b'),
    _re(r'\bbalance\s+alert\b'),
    _re(r'\brewards?\s+(?:points|balance)\b'),
  ];

  /// Nothing moved: the card was refused.
  static final List<RegExp> declined = <RegExp>[
    _re(r'\bdeclin(?:e|ed|es)\b'),
    _re(r'\bwas\s+not\s+approved\b'),
    _re(r'\bnot\s+authorized\b'),
    _re(r'\bcould\s+not\s+be\s+(?:completed|processed|approved)\b'),
    _re(r'\bunable\s+to\s+(?:complete|process|authorize)\b'),
    _re(r'\binsufficient\s+funds\b'),
    _re(r'\brefused\b'),
    _re(r'\btransaction\s+(?:was\s+)?blocked\b'),
  ];

  /// Money coming back from a merchant.
  ///
  /// `return` is matched only in its money senses, because "returned payment
  /// fee" and "return to the app" are not refunds.
  static final List<RegExp> refund = <RegExp>[
    _re(r'\brefund(?:ed)?\b'),
    _re(r'\breturn\s+of\s+[$€£\d]'),
    _re(r'\bwas\s+returned\s+to\s+your\b'),
    _re(r'\breversal\b|\breversed\b'),
    _re(r'\bchargeback\b'),
    _re(r'\ba\s+credit\s+of\b'),
    _re(r'\bwas\s+credited\s+to\s+your\b'),
    _re(r'\bcredited\s+back\b'),
  ];

  /// Payments that ARE spending, tested before [payment] so the word
  /// "payment" alone cannot exclude them.
  ///
  /// Paying a utility or a phone bill moves money out of the user's pocket;
  /// paying down a credit card does not. Both sentences contain "payment",
  /// so the only reliable separator is which one is recognised first.
  static final List<RegExp> spendingPayment = <RegExp>[
    _re(r'\bbill\s+payment\b'),
    _re(r'\bpre-?authoriz(?:ed|ation)\s+(?:debit|payment|charge)\b'),
  ];

  /// A payment toward a credit card or line of credit.
  ///
  /// Every pattern names the *destination* as a card or credit facility, or
  /// uses wording CIBC only sends for card payments.
  static final List<RegExp> payment = <RegExp>[
    _re(r'\bthank\s+you\s+for\s+your\s+payment\b'),
    _re(r'\bpayment\b[^\n]{0,60}?\b(?:to|toward|towards)\s+your\s+'
        r'[\w\s]{0,30}?(?:visa|mastercard|credit\s+card|card|'
        r'line\s+of\s+credit)\b'),
    _re(r'\b(?:credit\s+card|visa|mastercard|line\s+of\s+credit)\s+'
        r'payment\s+(?:of|was|has)\b'),
    // Generic "payment ... received" with no stated destination. Treating it
    // as a card payment is the conservative reading: the cost of being wrong
    // is a missed expense the user can add by hand, whereas the alternative
    // (guessing "purchase") would invent spending that never happened.
    _re(r'\bpayment\b[^\n]{0,60}?\b'
        r'(?:received|posted|applied|processed)\b'),
  ];

  /// Movement between the user's own accounts, or an Interac e-Transfer.
  static final List<RegExp> transfer = <RegExp>[
    _re(r'\binterac\b'),
    _re(r'\be-?transfer\b'),
    _re(r'\btransfer(?:red|ring|s)?\b'),
    _re(r'\bmoved\s+[$€£\d]'),
    _re(r'\bbetween\s+your\s+accounts\b'),
    _re(r'\bfrom\s+your\s+[\w\s]{2,30}\s+to\s+your\s+[\w\s]{2,30}\b'),
  ];

  /// Real outbound spending.
  static final List<RegExp> purchase = <RegExp>[
    _re(r'\bpurchase\b'),
    _re(r'\byou\s+spent\b|\bwas\s+spent\b|\bspent\b'),
    _re(r'\bwithdraw(?:al|n)\b|\bcash\s+advance\b'),
    _re(r'\bwas\s+(?:made|used|charged|processed)\b'),
    _re(r'\bcharged\s+[$€£\d]'),
    _re(r'\btransaction\b'), // generic catch-all, deliberately last
    // CIBC's real card alert carries no verb at all — just the card, the last
    // four digits, the merchant and the amount. Recognising the shape is the
    // only way to classify it. It sits last so any explicit decline, refund,
    // payment or transfer wording in the same message still wins.
    //
    // Crucially this spans newlines. CIBC splits the alert across three lines
    // in `EXTRA_TEXT`:
    //
    //     CIBC Adapta Mastercard, 2199
    //      SHEIN
    //      $28.51
    //
    // An earlier version used `[^\n]` between merchant and amount, which
    // cannot cross those breaks — so every real purchase was classified as
    // "not a transaction" and silently discarded.
    _re(r'\bCIBC\b[^,\n]{0,48},\s*\d{4}\s+[\s\S]{1,60}?'
        r'(?:US\$|CA\$|[$€£])\s?\d'),
  ];

  /// The ordered chain. Earlier tiers win outright.
  static final List<CibcRuleTier> ruleChain = <CibcRuleTier>[
    (patterns: declined, type: TransactionEventType.declined),
    (patterns: refund, type: TransactionEventType.refund),
    (patterns: spendingPayment, type: TransactionEventType.purchase),
    (patterns: payment, type: TransactionEventType.payment),
    (patterns: transfer, type: TransactionEventType.transfer),
    (patterns: purchase, type: TransactionEventType.purchase),
  ];

  /// Classifies [text], returning [TransactionEventType.unknown] when the
  /// message is informational or matches nothing.
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
