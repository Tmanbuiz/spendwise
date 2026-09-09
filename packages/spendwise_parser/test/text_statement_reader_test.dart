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

    test('a loan instalment is debt service, not spending', () {
      final result =
          TextStatementReader.read('Sep 4  CIBC LOAN PAYMENT  241.12');
      expect(result.rows.single.eventType, TransactionEventType.payment);
      expect(result.rows.single.countsAsSpending, isFalse);
    });

    test('a mortgage payment is debt service, not spending', () {
      final result =
          TextStatementReader.read('Sep 4  MORTGAGE PAYMENT  1240.00');
      expect(result.rows.single.countsAsSpending, isFalse);
    });

    // CIBC prints scheduled savings transfers under its own internal code,
    // with no word in the line saying that is what they are.
    test('CIBC-DISATF is a savings transfer', () {
      final result = TextStatementReader.read('Sep 4  CIBC-DISATF  50.00');
      expect(result.rows.single.eventType, TransactionEventType.transfer);
      expect(result.rows.single.countsAsSpending, isFalse);
    });

    test('a named savings transfer is not spending', () {
      final result =
          TextStatementReader.read('Sep 4  TRANSFER TO SAVINGS  100.00');
      expect(result.rows.single.eventType, TransactionEventType.transfer);
    });

    // The loan rule matches a whole word, so a merchant that merely contains
    // those letters is still an ordinary purchase.
    test('a merchant whose name contains "loan" still counts', () {
      final result = TextStatementReader.read('Sep 4  SLOANE COFFEE  6.75');
      expect(result.rows.single.countsAsSpending, isTrue);
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

    // The event type cannot answer this: an e-Transfer sent and an e-Transfer
    // received are both `transfer`. Only the balance separates them, which is
    // why direction is recorded rather than inferred later.
    test('the balance also records which way the money went', () {
      final rows = TextStatementReader.read(text).rows;

      expect(rows[0].direction, TransactionDirection.outbound);
      expect(rows[1].direction, TransactionDirection.inbound);
      expect(rows[2].direction, TransactionDirection.inbound);
      expect(rows[3].direction, TransactionDirection.outbound);
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

  group('a balance carried across a page break', () {
    // Every page of a multi-page account statement restates the running
    // balance before the first transaction on that page. The label is
    // furniture, but the number underneath it is not: left in the buffer it
    // pairs with the next transaction's amount, and that transaction is then
    // recorded as the carried balance. This is the shape that turned a $16.95
    // service charge into $1,801.78 and made whole runs of same-day rows
    // report the balance of the row above them.
    const pageBreak = '''
Transaction details
Aug 3
E-TRANSFER        106056182358
Tolulope
100.00
-102.38
(continued on next page)
Page 1 of 6
Transaction details (continued)
Date
Description
Withdrawals (\$)
Deposits (\$)
Balance (\$)
Aug 3
Balance forward
\$79.62
PREAUTHORIZED DEBIT
Wealthsimple Investments Inc.
40.00
39.62
Aug 4
CHEQUE
25.00
14.62
''';

    test('the carried balance is not recorded as a transaction', () {
      final result = TextStatementReader.read(pageBreak, year: 2026);

      expect(
        result.rows.map((r) => r.amount.cents),
        isNot(contains(7962)),
        reason: 'the carried balance must never surface as an amount',
      );
      expect(
        result.rows.map((r) => r.description),
        everyElement(isNot(contains('Balance forward'))),
      );
    });

    test('transactions after the break keep their own amounts', () {
      final result = TextStatementReader.read(pageBreak, year: 2026);

      final wealthsimple = result.rows.firstWhere(
        (r) => r.description.contains('Wealthsimple'),
      );
      expect(wealthsimple.amount.cents, 4000);

      final cheque = result.rows.firstWhere(
        (r) => r.description.contains('CHEQUE'),
      );
      expect(cheque.amount.cents, 2500);
    });

    test('a fee after a page break keeps its real value', () {
      // The exact sequence from the August statement, where the reader
      // published \$1.06 for a \$16.95 charge.
      const text = '''
Transaction details
Aug 31
Balance forward
\$1.06
SERVICE CHARGE
CAPPED MONTHLY FEE\$16.95
RECORD-KEEPING  N/A
16.95
-15.89
OVERDRAFT FEE
25.00
-40.89
OVERDRAFT INTEREST CHARGE
0.72
-41.61
Closing balance
-\$41.61
''';

      final result = TextStatementReader.read(text, year: 2026);
      final amounts = <String, int>{
        for (final row in result.rows) row.description: row.amount.cents,
      };

      expect(
        amounts.entries
            .firstWhere((e) => e.key.startsWith('SERVICE CHARGE'))
            .value,
        1695,
      );
      expect(amounts['OVERDRAFT FEE'], 2500);
      expect(amounts['OVERDRAFT INTEREST CHARGE'], 72);

      // The closing balance is a total, not money moving.
      expect(result.rows.map((r) => r.amount.cents), isNot(contains(4161)));
    });
  });

  group('several statements joined into one file', () {
    // Reading a merged file as one document fails silently: one layout is
    // chosen for the whole thing, a statement's running balance carries into
    // the next, and every date resolves against a single year. Measured
    // against a statement read on its own, a real merged file lost 36 of 39
    // transactions and misreported the 3 that survived — and reported
    // success. Refusing is the only honest answer.
    String statement(
      String product,
      String period,
      String merchant,
      String amount,
    ) =>
        '''
$product
$period statement period
Account number
4500 XXXX XXXX 2199
Page 1 of 3
Your new charges and credits
Trans
date
Post
date
Description
Amount(\$)
Jun 13
Jun 16
$merchant
$amount
''';

    test('one statement is read normally', () {
      final text =
          statement('CIBC Dividend Visa', 'August', 'WAL-MART SUPERCENTER', '5.11');
      expect(StatementSplitter.split(text), hasLength(1));
      final result = TextStatementReader.read(text, year: 2026);
      expect(result.rows, isNotEmpty);
      expect(result.problems, isEmpty);
    });

    test('a continuation page does not start a new statement', () {
      // Every page after the first repeats the title and the period. Cutting
      // on those would split one statement into as many pieces as it has
      // pages; only the first page carries "August statement period".
      const text = '''
CIBC Dividend Visa
August statement period
Your new charges and credits
Trans
date
Post
date
Description
Amount(\$)
Jun 13
Jun 16
WAL-MART SUPERCENTER
5.11
Page 1 of 3
CIBC Dividend Visa
Jul 16 to Aug 15, 2026
Account number: 4500 XXXX XXXX 2199
Page 2 of 3
Jun 14
Jun 17
VICTORY MEAT MARKET
19.04
''';

      expect(StatementSplitter.split(text), hasLength(1));
      expect(TextStatementReader.read(text, year: 2026).rows, hasLength(2));
    });

    test('a statement whose totals disagree is left out and reported', () {
      // A segment that does not reproduce its own printed totals is the one
      // case where importing is worse than refusing: the rows look perfectly
      // well-formed. Splitting is only safe because of this.
      final good =
          statement('CIBC Dividend Visa', 'August', 'WAL-MART SUPERCENTER', '5.11');
      final bad =
          '${statement('CIBC Adapta Mastercard', 'July', 'VICTORY MEAT MARKET', '19.04')}'
          'Total for\n4500 XXXX XXXX 2199\n\$999.99\n';

      final result = TextStatementReader.read('$good\n$bad', year: 2026);

      expect(result.rows.map((r) => r.description),
          contains('WAL-MART SUPERCENTER'));
      expect(result.rows.map((r) => r.description),
          isNot(contains('VICTORY MEAT MARKET')));
      expect(result.problems, hasLength(1));
      expect(result.problems.single.reason, contains('does not match'));
    });

    test('two statements are read one at a time, not as one document', () {
      final text =
          '${statement('CIBC Dividend Visa', 'August', 'WAL-MART SUPERCENTER', '5.11')}'
          '\n'
          '${statement('CIBC Adapta Mastercard', 'July', 'VICTORY MEAT MARKET', '19.04')}';

      expect(StatementSplitter.split(text), hasLength(2));
      final result = TextStatementReader.read(text, year: 2026);

      final descriptions = result.rows.map((r) => r.description).toList();
      expect(descriptions, contains('WAL-MART SUPERCENTER'));
      expect(descriptions, contains('VICTORY MEAT MARKET'));
      expect(result.rows, hasLength(2));
    });

    test('each statement keeps its own amounts across the boundary', () {
      final text =
          '${statement('CIBC Dividend Visa', 'August', 'WAL-MART SUPERCENTER', '5.11')}'
          '\n'
          '${statement('CIBC Adapta Mastercard', 'July', 'VICTORY MEAT MARKET', '19.04')}';

      final result = TextStatementReader.read(text, year: 2026);
      final byMerchant = <String, int>{
        for (final row in result.rows) row.description: row.amount.cents,
      };

      expect(byMerchant['WAL-MART SUPERCENTER'], 511);
      expect(byMerchant['VICTORY MEAT MARKET'], 1904);
    });

    test('a single-page statement that never numbers itself still reads', () {
      // Zero markers means "no page numbering", not "no statement".
      const text = '''
Statement 2026
Sep 4   SHEIN                    28.51
''';
      expect(TextStatementReader.statementCount(text), 0);
      expect(TextStatementReader.read(text).rows, hasLength(1));
    });
  });
}
