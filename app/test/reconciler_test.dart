import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/aggregation/aggregator_models.dart';
import 'package:spendwise/data/aggregation/reconciler.dart';
import 'package:spendwise/data/models/app_transaction.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

const reconciler = CrossSourceReconciler();
String nextId() => 'generated-id';

/// A transaction already captured from a bank notification.
AppTransaction captured({
  required int cents,
  required String merchant,
  required DateTime when,
  String? last4 = '1234',
  String? id,
  TransactionEventType type = TransactionEventType.purchase,
  SpendCategory category = SpendCategory.other,
  TransactionSource source = TransactionSource.notification,
  bool categorySetByUser = false,
  String? fingerprint,
}) {
  return AppTransaction(
    id: id ?? 'existing-$merchant-$cents',
    eventType: type,
    amountCents: cents,
    currency: 'CAD',
    occurredAt: when,
    category: category,
    source: source,
    merchant: merchant,
    merchantNormalized: MerchantExtractor.normalize(merchant),
    accountLast4: last4,
    bankId: 'cibc',
    fingerprint: fingerprint,
    categoryWasSetByUser: categorySetByUser,
  );
}

/// The same purchase as delivered later by the aggregator.
AggregatorTransaction incoming({
  required int cents,
  required String merchant,
  required DateTime date,
  String? last4 = '1234',
  TransactionEventType type = TransactionEventType.purchase,
  String providerId = 'plaid-txn-1',
  SpendCategory? category,
}) {
  return AggregatorTransaction(
    providerId: providerId,
    amountCents: cents,
    currency: 'CAD',
    date: date,
    eventType: type,
    merchant: merchant,
    accountLast4: last4,
    category: category,
  );
}

