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
import 'wealthsimple_rules.dart';

/// Parser for Wealthsimple alerts (Cash, Trade and Invest ship as one app).
///
/// Wealthsimple writes in prose rather than CIBC's terse card-first template,
/// so the generic anchor-based extractors work here — but the *rules* are its
/// own, because its balance alert quotes a dollar figure and would otherwise
/// be booked as spending.
class WealthsimpleParser implements BankNotificationParser {
  WealthsimpleParser();

  @override
  String get bankId => 'wealthsimple';

  @override
  String get displayName => 'Wealthsimple';

  @override
  Set<String> get packageNames => const <String>{
        'com.wealthsimple.trade',
        'com.wealthsimple.cash',
      };

  static final RegExp _bankMention =
      RegExp(r'\bWealthsimple\b', caseSensitive: false);

  /// Wealthsimple pads `EXTRA_BIG_TEXT` with runs of invisible combining
  /// characters to force the notification to expand. They carry no meaning and
  /// would otherwise end up inside a captured merchant name.
  static final RegExp _invisiblePadding =
      RegExp(r'[͏​-‍⁠﻿]+');

  static final List<RegExp> _atThenTo = <RegExp>[
    RegExp(r'\bat\s+', caseSensitive: false),
    RegExp(r'\bto\s+', caseSensitive: false),
  ];
  static final List<RegExp> _fromThenAt = <RegExp>[
    RegExp(r'\bfrom\s+', caseSensitive: false),
    RegExp(r'\bat\s+', caseSensitive: false),
  ];

  /// The Wealthsimple product a message refers to, e.g. `prepaid card`.
  static final RegExp _accountLabel = RegExp(
    r'\byour\s+((?:prepaid|cash|chequing|savings|life|trade|invest)'
    r'(?:\s+\w+){0,2}?\s*(?:card|account))\b',
    caseSensitive: false,
  );

  @override
  bool canHandle(NotificationMessage message) {
    if (packageNames.contains(message.packageName)) return true;
    return _bankMention.hasMatch(message.combinedText);
  }

  @override
  ParsedTransaction parse(NotificationMessage message) {
    final text = _clean(message.combinedText);

    if (text.trim().isEmpty) {
      return _unknown(message, const <ParseGap>[ParseGap.emptyMessage]);
    }

    final eventType = WealthsimpleRules.classify(text);
    if (eventType == TransactionEventType.unknown) {
      return _unknown(message, const <ParseGap>[ParseGap.notATransaction]);
    }

    final gaps = <ParseGap>[];

    final amount = AmountParser.extract(text);
    if (amount == null || amount.isZero) gaps.add(ParseGap.noAmount);

    final merchantRaw = _extractMerchant(text, eventType);
    if (merchantRaw == null && _merchantExpected(eventType)) {
      gaps.add(ParseGap.noMerchant);
    }

    final last4 = AccountExtractor.extractLast4(text);
    final label = _extractAccountLabel(text);
    if (last4 == null && label == null) gaps.add(ParseGap.noAccount);

    final timestamp = TimestampExtractor.extract(text, message.postedAt);
    if (!timestamp.isExact) gaps.add(ParseGap.noTimestamp);

    final merchantNormalized = MerchantExtractor.normalize(merchantRaw);

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
      fingerprint: TransactionFingerprint.build(
        bankId: bankId,
        eventType: eventType,
        amount: amount,
        merchantNormalized: merchantNormalized,
        accountLast4: last4,
      ),
      rawRetention: retention,
      redactedRaw: retention.keepsAnything ? Redactor.redact(text) : null,
      gaps: gaps,
    );
  }

  static String _clean(String input) =>
      input.replaceAll(_invisiblePadding, '').trim();

  /// A transfer names a counterparty, not a merchant, so its absence is not a
  /// gap worth flagging for review.
  bool _merchantExpected(TransactionEventType type) =>
      type == TransactionEventType.purchase ||
      type == TransactionEventType.refund ||
      type == TransactionEventType.declined;

  String? _extractMerchant(String text, TransactionEventType type) {
    switch (type) {
      case TransactionEventType.refund:
        return MerchantExtractor.extract(text, _fromThenAt);
      case TransactionEventType.purchase:
      case TransactionEventType.declined:
        return MerchantExtractor.extract(text, _atThenTo);
      case TransactionEventType.transfer:
      case TransactionEventType.payment:
      case TransactionEventType.unknown:
        return null;
    }
  }

  String? _extractAccountLabel(String text) {
    final match = _accountLabel.firstMatch(text);
    if (match == null) return null;
    final label = match.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (label == null || label.isEmpty) return null;
    return 'Wealthsimple $label';
  }

  ParsedTransaction _unknown(NotificationMessage message, List<ParseGap> gaps) {
    final text = _clean(message.combinedText);
    return ParsedTransaction(
      bankId: bankId,
      eventType: TransactionEventType.unknown,
      amount: null,
      occurredAt: message.postedAt,
      occurredAtIsExact: false,
      fingerprint: TransactionFingerprint.build(
        bankId: bankId,
        eventType: TransactionEventType.unknown,
      ),
      rawRetention: RawRetention.keepRedactedForReview,
      redactedRaw: text.isEmpty ? null : Redactor.redact(text),
      gaps: gaps,
    );
  }
}
