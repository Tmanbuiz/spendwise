import 'package:spendwise_parser/spendwise_parser.dart';

/// One realistic CIBC alert plus what the engine is expected to make of it.
class CibcSample {
  const CibcSample({
    required this.label,
    required this.body,
    required this.expectedType,
    this.title = 'CIBC',
    this.expectedCents,
    this.expectedCurrency = 'CAD',
    this.expectedMerchant,
    this.expectedLast4,
    this.expectsSpending = false,
  });

  /// Short description used as the test name.
  final String label;
  final String title;
  final String body;
  final TransactionEventType expectedType;

  /// Null means "the engine should not find an amount".
  final int? expectedCents;
  final String expectedCurrency;

  /// Normalised merchant. Null means the assertion is skipped for this sample.
  final String? expectedMerchant;
  final String? expectedLast4;

  /// Whether this event must increase monthly spending.
  final bool expectsSpending;

  NotificationMessage toMessage({DateTime? postedAt}) => NotificationMessage(
        packageName: 'com.cibc.android.mobi',
        title: title,
        body: body,
        postedAt: postedAt ?? DateTime(2026, 9, 3, 14, 30),
      );
}

/// Realistic CIBC wording, gathered across card products and alert channels.
///
/// The point of this list is coverage of *phrasing*, not of amounts: each
/// entry uses a construction CIBC actually ships, so a rules change that
/// breaks one template fails loudly here.
const List<CibcSample> cibcSamples = <CibcSample>[
  // --------------------------------------------------------------- purchases
  CibcSample(
    label: 'purchase: full template with card product, store and timestamp',
    body: r'A transaction of $45.67 was made on your CIBC Dividend Visa '
        'Infinite card ending in 1234 at TIM HORTONS #123 on Sep 3, 2026 '
        'at 8:14 AM.',
    expectedType: TransactionEventType.purchase,
    expectedCents: 4567,
    expectedMerchant: 'TIM HORTONS',
    expectedLast4: '1234',
    expectsSpending: true,
  ),
  CibcSample(
    label: 'purchase: short "you spent" phrasing',
    body: r'You spent $12.50 at STARBUCKS with your CIBC card ending in 4321.',
    expectedType: TransactionEventType.purchase,
    expectedCents: 1250,
    expectedMerchant: 'STARBUCKS',
    expectedLast4: '4321',
    expectsSpending: true,
  ),
  CibcSample(
    label: 'purchase: terse alert-style, no verb',
    title: 'CIBC Transaction alert',
    body: r'$89.99 at AMAZON.CA on your card ending 5678',
    expectedType: TransactionEventType.purchase,
    expectedCents: 8999,
    expectedMerchant: 'AMAZON CA',
    expectedLast4: '5678',
    expectsSpending: true,
  ),
  CibcSample(
    label: 'purchase: foreign currency',
    body: r'A purchase of $102.34 USD was made at APPLE.COM/BILL',
    expectedType: TransactionEventType.purchase,
    expectedCents: 10234,
    expectedCurrency: 'USD',
    expectedMerchant: 'APPLE COM BILL',
    expectsSpending: true,
  ),
  CibcSample(
    label: 'purchase: debit card wording',
    body: r'Your CIBC Advantage Debit Card was used for a purchase of $23.10 '
        'at LOBLAWS #456.',
    expectedType: TransactionEventType.purchase,
    expectedCents: 2310,
    expectedMerchant: 'LOBLAWS',
    expectsSpending: true,
  ),
  CibcSample(
    label: 'purchase: thousands separator, with balance in the same message',
    body: r'A transaction of $1,249.99 was made at BEST BUY #011 with your '
        'CIBC Aventura Visa ending in 9012. Your available balance is '
        r'$3,204.16.',
    expectedType: TransactionEventType.purchase,
    expectedCents: 124999,
    expectedMerchant: 'BEST BUY',
    expectedLast4: '9012',
    expectsSpending: true,
  ),
  CibcSample(
    label: 'purchase: payment-processor prefixed merchant',
    body: r'You spent $8.75 at SQ *BLUE DOOR CAFE with your CIBC card '
        'ending in 1111.',
    expectedType: TransactionEventType.purchase,
    expectedCents: 875,
    expectedMerchant: 'BLUE DOOR CAFE',
    expectedLast4: '1111',
    expectsSpending: true,
  ),
  CibcSample(
    label: 'purchase: bill payment to a utility is real spending',
    body: r'A bill payment of $142.08 to TORONTO HYDRO was made from your '
        'CIBC Smart Account ending in 3344.',
    expectedType: TransactionEventType.purchase,
    expectedCents: 14208,
    expectedMerchant: 'TORONTO HYDRO',
    expectedLast4: '3344',
    expectsSpending: true,
  ),
  CibcSample(
    label: 'purchase: pre-authorized debit',
    body: r'A pre-authorized debit of $79.00 to ROGERS was processed on your '
        'CIBC Smart Account ending in 3344.',
    expectedType: TransactionEventType.purchase,
    expectedCents: 7900,
    expectedMerchant: 'ROGERS',
    expectedLast4: '3344',
    expectsSpending: true,
  ),
  CibcSample(
    label: 'purchase: ATM withdrawal is an outflow',
    body: r'A withdrawal of $100.00 was made at CIBC ATM QUEEN ST from your '
        'account ending in 3344.',
    expectedType: TransactionEventType.purchase,
    expectedCents: 10000,
    expectedLast4: '3344',
    expectsSpending: true,
  ),
  CibcSample(
    label: 'purchase: merchant containing a stop-word ("AND")',
    body: r'You spent $56.20 at BED BATH AND BEYOND with your CIBC card '
        'ending in 1234.',
    expectedType: TransactionEventType.purchase,
    expectedCents: 5620,
    expectedMerchant: 'BED BATH AND BEYOND',
    expectedLast4: '1234',
    expectsSpending: true,
  ),
  CibcSample(
    label: 'purchase: time appears before the merchant',
    body: r'A transaction of $31.45 was made on Sep 2, 2026 at 7:02 p.m. at '
        'METRO #88 with your CIBC card ending in 1234.',
    expectedType: TransactionEventType.purchase,
    expectedCents: 3145,
    expectedMerchant: 'METRO',
    expectedLast4: '1234',
    expectsSpending: true,
  ),

  // ----------------------------------------------------------------- refunds
  CibcSample(
    label: 'refund: credited back from a merchant',
    body: r'A refund of $45.67 was credited to your CIBC Dividend Visa card '
        'ending in 1234 from BEST BUY.',
    expectedType: TransactionEventType.refund,
    expectedCents: 4567,
    expectedMerchant: 'BEST BUY',
    expectedLast4: '1234',
  ),
  CibcSample(
    label: 'refund: "a credit of" wording',
    body: r'A credit of $20.00 from WALMART was posted to your CIBC card '
        'ending in 4321.',
    expectedType: TransactionEventType.refund,
    expectedCents: 2000,
    expectedMerchant: 'WALMART',
    expectedLast4: '4321',
  ),
  CibcSample(
    label: 'refund: reversal wording',
    body: r'A reversal of $15.99 was applied to your CIBC card ending in 5678 '
        'from UBER EATS.',
    expectedType: TransactionEventType.refund,
    expectedCents: 1599,
    expectedMerchant: 'UBER EATS',
    expectedLast4: '5678',
  ),

  // ----------------------------------------------------------- card payments
  CibcSample(
    label: 'payment: thank-you wording',
    body: r'Thank you for your payment of $500.00 to your CIBC Visa ending '
        'in 1234.',
    expectedType: TransactionEventType.payment,
    expectedCents: 50000,
    expectedLast4: '1234',
  ),
  CibcSample(
    label: 'payment: received wording',
    body: r'Your payment of $1,200.00 has been received and applied to your '
        'CIBC credit card ending in 9012.',
    expectedType: TransactionEventType.payment,
    expectedCents: 120000,
    expectedLast4: '9012',
  ),
  CibcSample(
    label: 'payment: toward a line of credit',
    body: r'A payment of $250.00 was made to your CIBC line of credit '
        'ending in 7788.',
    expectedType: TransactionEventType.payment,
    expectedCents: 25000,
    expectedLast4: '7788',
  ),

  // --------------------------------------------------------------- transfers
  CibcSample(
    label: 'transfer: between own accounts',
    body: r'You transferred $300.00 from your CIBC Smart Account to your '
        'CIBC eAdvantage Savings Account.',
    expectedType: TransactionEventType.transfer,
    expectedCents: 30000,
  ),
  CibcSample(
    label: 'transfer: Interac e-Transfer sent',
    body: r'You sent an INTERAC e-Transfer of $50.00 to John Smith from your '
        'CIBC Smart Account ending in 3344.',
    expectedType: TransactionEventType.transfer,
    expectedCents: 5000,
    expectedLast4: '3344',
  ),
  CibcSample(
    label: 'transfer: Interac e-Transfer received',
    body: r'You received an INTERAC e-Transfer of $100.00 from Jane Doe.',
    expectedType: TransactionEventType.transfer,
    expectedCents: 10000,
  ),

  // ---------------------------------------------------------------- declines
  CibcSample(
    label: 'declined: transaction declined at a merchant',
    body: r'A transaction of $89.99 at AMAZON.CA was declined on your CIBC '
        'card ending in 5678.',
    expectedType: TransactionEventType.declined,
    expectedCents: 8999,
    expectedMerchant: 'AMAZON CA',
    expectedLast4: '5678',
  ),
  CibcSample(
    label: 'declined: insufficient funds',
    body: r'Your CIBC card ending in 1234 was declined for $45.00 at ESSO '
        'due to insufficient funds.',
    expectedType: TransactionEventType.declined,
    expectedCents: 4500,
    expectedLast4: '1234',
  ),
  CibcSample(
    label: 'declined: could not be completed',
    body: r'A purchase of $200.00 at CANADIAN TIRE could not be completed '
        'with your CIBC card ending in 9012.',
    expectedType: TransactionEventType.declined,
    expectedCents: 20000,
    expectedMerchant: 'CANADIAN TIRE',
    expectedLast4: '9012',
  ),

  // ----------------------------------------- informational, not a transaction
  CibcSample(
    label: 'unknown: statement ready',
    body: r'Your CIBC Dividend Visa statement is ready. Your statement '
        r'balance is $1,204.55.',
    expectedType: TransactionEventType.unknown,
  ),
  CibcSample(
    label: 'unknown: balance alert',
    body: r'Your available balance is $212.40 on your CIBC Smart Account '
        'ending in 3344.',
    expectedType: TransactionEventType.unknown,
  ),
  CibcSample(
    label: 'unknown: minimum payment due reminder',
    body: r'Your minimum payment of $35.00 is due on Sep 21, 2026 for your '
        'CIBC Visa ending in 1234.',
    expectedType: TransactionEventType.unknown,
  ),
  CibcSample(
    label: 'unknown: one-time security code',
    body: 'Your CIBC verification code is 448210. Do not share it.',
    expectedType: TransactionEventType.unknown,
  ),
  CibcSample(
    label: 'unknown: fraud confirmation prompt',
    body: r'Did you make a $620.00 purchase at NEWEGG with your CIBC card '
        'ending in 5678? Reply YES or NO.',
    expectedType: TransactionEventType.unknown,
  ),

  // ----------------------------------------------------- malformed / partial
  CibcSample(
    label: 'partial: purchase with no merchant',
    body: r'A transaction of $18.40 was made on your CIBC card ending in 1234.',
    expectedType: TransactionEventType.purchase,
    expectedCents: 1840,
    expectedLast4: '1234',
    expectsSpending: true,
  ),
  CibcSample(
    label: 'partial: purchase with no amount',
    body: 'A purchase was made at SHOPPERS DRUG MART with your CIBC card '
        'ending in 1234.',
    expectedType: TransactionEventType.purchase,
    expectedMerchant: 'SHOPPERS DRUG MART',
    expectedLast4: '1234',
  ),
  CibcSample(
    label: 'partial: no card details',
    body: r'You spent $6.99 at SPOTIFY.',
    expectedType: TransactionEventType.purchase,
    expectedCents: 699,
    expectedMerchant: 'SPOTIFY',
    expectsSpending: true,
  ),
  CibcSample(
    label: 'malformed: truncated mid-sentence',
    body: r'A transaction of $',
    expectedType: TransactionEventType.purchase,
  ),
  CibcSample(
    // No whitespace means the merchant cannot be isolated, but the type and
    // the amount are still recoverable — so this correctly books spending
    // with a merchant the user can fill in.
    label: 'malformed: amount glued to surrounding text',
    body: r'CIBC:purchase$14.25atMCDONALDS',
    expectedType: TransactionEventType.purchase,
    expectedCents: 1425,
    expectsSpending: true,
  ),
  CibcSample(
    label: 'malformed: no punctuation, all lower case',
    body: r'cibc you spent $4.10 at coffee culture with your card ending '
        'in 1234',
    expectedType: TransactionEventType.purchase,
    expectedCents: 410,
    expectedMerchant: 'COFFEE CULTURE',
    expectedLast4: '1234',
    expectsSpending: true,
  ),
  CibcSample(
    label: 'malformed: only a dollar amount',
    body: r'$27.00',
    expectedType: TransactionEventType.unknown,
  ),
  CibcSample(
    label: 'malformed: bank name only',
    body: 'CIBC',
    expectedType: TransactionEventType.unknown,
  ),
];