void main() {
  final tuesday = DateTime(2026, 9, 1, 12, 30);

  test('different cards veto even an otherwise exact match', () {
    final result = reconciler.reconcile(incoming(cents: 4567, merchant: 'TIM HORTONS', date: tuesday, last4: '9999'),
      [captured(cents: 4567, merchant: 'TIM HORTONS', when: tuesday)], idGenerator: nextId);
    expect(result.action, ReconcileAction.insert);
  });
  test('missing card identity stays separate for review', () {
    final result = reconciler.reconcile(incoming(cents: 4567, merchant: 'TIM HORTONS', date: tuesday, last4: null),
      [captured(cents: 4567, merchant: 'TIM HORTONS', when: tuesday)], idGenerator: nextId);
    expect(result.action, ReconcileAction.insert);
    expect(result.merged!.needsReview, isTrue);
  });
  test('two plausible purchases are not silently collapsed', () {
    final result = reconciler.reconcile(incoming(cents: 4567, merchant: 'TIM HORTONS', date: tuesday),
      [captured(cents: 4567, merchant: 'TIM HORTONS', when: tuesday, id: 'one'),
       captured(cents: 4567, merchant: 'TIM HORTONS', when: tuesday, id: 'two')], idGenerator: nextId);
    expect(result.action, ReconcileAction.insert);
    expect(result.merged!.needsReview, isTrue);
  });

  group('the same purchase from both sources is stored once', () {
    test('exact match on amount, merchant, card and date', () {
      final existing = <AppTransaction>[
        captured(cents: 4567, merchant: 'TIM HORTONS', when: tuesday),
      ];

      final result = reconciler.reconcile(
        incoming(
          cents: 4567,
          merchant: 'Tim Hortons',
          date: tuesday.add(const Duration(days: 2)),
        ),
        existing,
        idGenerator: nextId,
      );

      expect(result.action, ReconcileAction.mergeIntoExisting);
      expect(result.existing?.id, existing.first.id);
      // Crucially, the merged row keeps the ORIGINAL id — no second row.
      expect(result.merged?.id, existing.first.id);
    });

    test('a tip added at posting still matches', () {
      // The alert fired at $40.00 when the card was tapped; $48.00 posted.
      final existing = <AppTransaction>[
        captured(cents: 4000, merchant: 'THE KEG', when: tuesday),
      ];

      final result = reconciler.reconcile(
        incoming(
          cents: 4800,
          merchant: 'The Keg Steakhouse',
          date: tuesday.add(const Duration(days: 1)),
        ),
        existing,
        idGenerator: nextId,
      );

      expect(result.action, ReconcileAction.mergeIntoExisting);
      // The posted amount wins: it is what actually left the account.
      expect(result.merged?.amountCents, 4800);
    });

    test('a terminal string matches the aggregator name', () {
      final existing = <AppTransaction>[
        captured(
          cents: 875,
          merchant: 'SQ *BLUE DOOR CAFE #12',
          when: tuesday,
        ),
      ];

      final result = reconciler.reconcile(
        incoming(cents: 875, merchant: 'Blue Door Cafe', date: tuesday),
        existing,
        idGenerator: nextId,
      );

      expect(result.action, ReconcileAction.mergeIntoExisting);
    });

    test('a posted transaction several days later still matches', () {
      final existing = <AppTransaction>[
        captured(cents: 2310, merchant: 'LOBLAWS', when: tuesday),
      ];

      final result = reconciler.reconcile(
        incoming(
          cents: 2310,
          merchant: 'Loblaws',
          date: tuesday.add(const Duration(days: 4)),
        ),
        existing,
        idGenerator: nextId,
      );

      expect(result.action, ReconcileAction.mergeIntoExisting);
    });
  });

  group('genuinely different transactions are kept apart', () {
    test('beyond the date window it is a new transaction', () {
      final existing = <AppTransaction>[
        captured(cents: 4567, merchant: 'TIM HORTONS', when: tuesday),
      ];

      final result = reconciler.reconcile(
        incoming(
          cents: 4567,
          merchant: 'Tim Hortons',
          date: tuesday.add(const Duration(days: 10)),
        ),
        existing,
        idGenerator: nextId,
      );

      expect(result.action, ReconcileAction.insert);
    });

    test('a posted amount below the alert is a different purchase', () {
      // Tips push the posted amount up, never down.
      final existing = <AppTransaction>[
        captured(cents: 4000, merchant: 'THE KEG', when: tuesday),
      ];

      final result = reconciler.reconcile(
        incoming(cents: 1500, merchant: 'The Keg', date: tuesday),
        existing,
        idGenerator: nextId,
      );

      expect(result.action, ReconcileAction.insert);
    });

    test('a wildly different amount does not match', () {
      final existing = <AppTransaction>[
        captured(cents: 4000, merchant: 'THE KEG', when: tuesday),
      ];

      final result = reconciler.reconcile(
        incoming(cents: 40000, merchant: 'The Keg', date: tuesday),
        existing,
        idGenerator: nextId,
      );

      expect(result.action, ReconcileAction.insert);
    });

    test('a different merchant does not match', () {
      final existing = <AppTransaction>[
        captured(cents: 4567, merchant: 'TIM HORTONS', when: tuesday),
      ];

      final result = reconciler.reconcile(
        incoming(cents: 4567, merchant: 'STARBUCKS', date: tuesday),
        existing,
        idGenerator: nextId,
      );

      expect(result.action, ReconcileAction.insert);
    });

    test('a different card does not match', () {
      final existing = <AppTransaction>[
        captured(
          cents: 4567,
          merchant: 'TIM HORTONS',
          when: tuesday,
          last4: '1234',
        ),
      ];

      final result = reconciler.reconcile(
        incoming(
          cents: 4567,
          merchant: 'Timmies Coffee Shop',
          date: tuesday,
          last4: '9999',
        ),
        existing,
        idGenerator: nextId,
      );

      expect(result.action, ReconcileAction.insert);
    });

    test('a refund does not merge into the matching purchase', () {
      final existing = <AppTransaction>[
        captured(cents: 4567, merchant: 'BEST BUY', when: tuesday),
      ];

      final result = reconciler.reconcile(
        incoming(
          cents: 4567,
          merchant: 'Best Buy',
          date: tuesday.add(const Duration(days: 1)),
          type: TransactionEventType.refund,
        ),
        existing,
        idGenerator: nextId,
      );

      expect(result.action, ReconcileAction.insert);
      expect(result.merged?.eventType, TransactionEventType.refund);
      expect(result.merged?.countsAsSpending, isFalse);
    });

    test('a manually entered transaction is never absorbed', () {
      // The user's own record is deliberate and must not vanish into a merge.
      final existing = <AppTransaction>[
        captured(
          cents: 4567,
          merchant: 'TIM HORTONS',
          when: tuesday,
          source: TransactionSource.manual,
        ),
      ];

      final result = reconciler.reconcile(
        incoming(cents: 4567, merchant: 'Tim Hortons', date: tuesday),
        existing,
        idGenerator: nextId,
      );

      expect(result.action, ReconcileAction.insert);
    });
  });

  group('re-syncing is idempotent', () {
    test('the same aggregator record updates rather than duplicates', () {
      final first = reconciler.reconcile(
        incoming(cents: 4567, merchant: 'Tim Hortons', date: tuesday),
        const <AppTransaction>[],
        idGenerator: nextId,
      );
      expect(first.action, ReconcileAction.insert);

      final second = reconciler.reconcile(
        incoming(cents: 4567, merchant: 'Tim Hortons', date: tuesday),
        <AppTransaction>[first.merged!],
        idGenerator: nextId,
      );

      expect(second.action, ReconcileAction.updateExisting);
      expect(second.merged?.id, first.merged?.id);
    });

    test('a pending amount that changes updates the same row', () {
      final first = reconciler.reconcile(
        incoming(cents: 4000, merchant: 'The Keg', date: tuesday),
        const <AppTransaction>[],
        idGenerator: nextId,
      );

      final second = reconciler.reconcile(
        incoming(cents: 4800, merchant: 'The Keg', date: tuesday),
        <AppTransaction>[first.merged!],
        idGenerator: nextId,
      );

      expect(second.action, ReconcileAction.updateExisting);
      expect(second.merged?.amountCents, 4800);
    });

    test('running a whole sync twice does not double any total', () {
      final batch = <AggregatorTransaction>[
        incoming(
          cents: 4567,
          merchant: 'Tim Hortons',
          date: tuesday,
          providerId: 'a',
        ),
        incoming(
          cents: 2310,
          merchant: 'Loblaws',
          date: tuesday,
          providerId: 'b',
        ),
        incoming(
          cents: 875,
          merchant: 'Blue Door Cafe',
          date: tuesday,
          providerId: 'c',
        ),
      ];

      var stored = <AppTransaction>[];
      var counter = 0;

      void runSync() {
        for (final txn in batch) {
          final result = reconciler.reconcile(
            txn,
            stored,
            idGenerator: () => 'id-${counter++}',
          );
          final merged = result.merged;
          if (merged == null) continue;
          stored = <AppTransaction>[
            ...stored.where((t) => t.id != merged.id),
            merged,
          ];
        }
      }

      runSync();
      final afterFirst = stored.length;
      final totalAfterFirst =
          stored.fold<int>(0, (sum, t) => sum + t.amountCents);

      runSync();
      runSync();

      expect(stored.length, afterFirst);
      expect(stored.fold<int>(0, (sum, t) => sum + t.amountCents),
          totalAfterFirst);
    });
  });

  group('declines and unknowns are not recorded', () {
    test('a declined transaction is skipped', () {
      final result = reconciler.reconcile(
        incoming(
          cents: 8999,
          merchant: 'Amazon',
          date: tuesday,
          type: TransactionEventType.declined,
        ),
        const <AppTransaction>[],
        idGenerator: nextId,
      );

      expect(result.action, ReconcileAction.skip);
      expect(result.writes, isFalse);
    });

    test('an unknown event type is skipped', () {
      final result = reconciler.reconcile(
        incoming(
          cents: 100,
          merchant: 'Mystery',
          date: tuesday,
          type: TransactionEventType.unknown,
        ),
        const <AppTransaction>[],
        idGenerator: nextId,
      );

      expect(result.action, ReconcileAction.skip);
    });
  });

  group('categorisation on merge', () {
    test('a user-set category survives the merge', () {
      final existing = <AppTransaction>[
        captured(
          cents: 4567,
          merchant: 'TIM HORTONS',
          when: tuesday,
          category: SpendCategory.entertainment,
          categorySetByUser: true,
        ),
      ];

      final result = reconciler.reconcile(
        incoming(
          cents: 4567,
          merchant: 'Tim Hortons',
          date: tuesday,
          category: SpendCategory.dining,
        ),
        existing,
        idGenerator: nextId,
        categorizer: Categorizer(),
      );

      expect(result.action, ReconcileAction.mergeIntoExisting);
      expect(result.merged?.category, SpendCategory.entertainment);
    });

    test("SpendWise's own rules beat the aggregator's category", () {
      final result = reconciler.reconcile(
        incoming(
          cents: 4567,
          merchant: 'Tim Hortons',
          date: tuesday,
          category: SpendCategory.shopping,
        ),
        const <AppTransaction>[],
        idGenerator: nextId,
        categorizer: Categorizer(),
      );

      expect(result.merged?.category, SpendCategory.dining);
    });

    test("the aggregator's category is used when we have no opinion", () {
      final result = reconciler.reconcile(
        incoming(
          cents: 4567,
          merchant: 'Obscure Local Shop',
          date: tuesday,
          category: SpendCategory.shopping,
        ),
        const <AppTransaction>[],
        idGenerator: nextId,
        categorizer: Categorizer(),
      );

      expect(result.merged?.category, SpendCategory.shopping);
    });

    test('a user merchant rule beats everything', () {
      final result = reconciler.reconcile(
        incoming(
          cents: 4567,
          merchant: 'Tim Hortons',
          date: tuesday,
          category: SpendCategory.shopping,
        ),
        const <AppTransaction>[],
        idGenerator: nextId,
        categorizer: Categorizer(userRules: <MerchantRule>[
          const MerchantRule(
            pattern: 'TIM HORTONS',
            category: SpendCategory.groceries,
            source: RuleSource.user,
          ),
        ]),
      );

      expect(result.merged?.category, SpendCategory.groceries);
    });
  });

  group('merged rows are authoritative', () {
    test('the posted date and merchant replace the alert version', () {
      final posted = tuesday.add(const Duration(days: 2));
      final existing = <AppTransaction>[
        captured(cents: 4567, merchant: 'SQ *TIM HORTONS #9', when: tuesday),
      ];

      final result = reconciler.reconcile(
        incoming(cents: 4567, merchant: 'Tim Hortons', date: posted),
        existing,
        idGenerator: nextId,
      );

      expect(result.merged?.occurredAt, posted);
      expect(result.merged?.merchant, 'Tim Hortons');
    });

    test('merging clears the needs-review flag', () {
      final existing = <AppTransaction>[
        AppTransaction(
          id: 'x',
          eventType: TransactionEventType.purchase,
          amountCents: 1840,
          currency: 'CAD',
          occurredAt: tuesday,
          category: SpendCategory.other,
          source: TransactionSource.notification,
          merchant: 'TIM HORTONS',
          merchantNormalized: 'TIM HORTONS',
          accountLast4: '1234',
          needsReview: true,
        ),
      ];

      final result = reconciler.reconcile(
        incoming(cents: 1840, merchant: 'Tim Hortons', date: tuesday),
        existing,
        idGenerator: nextId,
      );

      expect(result.merged?.needsReview, isFalse);
    });

    test('an aggregator-sourced row is labelled as such', () {
      final result = reconciler.reconcile(
        incoming(cents: 4567, merchant: 'Tim Hortons', date: tuesday),
        const <AppTransaction>[],
        idGenerator: nextId,
      );

      expect(result.merged?.source, TransactionSource.aggregator);
    });
  });
}
