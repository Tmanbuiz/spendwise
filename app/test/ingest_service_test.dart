import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/models/app_transaction.dart';
import 'package:spendwise/services/ingest_service.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

/// Collects everything the pipeline stores, so tests can assert on it.
class _FakeSink implements TransactionSink {
  final List<AppTransaction> saved = <AppTransaction>[];
  List<AppTransaction> seed = <AppTransaction>[];

  @override
  Future<void> save(AppTransaction transaction) async => saved.add(transaction);

  @override
  Future<List<AppTransaction>> recent({required Duration window}) async => seed;

  /// Mirrors the real repository: everything already written counts, however
  /// long ago this process last saw it.
  @override
  Future<bool> existsNear(
    String fingerprint,
    DateTime at,
    Duration window,
  ) async {
    return <AppTransaction>[...saved, ...seed].any((t) =>
        t.fingerprint == fingerprint &&
        t.occurredAt.difference(at).abs() <= window);
  }
}

NotificationMessage cibc(String body, {DateTime? at}) => NotificationMessage(
      packageName: 'com.cibc.android.mobi',
      title: 'CIBC',
      body: body,
      postedAt: at ?? DateTime(2026, 9, 3, 8, 14),
    );

void main() {
  late _FakeSink sink;
  late IngestService service;
  var counter = 0;

  setUp(() {
    counter = 0;
    sink = _FakeSink();
    service = IngestService(
      sink: sink,
      idGenerator: () => 'id-${counter++}',
    );
  });

  const cibcOnly = <String>{'cibc'};

  group('what gets stored', () {
    test('a purchase is stored and counts as spending', () async {
      final result = await service.ingest(
        cibc(r'You spent $12.50 at STARBUCKS with your CIBC card ending '
            'in 4321.'),
        selectedBankIds: cibcOnly,
      );

      expect(result.status, IngestStatus.stored);
      expect(sink.saved, hasLength(1));
      final stored = sink.saved.single;
      expect(stored.amountCents, 1250);
      expect(stored.merchant, 'STARBUCKS');
      expect(stored.category, SpendCategory.dining);
      expect(stored.countsAsSpending, isTrue);
      expect(stored.source, TransactionSource.notification);
    });

    test('a refund is stored but does not count as spending', () async {
      final result = await service.ingest(
        cibc(r'A refund of $45.67 was credited to your CIBC card ending in '
            '1234 from BEST BUY.'),
        selectedBankIds: cibcOnly,
      );

      expect(result.status, IngestStatus.stored);
      expect(sink.saved.single.eventType, TransactionEventType.refund);
      expect(sink.saved.single.countsAsSpending, isFalse);
    });

    test('a card payment is stored but does not count as spending', () async {
      await service.ingest(
        cibc(r'Thank you for your payment of $500.00 to your CIBC Visa '
            'ending in 1234.'),
        selectedBankIds: cibcOnly,
      );

      expect(sink.saved.single.eventType, TransactionEventType.payment);
      expect(sink.saved.single.countsAsSpending, isFalse);
    });

    test('a transfer is stored but does not count as spending', () async {
      await service.ingest(
        cibc(r'You sent an INTERAC e-Transfer of $50.00 to John Smith.'),
        selectedBankIds: cibcOnly,
      );

      expect(sink.saved.single.eventType, TransactionEventType.transfer);
      expect(sink.saved.single.countsAsSpending, isFalse);
    });
  });

  group('what does not get stored', () {
    test('a decline is never written to the ledger', () async {
      final result = await service.ingest(
        cibc(r'A transaction of $89.99 at AMAZON.CA was declined.'),
        selectedBankIds: cibcOnly,
      );

      expect(result.status, IngestStatus.notRecorded);
      expect(sink.saved, isEmpty);
    });

    test('an informational message is not written', () async {
      final result = await service.ingest(
        cibc('Your CIBC Dividend Visa statement is ready.'),
        selectedBankIds: cibcOnly,
      );

      expect(result.status, IngestStatus.notRecorded);
      expect(sink.saved, isEmpty);
    });

    test('a purchase with no amount is not written', () async {
      final result = await service.ingest(
        cibc('A purchase was made at SHOPPERS DRUG MART.'),
        selectedBankIds: cibcOnly,
      );

      expect(result.status, IngestStatus.notRecorded);
      expect(sink.saved, isEmpty);
    });

    test('a bank the user did not select is never examined', () async {
      final result = await service.ingest(
        cibc(r'You spent $12.50 at STARBUCKS.'),
        selectedBankIds: const <String>{'rbc'},
      );

      expect(result.status, IngestStatus.bankNotSelected);
      expect(result.parsed, isNull);
      expect(sink.saved, isEmpty);
    });

    test('an unrelated app is ignored entirely', () async {
      final result = await service.ingest(
        NotificationMessage(
          packageName: 'com.whatsapp',
          title: 'Mum',
          body: r'can you send me $20',
          postedAt: DateTime(2026, 9, 3),
        ),
        selectedBankIds: cibcOnly,
      );

      expect(result.status, IngestStatus.bankNotSelected);
      expect(sink.saved, isEmpty);
    });
  });

  group('duplicate suppression', () {
    test('the same alert twice is stored once', () async {
      const body = r'A transaction of $45.67 was made on your CIBC card '
          'ending in 1234 at TIM HORTONS.';

      final first = await service.ingest(
        cibc(body, at: DateTime(2026, 9, 3, 8, 14)),
        selectedBankIds: cibcOnly,
      );
      final second = await service.ingest(
        cibc(body, at: DateTime(2026, 9, 3, 8, 14, 40)),
        selectedBankIds: cibcOnly,
      );

      expect(first.status, IngestStatus.stored);
      expect(second.status, IngestStatus.duplicate);
      expect(sink.saved, hasLength(1));
    });

    test('the same purchase hours later is a separate transaction', () async {
      const body = r'A transaction of $45.67 was made on your CIBC card '
          'ending in 1234 at TIM HORTONS.';

      await service.ingest(
        cibc(body, at: DateTime(2026, 9, 3, 8, 14)),
        selectedBankIds: cibcOnly,
      );
      final second = await service.ingest(
        cibc(body, at: DateTime(2026, 9, 3, 16, 40)),
        selectedBankIds: cibcOnly,
      );

      expect(second.status, IngestStatus.stored);
      expect(sink.saved, hasLength(2));
    });

    test('history is restored after a restart, so repeats stay suppressed',
        () async {
      const body = r'A transaction of $45.67 was made on your CIBC card '
          'ending in 1234 at TIM HORTONS.';

      // Simulate the app having already stored this before restarting.
      final earlier = await service.ingest(
        cibc(body, at: DateTime(2026, 9, 3, 8, 14)),
        selectedBankIds: cibcOnly,
      );

      final restarted = IngestService(
        sink: sink..seed = <AppTransaction>[earlier.transaction!],
        idGenerator: () => 'id-restart',
      );
      await restarted.warmUp();

      final repeat = await restarted.ingest(
        cibc(body, at: DateTime(2026, 9, 3, 8, 16)),
        selectedBankIds: cibcOnly,
      );
      expect(repeat.status, IngestStatus.duplicate);
    });
  });

  group('categorisation', () {
    test('user rules override built-in knowledge during ingest', () async {
      service.updateRules(<MerchantRule>[
        const MerchantRule(
          pattern: 'STARBUCKS',
          category: SpendCategory.subscriptions,
          source: RuleSource.user,
        ),
      ]);

      await service.ingest(
        cibc(r'You spent $12.50 at STARBUCKS.'),
        selectedBankIds: cibcOnly,
      );

      expect(sink.saved.single.category, SpendCategory.subscriptions);
    });

    test('an incomplete parse is flagged for review', () async {
      await service.ingest(
        cibc(r'A transaction of $18.40 was made on your CIBC card ending '
            'in 1234.'),
        selectedBankIds: cibcOnly,
      );

      expect(sink.saved.single.needsReview, isTrue);
    });

    test('a complete parse is not flagged for review', () async {
      await service.ingest(
        cibc(r'A transaction of $45.67 was made on your CIBC Dividend Visa '
            'card ending in 1234 at TIM HORTONS on Sep 3, 2026 at 8:14 AM.'),
        selectedBankIds: cibcOnly,
      );

      expect(sink.saved.single.needsReview, isFalse);
    });
  });

  group('re-reading the notification shade never duplicates', () {
    // The failure this guards against, seen on a real device: a rescan
    // replayed alerts that were hours old, the in-memory detector had been
    // seeded only from the last two hours, and the same $29 purchase was
    // stored twice — inflating the month's total by exactly that amount.
    const old = Duration(hours: 26);

    test('an alert older than the warm-up window is not stored twice',
        () async {
      final when = DateTime.now().subtract(old);
      final message = cibc(
        r'CIBC Adapta Mastercard, 2199 TEL-E-SIM.COM $29.00',
        at: when,
      );

      final first = await service.ingest(message, selectedBankIds: cibcOnly);
      expect(first.wasStored, isTrue);

      // Warm-up only looks back two hours, so this alert is invisible to it.
      await service.warmUp();

      final second = await service.ingest(message, selectedBankIds: cibcOnly);
      expect(second.status, IngestStatus.duplicate);
      expect(sink.saved, hasLength(1));
    });

    test('a fresh service with an empty detector still refuses a duplicate',
        () async {
      // Any provider rebuild hands the pipeline a brand-new detector. Storage
      // is what makes that safe.
      final when = DateTime.now().subtract(old);
      final message = cibc(
        r'CIBC Adapta Mastercard, 2199 TEL-E-SIM.COM $29.00',
        at: when,
      );

      await service.ingest(message, selectedBankIds: cibcOnly);

      final rebuilt = IngestService(
        sink: sink,
        idGenerator: () => 'rebuilt-${counter++}',
      );
      final again = await rebuilt.ingest(message, selectedBankIds: cibcOnly);

      expect(again.status, IngestStatus.duplicate);
      expect(sink.saved, hasLength(1));
    });

    test('scanning the whole shade repeatedly keeps the total stable',
        () async {
      final when = DateTime.now().subtract(old);
      final shade = <NotificationMessage>[
        cibc(r'CIBC Adapta Mastercard, 2199 SHEIN $28.51', at: when),
        cibc(r'CIBC Adapta Mastercard, 2199 TEL-E-SIM.COM $29.00', at: when),
        cibc(r'CIBC Adapta Mastercard, 2199 TEL-E-SIM.COM $250.00', at: when),
      ];

      Future<void> scan() async {
        for (final message in shade) {
          await service.ingest(message, selectedBankIds: cibcOnly);
        }
      }

      await scan();
      final afterFirst = sink.saved.length;
      final totalAfterFirst =
          sink.saved.fold<int>(0, (sum, t) => sum + t.amountCents);

      await scan();
      await scan();

      expect(sink.saved, hasLength(afterFirst));
      expect(
        sink.saved.fold<int>(0, (sum, t) => sum + t.amountCents),
        totalAfterFirst,
        reason: 'rescanning must not inflate the month total',
      );
      expect(totalAfterFirst, 30751);
    });

    test('two genuinely different purchases are both kept', () async {
      final when = DateTime.now().subtract(old);
      await service.ingest(
        cibc(r'CIBC Adapta Mastercard, 2199 TEL-E-SIM.COM $29.00', at: when),
        selectedBankIds: cibcOnly,
      );
      await service.ingest(
        cibc(r'CIBC Adapta Mastercard, 2199 TEL-E-SIM.COM $250.00', at: when),
        selectedBankIds: cibcOnly,
      );

      expect(sink.saved, hasLength(2));
    });
  });

  group('no sensitive data reaches storage', () {
    test('a full card number is never stored', () async {
      await service.ingest(
        cibc(r'A transaction of $45.67 was made on card 4519 1234 5678 9012 '
            'at TIM HORTONS.'),
        selectedBankIds: cibcOnly,
      );

      final stored = sink.saved.single;
      expect(stored.accountLast4, isNull);
      expect(stored.toJson().toString(), isNot(contains('4519')));
      expect(stored.toJson().toString(), isNot(contains('9012')));
    });
  });
}
