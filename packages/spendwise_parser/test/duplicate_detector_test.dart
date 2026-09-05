import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:test/test.dart';

/// Builds a parsed CIBC purchase at a chosen delivery time.
ParsedTransaction purchaseAt(DateTime at, {String body = ''}) {
  return CibcParser().parse(
    NotificationMessage(
      packageName: 'com.cibc.android.mobi',
      title: 'CIBC',
      body: body.isEmpty
          ? r'A transaction of $45.67 was made on your CIBC card ending in '
              '1234 at TIM HORTONS.'
          : body,
      postedAt: at,
    ),
  );
}

void main() {
  group('duplicate detection', () {
    test('the same alert delivered twice is booked once', () {
      final detector = DuplicateDetector();
      final first = purchaseAt(DateTime(2026, 9, 3, 8, 14));
      final second = purchaseAt(DateTime(2026, 9, 3, 8, 14, 30));

      expect(detector.evaluate(first).shouldStore, isTrue);
      final verdict = detector.evaluate(second);
      expect(verdict.isDuplicate, isTrue);
      expect(verdict.matchedFingerprint, first.fingerprint);
    });

    test('duplicates are caught across a minute boundary', () {
      final detector = DuplicateDetector();
      detector.evaluate(purchaseAt(DateTime(2026, 9, 3, 8, 14, 59)));
      expect(
        detector.isDuplicate(purchaseAt(DateTime(2026, 9, 3, 8, 15, 2))),
        isTrue,
      );
    });

    test('the same purchase later in the day is a separate transaction', () {
      final detector = DuplicateDetector();
      detector.evaluate(purchaseAt(DateTime(2026, 9, 3, 8, 14)));
      expect(
        detector.evaluate(purchaseAt(DateTime(2026, 9, 3, 16, 40))).shouldStore,
        isTrue,
      );
    });

    test('a different amount at the same merchant is not a duplicate', () {
      final detector = DuplicateDetector();
      detector.evaluate(purchaseAt(DateTime(2026, 9, 3, 8, 14)));
      final other = purchaseAt(
        DateTime(2026, 9, 3, 8, 15),
        body: r'A transaction of $9.99 was made on your CIBC card ending in '
            '1234 at TIM HORTONS.',
      );
      expect(detector.evaluate(other).shouldStore, isTrue);
    });

    test('the same amount at a different merchant is not a duplicate', () {
      final detector = DuplicateDetector();
      detector.evaluate(purchaseAt(DateTime(2026, 9, 3, 8, 14)));
      final other = purchaseAt(
        DateTime(2026, 9, 3, 8, 15),
        body: r'A transaction of $45.67 was made on your CIBC card ending in '
            '1234 at METRO.',
      );
      expect(detector.evaluate(other).shouldStore, isTrue);
    });

    test('the same purchase on a different card is not a duplicate', () {
      final detector = DuplicateDetector();
      detector.evaluate(purchaseAt(DateTime(2026, 9, 3, 8, 14)));
      final other = purchaseAt(
        DateTime(2026, 9, 3, 8, 15),
        body: r'A transaction of $45.67 was made on your CIBC card ending in '
            '9999 at TIM HORTONS.',
      );
      expect(detector.evaluate(other).shouldStore, isTrue);
    });

    test('a refund is never a duplicate of the matching purchase', () {
      final detector = DuplicateDetector();
      detector.evaluate(purchaseAt(DateTime(2026, 9, 3, 8, 14)));
      final refund = CibcParser().parse(
        NotificationMessage(
          packageName: 'com.cibc.android.mobi',
          title: 'CIBC',
          body: r'A refund of $45.67 was credited to your CIBC card ending in '
              '1234 from TIM HORTONS.',
          postedAt: DateTime(2026, 9, 3, 8, 15),
        ),
      );
      expect(detector.evaluate(refund).shouldStore, isTrue);
    });

    test('declined events are never stored or deduplicated', () {
      final detector = DuplicateDetector();
      final declined = CibcParser().parse(
        NotificationMessage(
          packageName: 'com.cibc.android.mobi',
          title: 'CIBC',
          body: r'A transaction of $89.99 at AMAZON.CA was declined.',
          postedAt: DateTime(2026, 9, 3, 8, 14),
        ),
      );
      final decision = detector.evaluate(declined);
      expect(decision.verdict, DuplicateVerdict.notBookable);
      expect(decision.shouldStore, isFalse);
      expect(detector.trackedCount, 0);
    });

    test('unparseable notifications are not stored', () {
      final detector = DuplicateDetector();
      final unknown = CibcParser().parse(
        NotificationMessage(
          packageName: 'com.cibc.android.mobi',
          title: 'CIBC',
          body: 'Your CIBC statement is ready.',
          postedAt: DateTime(2026, 9, 3, 8, 14),
        ),
      );
      expect(detector.evaluate(unknown).verdict, DuplicateVerdict.notBookable);
    });

    test('a seeded history suppresses a repeat after a restart', () {
      final original = purchaseAt(DateTime(2026, 9, 3, 8, 14));
      final detector = DuplicateDetector(seed: <ParsedTransaction>[original]);
      expect(
        detector.isDuplicate(purchaseAt(DateTime(2026, 9, 3, 8, 16))),
        isTrue,
      );
    });

    test('old entries are purged so memory stays bounded', () {
      final detector = DuplicateDetector();
      for (var i = 0; i < 50; i++) {
        detector.evaluate(purchaseAt(DateTime(2026, 9, 3, 8).add(
          Duration(hours: i),
        )));
      }
      expect(detector.trackedCount, lessThan(5));
    });
  });

  group('fingerprint', () {
    test('is stable for identical content', () {
      final a = purchaseAt(DateTime(2026, 9, 3, 8, 14));
      final b = purchaseAt(DateTime(2026, 9, 4, 19, 2));
      expect(a.fingerprint, b.fingerprint);
    });

    test('is 16 hex characters', () {
      expect(
        purchaseAt(DateTime(2026, 9, 3)).fingerprint,
        matches(RegExp(r'^[0-9a-f]{16}$')),
      );
    });

    test('differs when any identity field differs', () {
      final base = TransactionFingerprint.build(
        bankId: 'cibc',
        eventType: TransactionEventType.purchase,
        amount: const Money(4567, 'CAD'),
        merchantNormalized: 'TIM HORTONS',
        accountLast4: '1234',
      );
      final variants = <String>[
        TransactionFingerprint.build(
          bankId: 'rbc',
          eventType: TransactionEventType.purchase,
          amount: const Money(4567, 'CAD'),
          merchantNormalized: 'TIM HORTONS',
          accountLast4: '1234',
        ),
        TransactionFingerprint.build(
          bankId: 'cibc',
          eventType: TransactionEventType.refund,
          amount: const Money(4567, 'CAD'),
          merchantNormalized: 'TIM HORTONS',
          accountLast4: '1234',
        ),
        TransactionFingerprint.build(
          bankId: 'cibc',
          eventType: TransactionEventType.purchase,
          amount: const Money(4567, 'USD'),
          merchantNormalized: 'TIM HORTONS',
          accountLast4: '1234',
        ),
        TransactionFingerprint.build(
          bankId: 'cibc',
          eventType: TransactionEventType.purchase,
          amount: const Money(4568, 'CAD'),
          merchantNormalized: 'TIM HORTONS',
          accountLast4: '1234',
        ),
        TransactionFingerprint.build(
          bankId: 'cibc',
          eventType: TransactionEventType.purchase,
          amount: const Money(4567, 'CAD'),
          merchantNormalized: 'METRO',
          accountLast4: '1234',
        ),
        TransactionFingerprint.build(
          bankId: 'cibc',
          eventType: TransactionEventType.purchase,
          amount: const Money(4567, 'CAD'),
          merchantNormalized: 'TIM HORTONS',
          accountLast4: '9999',
        ),
      ];
      for (final variant in variants) {
        expect(variant, isNot(base));
      }
    });

    test('store-number noise does not split one merchant in two', () {
      final a = purchaseAt(
        DateTime(2026, 9, 3, 8, 14),
        body: r'You spent $8.75 at SQ *BLUE DOOR CAFE #12 with your CIBC card '
            'ending in 1111.',
      );
      final b = purchaseAt(
        DateTime(2026, 9, 3, 8, 15),
        body: r'You spent $8.75 at BLUE DOOR CAFE with your CIBC card '
            'ending in 1111.',
      );
      expect(a.fingerprint, b.fingerprint);
    });
  });
}
