import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:test/test.dart';

import 'fixtures/cibc_samples.dart';

void main() {
  final parser = CibcParser();

  group('CIBC sample corpus', () {
    for (final sample in cibcSamples) {
      test(sample.label, () {
        final result = parser.parse(sample.toMessage());

        expect(
          result.eventType,
          sample.expectedType,
          reason: 'wrong event type for: ${sample.body}',
        );

        if (sample.expectedCents != null) {
          expect(result.amount, isNotNull, reason: 'expected an amount');
          expect(result.amount!.cents, sample.expectedCents);
          expect(result.amount!.currency, sample.expectedCurrency);
        }

        if (sample.expectedMerchant != null) {
          expect(result.merchantNormalized, sample.expectedMerchant);
        }

        if (sample.expectedLast4 != null) {
          expect(result.accountLast4, sample.expectedLast4);
        }

        expect(
          result.countsAsSpending,
          sample.expectsSpending,
          reason: 'spending classification wrong for: ${sample.body}',
        );
      });
    }
  });

  group('only purchases increase spending', () {
    test('every non-purchase event type is excluded', () {
      for (final type in TransactionEventType.values) {
        expect(
          type.countsAsSpending,
          type == TransactionEventType.purchase,
          reason: '$type must not count as spending',
        );
      }
    });

    test('a purchase with no amount does not book spending', () {
      final result = parser.parse(
        NotificationMessage(
          packageName: 'com.cibc.android.mobi',
          title: 'CIBC',
          body: 'A purchase was made at SHOPPERS DRUG MART.',
          postedAt: DateTime(2026, 9, 3, 10),
        ),
      );
      expect(result.eventType, TransactionEventType.purchase);
      expect(result.amount, isNull);
      expect(result.countsAsSpending, isFalse);
      expect(result.gaps, contains(ParseGap.noAmount));
    });

    test('a zero-dollar purchase does not book spending', () {
      final result = parseCibcText(r'You spent $0.00 at TEST MERCHANT.');
      expect(result.eventType, TransactionEventType.purchase);
      expect(result.countsAsSpending, isFalse);
    });

    test('refund of the same amount as a purchase is still not spending', () {
      final purchase = parseCibcText(r'You spent $45.67 at BEST BUY.');
      final refund =
          parseCibcText(r'A refund of $45.67 was credited from BEST BUY.');
      expect(purchase.countsAsSpending, isTrue);
      expect(refund.countsAsSpending, isFalse);
      expect(refund.eventType, TransactionEventType.refund);
    });
  });

  group('classification precedence', () {
    test('declined beats the purchase wording in the same sentence', () {
      final result = parseCibcText(
        r'A purchase of $89.99 at AMAZON.CA was declined.',
      );
      expect(result.eventType, TransactionEventType.declined);
    });

    test('refund beats the transaction wording in the same sentence', () {
      final result = parseCibcText(
        r'A refund transaction of $12.00 from WALMART was credited back.',
      );
      expect(result.eventType, TransactionEventType.refund);
    });

    test('card payment is not confused with a bill payment', () {
      final card = parseCibcText(
        r'Thank you for your payment of $500.00 to your CIBC Visa.',
      );
      final bill = parseCibcText(
        r'A bill payment of $142.08 to TORONTO HYDRO was made.',
      );
      expect(card.eventType, TransactionEventType.payment);
      expect(card.countsAsSpending, isFalse);
      expect(bill.eventType, TransactionEventType.purchase);
      expect(bill.countsAsSpending, isTrue);
    });

    test('e-Transfer is a transfer, not a purchase', () {
      final result = parseCibcText(
        r'You sent an INTERAC e-Transfer of $50.00 to John Smith.',
      );
      expect(result.eventType, TransactionEventType.transfer);
      expect(result.countsAsSpending, isFalse);
    });
  });

  group('amount selection', () {
    test('picks the transaction amount, not the available balance', () {
      final result = parseCibcText(
        r'A transaction of $45.67 was made at TIM HORTONS. '
        r'Your available balance is $3,204.16.',
      );
      expect(result.amount!.cents, 4567);
    });

    test('picks the transaction amount when the balance is quoted first', () {
      final result = parseCibcText(
        r'Your available balance is $3,204.16 after a transaction of $45.67 '
        'at TIM HORTONS.',
      );
      expect(result.amount!.cents, 4567);
    });

    test('does not mistake a card suffix for an amount', () {
      final result = parseCibcText(
        'A purchase was made at METRO with your CIBC card ending in 1234.',
      );
      expect(result.amount, isNull);
    });

    test('handles thousands separators', () {
      final result = parseCibcText(r'You spent $12,345.67 at A DEALERSHIP.');
      expect(result.amount!.cents, 1234567);
    });

    test('handles whole-dollar amounts', () {
      final result = parseCibcText(r'You spent $20 at ESSO.');
      expect(result.amount!.cents, 2000);
    });

    test('reads USD from a trailing code and from a US-dollar prefix', () {
      expect(
        parseCibcText(r'A purchase of $102.34 USD was made at APPLE.COM')
            .amount!
            .currency,
        'USD',
      );
      expect(
        parseCibcText(r'A purchase of US$40.00 was made at NEWEGG')
            .amount!
            .currency,
        'USD',
      );
    });

    test('defaults to CAD', () {
      expect(
        parseCibcText(r'You spent $5.00 at METRO.').amount!.currency,
        'CAD',
      );
    });

    test('falls back to a bare two-decimal amount with a trailing code', () {
      final result = parseCibcText('You spent 45.67 CAD at METRO.');
      expect(result.amount!.cents, 4567);
      expect(result.amount!.currency, 'CAD');
    });

    test('the bare fallback ignores integers, which are usually suffixes', () {
      expect(
        parseCibcText('A purchase was made at METRO on card 1234').amount,
        isNull,
      );
    });
  });

  group('ambiguous wording resolves in the safe direction', () {
    test('a payment with no stated destination is not booked as spending', () {
      // Conservative on purpose: a missed expense can be added by hand, an
      // invented one silently corrupts the month's totals.
      final result = parseCibcText(r'Your payment of $500.00 was received.');
      expect(result.eventType, TransactionEventType.payment);
      expect(result.countsAsSpending, isFalse);
    });

    test('a card payment that also says "processed" is still a payment', () {
      final result = parseCibcText(
        r'Your payment of $1,200.00 has been received and applied to your '
        'CIBC credit card ending in 9012.',
      );
      expect(result.eventType, TransactionEventType.payment);
    });

    test('a bill payment that says "processed" is still spending', () {
      final result = parseCibcText(
        r'A bill payment of $142.08 to TORONTO HYDRO was processed.',
      );
      expect(result.eventType, TransactionEventType.purchase);
      expect(result.countsAsSpending, isTrue);
    });

    test('a declined bill payment is a decline, not spending', () {
      final result = parseCibcText(
        r'A bill payment of $142.08 to TORONTO HYDRO was declined.',
      );
      expect(result.eventType, TransactionEventType.declined);
      expect(result.countsAsSpending, isFalse);
    });
  });

  group('merchant extraction', () {
    test('stops at a trailing clause', () {
      final result = parseCibcText(
        r'You spent $12.50 at STARBUCKS with your CIBC card ending in 4321.',
      );
      expect(result.merchantRaw, 'STARBUCKS');
    });

    test('keeps merchants that contain a stop-word', () {
      final result =
          parseCibcText(r'You spent $56.20 at BED BATH AND BEYOND with '
              'your CIBC card.');
      expect(result.merchantNormalized, 'BED BATH AND BEYOND');
    });

    test('skips a time and finds the merchant after it', () {
      final result = parseCibcText(
        r'A transaction of $31.45 was made on Sep 2, 2026 at 7:02 p.m. at '
        'METRO #88.',
      );
      expect(result.merchantNormalized, 'METRO');
    });

    test('strips processor prefixes and store numbers when normalising', () {
      expect(MerchantExtractor.normalize('SQ *BLUE DOOR CAFE #12'),
          'BLUE DOOR CAFE');
      expect(MerchantExtractor.normalize('LOBLAWS #456 TORONTO ON'),
          'LOBLAWS TORONTO');
    });

    test('a card payment has no merchant and that is not a gap', () {
      final result = parseCibcText(
        r'Thank you for your payment of $500.00 to your CIBC Visa ending '
        'in 1234.',
      );
      expect(result.merchantRaw, isNull);
      expect(result.gaps, isNot(contains(ParseGap.noMerchant)));
    });
  });

  group('account extraction', () {
    test('reads the last four digits', () {
      final result = parseCibcText(
        r'You spent $12.50 at STARBUCKS with your CIBC card ending in 4321.',
      );
      expect(result.accountLast4, '4321');
    });

    test('reads a masked suffix', () {
      final result =
          parseCibcText(r'You spent $12.50 at STARBUCKS on card ****4321.');
      expect(result.accountLast4, '4321');
    });

    test('reads the card product label', () {
      final result = parseCibcText(
        r'A transaction of $45.67 was made on your CIBC Dividend Visa '
        'Infinite card ending in 1234 at TIM HORTONS.',
      );
      expect(result.accountLabel, 'CIBC Dividend Visa Infinite card');
    });

    test('refuses to slice a last-4 out of a full card number', () {
      expect(
        AccountExtractor.extractLast4('card 4519 1234 5678 9012 was used'),
        isNull,
      );
    });
  });

  group('timestamp extraction', () {
    test('reads an explicit date and time', () {
      final result = parseCibcText(
        r'A transaction of $45.67 was made at TIM HORTONS on Sep 3, 2026 '
        'at 8:14 AM.',
        postedAt: DateTime(2026, 9, 3, 14, 30),
      );
      expect(result.occurredAt, DateTime(2026, 9, 3, 8, 14));
      expect(result.occurredAtIsExact, isTrue);
    });

    test('reads a p.m. time', () {
      final result = parseCibcText(
        r'A transaction of $31.45 at METRO on Sep 2, 2026 at 7:02 p.m.',
        postedAt: DateTime(2026, 9, 3, 14, 30),
      );
      expect(result.occurredAt, DateTime(2026, 9, 2, 19, 2));
    });

    test('falls back to delivery time when no date is present', () {
      final posted = DateTime(2026, 9, 3, 14, 30);
      final result =
          parseCibcText(r'You spent $5.00 at METRO.', postedAt: posted);
      expect(result.occurredAt, posted);
      expect(result.occurredAtIsExact, isFalse);
      expect(result.gaps, contains(ParseGap.noTimestamp));
    });

    test('infers the previous year for a future-looking month/day', () {
      final result = parseCibcText(
        r'You spent $5.00 at METRO on Dec 28 at 9:00 AM.',
        postedAt: DateTime(2026, 1, 4, 10),
      );
      expect(result.occurredAt.year, 2025);
      expect(result.occurredAt.month, 12);
      expect(result.occurredAt.day, 28);
    });

    test('reads an ISO date', () {
      final result = parseCibcText(
        r'You spent $5.00 at METRO on 2026-08-15.',
        postedAt: DateTime(2026, 9, 3),
      );
      expect(result.occurredAt, DateTime(2026, 8, 15));
    });

    test('does not read a month name out of a merchant', () {
      final posted = DateTime(2026, 9, 3, 14, 30);
      final result =
          parseCibcText(r'You spent $18.00 at MARSHALLS.', postedAt: posted);
      expect(result.occurredAtIsExact, isFalse);
      expect(result.occurredAt, posted);
    });
  });

  group('malformed and partial input', () {
    test('an empty notification is unknown and keeps nothing', () {
      final result = CibcParser().parse(
        NotificationMessage(
          packageName: 'com.cibc.android.mobi',
          title: '',
          body: '',
          postedAt: DateTime(2026, 9, 3),
        ),
      );
      expect(result.eventType, TransactionEventType.unknown);
      expect(result.gaps, contains(ParseGap.emptyMessage));
      expect(result.redactedRaw, isNull);
    });

    test('a truncated purchase yields a purchase with a recorded gap', () {
      final result = parseCibcText(r'A transaction of $');
      expect(result.eventType, TransactionEventType.purchase);
      expect(result.amount, isNull);
      expect(result.countsAsSpending, isFalse);
      expect(result.gaps, contains(ParseGap.noAmount));
      expect(result.isComplete, isFalse);
    });

    test('confidence is zero for unknown and high for a complete parse', () {
      expect(parseCibcText('CIBC').confidence, 0.0);
      final complete = parseCibcText(
        r'A transaction of $45.67 was made on your CIBC Dividend Visa card '
        'ending in 1234 at TIM HORTONS on Sep 3, 2026 at 8:14 AM.',
      );
      expect(complete.confidence, greaterThanOrEqualTo(0.9));
    });

    test('never throws on adversarial input', () {
      final nasty = <String>[
        '',
        '   ',
        r'$',
        r'$$$$',
        // Bidi override, built at runtime so the source file stays readable.
        'CIBC   ${String.fromCharCode(0x202E)}',
        'purchase of \$..,, at',
        'ending in ending in ending in',
        r'$1$2$3$4$5$6$7$8$9',
        'a' * 5000,
      ];
      for (final input in nasty) {
        expect(
          () => parseCibcText(input),
          returnsNormally,
          reason: 'threw on: ${input.substring(0, input.length.clamp(0, 40))}',
        );
      }
    });
  });

  group('routing', () {
    test('claims its own package', () {
      expect(
        parser.canHandle(
          NotificationMessage(
            packageName: 'com.cibc.android.mobi',
            title: 'Alert',
            body: 'anything',
            postedAt: DateTime(2026, 9, 3),
          ),
        ),
        isTrue,
      );
    });

    test('claims pasted text that mentions CIBC (debug screen path)', () {
      expect(
        parser.canHandle(
          NotificationMessage(
            packageName: '',
            title: '',
            body: r'Your CIBC card was used for $5.00',
            postedAt: DateTime(2026, 9, 3),
          ),
        ),
        isTrue,
      );
    });

    test('does not claim an unrelated notification', () {
      expect(
        parser.canHandle(
          NotificationMessage(
            packageName: 'com.whatsapp',
            title: 'Mum',
            body: 'call me',
            postedAt: DateTime(2026, 9, 3),
          ),
        ),
        isFalse,
      );
    });

    test('the registry routes CIBC notifications to the CIBC parser', () {
      final registry = ParserRegistry.standard();
      final message = NotificationMessage(
        packageName: 'com.cibc.android.mobi',
        title: 'CIBC',
        body: r'You spent $5.00 at METRO.',
        postedAt: DateTime(2026, 9, 3),
      );
      expect(registry.parserFor(message)?.bankId, 'cibc');
      expect(registry.parse(message)?.eventType, TransactionEventType.purchase);
    });

    test('the registry returns null for an unsupported bank', () {
      final registry = ParserRegistry.standard();
      expect(
        registry.parse(
          NotificationMessage(
            packageName: 'com.rbc.mobile.android',
            title: 'RBC',
            body: r'You spent $5.00 at METRO.',
            postedAt: DateTime(2026, 9, 3),
          ),
        ),
        isNull,
      );
    });
  });
}
