import '../bank_notification_parser.dart';
import '../models/notification_message.dart';
import '../models/parsed_transaction.dart';
import '../models/raw_retention.dart';
import '../models/transaction_event_type.dart';
import '../util/account_extractor.dart';
import '../util/amount_parser.dart';
import '../util/datetime_parser.dart';
import '../util/fingerprint.dart';
import '../util/merchant_cleaner.dart';
import 'cibc_rules.dart';
import 'cibc_terse_alert.dart';

/// Parser for CIBC mobile-banking alerts.
///
/// CIBC does not use one fixed template — wording differs by card product, by
/// alert type, and between the push and in-app channels — so the engine is
/// built as independent extractors (type, amount, merchant, account, time)
/// rather than one monolithic regex. A partial match still yields a usable
/// transaction with its gaps recorded, instead of nothing at all.
class CibcParser implements BankNotificationParser {
  CibcParser();

  @override
  String get bankId => 'cibc';

  @override
  String get displayName => 'CIBC';

  @override
  Set<String> get packageNames => const <String>{
        'com.cibc.android.mobi',
        'com.cibc.mobile',
        'com.cibc.ca',
        'com.cibc.android.mobi.dev',
      };

  static final RegExp _bankMention = RegExp(
    r'\bCIBC\b|\bCanadian\s+Imperial\s+Bank\b',
    caseSensitive: false,
  );

  /// Merchant introducers, per event type. A refund arrives *from* a merchant;
  /// a purchase happens *at* one; a bill payment or e-Transfer goes *to* one.
  static final List<RegExp> _atThenTo = <RegExp>[
    RegExp(r'\bat\s+', caseSensitive: false),
    RegExp(r'\bto\s+', caseSensitive: false),
  ];
  static final List<RegExp> _fromThenAt = <RegExp>[
    RegExp(r'\bfrom\s+', caseSensitive: false),
    RegExp(r'\bat\s+', caseSensitive: false),
  ];
  static final List<RegExp> _toThenFrom = <RegExp>[
    RegExp(r'\bto\s+', caseSensitive: false),
    RegExp(r'\bfrom\s+', caseSensitive: false),
  ];

  @override
  bool canHandle(NotificationMessage message) {
    if (packageNames.contains(message.packageName)) return true;
    // The debug/test screen feeds pasted text with no package name, so fall
    // back to recognising the bank from the wording itself.
    return _bankMention.hasMatch(message.combinedText);
  }

  @override
  ParsedTransaction parse(NotificationMessage message) {
    final text = message.combinedText;

    if (text.trim().isEmpty) {
      return _unknown(message, const <ParseGap>[ParseGap.emptyMessage]);
    }

    final eventType = CibcRules.classify(text);
    if (eventType == TransactionEventType.unknown) {
      return _unknown(message, const <ParseGap>[ParseGap.notATransaction]);
    }

    final gaps = <ParseGap>[];

    // CIBC's real card alert is a fixed template with no verb and no
    // preposition to anchor on, so it is read positionally. Tried first
    // because the generic extractors cannot see a merchant in it at all.
    final terse = CibcTerseFormat.tryParse(text);

    final amount = AmountParser.extract(text);
    if (amount == null || amount.isZero) gaps.add(ParseGap.noAmount);

    final merchantRaw =
        terse?.merchantRaw ?? _extractMerchant(text, eventType);
    if (merchantRaw == null && _merchantExpected(eventType)) {
      gaps.add(ParseGap.noMerchant);
    }

    final last4 = terse?.last4 ?? AccountExtractor.extractLast4(text);
    final label =
        terse?.accountLabel ?? AccountExtractor.extractLabel(text, 'CIBC');
    if (last4 == null && label == null) gaps.add(ParseGap.noAccount);

    final timestamp = TimestampExtractor.extract(text, message.postedAt);
    if (!timestamp.isExact) gaps.add(ParseGap.noTimestamp);

    final merchantNormalized = MerchantExtractor.normalize(merchantRaw);

    final fingerprint = TransactionFingerprint.build(
      bankId: bankId,
      eventType: eventType,
      amount: amount,
      merchantNormalized: merchantNormalized,
      accountLast4: last4,
    );

    // Raw text is kept only when something is genuinely missing, and even then
    // only in redacted form for a bounded window. A clean parse drops it.
    final needsReview = amount == null ||
        (merchantRaw == null && _merchantExpected(eventType));
    final retention = needsReview
        ? RawRetention.keepRedactedForReview
        : RawRetention.discard;

    return ParsedTransaction(
      bankId: bankId,
      eventType: eventType,
      amount: amount,
      merchantRaw: merchantRaw,
      merchantNormalized: merchantNormalized,
      accountLabel: label,
      accountLast4: last4,
      occurredAt: timestamp.value,
      occurredAtIsExact: timestamp.isExact,
      fingerprint: fingerprint,
      rawRetention: retention,
      redactedRaw: retention.keepsAnything ? Redactor.redact(text) : null,
      gaps: gaps,
    );
  }

  /// A card payment names no merchant — the destination is the card itself —
  /// so a missing merchant there is expected, not a gap.
  bool _merchantExpected(TransactionEventType type) =>
      type != TransactionEventType.payment;

  String? _extractMerchant(String text, TransactionEventType type) {
    switch (type) {
      case TransactionEventType.refund:
        return MerchantExtractor.extract(text, _fromThenAt);
      case TransactionEventType.transfer:
        return MerchantExtractor.extract(text, _toThenFrom);
      case TransactionEventType.purchase:
      case TransactionEventType.declined:
        return MerchantExtractor.extract(text, _atThenTo);
      case TransactionEventType.payment:
      case TransactionEventType.unknown:
        return null;
    }
  }

  ParsedTransaction _unknown(NotificationMessage message, List<ParseGap> gaps) {
    final text = message.combinedText;
    return ParsedTransaction(
      bankId: bankId,
      eventType: TransactionEventType.unknown,
      amount: null,
      occurredAt: message.postedAt,
      occurredAtIsExact: false,
      fingerprint: TransactionFingerprint.build(
        bankId: bankId,
        eventType: TransactionEventType.unknown,
        amount: null,
        merchantNormalized: null,
        accountLast4: null,
      ),
      // Unrecognised wording is exactly the case worth sampling, so keep a
      // redacted copy long enough to extend the rules — then it expires.
      rawRetention: RawRetention.keepRedactedForReview,
      redactedRaw: text.trim().isEmpty ? null : Redactor.redact(text),
      gaps: gaps,
    );
  }
}

/// Convenience for the debug/test screen: parse a pasted string with no
/// surrounding Android metadata.
ParsedTransaction parseCibcText(String text, {DateTime? postedAt}) {
  final message = NotificationMessage(
    packageName: 'com.cibc.android.mobi',
    title: 'CIBC',
    body: text,
    postedAt: postedAt ?? DateTime.now(),
  );
  return CibcParser().parse(message);
}

