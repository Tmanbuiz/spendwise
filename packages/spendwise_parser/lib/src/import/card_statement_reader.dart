import '../models/money.dart';
import '../models/transaction_event_type.dart';
import 'statement_reader.dart';

/// Which part of a credit-card statement a row was printed under.
///
/// The section is the strongest signal a card statement gives about what a
/// row means, and it is the one thing the wording often cannot supply: a row
/// reading `PAYMENT THANK YOU/PAIEMENT MERCI` and a row reading
/// `REGULAR PURCHASES` are both unremarkable text, but one is a card payment
/// and the other is an interest charge.
enum CardStatementSection {
  /// Payments made toward the card. Money in, and never spending.
  payments,

  /// Interest charged this period, and any interest reversed.
  interest,

  /// Annual and service fees, when the statement breaks them out.
  fees,

  /// Purchases, cash advances, fees charged inline, and merchant credits.
  charges,

  /// Anything before the first transaction table — the account summary, the
  /// payment slip, the mailing address.
  none,
}

/// Reads a CIBC-style **credit card** statement out of extracted PDF text.
///
/// A card statement is not the same document as the chequing-account
/// statement [TextStatementReader] was built for, and the difference is
/// structural rather than cosmetic:
///
/// * **Every row carries two dates** — the transaction date and the posting
///   date — where an account statement prints one, once per day.
/// * **There is no running balance.** The account reader works out direction
///   from a balance that rose or fell; a card statement offers no such
///   arithmetic, so direction has to come from the section heading and the
///   sign on the amount.
/// * **Rows are grouped under headings** (`Your payments`, `Your interest`,
///   `Your new charges and credits`) that change what an identically worded
///   row means.
///
/// Text extraction flattens the table to one cell per line, so a row arrives
/// as a short run of lines:
///
/// ```
/// Jun 13                                   <- transaction date
/// Jun 16                                   <- posting date
/// WAL-MART SUPERCENTER#1067FREDERICTON  NB <- description
///                                          <- (empty cell)
/// Retail and Grocery                       <- CIBC's own spend category
/// 5.11                                     <- amount
/// ```
///
/// A row is only accepted when that whole sequence appears in order: two
/// plausible dates, then at least one description line, then an amount.
/// Anything that interrupts the sequence discards the part-built row instead
/// of completing it from whatever comes next. Statements are dense with dates
/// and amounts that are not transactions — totals, credit limits, a payment
/// due date sitting beside a minimum payment — and a reader that guesses at
/// those does not merely miss a row, it invents spending that never happened.
abstract final class CardStatementReader {
  /// A line that is nothing but a date, in the forms card statements print:
  /// `Jun 13`, `JUL 15`, `Aug 3, 2026`.
  static final RegExp _bareDate = RegExp(
    r'^([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:,?\s+(\d{4}))?$',
  );

  /// A line that is nothing but an amount. The trailing `***` marks an
  /// interest adjustment excluded from CIBC's own total; it is still a real
  /// movement, so it is kept and the marker dropped.
  static final RegExp _bareMoney = RegExp(
    r'^-?\$?\s?\d{1,3}(?:,\d{3})*\.\d{2}\s*\**$',
  );

  /// The interest-rate column, which sits between description and amount on
  /// the interest table. Not an amount, and not part of the description.
  static final RegExp _percent = RegExp(r'^\d{1,2}(?:\.\d{1,2})?%$');

  /// Lines that are table furniture rather than part of any row.
  static final RegExp _furniture = RegExp(
    r'^(?:trans|post|date|description|amount\s*\(\$\)|'
    r'annual\s+interest\s+rate|spend\s+categories|'
    r'card\s+number\b.*|page|of\s+\d+|\d+|continued|'
    r'\(continued\)|total\b.*)$',
    caseSensitive: false,
  );

