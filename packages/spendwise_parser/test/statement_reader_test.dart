import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:test/test.dart';

void main() {
  group('CSV splitting', () {
    test('handles a plain row', () {
      expect(
        CsvReader.parse('a,b,c'),
        <List<String>>[
          <String>['a', 'b', 'c'],
        ],
      );
    });

    test('keeps commas inside quoted fields', () {
      // Merchant names contain commas. Splitting naively shifts every later
      // column by one and imports the wrong number as the amount.
      final rows = CsvReader.parse('2026-09-04,"SHEIN, INC",28.51');
      expect(rows.single, <String>['2026-09-04', 'SHEIN, INC', '28.51']);
    });

    test('handles doubled quotes as an escape', () {
      final rows = CsvReader.parse('1,"He said ""hi""",2');
      expect(rows.single[1], 'He said "hi"');
    });

    test('handles a newline inside a quoted field', () {
      final rows = CsvReader.parse('1,"line one\nline two",3');
      expect(rows, hasLength(1));
      expect(rows.single[1], 'line one\nline two');
    });

    test('handles CRLF and LF alike', () {
      expect(CsvReader.parse('a,b\r\nc,d'), hasLength(2));
      expect(CsvReader.parse('a,b\nc,d'), hasLength(2));
    });

    test('drops blank trailing lines', () {
      expect(CsvReader.parse('a,b\nc,d\n\n\n'), hasLength(2));
    });

    test('detects a semicolon delimiter', () {
      expect(CsvReader.detectDelimiter('a;b;c\nd;e;f'), ';');
    });

    test('detects a tab delimiter', () {
      expect(CsvReader.detectDelimiter('a\tb\tc\nd\te\tf'), '\t');
    });

    test('defaults to a comma', () {
      expect(CsvReader.detectDelimiter('a,b\nc,d'), ',');
    });
  });

  group('CIBC-style export: headerless, debit and credit columns', () {
    // CIBC exports no header row and splits money-out from money-in.
    const csv = '''
2026-09-04,SHEIN,28.51,,4519********2199
2026-09-03,TIM HORTONS #123,4.50,,4519********2199
2026-09-02,PAYMENT THANK YOU,,500.00,4519********2199
2026-09-01,LOBLAWS,87.31,,4519********2199
''';

    test('detects the layout without a header', () {
      final result = StatementReader.read(csv);
      expect(result.layout!.hasHeader, isFalse);
      expect(result.layout!.usesDebitCredit, isTrue);
    });

    test('reads every row', () {
      final result = StatementReader.read(csv);
      expect(result.rows, hasLength(4));
      expect(result.problems, isEmpty);
    });

    test('debits are spending, credits are not', () {
      final result = StatementReader.read(csv);
      final spending = result.rows.where((r) => r.countsAsSpending).toList();

      expect(spending, hasLength(3));
      // 28.51 + 4.50 + 87.31
      expect(result.spendingTotalCents, 12032);
    });

    test('the credit line is not counted as spending', () {
      final result = StatementReader.read(csv);
      final credit =
          result.rows.firstWhere((r) => r.description.contains('PAYMENT'));
      expect(credit.countsAsSpending, isFalse);
      expect(credit.amount.cents, 50000);
    });

    test('merchants normalise for categorisation', () {
      final result = StatementReader.read(csv);
      final tims =
          result.rows.firstWhere((r) => r.description.contains('TIM HORTONS'));
      expect(tims.merchantNormalized, 'TIM HORTONS');
      expect(
        Categorizer().categoryFor(tims.merchantNormalized),
        SpendCategory.dining,
      );
    });
  });

  group('header + single signed amount column', () {
    const csv = '''
Date,Description,Amount,Balance
2026-09-04,Tel-E-Sim.com,-29.00,120.00
2026-09-03,Interac e-Transfer received,250.00,149.00
2026-09-02,SHEIN,-28.51,-101.00
''';

    test('detects the header and the amount column', () {
      final result = StatementReader.read(csv);
      expect(result.layout!.hasHeader, isTrue);
      expect(result.layout!.usesDebitCredit, isFalse);
      expect(result.layout!.amountColumn, 2);
    });

    test('negative is read as spending', () {
      final result = StatementReader.read(csv);
      expect(result.signConvention, AmountSign.negativeIsSpending);
      // 29.00 + 28.51, not the 250.00 deposit.
      expect(result.spendingTotalCents, 5751);
    });

    test('the deposit is a transfer, not spending', () {
      final result = StatementReader.read(csv);
      final deposit =
          result.rows.firstWhere((r) => r.description.contains('Interac'));
      expect(deposit.eventType, TransactionEventType.transfer);
      expect(deposit.countsAsSpending, isFalse);
    });

    test('the sign convention can be overridden from the preview', () {
      // Getting this backwards would turn every deposit into spending, so the
      // user can flip it. Then the 250.00 becomes the only "spending".
      final flipped = StatementReader.read(
        csv,
        signOverride: AmountSign.positiveIsSpending,
      );
      expect(flipped.spendingTotalCents, 25000);
    });

    test('a mostly-positive file is read as positive-is-spending', () {
      const positives = '''
Date,Description,Amount
2026-09-04,A,29.00
2026-09-03,B,10.00
2026-09-02,C,5.00
2026-09-01,D,-100.00
''';
      expect(
        StatementReader.read(positives).signConvention,
        AmountSign.positiveIsSpending,
      );
    });
  });

  group('money and date formats', () {
    test('reads dollar signs and thousands separators', () {
      const csv = '''
Date,Description,Debit,Credit
2026-09-04,BIG PURCHASE,"\$1,249.99",
''';
      final result = StatementReader.read(csv);
      expect(result.rows.single.amount.cents, 124999);
    });

    test('reads bracketed negatives', () {
      const csv = '''
Date,Description,Amount
2026-09-04,A,(45.67)
2026-09-03,B,(10.00)
''';
      final result = StatementReader.read(csv);
      expect(result.rows.first.amount.cents, 4567);
      expect(result.rows.first.countsAsSpending, isTrue);
    });

    test('reads a trailing minus', () {
      const csv = '''
Date,Description,Amount
2026-09-04,A,45.67-
2026-09-03,B,10.00-
''';
      expect(StatementReader.read(csv).rows.first.countsAsSpending, isTrue);
    });

    test('reads slash dates', () {
      const csv = '''
Date,Description,Amount
09/04/2026,A,-10.00
''';
      expect(StatementReader.read(csv).rows.single.date, DateTime(2026, 9, 4));
    });

    test('reads day-first slash dates when the day exceeds 12', () {
      const csv = '''
Date,Description,Amount
25/09/2026,A,-10.00
''';
      expect(StatementReader.read(csv).rows.single.date, DateTime(2026, 9, 25));
    });

    test('reads text dates', () {
      const csv = '''
Date,Description,Amount
"Sep 4, 2026",A,-10.00
''';
      expect(StatementReader.read(csv).rows.single.date, DateTime(2026, 9, 4));
    });
  });

  group('bad input is reported, not swallowed', () {
    test('a row with no date is flagged with its line number', () {
      const csv = '''
Date,Description,Amount
2026-09-04,GOOD,-10.00
not-a-date,BAD,-20.00
2026-09-02,ALSO GOOD,-30.00
''';
      final result = StatementReader.read(csv);
      expect(result.rows, hasLength(2));
      expect(result.problems, hasLength(1));
      expect(result.problems.single.lineNumber, 3);
      expect(result.problems.single.reason, contains('date'));
    });

    test('a row with no amount is flagged', () {
      const csv = '''
Date,Description,Amount
2026-09-04,NO AMOUNT,
''';
      expect(StatementReader.read(csv).problems, hasLength(1));
    });

    test('an unreadable file reports a problem rather than importing junk', () {
      final result = StatementReader.read('just some prose\nwith no columns');
      expect(result.rows, isEmpty);
      expect(result.problems, isNotEmpty);
    });

    test('empty input is handled', () {
      final result = StatementReader.read('');
      expect(result.isEmpty, isTrue);
      expect(result.problems, isEmpty);
    });

    test('never throws on adversarial input', () {
      const nasty = <String>[
        '',
        ',,,,',
        '\n\n\n',
        '"unclosed quote',
        'a,b,c',
        '2026-09-04',
      ];
      for (final input in nasty) {
        expect(() => StatementReader.read(input), returnsNormally,
            reason: 'threw on: $input');
      }
    });
  });

  group('the import total is trustworthy', () {
    test('only outgoing rows contribute', () {
      const csv = '''
Date,Description,Debit,Credit
2026-09-04,SHEIN,28.51,
2026-09-03,REFUND FROM SHEIN,,28.51
2026-09-02,PAYMENT - THANK YOU,,500.00
2026-09-01,INTERAC E-TRANSFER,,250.00
2026-08-31,TIM HORTONS,4.50,
''';
      final result = StatementReader.read(csv);
      expect(result.rows, hasLength(5));
      // Only 28.51 + 4.50 is spending.
      expect(result.spendingTotalCents, 3301);
    });

    test('a refund is recognised from its description', () {
      const csv = '''
Date,Description,Debit,Credit
2026-09-03,REFUND FROM SHEIN,,28.51
''';
      expect(
        StatementReader.read(csv).rows.single.eventType,
        TransactionEventType.refund,
      );
    });
  });
}
