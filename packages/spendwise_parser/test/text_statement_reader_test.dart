import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:test/test.dart';

void main() {
  group('a typical credit-card statement page', () {
    // What PDF text extraction produces: columns flattened into runs of
    // spaces, page furniture interleaved with the rows.
    const text = '''
CIBC Adapta Mastercard
Statement period: Aug 5 to Sep 4, 2026
Account number 4519 ******** 2199

Date        Description                     Amount
Sep 4       SHEIN                            28.51
Sep 3       TIM HORTONS #123                  4.50
Sep 2       PAYMENT - THANK YOU             500.00
Sep 1       LOBLAWS                          87.31

Previous balance                            120.00
Total                                       620.32
Page 1 of 2
''';

    test('finds only the transaction rows', () {
      final result = TextStatementReader.read(text);
      expect(result.rows, hasLength(4));
    });

    test('ignores headers, totals and page furniture', () {
      final result = TextStatementReader.read(text);
      final descriptions = result.rows.map((r) => r.description).toList();

      expect(descriptions, isNot(contains('Description')));
      for (final row in result.rows) {
        expect(row.description.toLowerCase(), isNot(contains('balance')));
        expect(row.description.toLowerCase(), isNot(contains('total')));
      }
    });

    test('reads dates using the year from the page header', () {
      final result = TextStatementReader.read(text);
      expect(result.rows.first.date, DateTime(2026, 9, 4));
    });

    test('reads amounts', () {
      final result = TextStatementReader.read(text);
      expect(result.rows.first.amount.cents, 2851);
      expect(result.rows.first.description, 'SHEIN');
    });

    test('a payment line is not counted as spending', () {
      final result = TextStatementReader.read(text);
      final payment =
          result.rows.firstWhere((r) => r.description.contains('PAYMENT'));
      expect(payment.eventType, TransactionEventType.payment);
      expect(payment.countsAsSpending, isFalse);
    });

    test('the spending total excludes the payment', () {
      final result = TextStatementReader.read(text);
      // 28.51 + 4.50 + 87.31
      expect(result.spendingTotalCents, 12032);
    });

    test('merchants normalise for categorisation', () {
      final result = TextStatementReader.read(text);
      final tims =
          result.rows.firstWhere((r) => r.description.contains('TIM HORTONS'));
      expect(
        Categorizer().categoryFor(tims.merchantNormalized),
        SpendCategory.dining,
      );
    });
  });

  group('statements that print a running balance', () {
    // Two amounts at the end of the line: the transaction, then the balance.
    // Taking the last one would import the balance as the spend.
    const text = '''
Statement 2026
Sep 4   SHEIN                    28.51      148.51
Sep 3   TIM HORTONS               4.50      120.00
''';

    test('takes the transaction amount, not the running balance', () {
      final result = TextStatementReader.read(text);
      expect(result.rows.first.amount.cents, 2851);
      expect(result.rows.first.amount.cents, isNot(14851));
    });

    test('the description excludes both amounts', () {
      final result = TextStatementReader.read(text);
      expect(result.rows.first.description, 'SHEIN');
    });
  });

  group('date formats', () {
    test('reads a full date on the row', () {
      final result = TextStatementReader.read('Sep 4, 2026  SHEIN  28.51');
      expect(result.rows.single.date, DateTime(2026, 9, 4));
    });

    test('reads day-first dates', () {
      final result = TextStatementReader.read('4 Sep 2026  SHEIN  28.51');
      expect(result.rows.single.date, DateTime(2026, 9, 4));
    });

    test('reads ISO dates', () {
      final result = TextStatementReader.read('2026-09-04  SHEIN  28.51');
      expect(result.rows.single.date, DateTime(2026, 9, 4));
    });

    test('reads slash dates', () {
      final result = TextStatementReader.read('09/04/2026  SHEIN  28.51');
      expect(result.rows.single.date, DateTime(2026, 9, 4));
    });

    test('an explicit year overrides the inferred one', () {
      final result = TextStatementReader.read(
        'Sep 4  SHEIN  28.51',
        year: 2025,
      );
      expect(result.rows.single.date.year, 2025);
    });
  });

  group('credits are recognised from wording, not sign', () {
    // PDF statements rarely sign the amount; they mark credits in the text.
    test('a refund line', () {
      final result =
          TextStatementReader.read('Sep 4  REFUND FROM SHEIN  28.51');
      expect(result.rows.single.eventType, TransactionEventType.refund);
      expect(result.rows.single.countsAsSpending, isFalse);
    });

    test('a trailing CR marks a credit', () {
      final result =
          TextStatementReader.read('Sep 4  SOME ADJUSTMENT CR  28.51');
      expect(result.rows.single.countsAsSpending, isFalse);
    });

    test('an e-Transfer is a transfer', () {
      final result =
          TextStatementReader.read('Sep 4  INTERAC E-TRANSFER  250.00');
      expect(result.rows.single.eventType, TransactionEventType.transfer);
      expect(result.rows.single.countsAsSpending, isFalse);
    });

    test('an ordinary purchase counts', () {
      final result = TextStatementReader.read('Sep 4  SHEIN  28.51');
      expect(result.rows.single.countsAsSpending, isTrue);
    });
  });

  group('lines that are not transactions are skipped, not guessed', () {
    test('a line with a date but no amount is ignored', () {
      final result = TextStatementReader.read('Sep 4  SOME NOTE');
      expect(result.rows, isEmpty);
    });

    test('a line with an amount but no date is ignored', () {
      final result = TextStatementReader.read('Interest charged  12.34');
      expect(result.rows, isEmpty);
    });

    test('an address block is ignored', () {
      const text = '''
123 Main Street
Fredericton NB E3B 1A1
Statement 2026
Sep 4  SHEIN  28.51
''';
      expect(TextStatementReader.read(text).rows, hasLength(1));
    });

    test('a credit limit line is ignored even though it has a number', () {
      const text = '''
Statement 2026
Credit limit                          5,000.00
Sep 4  SHEIN  28.51
''';
      final result = TextStatementReader.read(text);
      expect(result.rows, hasLength(1));
      expect(result.spendingTotalCents, 2851);
    });
  });

  group('CIBC account statement: one cell per line', () {
    // Extracted verbatim from a real CIBC account statement PDF. The table
    // flattens to one *cell* per line, the date is printed once per day, and
    // the withdrawal/deposit columns vanish when empty — so the running
    // balance is the only reliable direction signal.
    const text = '''
CIBC Account Statement
For Aug 1 to Aug 31, 2026
Account number
87-53083

Account summary
Opening balance on Aug 1, 2026
-\$2.38
Withdrawals
-
8,567.26
Deposits
+
8,528.03
Closing balance on Aug 31, 2026
=
-\$41.61

Transaction details
Date
Description
Withdrawals (\$)
Deposits (\$)
Balance (\$)
Aug 1
Opening balance
-\$2.38
Aug 3
E-TRANSFER        106056182358
Tolulope
100.00
-102.38

E-TRANSFER        011662073398
Tolulope Sunday Atoyeje
100.00
-2.38

E-TRANSFER        011662446254
Tolulope Sunday Atoyeje
100.00
97.62

E-TRANSFER        106056516196
Tolulope
100.00
-2.38
''';

    test('reads all four transactions', () {
      final result = TextStatementReader.read(text);
      expect(result.rows, hasLength(4));
    });

    test('ignores the account summary totals above the table', () {
      final result = TextStatementReader.read(text);
      // 8,567.26 and 8,528.03 are summary figures, not transactions.
      for (final row in result.rows) {
        expect(row.amount.cents, 10000);
      }
    });

    test('carries the date forward to same-day transactions', () {
      final result = TextStatementReader.read(text);
      // Only the first is labelled "Aug 3"; the rest inherit it.
      for (final row in result.rows) {
        expect(row.date, DateTime(2026, 8, 3));
      }
    });

    test('uses the running balance to tell money out from money in', () {
      final result = TextStatementReader.read(text);

      // -2.38 -> -102.38 fell, so money left.
      expect(result.rows[0].eventType, TransactionEventType.transfer);
      // -102.38 -> -2.38 rose, so money arrived.
      expect(result.rows[1].eventType, TransactionEventType.transfer);
      // Both are e-Transfers either way, so neither is spending.
      expect(result.rows.every((r) => !r.countsAsSpending), isTrue);
    });

    test('an e-Transfer is never counted as spending', () {
      expect(TextStatementReader.read(text).spendingTotalCents, 0);
    });

    test('the opening balance line does not become a transaction', () {
      final result = TextStatementReader.read(text);
      expect(
        result.rows.any((r) => r.description.contains('Opening balance')),
        isFalse,
      );
    });

    test('descriptions are joined and tidied', () {
      final result = TextStatementReader.read(text);
      expect(result.rows.first.description, contains('E-TRANSFER'));
      expect(result.rows.first.description, contains('Tolulope'));
      expect(result.rows.first.description, isNot(contains('  ')));
    });
  });

  group('cell-per-line with real purchases', () {
    // The same layout, but with card purchases rather than transfers, so the
    // spending total is exercised.
    const text = '''
Transaction details
Date
Description
Withdrawals (\$)
Deposits (\$)
Balance (\$)
Sep 1
Opening balance
1,000.00
Sep 2
SHEIN
28.51
971.49

TIM HORTONS
4.50
966.99
Sep 3
PAYROLL DEPOSIT
2,000.00
2,966.99
Sep 4
LOBLAWS
87.31
2,879.68
''';

    test('reads purchases and the deposit', () {
      final result = TextStatementReader.read(text, year: 2026);
      expect(result.rows, hasLength(4));
    });

    test('the deposit is money in, not spending', () {
      final result = TextStatementReader.read(text, year: 2026);
      final payroll =
          result.rows.firstWhere((r) => r.description.contains('PAYROLL'));
      expect(payroll.countsAsSpending, isFalse);
      expect(payroll.amount.cents, 200000);
    });

    test('the spending total counts only the purchases', () {
      final result = TextStatementReader.read(text, year: 2026);
      // 28.51 + 4.50 + 87.31
      expect(result.spendingTotalCents, 12032);
    });

    test('same-day rows inherit the date, later rows get their own', () {
      final result = TextStatementReader.read(text, year: 2026);
      expect(result.rows[0].date, DateTime(2026, 9, 2));
      expect(result.rows[1].date, DateTime(2026, 9, 2));
      expect(result.rows[2].date, DateTime(2026, 9, 3));
      expect(result.rows[3].date, DateTime(2026, 9, 4));
    });

    test('merchants categorise', () {
      final result = TextStatementReader.read(text, year: 2026);
      final tims =
          result.rows.firstWhere((r) => r.description.contains('TIM HORTONS'));
      expect(
        Categorizer().categoryFor(tims.merchantNormalized),
        SpendCategory.dining,
      );
    });
  });

  group('robustness', () {
    test('empty input yields nothing', () {
      expect(TextStatementReader.read('').isEmpty, isTrue);
    });

    test('prose yields nothing rather than junk', () {
      final result = TextStatementReader.read(
        'Thank you for banking with us. Please retain this statement.',
      );
      expect(result.rows, isEmpty);
    });

    test('never throws on adversarial input', () {
      const nasty = <String>[
        '',
        '   ',
        'Sep',
        'Sep 4',
        '28.51',
        r'$$$$',
        'Sep 99  X  99.99',
        'Sep 4  X  ....',
      ];
      for (final input in nasty) {
        expect(() => TextStatementReader.read(input), returnsNormally,
            reason: 'threw on: $input');
      }
    });

    test('an impossible date is reported, not imported', () {
      final result = TextStatementReader.read('Feb 31 2026  SHEIN  28.51');
      expect(result.rows, isEmpty);
      expect(result.problems, isNotEmpty);
    });
  });
}