  /// CIBC's own spend categories, printed in their own column on cards that
  /// carry one. They are stripped from the description because they are the
  /// bank's classification, not part of the merchant name, and leaving them
  /// in breaks merchant matching against notification-captured transactions.
  ///
  /// Longest first, so `Cash Advances, Balance Transfers, CIBC GMT` is not
  /// half-matched by a shorter entry.
  static const List<String> _spendCategories = <String>[
    'Cash Advances, Balance Transfers, CIBC GMT',
    'Hotel, Entertainment and Recreation',
    'Professional and Financial Services',
    'Personal and Household Expenses',
    'Home and Office Improvement',
    'Foreign Currency Transactions',
    'Health and Education',
    'Other Transactions',
    'Retail and Grocery',
    'Transportation',
    'Restaurants',
  ];

  /// Whether [text] is a credit-card statement rather than an account one.
  ///
  /// Keyed on the two-date column header, because that is the structural
  /// difference this reader exists to handle, with the charges heading as a
  /// second signal for statements whose header extracts differently.
  static bool looksLikeCardStatement(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('new charges and credits')) return true;

    final lines = text
        .split(RegExp(r'\r\n|\r|\n'))
        .map((l) => l.trim().toLowerCase())
        .where((l) => l.isNotEmpty)
        .toList();
    for (var i = 0; i + 3 < lines.length; i++) {
      if (lines[i] == 'trans' &&
          lines[i + 1] == 'date' &&
          lines[i + 2] == 'post' &&
          lines[i + 3] == 'date') {
        return true;
      }
    }
    return false;
  }

  /// Reads [text] extracted from a credit-card statement PDF.
  ///
  /// [year] fills in the year for rows printed as `Jun 13`, which is how card
  /// statements print every row — the year appears only in the page header.
  static StatementImport read(
    String text, {
    String currency = 'CAD',
    int? year,
  }) {
    final lines = text.split(RegExp(r'\r\n|\r|\n'));
    final anchorYear = year ?? _inferYear(text) ?? DateTime.now().year;
    final stripCategories =
        RegExp(r'spend\s+categories', caseSensitive: false).hasMatch(text);

    final rows = <StatementRow>[];
    final problems = <StatementProblem>[];

    var section = CardStatementSection.none;
    DateTime? transDate;
    DateTime? postDate;
    var descriptions = <String>[];
    var recordLine = 0;

    // What the statement says each section adds up to, and what was actually
    // read for it. A statement that totals itself can be checked against the
    // parse, which is the only independent evidence available that the
    // reading is right.
    final declared = <String, int>{};
    final readTotals = <String, int>{};
    String? awaitingTotalFor;

    void discard() {
      transDate = null;
      postDate = null;
      descriptions = <String>[];
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // A section total is the statement checking its own arithmetic, and it
      // is caught before the furniture rule below swallows it. The figure
      // itself follows on a later line — "Total for" is separated from its
      // amount by the card number — so the label only arms the capture.
      final totalLabel = _totalLabelOf(line);
      if (totalLabel != null) {
        discard();
        awaitingTotalFor = totalLabel;
        continue;
      }

      final heading = _sectionOf(line);
      if (heading != null) {
        discard();
        awaitingTotalFor = null;
        section = heading;
        continue;
      }

      // The spend report on the last page restates the same transactions as
      // category totals. Reading past it would count every purchase twice.
      if (_endsTransactions(line)) {
        discard();
        section = CardStatementSection.none;
        continue;
      }

      if (section == CardStatementSection.none) continue;

      final date = _parseDate(line, anchorYear);
      if (date != null) {
        if (transDate == null) {
          transDate = date;
          recordLine = i + 1;
        } else if (postDate == null && descriptions.isEmpty) {
          // A posting date is the same transaction settling, so it follows
          // within days. A date further out is the start of a new row whose
          // predecessor never completed.
          final gap = date.difference(transDate!).inDays;
          if (gap >= 0 && gap <= 31) {
            postDate = date;
          } else {
            transDate = date;
            recordLine = i + 1;
          }
        } else {
          discard();
          transDate = date;
          recordLine = i + 1;
        }
        continue;
      }

      if (_bareMoney.hasMatch(line)) {
        if (awaitingTotalFor != null) {
          final cents = _parseCents(line);
          if (cents != null) {
            // Added rather than assigned, because a statement covering more
            // than one card prints "Total for <card>" once per card. Taking
            // only the last left the check comparing every row against one
            // card's subtotal, which rejected a correct parse of a statement
            // whose second card carried a single $6.29 purchase.
            final key = awaitingTotalFor;
            declared[key] = (declared[key] ?? 0) + cents.abs();
          }
          awaitingTotalFor = null;
          discard();
          continue;
        }
        if (transDate == null || postDate == null || descriptions.isEmpty) {
          // An amount with no row above it is a total or a summary figure.
          discard();
          continue;
        }
        final cents = _parseCents(line);
        if (cents == null || cents == 0) {
          problems.add(StatementProblem(i + 1, 'Unreadable amount', line));
          discard();
          continue;
        }

        final description = _cleanDescription(descriptions, stripCategories);
        if (description.isEmpty) {
          problems.add(
            StatementProblem(recordLine, 'No description found', line),
          );
          discard();
          continue;
        }

        rows.add(StatementRow(
          date: transDate!,
          description: _label(section, description),
          amount: Money(cents.abs(), currency),
          eventType: _classify(description, cents, section),
          lineNumber: recordLine,
        ));

        // Accumulate against the section's own total. Credits are subtracted
        // because the statement's section total is a net figure: a cash-back
        // credit reduces what the card charged that month.
        //
        // A trailing `***` marks an interest adjustment that CIBC states it
        // excludes from "Total interest this period". The row is still a real
        // movement and is kept, but counting it here would make the check
        // disagree with the statement by exactly the adjustment — which is
        // the parse being right and the check being wrong.
        final key = _totalKeyOf(section);
        if (key != null && !line.contains('*')) {
          readTotals[key] = (readTotals[key] ?? 0) + cents;
        }

        discard();
        continue;
      }

      if (_percent.hasMatch(line)) continue;
      if (_furniture.hasMatch(line)) continue;

      // A description only belongs to a row whose two dates have both been
      // seen. Text arriving at any other moment is page furniture, legal
      // small print, or an address.
      if (transDate != null && postDate != null) descriptions.add(line);
    }

    return StatementImport(
      rows: rows,
      problems: problems,
      layout: null,
      signConvention: AmountSign.debitCreditColumns,
      checks: <StatementCheck>[
        for (final entry in declared.entries)
          StatementCheck(
            label: _totalNames[entry.key] ?? entry.key,
            declaredCents: entry.value,
            // A section the statement totalled but where nothing was read is
            // the most important case to report, not to skip: it is exactly
            // what a whole missing section looks like.
            readCents: (readTotals[entry.key] ?? 0).abs(),
          ),
      ],
    );
  }

  /// Section totals the statement prints about itself.
  static const Map<String, String> _totalNames = <String, String>{
    'payments': 'Total payments',
    'interest': 'Total interest',
    'fees': 'Total fees',
    'charges': 'Total charges and credits',
  };

  /// Recognises a line that labels a section total, returning which section.
  ///
  /// Anchored at the start so a sentence merely containing the word "total" —
  /// the legal small print is full of them — is not mistaken for one.
  static String? _totalLabelOf(String line) {
    final text = line.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!text.startsWith('total')) return null;
    if (text.startsWith('total payments')) return 'payments';
    if (text.startsWith('total interest')) return 'interest';
    if (text.startsWith('total fees')) return 'fees';
    if (text.startsWith('total for')) return 'charges';
    return null;
  }

  /// Which running total a row read in [section] contributes to.
  static String? _totalKeyOf(CardStatementSection section) {
    switch (section) {
      case CardStatementSection.payments:
        return 'payments';
      case CardStatementSection.interest:
        return 'interest';
      case CardStatementSection.fees:
        return 'fees';
      case CardStatementSection.charges:
        return 'charges';
      case CardStatementSection.none:
        return null;
    }
  }

  static CardStatementSection? _sectionOf(String line) {
    final text = line.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.startsWith('your payments')) return CardStatementSection.payments;
    if (text.startsWith('your interest')) return CardStatementSection.interest;
    if (text.startsWith('your fees')) return CardStatementSection.fees;
    if (text.startsWith('your new charges and credits')) {
      return CardStatementSection.charges;
    }
    return null;
  }

  static bool _endsTransactions(String line) {
    final text = line.toLowerCase();
    return text.contains('spend report') ||
        text.contains('creditsmart') ||
        text.startsWith('your message centre');
  }

  /// Joins the collected cells and removes CIBC's own category column.
  static String _cleanDescription(
    List<String> descriptions,
    bool stripCategories,
  ) {
    var text =
        descriptions.join(' ').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    if (stripCategories) {
      for (final category in _spendCategories) {
        if (text.length > category.length && text.endsWith(category)) {
          text = text.substring(0, text.length - category.length).trim();
          break;
        }
      }
    }

    // The cash-back multiplier marker is a symbol in the margin, not text.
    return text.replaceAll(RegExp(r'^[^A-Za-z0-9]+'), '').trim();
  }

  /// Interest and fee rows describe a charge, not a merchant. Saying so keeps
  /// a row reading `REGULAR PURCHASES` from looking like a shop.
  static String _label(CardStatementSection section, String description) {
    return switch (section) {
      CardStatementSection.interest => 'Interest — $description',
      CardStatementSection.fees => 'Fee — $description',
      _ => description,
    };
  }

  /// Works out what a row means from its section first, then its sign, then
  /// its wording.
  ///
  /// Section beats wording because the heading is the bank's own statement of
  /// what the table holds. Sign beats wording because a card statement prints
  /// a credit as a negative amount and frequently gives it no explanatory
  /// text at all — `CREDIT  TORONTO  ON  -90.75` is money returned, and
  /// nothing but the minus sign says so.
  static TransactionEventType _classify(
    String description,
    int cents,
    CardStatementSection section,
  ) {
    if (section == CardStatementSection.payments) {
      return TransactionEventType.payment;
    }

    // Negative on a card statement is money coming back, in every section.
    if (cents < 0) return TransactionEventType.refund;

    if (section == CardStatementSection.interest ||
        section == CardStatementSection.fees) {
      return TransactionEventType.purchase;
    }

    final text = description.toLowerCase();

    if (text.contains('refund') ||
        text.contains('reversal') ||
        RegExp(r'\breturn\b').hasMatch(text)) {
      return TransactionEventType.refund;
    }

    if (text.contains('payment') &&
        (text.contains('thank you') ||
            text.contains('merci') ||
            text.contains('received'))) {
      return TransactionEventType.payment;
    }

    // A cash advance hands the cardholder their own credit as cash. Nothing
    // has been bought yet, and counting it would double up against whatever
    // that cash is then spent on. The fee charged for taking it is a real
    // cost, so it stays a purchase.
    final isFee = text.contains('fee');
    if (!isFee &&
        (text.contains('cash advance') ||
            text.contains('avance de fonds') ||
            text.contains('balance transfer'))) {
      return TransactionEventType.transfer;
    }

    return TransactionEventType.purchase;
  }

  static const Map<String, int> _months = <String, int>{
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static DateTime? _parseDate(String raw, int fallbackYear) {
    final match = _bareDate.firstMatch(raw.trim());
    if (match == null) return null;
    final month = _months[match.group(1)!.toLowerCase().substring(0, 3)];
    if (month == null) return null;
    final day = int.parse(match.group(2)!);
    final year =
        match.group(3) == null ? fallbackYear : int.parse(match.group(3)!);
    if (year < 1970 || year > 2999) return null;
    if (day < 1 || day > 31) return null;
    final probe = DateTime(year, month, day);
    if (probe.month != month || probe.day != day) return null;
    return probe;
  }

  /// Finds the statement year in the page header, so rows printed as `Jun 13`
  /// can be dated.
  static int? _inferYear(String text) {
    final match = RegExp(r'\b(20\d{2})\b').firstMatch(text);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    if (year < 2000 || year > DateTime.now().year + 1) return null;
    return year;
  }

  static int? _parseCents(String raw) {
    var text = raw.trim().replaceAll('*', '').trim();
    var negative = false;
    if (text.startsWith('-')) {
      negative = true;
      text = text.substring(1);
    }
    text = text.replaceAll(RegExp(r'[$,\s]'), '');
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value.isNaN || value.isInfinite) return null;
    final cents = (value * 100).round();
    return negative ? -cents : cents;
  }
}
