import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/aggregation/aggregator_models.dart';
import 'package:spendwise/services/aggregator_client.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

Map<String, Object?> row({
  String providerId = 'plaid-1',
  Object? amountCents = 4567,
  String date = '2026-09-01',
  String eventType = 'purchase',
  String? merchant = 'Tim Hortons',
  String? currency = 'CAD',
  String? category,
  String? last4 = '1234',
}) {
  return <String, Object?>{
    'provider_id': providerId,
    'amount_cents': amountCents,
    'currency': currency,
    'date': date,
    'event_type': eventType,
    'merchant': merchant,
    'account_last4': last4,
    'category': category,
  };
}

void main() {
  group('parsing sync rows', () {
    test('reads a well-formed purchase', () {
      final txn = parseAggregatorTransaction(row())!;
      expect(txn.providerId, 'plaid-1');
      expect(txn.amountCents, 4567);
      expect(txn.currency, 'CAD');
      expect(txn.eventType, TransactionEventType.purchase);
      expect(txn.merchant, 'Tim Hortons');
      expect(txn.accountLast4, '1234');
    });

    test('stores magnitude, so a credit does not arrive negative', () {
      // Plaid signs money-in as negative. Direction is carried by the event
      // type here, so a negative amount would corrupt every total.
      final txn = parseAggregatorTransaction(
        row(amountCents: -2000, eventType: 'refund'),
      )!;
      expect(txn.amountCents, 2000);
      expect(txn.eventType, TransactionEventType.refund);
      expect(txn.eventType.countsAsSpending, isFalse);
    });

    test('normalises the merchant for rule matching', () {
      final txn = parseAggregatorTransaction(
        row(merchant: 'SQ *Blue Door Cafe #12'),
      )!;
      expect(txn.merchantNormalized, 'BLUE DOOR CAFE');
    });

    test('maps a category slug when one is given', () {
      final txn = parseAggregatorTransaction(row(category: 'dining'))!;
      expect(txn.category, SpendCategory.dining);
    });

    test('leaves the category null when the provider had no opinion', () {
      expect(parseAggregatorTransaction(row())!.category, isNull);
    });

    test('an unrecognised event type becomes unknown, not a purchase', () {
      // Failing safe: an unknown type is skipped by the reconciler, whereas
      // guessing "purchase" would invent spending.
      final txn = parseAggregatorTransaction(row(eventType: 'nonsense'))!;
      expect(txn.eventType, TransactionEventType.unknown);
    });

    test('defaults currency to CAD and upper-cases it', () {
      expect(parseAggregatorTransaction(row(currency: null))!.currency, 'CAD');
      expect(parseAggregatorTransaction(row(currency: 'usd'))!.currency, 'USD');
    });
  });

  group('bad rows are dropped, not thrown', () {
    test('a row with no provider id is dropped', () {
      expect(parseAggregatorTransaction(row(providerId: '')), isNull);
    });

    test('a row with no amount is dropped', () {
      expect(parseAggregatorTransaction(row(amountCents: null)), isNull);
    });

    test('a row with an unparseable date is dropped', () {
      expect(parseAggregatorTransaction(row(date: 'not-a-date')), isNull);
    });

    test('an empty map is dropped', () {
      expect(parseAggregatorTransaction(const <String, Object?>{}), isNull);
    });

    test('one bad row never throws, so a sync is not aborted by it', () {
      final rows = <Map<String, Object?>>[
        row(providerId: 'a'),
        const <String, Object?>{'garbage': true},
        row(providerId: 'c'),
      ];

      final parsed = rows
          .map(parseAggregatorTransaction)
          .whereType<AggregatorTransaction>()
          .toList();

      expect(parsed, hasLength(2));
    });
  });

  group('configuration gating', () {
    test('the feature is off when not configured', () {
      const client = SupabaseAggregatorClient(enabled: false);
      expect(client.isConfigured, isFalse);
    });

    test('the feature is on when configured', () {
      const client = SupabaseAggregatorClient(enabled: true);
      expect(client.isConfigured, isTrue);
    });
  });
}
