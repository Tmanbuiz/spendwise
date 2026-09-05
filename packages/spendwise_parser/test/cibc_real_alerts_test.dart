import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:test/test.dart';

/// Builds the message exactly as the Android service delivers it.
///
/// Real CIBC transaction alerts have a **null title** and a **null subText**,
/// and the visible body is truncated with an ellipsis — the full sentence is
/// only in `EXTRA_BIG_TEXT`. The service already prefers whichever of text and
/// bigText is longer, so bigText is what reaches the parser.
NotificationMessage realAlert(String bigText, {DateTime? postedAt}) {
  return NotificationMessage(
    packageName: 'com.cibc.android.mobi',
    title: '',
    body: bigText,
    postedAt: postedAt ?? DateTime(2026, 9, 4, 16, 48),
  );
}

/// Alias for readability where the multi-line body is the point.
NotificationMessage parserMessage(String body) => realAlert(body);

void main() {
  final parser = CibcParser();

  group('the multi-line body Android actually delivers', () {
    // The exact bytes from `EXTRA_TEXT` on a real device, newlines included:
    //
    //     CIBC Adapta Mastercard, 2199
    //      SHEIN
    //      $28.51
    //
    // This is what reaches the parser, because it is *longer* than
    // EXTRA_BIG_TEXT and the Android service prefers the longer of the two.
    // An earlier classifier used `[^\n]` between merchant and amount, which
    // cannot cross those breaks, so every real purchase was discarded as
    // "not a transaction" while the single-line form parsed perfectly.
    const multiline = 'CIBC Adapta Mastercard, 2199\n SHEIN\n \$28.51';

    test('is classified as a purchase', () {
      final result = parser.parse(realAlert(multiline));
      expect(
        result.eventType,
        TransactionEventType.purchase,
        reason: 'the line breaks must not defeat classification',
      );
      expect(result.countsAsSpending, isTrue);
    });

    test('reads every field across the line breaks', () {
      final result = parser.parse(realAlert(multiline));
      expect(result.amount!.cents, 2851);
      expect(result.merchantRaw, 'SHEIN');
      expect(result.merchantNormalized, 'SHEIN');
      expect(result.accountLast4, '2199');
      expect(result.accountLabel, 'CIBC Adapta Mastercard');
    });

    test('a multi-word merchant survives the line breaks', () {
      final result = parser.parse(
        parserMessage('CIBC Adapta Mastercard, 2199\n TIM HORTONS #123\n \$4.50'),
      );
      expect(result.merchantNormalized, 'TIM HORTONS');
      expect(result.amount!.cents, 450);
    });

    test('carriage returns are tolerated too', () {
      final result = parser.parse(
        parserMessage('CIBC Adapta Mastercard, 2199\r\n SHEIN\r\n \$28.51'),
      );
      expect(result.eventType, TransactionEventType.purchase);
      expect(result.amount!.cents, 2851);
    });

    test('single-line and multi-line forms agree', () {
      final single = parser.parse(
        realAlert(r'CIBC Adapta Mastercard, 2199 SHEIN $28.51'),
      );
      final multi = parser.parse(realAlert(multiline));

      expect(multi.eventType, single.eventType);
      expect(multi.amount, single.amount);
      expect(multi.merchantNormalized, single.merchantNormalized);
      expect(multi.accountLast4, single.accountLast4);
      // Same purchase either way, so the fingerprints must match — otherwise
      // the two channels would double-count.
      expect(multi.fingerprint, single.fingerprint);
    });
  });

  group("CIBC's real card alert format", () {
    // Captured verbatim from a device on 2026-09-04. Every earlier fixture in
    // this suite was written from imagination and got the shape wrong: the
    // real alert has no verb, no "at", and puts the last four digits after a
    // comma rather than after "ending in".
    const captured = r'CIBC Adapta Mastercard, 2199 SHEIN $28.51';

    test('is recognised as a purchase despite having no verb', () {
      final result = parser.parse(realAlert(captured));
      expect(result.eventType, TransactionEventType.purchase);
      expect(result.countsAsSpending, isTrue);
    });

    test('reads every field', () {
      final result = parser.parse(realAlert(captured));
      expect(result.amount!.cents, 2851);
      expect(result.amount!.currency, 'CAD');
      expect(result.merchantRaw, 'SHEIN');
      expect(result.merchantNormalized, 'SHEIN');
      expect(result.accountLast4, '2199');
      expect(result.accountLabel, 'CIBC Adapta Mastercard');
    });

    test('does not mistake the card digits for the amount', () {
      final result = parser.parse(realAlert(captured));
      expect(result.amount!.cents, isNot(219900));
      expect(result.amount!.cents, 2851);
    });

    test('is complete enough to discard the raw text', () {
      final result = parser.parse(realAlert(captured));
      expect(result.gaps, isNot(contains(ParseGap.noAmount)));
      expect(result.gaps, isNot(contains(ParseGap.noMerchant)));
      expect(result.gaps, isNot(contains(ParseGap.noAccount)));
      expect(result.rawRetention, RawRetention.discard);
    });

    test('categorises the merchant', () {
      final result = parser.parse(realAlert(captured));
      expect(
        Categorizer().categoryFor(result.merchantNormalized),
        SpendCategory.shopping,
      );
    });
  });

  group('the same template with other merchants and cards', () {
    test('multi-word merchant stays intact', () {
      final result = parser.parse(
        realAlert(r'CIBC Adapta Mastercard, 2199 TIM HORTONS #123 $4.50'),
      );
      expect(result.merchantRaw, 'TIM HORTONS #123');
      expect(result.merchantNormalized, 'TIM HORTONS');
      expect(result.amount!.cents, 450);
      expect(
        Categorizer().categoryFor(result.merchantNormalized),
        SpendCategory.dining,
      );
    });

    test('a different card product', () {
      final result = parser.parse(
        realAlert(r'CIBC Dividend Visa Infinite, 1234 LOBLAWS $87.31'),
      );
      expect(result.accountLabel, 'CIBC Dividend Visa Infinite');
      expect(result.accountLast4, '1234');
      expect(result.merchantNormalized, 'LOBLAWS');
      expect(result.amount!.cents, 8731);
    });

    test('a thousands separator', () {
      final result = parser.parse(
        realAlert(r'CIBC Adapta Mastercard, 2199 BEST BUY $1,249.99'),
      );
      expect(result.amount!.cents, 124999);
    });

    test('a whole-dollar amount', () {
      final result = parser.parse(
        realAlert(r'CIBC Adapta Mastercard, 2199 ESSO $40'),
      );
      expect(result.amount!.cents, 4000);
    });

    test('a US-dollar amount', () {
      final result = parser.parse(
        realAlert(r'CIBC Adapta Mastercard, 2199 APPLE.COM/BILL US$9.99'),
      );
      expect(result.amount!.currency, 'USD');
      expect(result.amount!.cents, 999);
    });

    test('a processor-prefixed merchant normalises', () {
      final result = parser.parse(
        realAlert(r'CIBC Adapta Mastercard, 2199 SQ *BLUE DOOR CAFE $8.75'),
      );
      expect(result.merchantNormalized, 'BLUE DOOR CAFE');
    });
  });

  group('explicit wording still wins over the terse shape', () {
    test('a decline in the same template is not spending', () {
      final result = parser.parse(realAlert(
        r'CIBC Adapta Mastercard, 2199 SHEIN $28.51 was declined',
      ));
      expect(result.eventType, TransactionEventType.declined);
      expect(result.countsAsSpending, isFalse);
    });

    test('a refund in the same template is not spending', () {
      final result = parser.parse(realAlert(
        r'A refund of $28.51 from SHEIN to CIBC Adapta Mastercard, 2199',
      ));
      expect(result.eventType, TransactionEventType.refund);
      expect(result.countsAsSpending, isFalse);
    });

    test('a card payment in the same template is not spending', () {
      final result = parser.parse(realAlert(
        r'Thank you for your payment of $500.00 to your CIBC Adapta '
        'Mastercard, 2199',
      ));
      expect(result.eventType, TransactionEventType.payment);
      expect(result.countsAsSpending, isFalse);
    });
  });

  group('other real CIBC notifications must not become transactions', () {
    test('the sign-in status notification is ignored', () {
      // Captured from the same device: an ongoing "Currently signed in"
      // notification the CIBC app keeps posted. It carries no amount, and
      // booking it would invent spending.
      final result = parser.parse(realAlert('CIBC Mobile Banking'));
      expect(result.eventType, TransactionEventType.unknown);
      expect(result.countsAsSpending, isFalse);
    });

    test('a bare card name with no amount is not a transaction', () {
      final result = parser.parse(realAlert('CIBC Adapta Mastercard, 2199'));
      expect(result.countsAsSpending, isFalse);
    });
  });

  group('duplicate suppression on the real format', () {
    test('the same alert twice is booked once', () {
      final detector = DuplicateDetector();
      const text = r'CIBC Adapta Mastercard, 2199 SHEIN $28.51';

      final first = parser.parse(
        realAlert(text, postedAt: DateTime(2026, 9, 4, 16, 48)),
      );
      final second = parser.parse(
        realAlert(text, postedAt: DateTime(2026, 9, 4, 16, 48, 40)),
      );

      expect(detector.evaluate(first).shouldStore, isTrue);
      expect(detector.evaluate(second).isDuplicate, isTrue);
    });

    test('two different merchants at the same amount are both kept', () {
      final detector = DuplicateDetector();
      final a = parser.parse(
        realAlert(r'CIBC Adapta Mastercard, 2199 SHEIN $28.51'),
      );
      final b = parser.parse(
        realAlert(r'CIBC Adapta Mastercard, 2199 AMAZON $28.51'),
      );

      expect(detector.evaluate(a).shouldStore, isTrue);
      expect(detector.evaluate(b).shouldStore, isTrue);
    });
  });
}
