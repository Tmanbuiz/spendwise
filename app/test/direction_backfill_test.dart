import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/aggregation/aggregator_models.dart';
import 'package:spendwise/data/aggregation/reconciler.dart';
import 'package:spendwise/data/models/app_transaction.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

const reconciler = CrossSourceReconciler();

/// A row stored before direction was recorded at all.
AppTransaction stored({
  required int cents,
  required String merchant,
  required DateTime when,
  String? fingerprint,
}) {
  return AppTransaction(
    id: 'old-row',
    eventType: TransactionEventType.transfer,
    amountCents: cents,
    currency: 'CAD',
    occurredAt: when,
    category: SpendCategory.other,
    source: TransactionSource.statement,
    merchant: merchant,
    merchantNormalized: MerchantExtractor.normalize(merchant),
    fingerprint: fingerprint,
  );
}

void main() {
  final day = DateTime(2026, 8, 14, 12);

  // Re-importing a statement is the only way to settle an e-Transfer that was
  // received rather than sent: nothing in the wording distinguishes the two,
  // and only the running balance knows.
  group('re-importing a statement repairs rows that never knew', () {
    test('an incoming direction is written onto the existing row', () {
      // A row imported from a statement carries the importer's own
      // fingerprint, which is what lets a re-import find it again.
      final existing = <AppTransaction>[
        stored(
          cents: 25000,
          merchant: 'E-TRANSFER 011741126957 Tolulope Sunday Atoyeje',
          when: day,
          fingerprint: 'agg:stmt:2026-08-14:25000:E-TRANSFER',
        ),
      ];
      expect(existing.single.direction, TransactionDirection.outbound);

      final result = reconciler.reconcile(
        AggregatorTransaction(
          providerId: 'stmt:2026-08-14:25000:E-TRANSFER',
          amountCents: 25000,
          currency: 'CAD',
          date: day,
          eventType: TransactionEventType.transfer,
          merchant: 'E-TRANSFER 011741126957 Tolulope Sunday Atoyeje',
          recordedDirection: TransactionDirection.inbound,
        ),
        existing,
        idGenerator: () => 'new-id',
      );

      expect(result.action, ReconcileAction.updateExisting);
      // The same row, not a second one.
      expect(result.merged?.id, 'old-row');
      expect(result.merged?.direction, TransactionDirection.inbound);
      expect(result.merged?.recordedDirection, TransactionDirection.inbound);
    });

    test('a fresh row keeps the direction the statement observed', () {
      final result = reconciler.reconcile(
        AggregatorTransaction(
          providerId: 'stmt:2026-08-14:163636:PAY',
          amountCents: 163636,
          currency: 'CAD',
          date: day,
          eventType: TransactionEventType.transfer,
          merchant: 'PAY HARMONY FAMILY',
          recordedDirection: TransactionDirection.inbound,
        ),
        const <AppTransaction>[],
        idGenerator: () => 'new-id',
      );

      expect(result.action, ReconcileAction.insert);
      expect(result.merged?.direction, TransactionDirection.inbound);
    });
  });

  group('a row that was never re-imported', () {
    test('a payroll credit is read as money in from its wording', () {
      final row = stored(cents: 163636, merchant: 'PAY HARMONY FAMILY', when: day);
      expect(row.recordedDirection, isNull);
      expect(row.direction, TransactionDirection.inbound);
    });

    test('an e-Transfer stays money out until a statement says otherwise', () {
      final row = stored(
        cents: 10000,
        merchant: 'E-TRANSFER 011662073398 Tolulope Sunday Atoyeje',
        when: day,
      );
      expect(row.direction, TransactionDirection.outbound);
    });
  });
}
