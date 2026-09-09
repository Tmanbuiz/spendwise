import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:test/test.dart';

void main() {
  group('direction a reader could not observe', () {
    test('a refund is the only event type that means money in', () {
      expect(
        TransactionDirection.inferFrom(TransactionEventType.refund),
        TransactionDirection.inbound,
      );
    });

    // Guessing "inbound" for an unknown transfer would inflate reported
    // income, which is the failure that actually misleads someone.
    test('an unobserved transfer is assumed to be money out', () {
      expect(
        TransactionDirection.inferFrom(TransactionEventType.transfer),
        TransactionDirection.outbound,
      );
    });

    test('an unknown wire value falls back to money out', () {
      expect(
        TransactionDirection.fromWireName('sideways'),
        TransactionDirection.outbound,
      );
    });

    test('wire names round-trip', () {
      for (final direction in TransactionDirection.values) {
        expect(
          TransactionDirection.fromWireName(direction.wireName),
          direction,
        );
      }
    });
  });

  group('a row that was never told its direction', () {
    StatementRow row(TransactionEventType type) => StatementRow(
          date: DateTime(2026, 9, 4),
          description: 'SOMETHING',
          amount: const Money(1000, 'CAD'),
          eventType: type,
          lineNumber: 1,
        );

    test('falls back to what the event type implies', () {
      expect(
        row(TransactionEventType.purchase).direction,
        TransactionDirection.outbound,
      );
      expect(
        row(TransactionEventType.refund).direction,
        TransactionDirection.inbound,
      );
    });
  });
}
