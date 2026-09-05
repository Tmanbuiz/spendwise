import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:test/test.dart';

/// A CIBC credit-card statement as `PdfTextExtractor` flattens it: one table
/// cell per line, with the page furniture that surrounds the tables.
///
/// The wording, section order, column headings and stray amounts are copied
/// from a real statement's extraction; the merchants, dates and figures are
/// invented, so no real financial data lives in the repository.
///
/// The account-summary block at the top matters as much as the tables: it is
/// full of dates and amounts that are not transactions, and it is what an
/// earlier reader turned into a fabricated $1,000.00 purchase.
const String _cardWithCategories = '''
CIBC Dividend Platinum
 Visa* Card
Your account at a glance
Previous balance
\$1,196.40
Payments
\$900.00
Total credits
-
\$912.95
Total balance
=
\$1,018.54
Your payment due this month
Amount Due
\$1,018.54
Summary
Credit
Limit
\$1,000.00
Available
\$0.00
Interest rates
Annual
Regular purchases
21.99%
Total Minimum Payment due by
Aug 12, 2026
\$76.72
Account number
4500 XXXX XXXX 2199
Page
2
of 4
Your payments
Trans
date
Post
date
Description
Amount(\$)
Jun 13
Jun 16
PAYMENT THANK YOU/PAIEMENT MERCI
50.00
Jun 19
Jun 22
PAYMENT THANK YOU/PAIEMENT MERCI
129.00
Total payments
\$179.00
Your interest
Trans
date
Post
date
Description
Annual interest rate
Amount(\$)
Jul 15
Jul 15
REGULAR PURCHASES
21.99%
8.78
Jun 13
Jun 16
INTEREST REVERSAL
-0.09***
Total interest this period
\$8.78
Your new charges and credits
Ý
 Identifies Cash Back Multiplier transactions that have earned enhanced cash back rewards.
Trans
date
Post
date
Description
Spend Categories
Amount(\$)
Card number 4500 XXXX XXXX 2199
Jun 13
Jun 16
BLUE DOOR CAFE           FREDERICTON  NB

Restaurants
5.11
Jun 13
Jun 16
CASH ADVANCE/AVANCE DE FONDS

Cash Advances, Balance Transfers, CIBC
GMT
30.00
Jun 16
Jun 16
CASH ADV/BT/CONV CHQ FEE

Professional and Financial Services
5.00
Jun 15
Jun 16
Ý
NORTHSIDE GROCERS        FREDERICTON  NB

Retail and Grocery
14.53
Jul 06
Jul 07
CASHBACK/REMISE EN ARGENT

Other Transactions
-12.68
Total for 4500 XXXX XXXX 2199
\$41.96
Page
4
of 4
CIBC CreditSmart
Spend Report
Spend Categories
Transactions
Amount(\$)
Restaurants
1
5.11
Retail and Grocery
1
14.53
''';

/// The other card in the same family prints no Spend Categories column, so a
/// row is exactly four lines. Its month names are upper case.
const String _cardWithoutCategories = '''
Your new charges and credits
Trans
date
Post
date
Description
Amount(\$)
Card number 5177 XXXX XXXX 5987
JUL 15
JUL 16
HARBOUR BOOKS            866-216-1072 ON
24.10
JUL 20
JUL 20
CREDIT                   TORONTO      ON
-90.75
AUG 13
AUG 14
NORTHSIDE GROCERS        FREDERICTON  NB
23.73
Total for
5177 XXXX XXXX 5987
-\$42.92
''';

StatementRow _byDescription(StatementImport result, String needle) {
  return result.rows.firstWhere((r) => r.description.contains(needle));
}

