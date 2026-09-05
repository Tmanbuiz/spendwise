import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:test/test.dart';

/// Builds the message as the Android service delivers it, title included —
/// Wealthsimple puts the merchant in the title for card purchases.
NotificationMessage wsAlert({
  required String title,
  required String body,
  DateTime? postedAt,
}) {
  return NotificationMessage(
    packageName: 'com.wealthsimple.trade',
    title: title,
    body: body,
    postedAt: postedAt ?? DateTime(2026, 9, 5, 12, 30),
  );
}

void main() {
  final parser = WealthsimpleParser();

  // Every string below was captured verbatim from a real device on
  // 2026-09-05 via `dumpsys notification`.
  group('real card purchase', () {
    final message = wsAlert(
      title: 'Tel-E-Sim.com ',
      body: r'You spent $29 at Tel-E-Sim.com with your prepaid card.',
    );

    test('is a purchase and counts as spending', () {
      final result = parser.parse(message);
      expect(result.eventType, TransactionEventType.purchase);
      expect(result.countsAsSpending, isTrue);
    });

    test('reads the amount, including a whole-dollar figure', () {
      expect(parser.parse(message).amount!.cents, 2900);
      expect(parser.parse(message).amount!.currency, 'CAD');
    });

    test('reads the merchant and stops before the card clause', () {
      final result = parser.parse(message);
      expect(result.merchantRaw, 'Tel-E-Sim.com');
      expect(result.merchantNormalized, 'TEL E SIM COM');
    });

    test('names the account product', () {
      expect(parser.parse(message).accountLabel, 'Wealthsimple prepaid card');
    });
  });

  group('real balance alert', () {
    // The dangerous one: it quotes $3.17 while reporting the opposite of
    // spending. Booking it would invent an expense from a low-balance warning.
    final message = wsAlert(
      title: 'Your chequing account balance',
      body: 'Heads up, you’ve got \$3.17 left in your account.',
    );

    test('is not a transaction', () {
      final result = parser.parse(message);
      expect(result.eventType, TransactionEventType.unknown);
      expect(result.countsAsSpending, isFalse);
    });

    test('does not book the balance as spending', () {
      expect(parser.parse(message).amount, isNull);
    });

    test('a straight-apostrophe variant is caught too', () {
      final plain = wsAlert(
        title: 'Your chequing account balance',
        body: "Heads up, you've got \$3.17 left in your account.",
      );
      expect(parser.parse(plain).countsAsSpending, isFalse);
    });
  });

  group('real incoming e-Transfer', () {
    final message = wsAlert(
      title: 'You got an Interac e-Transfer®',
      body: 'Tolulope sunday Atoyeje sent you \$10.00. We deposited the '
          'funds into your 🎉 Life account.',
    );

    test('is a transfer, not a refund and not spending', () {
      final result = parser.parse(message);
      expect(result.eventType, TransactionEventType.transfer);
      expect(result.countsAsSpending, isFalse);
    });

    test('still reads the amount for the record', () {
      expect(parser.parse(message).amount!.cents, 1000);
    });

    test('an emoji in the account name does not break parsing', () {
      expect(() => parser.parse(message), returnsNormally);
    });
  });

  group('real transfer with no amount', () {
    // Wealthsimple pads this one with runs of invisible combining characters
    // to force the notification to expand.
    final message = wsAlert(
      title: 'Wealthsimple',
      body: 'You made a transfer\n${'͏ ' * 40}',
    );

    test('is a transfer', () {
      expect(parser.parse(message).eventType, TransactionEventType.transfer);
    });

    test('books nothing, because there is no amount', () {
      final result = parser.parse(message);
      expect(result.amount, isNull);
      expect(result.countsAsSpending, isFalse);
      expect(result.gaps, contains(ParseGap.noAmount));
    });

    test('the invisible padding never lands in a captured field', () {
      final result = parser.parse(message);
      expect(result.merchantRaw ?? '', isNot(contains('͏')));
      expect(result.redactedRaw ?? '', isNot(contains('͏')));
    });
  });

  group('a second batch captured from the same device', () {
    // Pulled later the same day. Same templates, larger amounts — which is
    // exactly what a format check needs: confirmation the shape holds rather
    // than a single lucky sample.
    test('a three-figure whole-dollar purchase reads correctly', () {
      final result = parser.parse(wsAlert(
        title: 'Tel-E-Sim.com ',
        body: r'You spent $250 at Tel-E-Sim.com with your prepaid card.',
      ));

      expect(result.eventType, TransactionEventType.purchase);
      expect(result.amount!.cents, 25000);
      expect(result.merchantNormalized, 'TEL E SIM COM');
      expect(result.countsAsSpending, isTrue);
    });

    test('a larger incoming e-Transfer is still not spending', () {
      final result = parser.parse(wsAlert(
        title: 'You got an Interac e-Transfer®',
        body: 'Tolulope sunday Atoyeje sent you \$250.00. We deposited the '
            'funds into your 🎉 Life account.',
      ));

      expect(result.eventType, TransactionEventType.transfer);
      expect(result.amount!.cents, 25000);
      expect(result.countsAsSpending, isFalse);
    });

    test('an equal purchase and transfer never collide', () {
      // Same amount, same day, same bank. Only the event type differs, and
      // that alone must keep them apart — otherwise receiving money would
      // suppress an equal purchase.
      final purchase = parser.parse(wsAlert(
        title: 'Tel-E-Sim.com ',
        body: r'You spent $250 at Tel-E-Sim.com with your prepaid card.',
      ));
      final transfer = parser.parse(wsAlert(
        title: 'You got an Interac e-Transfer®',
        body: r'Tolulope sunday Atoyeje sent you $250.00.',
      ));

      expect(purchase.fingerprint, isNot(transfer.fingerprint));

      final detector = DuplicateDetector();
      expect(detector.evaluate(purchase).shouldStore, isTrue);
      expect(detector.evaluate(transfer).shouldStore, isTrue);
    });

    test('two different amounts at the same merchant are both kept', () {
      // $29 and $250 at Tel-E-Sim.com both appeared on the device. Wealthsimple
      // gives no card digits, so amount and merchant carry the whole identity —
      // if that were too coarse, one of these would vanish.
      final detector = DuplicateDetector();
      final small = parser.parse(wsAlert(
        title: 'Tel-E-Sim.com ',
        body: r'You spent $29 at Tel-E-Sim.com with your prepaid card.',
      ));
      final large = parser.parse(wsAlert(
        title: 'Tel-E-Sim.com ',
        body: r'You spent $250 at Tel-E-Sim.com with your prepaid card.',
      ));

      expect(small.fingerprint, isNot(large.fingerprint));
      expect(detector.evaluate(small).shouldStore, isTrue);
      expect(detector.evaluate(large).shouldStore, isTrue);
    });

    test('the same purchase repeated is still suppressed', () {
      final detector = DuplicateDetector();
      NotificationMessage same() => wsAlert(
            title: 'Tel-E-Sim.com ',
            body: r'You spent $250 at Tel-E-Sim.com with your prepaid card.',
          );

      expect(detector.evaluate(parser.parse(same())).shouldStore, isTrue);
      expect(detector.evaluate(parser.parse(same())).isDuplicate, isTrue);
    });

    test('all five captured alerts classify correctly together', () {
      final captured = <({String title, String body, bool spends})>[
        (
          title: 'Tel-E-Sim.com ',
          body: r'You spent $250 at Tel-E-Sim.com with your prepaid card.',
          spends: true,
        ),
        (
          title: 'Tel-E-Sim.com ',
          body: r'You spent $29 at Tel-E-Sim.com with your prepaid card.',
          spends: true,
        ),
        (
          title: 'You got an Interac e-Transfer®',
          body: 'Tolulope sunday Atoyeje sent you \$250.00. We deposited the '
              'funds into your 🎉 Life account.',
          spends: false,
        ),
        (
          title: 'You got an Interac e-Transfer®',
          body: 'Tolulope sunday Atoyeje sent you \$10.00. We deposited the '
              'funds into your 🎉 Life account.',
          spends: false,
        ),
        (
          title: 'Your chequing account balance',
          body: 'Heads up, you’ve got \$3.17 left in your account.',
          spends: false,
        ),
      ];

      var spendingTotal = 0;
      for (final alert in captured) {
        final result =
            parser.parse(wsAlert(title: alert.title, body: alert.body));
        expect(
          result.countsAsSpending,
          alert.spends,
          reason: 'wrong for: ${alert.body}',
        );
        if (result.countsAsSpending) {
          spendingTotal += result.amount!.cents;
        }
      }

      // Only the two purchases count: $250 + $29. The $250 transfer, the $10
      // transfer and the $3.17 balance must contribute nothing.
      expect(spendingTotal, 27900);
    });
  });

  group('routing', () {
    test('the registry sends Wealthsimple alerts to its own parser', () {
      final registry = ParserRegistry.standard();
      final message = wsAlert(
        title: 'Tel-E-Sim.com ',
        body: r'You spent $29 at Tel-E-Sim.com with your prepaid card.',
      );

      expect(registry.parserFor(message)?.bankId, 'wealthsimple');
      expect(registry.parse(message)?.countsAsSpending, isTrue);
    });

    test('CIBC alerts still route to the CIBC parser', () {
      final registry = ParserRegistry.standard();
      final message = NotificationMessage(
        packageName: 'com.cibc.android.mobi',
        title: '',
        body: r'CIBC Adapta Mastercard, 2199 SHEIN $28.51',
        postedAt: DateTime(2026, 9, 4, 16, 48),
      );

      expect(registry.parserFor(message)?.bankId, 'cibc');
      expect(registry.parse(message)?.merchantNormalized, 'SHEIN');
    });

    test('an unrelated app is claimed by neither parser', () {
      final registry = ParserRegistry.standard();
      expect(
        registry.parse(NotificationMessage(
          packageName: 'com.whatsapp',
          title: 'Mum',
          body: r'I sent you $20',
          postedAt: DateTime(2026, 9, 5),
        )),
        isNull,
      );
    });
  });

  group('categorisation and duplicates', () {
    test('the purchase categorises', () {
      final parsed = parser.parse(wsAlert(
        title: 'Tim Hortons',
        body: r'You spent $4.50 at TIM HORTONS with your prepaid card.',
      ));
      expect(
        Categorizer().categoryFor(parsed.merchantNormalized),
        SpendCategory.dining,
      );
    });

    test('the same alert twice is booked once', () {
      final detector = DuplicateDetector();
      final message = wsAlert(
        title: 'Tel-E-Sim.com ',
        body: r'You spent $29 at Tel-E-Sim.com with your prepaid card.',
      );

      expect(detector.evaluate(parser.parse(message)).shouldStore, isTrue);
      expect(detector.evaluate(parser.parse(message)).isDuplicate, isTrue);
    });

    test('a Wealthsimple purchase never collides with a CIBC one', () {
      // Same amount and merchant on two different banks must stay distinct.
      final ws = parser.parse(wsAlert(
        title: 'SHEIN',
        body: r'You spent $28.51 at SHEIN with your prepaid card.',
      ));
      final cibc = CibcParser().parse(NotificationMessage(
        packageName: 'com.cibc.android.mobi',
        title: '',
        body: r'CIBC Adapta Mastercard, 2199 SHEIN $28.51',
        postedAt: DateTime(2026, 9, 5, 12, 30),
      ));

      expect(ws.fingerprint, isNot(cibc.fingerprint));
    });
  });

  group('adversarial input', () {
    test('never throws', () {
      const nasty = <String>[
        '',
        '   ',
        r'$',
        'You spent at',
        'Heads up',
        r'You spent $$$ at',
      ];
      for (final body in nasty) {
        expect(
          () => parser.parse(wsAlert(title: 'Wealthsimple', body: body)),
          returnsNormally,
          reason: 'threw on: $body',
        );
      }
    });
  });
}
