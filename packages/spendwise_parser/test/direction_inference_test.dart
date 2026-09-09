import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:test/test.dart';

TransactionDirection guess(String description) =>
    TransactionDirection.infer(
      type: TransactionEventType.transfer,
      description: description,
    );

void main() {
  group('reading direction out of the wording alone', () {
    // These are the rows that made the report wrong: a salary filed as money
    // leaving the account overstates outflow by the largest single figure on
    // the statement.
    test('a payroll credit is money in', () {
      expect(guess('PAY HARMONY FAMILY'), TransactionDirection.inbound);
      expect(
        guess('PAY 10749976074 BEYOND BEHAVIOURAL INTERV'),
        TransactionDirection.inbound,
      );
    });

    test('a deposit is money in', () {
      expect(guess('DEPOSIT'), TransactionDirection.inbound);
      expect(guess('DIRECT DEPOSIT ACME LTD'), TransactionDirection.inbound);
    });

    // The word boundary is the whole point: PAYMENT starts with PAY and goes
    // the other way.
    test('a payment is not a payroll credit', () {
      expect(guess('PAYMENT TO SOMEONE'), TransactionDirection.outbound);
      expect(
        guess('PREAUTHORIZED DEBIT LN # 5908231831 CIBC LOANS'),
        TransactionDirection.outbound,
      );
    });

    // Sent and received look identical, so the guess stays outbound and only
    // a statement's running balance can settle it.
    test('an e-Transfer is left as money out', () {
      expect(
        guess('E-TRANSFER 011662073398 Tolulope Sunday Atoyeje'),
        TransactionDirection.outbound,
      );
    });

    test('wording is only consulted for transfers', () {
      expect(
        TransactionDirection.infer(
          type: TransactionEventType.purchase,
          description: 'PAY N GO CONVENIENCE',
        ),
        TransactionDirection.outbound,
      );
    });

    test('a row with no description at all still resolves', () {
      expect(
        TransactionDirection.infer(type: TransactionEventType.transfer),
        TransactionDirection.outbound,
      );
    });
  });
}