void main() {
  group('recognising a card statement', () {
    test('recognises the charges heading', () {
      expect(
        CardStatementReader.looksLikeCardStatement(_cardWithCategories),
        isTrue,
      );
    });

    test('recognises the two-date column header on its own', () {
      const header = 'Trans\ndate\nPost\ndate\nDescription\nAmount(\$)';
      expect(CardStatementReader.looksLikeCardStatement(header), isTrue);
    });

    test('does not claim an account statement', () {
      const account = '''
Transaction details
Date
Description
Withdrawals (\$)
Deposits (\$)
Balance (\$)
Aug 3
E-TRANSFER 106056182358
100.00
-102.38
''';
      expect(CardStatementReader.looksLikeCardStatement(account), isFalse);
    });

    test('TextStatementReader routes a card statement to this reader', () {
      // Reached through the same entry point the app calls, so the routing is
      // covered and not just the reader in isolation.
      final result = TextStatementReader.read(_cardWithCategories);
      expect(result.rows, hasLength(9));
      expect(_byDescription(result, 'BLUE DOOR CAFE').amount.cents, 511);
    });
  });

  group('the account summary is never read as transactions', () {
    test('no row is invented from the summary block', () {
      final result = CardStatementReader.read(_cardWithCategories);

      // $1,000.00 credit limit, $1,018.54 amount due, $76.72 minimum payment
      // and $1,196.40 previous balance all sit beside dates in the summary.
      const summaryFigures = <int>[100000, 101854, 7672, 119640, 91295];
      for (final cents in summaryFigures) {
        expect(
          result.rows.where((r) => r.amount.cents == cents),
          isEmpty,
          reason: 'summary figure $cents was read as a transaction',
        );
      }
    });

    test('a section total is not a transaction', () {
      final result = CardStatementReader.read(_cardWithCategories);
      expect(result.rows.where((r) => r.amount.cents == 17900), isEmpty);
      expect(result.rows.where((r) => r.amount.cents == 4196), isEmpty);
    });

    test('the spend report on the last page is not counted twice', () {
      final result = CardStatementReader.read(_cardWithCategories);
      expect(
        result.rows.where((r) => r.amount.cents == 511),
        hasLength(1),
        reason: 'the row and its spend-report echo were both read',
      );
    });

    test('a lone date followed by an amount yields nothing', () {
      // The payment slip prints "Aug 12, 2026" next to "$76.72" with no
      // second date. One date is not a row.
      const slip = 'Your new charges and credits\nAug 12, 2026\n\$76.72\n';
      expect(CardStatementReader.read(slip).rows, isEmpty);
    });

    test('a row with no description is refused', () {
      const bare = 'Your new charges and credits\nJun 13\nJun 16\n41.96\n';
      final result = CardStatementReader.read(bare);
      expect(result.rows, isEmpty);
    });
  });

  group('the section decides what a row means', () {
    test('a payment is a payment, not spending', () {
      final result = CardStatementReader.read(_cardWithCategories);
      final payments =
          result.rows.where((r) => r.eventType == TransactionEventType.payment);
      expect(payments, hasLength(2));
      expect(payments.every((r) => !r.countsAsSpending), isTrue);
    });

    test('interest is a real cost and counts', () {
      final result = CardStatementReader.read(_cardWithCategories);
      final interest = _byDescription(result, 'REGULAR PURCHASES');
      expect(interest.eventType, TransactionEventType.purchase);
      expect(interest.amount.cents, 878);
    });

    test('an interest row is labelled so it does not read as a merchant', () {
      final result = CardStatementReader.read(_cardWithCategories);
      expect(
        _byDescription(result, 'REGULAR PURCHASES').description,
        startsWith('Interest'),
      );
    });

    test('an interest reversal is money back', () {
      final result = CardStatementReader.read(_cardWithCategories);
      final reversal = _byDescription(result, 'INTEREST REVERSAL');
      expect(reversal.eventType, TransactionEventType.refund);
      expect(reversal.amount.cents, 9,
          reason: 'the *** adjustment marker must not corrupt the amount');
    });
  });

  group('the sign decides direction when wording cannot', () {
    test('a negative amount is a credit even with no wording for it', () {
      final result = CardStatementReader.read(_cardWithoutCategories);
      final credit = _byDescription(result, 'CREDIT');
      expect(credit.eventType, TransactionEventType.refund);
      expect(credit.amount.cents, 9075);
      expect(credit.countsAsSpending, isFalse);
    });

    test('cash back is a credit, not a purchase', () {
      final result = CardStatementReader.read(_cardWithCategories);
      final cashback = _byDescription(result, 'CASHBACK');
      expect(cashback.eventType, TransactionEventType.refund);
      expect(cashback.amount.cents, 1268);
    });
  });

  group('cash advances', () {
    test('taking cash is not spending', () {
      final result = CardStatementReader.read(_cardWithCategories);
      final advance = _byDescription(result, 'CASH ADVANCE/AVANCE DE FONDS');
      expect(advance.eventType, TransactionEventType.transfer);
      expect(advance.countsAsSpending, isFalse);
    });

    test('the fee charged for taking it is', () {
      final result = CardStatementReader.read(_cardWithCategories);
      final fee = _byDescription(result, 'CASH ADV/BT/CONV CHQ FEE');
      expect(fee.eventType, TransactionEventType.purchase);
      expect(fee.amount.cents, 500);
    });
  });

  group('descriptions', () {
    test("CIBC's own spend category is not part of the merchant", () {
      final result = CardStatementReader.read(_cardWithCategories);
      expect(_byDescription(result, 'BLUE DOOR CAFE').description,
          'BLUE DOOR CAFE FREDERICTON NB');
    });

    test('a category wrapped over two lines is still stripped', () {
      final result = CardStatementReader.read(_cardWithCategories);
      expect(_byDescription(result, 'AVANCE DE FONDS').description,
          'CASH ADVANCE/AVANCE DE FONDS');
    });

    test('the cash-back multiplier marker is dropped', () {
      final result = CardStatementReader.read(_cardWithCategories);
      expect(_byDescription(result, 'NORTHSIDE GROCERS').description,
          'NORTHSIDE GROCERS FREDERICTON NB');
    });

    test('a merchant normalises for matching against a captured alert', () {
      final result = CardStatementReader.read(_cardWithCategories);
      expect(
        _byDescription(result, 'BLUE DOOR CAFE').merchantNormalized,
        isNotNull,
      );
    });
  });

  group('dates', () {
    test('the transaction date is used, not the posting date', () {
      final result = CardStatementReader.read(_cardWithCategories);
      // Jun 13 traded, Jun 16 posted.
      expect(_byDescription(result, 'BLUE DOOR CAFE').date,
          DateTime(2026, 6, 13));
    });

    test('the year comes from the statement, not today', () {
      final result = CardStatementReader.read(_cardWithCategories);
      expect(result.rows.every((r) => r.date.year == 2026), isTrue);
    });

    test('an explicit year overrides the one inferred', () {
      final result = CardStatementReader.read(_cardWithCategories, year: 2024);
      expect(_byDescription(result, 'BLUE DOOR CAFE').date,
          DateTime(2024, 6, 13));
    });

    test('upper-case month names parse', () {
      final result = CardStatementReader.read(_cardWithoutCategories);
      expect(_byDescription(result, 'HARBOUR BOOKS').date,
          DateTime(2026, 7, 15));
    });
  });

  group('a statement with no category column', () {
    test('reads every row', () {
      final result = CardStatementReader.read(_cardWithoutCategories);
      expect(result.rows, hasLength(3));
      expect(result.problems, isEmpty);
    });

    test('spending excludes the credit', () {
      final result = CardStatementReader.read(_cardWithoutCategories);
      expect(result.spendingTotalCents, 2410 + 2373);
    });
  });

  group('totals reconcile', () {
    test('only purchases count toward spending', () {
      final result = CardStatementReader.read(_cardWithCategories);
      // 5.11 cafe + 5.00 advance fee + 14.53 grocers + 8.78 interest.
      // Excluded: two payments, the 30.00 cash advance, the 12.68 cash back
      // and the 0.09 interest reversal.
      expect(result.spendingTotalCents, 511 + 500 + 1453 + 878);
    });

    test('every row is read and none is invented', () {
      final result = CardStatementReader.read(_cardWithCategories);
      expect(result.rows, hasLength(9));
      expect(result.problems, isEmpty);
    });
  });

  group('degrading safely', () {
    test('empty text yields nothing rather than failing', () {
      final result = CardStatementReader.read('');
      expect(result.rows, isEmpty);
      expect(result.problems, isEmpty);
    });

    test('a statement with headings but no rows yields nothing', () {
      const empty = 'Your payments\nTotal payments\n\$0.00\n';
      expect(CardStatementReader.read(empty).rows, isEmpty);
    });

    test('text before the first heading is ignored entirely', () {
      const stray = 'Jun 13\nJun 16\nSOMETHING\n40.00\n';
      expect(CardStatementReader.read(stray).rows, isEmpty);
    });
  });
}
