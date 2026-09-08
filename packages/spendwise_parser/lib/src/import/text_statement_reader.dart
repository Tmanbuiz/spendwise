import '../models/money.dart';
import '../models/transaction_event_type.dart';
import 'card_statement_reader.dart';
import 'statement_reader.dart';
import 'statement_splitter.dart';

/// Reads transactions out of statement *text*, as extracted from a PDF.
///
/// A PDF has no columns — only glyphs at coordinates. Text extraction flattens
/// that into lines where the former columns are separated by runs of spaces,
/// and any structure has to be inferred back. That makes this fundamentally
/// less reliable than [StatementReader] over a CSV, which is why the UI
/// recommends CSV first and always shows a preview before importing.
///
/// The approach is deliberately conservative: a line is only treated as a
/// transaction when it contains **both** a date and a money amount. Anything
/// else — headers, totals, addresses, page furniture — is ignored rather than
/// guessed at, because a wrong guess silently invents spending.
abstract final class TextStatementReader {
  /// A date at the start of a line, in the forms Canadian statements use.
  static final RegExp _leadingDate = RegExp(
    r'^\s*('
    r'\d{4}-\d{1,2}-\d{1,2}'
    r'|\d{1,2}/\d{1,2}/\d{2,4}'
    r'|[A-Za-z]{3,9}\.?\s+\d{1,2}(?:,?\s+\d{4})?'
    r'|\d{1,2}\s+[A-Za-z]{3,9}\.?(?:,?\s+\d{4})?'
    r')\b',
  );

  /// Money at the end of a line, optionally negative or bracketed.
  ///
  /// Anchored to the end because statement rows put the amount last; matching
  /// anywhere would pick up account numbers and running balances.
  static final RegExp _trailingMoney = RegExp(
    r'(\(?-?\$?\s?\d{1,3}(?:,\d{3})*\.\d{2}\)?-?)\s*$',
  );

  /// A second amount before the last one — the running balance on statements
  /// that show one. The transaction amount is the *first* of the pair.
  static final RegExp _twoTrailingAmounts = RegExp(
    r'(\(?-?\$?\s?\d{1,3}(?:,\d{3})*\.\d{2}\)?-?)\s+'
    r'(\(?-?\$?\s?\d{1,3}(?:,\d{3})*\.\d{2}\)?-?)\s*$',
  );

  /// A statement numbers its own pages, so "Page 1 of N" appears exactly once
  /// in a single document and once per statement in a merged one. That makes
  /// it a more reliable boundary than any bank's wording, which differs per
  /// product and changes without notice.
  static final RegExp _firstPageMarker =
      RegExp(r'page\s+1\s+of\s+\d+', caseSensitive: false);

  /// How many separate statements [text] appears to hold.
  ///
  /// Zero means the marker was not found at all — some statements are a single
  /// page and never number themselves — which is treated as one document
  /// rather than as an error.
  static int statementCount(String text) =>
      _firstPageMarker.allMatches(text).length;

  /// Lines that are never transactions, however they are shaped.
  static final RegExp _furniture = RegExp(
    r'^\s*(?:page\s+\d|opening\s+balance|closing\s+balance|'
    r'balance\s+forward|previous\s+balance|total|subtotal|'
    r'statement\s+period|account\s+number|minimum\s+payment|'
    r'credit\s+limit|available\s+credit|payment\s+due)',
    caseSensitive: false,
  );

  /// Reads [text] extracted from a PDF statement.
  ///
  /// [year] fills in a year for statements that print only "Sep 4" — most do,
  /// because the year is in the page header rather than on each row.
  ///
  /// A credit-card statement is recognised first and read on its own terms.
  /// Its rows carry two dates and no running balance, and their meaning
  /// depends on the section heading above them, so neither pass below can
  /// read one correctly — and both fail in the dangerous direction, matching
  /// stray dates and totals in the account summary into transactions that
  /// were never made.
  ///
  /// Otherwise two layouts are tried, because PDF extractors disagree about
  /// how to flatten a table. Some keep a row on one line; others emit **one
  /// cell per line**, which is what CIBC's account statement produces. The
  /// row-per-line pass runs first because it is stricter; the cell-per-line
  /// pass is the fallback.
  static StatementImport read(
    String text, {
    String currency = 'CAD',
    int? year,
    AmountSign? signOverride,
  }) {
    // Several statements in one file are read one at a time, never as a
    // single document. Read whole, the failure is silent: one layout is
    // chosen for the entire file, a statement's running balance carries into
    // the next, and every date resolves against one inferred year. Measured
    // against a statement read on its own, a real merged file lost 36 of its
    // 39 transactions and misreported the 3 that survived — while reporting
    // success.
    //
    // Splitting is only safe because each segment is then checked against the
    // totals its own statement prints. A segment that does not reproduce them
    // is left out rather than imported, so a bad cut surfaces as a stated
    // refusal instead of as plausible-looking numbers.
    final segments = StatementSplitter.split(text);
    if (segments.length > 1) {
      return _readSegments(
        segments,
        currency: currency,
        year: year,
        signOverride: signOverride,
      );
    }

    return _readOne(
      text,
      currency: currency,
      year: year,
      signOverride: signOverride,
    );
  }

  /// Reads one statement, choosing the layout that fits it.
  static StatementImport _readOne(
    String text, {
    required String currency,
    int? year,
    AmountSign? signOverride,
  }) {
    if (CardStatementReader.looksLikeCardStatement(text)) {
      return CardStatementReader.read(text, currency: currency, year: year);
    }

    final byRow = _readRowPerLine(
      text,
      currency: currency,
      year: year,
      signOverride: signOverride,
    );
    if (byRow.rows.isNotEmpty) return byRow;

    final byCell = _readCellPerLine(text, currency: currency, year: year);
    if (byCell.rows.isNotEmpty) return byCell;

    // Neither layout produced rows. Return whichever pass actually diagnosed
    // something, so the user is told *why* nothing was read rather than being
    // shown a silent empty result.
    return byRow.problems.isNotEmpty ? byRow : byCell;
  }

  /// Reads each statement in a merged file on its own terms and keeps the ones
  /// that hold up.
  ///
  /// A statement that prints totals must reproduce them to be accepted. One
  /// that prints none cannot be checked, so it is accepted on the same footing
  /// as if it had been imported by itself — no worse, and no better.
  static StatementImport _readSegments(
    List<String> segments, {
    required String currency,
    int? year,
    AmountSign? signOverride,
  }) {
    final rows = <StatementRow>[];
    final problems = <StatementProblem>[];
    final checks = <StatementCheck>[];
    var accepted = 0;

    for (var i = 0; i < segments.length; i++) {
      final one = _readOne(
        segments[i],
        currency: currency,
        year: year,
        signOverride: signOverride,
      );

      if (one.rows.isEmpty) {
        // A cover page or a segment holding no table. Nothing to import and
        // nothing wrong; saying so would only be noise.
        continue;
      }

      if (one.checks.isNotEmpty && !one.verified) {
        final failed = one.failedChecks
            .map((c) => '${c.label} reads '
                '${_money(c.readCents)} but the statement says '
                '${_money(c.declaredCents)}')
            .join('; ');
        problems.add(
          StatementProblem(
            i + 1,
            'Statement ${i + 1} of ${segments.length} does not match its own '
            'totals and was left out — $failed',
            '',
          ),
        );
        continue;
      }

      rows.addAll(one.rows);
      problems.addAll(one.problems);
      checks.addAll(one.checks);
      accepted++;
    }

    if (accepted == 0 && problems.isEmpty) {
      problems.add(
        StatementProblem(
          1,
          'This file holds ${segments.length} statements but no transactions '
          'could be read from any of them.',
          '',
        ),
      );
    }

    return StatementImport(
      rows: rows,
      problems: problems,
      layout: null,
      signConvention: signOverride ?? AmountSign.debitCreditColumns,
      checks: checks,
    );
  }

  static String _money(int cents) =>
      '\$${(cents / 100).toStringAsFixed(2)}';

  static StatementImport _readRowPerLine(
    String text, {
    required String currency,
    int? year,
    AmountSign? signOverride,
  }) {
    final lines = text.split(RegExp(r'\r\n|\r|\n'));
    final rows = <StatementRow>[];
    final problems = <StatementProblem>[];
    final inferredYear = year ?? _inferYear(text) ?? DateTime.now().year;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      if (_furniture.hasMatch(line)) continue;

      final dateMatch = _leadingDate.firstMatch(line);
      if (dateMatch == null) continue;

      final moneyMatch = _twoTrailingAmounts.firstMatch(line) ??
          _trailingMoney.firstMatch(line);
      if (moneyMatch == null) continue;

      final date = _parseDate(dateMatch.group(1)!, inferredYear);
      if (date == null) {
        problems.add(StatementProblem(i + 1, 'Unreadable date', line.trim()));
        continue;
      }

      final amountText = moneyMatch.group(1)!;
      final cents = _parseCents(amountText);
      if (cents == null || cents == 0) {
        problems.add(StatementProblem(i + 1, 'Unreadable amount', line.trim()));
        continue;
      }

      final description = line
          .substring(dateMatch.end, moneyMatch.start)
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();

      if (description.isEmpty) {
        problems.add(
          StatementProblem(i + 1, 'No description found', line.trim()),
        );
        continue;
      }

      rows.add(StatementRow(
        date: date,
        description: description,
        amount: Money(cents.abs(), currency),
        eventType: _classify(description, cents, signOverride),
        lineNumber: i + 1,
      ));
    }

    return StatementImport(
      rows: rows,
      problems: problems,
      layout: null,
      signConvention: signOverride ?? AmountSign.negativeIsSpending,
    );
  }

  /// A line that is nothing but a date, e.g. `Aug 3`.
  static final RegExp _bareDate = RegExp(
    r'^\s*('
    r'\d{4}-\d{1,2}-\d{1,2}'
    r'|\d{1,2}/\d{1,2}/\d{2,4}'
    r'|[A-Za-z]{3,9}\.?\s+\d{1,2}(?:,?\s+\d{4})?'
    r'|\d{1,2}\s+[A-Za-z]{3,9}\.?(?:,?\s+\d{4})?'
    r')\s*$',
  );

  /// A line that is nothing but a money amount.
  static final RegExp _bareMoney = RegExp(
    r'^\s*\(?-?\$?\s?-?\d{1,3}(?:,\d{3})*\.\d{2}\)?-?\s*$',
  );

  /// Where the transaction table starts. Anything above it — the account
  /// summary — contains totals that would otherwise be read as transactions.
  static final RegExp _tableStart =
      RegExp(r'transaction\s+details', caseSensitive: false);

  /// Column headings and page-break markers, which repeat on every page of a
  /// multi-page statement and are not part of any description.
  /// Labels whose following number restates the running balance instead of
  /// recording money moving.
  ///
  /// Kept separate from [_repeatedFurniture] because dropping the label is not
  /// enough: the number underneath it has to be consumed too, or it pairs with
  /// the next transaction and is published as that transaction's amount.
  static final RegExp _balanceCarry = RegExp(
    r'^(?:balance\s+forward|opening\s+balance|closing\s+balance|'
    r'balance\s+brought\s+forward)\b',
    caseSensitive: false,
  );

  static final RegExp _repeatedFurniture = RegExp(
    r'^(?:date|description|withdrawals?(?:\s*\(\$\))?|'
    r'deposits?(?:\s*\(\$\))?|balance(?:\s*\(\$\))?|'
    r'balance\s+forward|continued(?:\s+on\s+next\s+page)?|'
    r'transaction\s+details|opening\s+balance|closing\s+balance|'
    r'page\s+\d+(?:\s+of\s+\d+)?)$',
    caseSensitive: false,
  );

  /// Reads the layout where each table cell lands on its own line.
  ///
  /// CIBC's account statement extracts like this:
  ///
  /// ```
  /// Aug 3
  /// E-TRANSFER        106056182358
  /// Tolulope
  /// 100.00
  /// -102.38
  /// ```
  ///
  /// Two things make this harder than it looks. The date is printed **once per
  /// day**, so later transactions on the same day inherit it. And withdrawals
  /// and deposits are separate columns whose empty cells simply vanish, so the
  /// amount's position cannot say which it was.
  ///
  /// The running balance settles it: a balance that fell is money out, one
  /// that rose is money in. That is derived from the statement's own arithmetic
  /// rather than guessed from wording, which makes it the most trustworthy
  /// signal available here.
  static StatementImport _readCellPerLine(
    String text, {
    required String currency,
    int? year,
  }) {
    final all = text.split(RegExp(r'\r\n|\r|\n'));
    final inferredYear = year ?? _inferYear(text) ?? DateTime.now().year;

    var start = all.indexWhere(_tableStart.hasMatch);
    if (start < 0) start = 0;

    final rows = <StatementRow>[];
    final problems = <StatementProblem>[];

    DateTime? currentDate;
    int? previousBalance;

    /// Set when a balance-carry label has been seen and the number that
    /// follows it belongs to the running balance rather than to a
    /// transaction.
    var expectingCarriedBalance = false;
    var descriptions = <String>[];
    var numbers = <int>[];
    var recordLine = 0;

    void reset() {
      descriptions = <String>[];
      numbers = <int>[];
    }

    void flush() {
      if (numbers.isEmpty) {
        reset();
        return;
      }

      // A single number is a balance line — the opening balance. It sets the
      // baseline the first real transaction is measured against.
      if (numbers.length == 1) {
        previousBalance = numbers.first;
        reset();
        return;
      }

      final amount = numbers[numbers.length - 2].abs();
      final balance = numbers.last;
      final description = descriptions
          .join(' ')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();

      if (currentDate == null || amount == 0 || description.isEmpty) {
        previousBalance = balance;
        reset();
        return;
      }

      // Balance fell means money left the account.
      final outward = previousBalance == null
          ? true
          : balance < previousBalance!;

      rows.add(StatementRow(
        date: currentDate,
        description: description,
        amount: Money(amount, currency),
        eventType: outward
            ? _outwardType(description)
            : _inwardType(description),
        lineNumber: recordLine,
      ));

      previousBalance = balance;
      reset();
    }

    for (var i = start; i < all.length; i++) {
      final line = all[i].trim();
      if (line.isEmpty) continue;

      if (_bareDate.hasMatch(line)) {
        flush();
        final parsed = _parseDate(line, inferredYear);
        if (parsed == null) {
          problems.add(StatementProblem(i + 1, 'Unreadable date', line));
        } else {
          currentDate = parsed;
        }
        recordLine = i + 1;
        continue;
      }

      if (_bareMoney.hasMatch(line)) {
        final cents = _parseCents(line);

        // A carried balance is a running total, not money that moved. Taking
        // it as an amount would both invent a transaction and, worse, leave
        // the number in the buffer for the next row to pair against — so
        // every row after it reports the row before it. See [_balanceCarry].
        if (expectingCarriedBalance) {
          expectingCarriedBalance = false;
          if (cents != null) previousBalance = cents;
          continue;
        }

        if (cents != null) numbers.add(cents);
        // Amount then balance completes a row.
        if (numbers.length >= 2) flush();
        continue;
      }

      // A statement page break restates the running balance:
      //
      //     Balance forward
      //     $79.62
      //     PREAUTHORIZED DEBIT
      //     100.00
      //
      // The label is dropped as furniture below, but its number is not, and a
      // lone number never completes a record — so it sat in the buffer and
      // paired with the next transaction's amount, publishing $79.62 as that
      // transaction's value. The shift then persisted until the next date
      // line happened to flush it, which is why whole same-day runs came out
      // as the balances of the rows above them.
      if (_balanceCarry.hasMatch(line)) {
        flush();
        expectingCarriedBalance = true;
        continue;
      }

      // Page-break markers and column headings repeat throughout a multi-page
      // statement. Left in, they get glued onto the next transaction's
      // description — "Balance forward PREAUTHORIZED DEBIT ..." — which then
      // breaks merchant matching and categorisation.
      if (_repeatedFurniture.hasMatch(line)) continue;

      if (descriptions.isEmpty) recordLine = i + 1;
      descriptions.add(line);
    }

    flush();

    return StatementImport(
      rows: rows,
      problems: problems,
      layout: null,
      signConvention: AmountSign.debitCreditColumns,
    );
  }

  /// Money out. Wording can still override it — a card payment is money out
  /// of a chequing account but is not spending.
  static TransactionEventType _outwardType(String description) {
    final text = description.toLowerCase();

    // Paying down a card moves debt, it does not create new spending — and
    // the purchases on that card were already counted when they happened.
    if (RegExp(r'\bto\s+card\b').hasMatch(text) ||
        (text.contains('payment') &&
            (text.contains('card') ||
                text.contains('visa') ||
                text.contains('mastercard')))) {
      return TransactionEventType.payment;
    }

    // Money moved into the user's own investment or savings account is still
    // theirs. Counting a contribution as spending would tell someone they
    // overspent in the month they saved most.
    if (text.contains('investment') ||
        text.contains('securities') ||
        text.contains('brokerage') ||
        RegExp(r'\b(?:rrsp|tfsa|resp|fhsa)\b').hasMatch(text)) {
      return TransactionEventType.transfer;
    }

    if (text.contains('e-transfer') ||
        text.contains('etransfer') ||
        text.contains('transfer')) {
      return TransactionEventType.transfer;
    }

    return TransactionEventType.purchase;
  }

  /// Money in is never spending.
  static TransactionEventType _inwardType(String description) {
    final text = description.toLowerCase();
    if (text.contains('refund') ||
        text.contains('reversal') ||
        RegExp(r'\breturn\b').hasMatch(text)) {
      return TransactionEventType.refund;
    }
    return TransactionEventType.transfer;
  }

  /// Decides direction from the description first, sign second.
  ///
  /// PDF statements usually do not sign the amount at all — a credit is marked
  /// with wording like "PAYMENT - THANK YOU" or a trailing `CR`. So wording is
  /// the stronger signal here, the opposite of a CSV.
  static TransactionEventType _classify(
    String description,
    int cents,
    AmountSign? sign,
  ) {
    final text = description.toLowerCase();

    if (text.contains('refund') ||
        text.contains('reversal') ||
        RegExp(r'\breturn\b').hasMatch(text)) {
      return TransactionEventType.refund;
    }
    if (text.contains('payment') &&
        (text.contains('thank you') || text.contains('received'))) {
      return TransactionEventType.payment;
    }
    if (text.contains('e-transfer') ||
        text.contains('etransfer') ||
        text.contains('transfer') ||
        text.contains('deposit')) {
      return TransactionEventType.transfer;
    }
    // A trailing CR marks a credit on many statements.
    if (RegExp(r'\bcr\b').hasMatch(text)) {
      return TransactionEventType.transfer;
    }

    if (sign == AmountSign.positiveIsSpending) {
      return cents > 0
          ? TransactionEventType.purchase
          : TransactionEventType.transfer;
    }
    if (cents < 0) return TransactionEventType.purchase;
    return TransactionEventType.purchase;
  }

  /// Finds a four-digit year in the page header, so rows printed as "Sep 4"
  /// can be dated correctly.
  static int? _inferYear(String text) {
    final match = RegExp(r'\b(20\d{2})\b').firstMatch(text);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    if (year < 2000 || year > DateTime.now().year + 1) return null;
    return year;
  }

  static const Map<String, int> _months = <String, int>{
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static DateTime? _parseDate(String raw, int fallbackYear) {
    final text = raw.trim();

    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text);
    if (iso != null) {
      return _build(int.parse(iso.group(1)!), int.parse(iso.group(2)!),
          int.parse(iso.group(3)!));
    }

    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$').firstMatch(text);
    if (slash != null) {
      var first = int.parse(slash.group(1)!);
      var second = int.parse(slash.group(2)!);
      final rawYear = int.parse(slash.group(3)!);
      if (first > 12 && second <= 12) {
        final swap = first;
        first = second;
        second = swap;
      }
      return _build(rawYear < 100 ? 2000 + rawYear : rawYear, first, second);
    }

    // "Sep 4" / "Sep 4, 2026"
    final monthFirst =
        RegExp(r'^([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:,?\s+(\d{4}))?$')
            .firstMatch(text);
    if (monthFirst != null) {
      final month = _months[monthFirst.group(1)!.toLowerCase().substring(0, 3)];
      if (month == null) return null;
      return _build(
        monthFirst.group(3) == null
            ? fallbackYear
            : int.parse(monthFirst.group(3)!),
        month,
        int.parse(monthFirst.group(2)!),
      );
    }

    // "4 Sep" / "4 Sep 2026"
    final dayFirst =
        RegExp(r'^(\d{1,2})\s+([A-Za-z]{3,9})\.?(?:,?\s+(\d{4}))?$')
            .firstMatch(text);
    if (dayFirst != null) {
      final month = _months[dayFirst.group(2)!.toLowerCase().substring(0, 3)];
      if (month == null) return null;
      return _build(
        dayFirst.group(3) == null
            ? fallbackYear
            : int.parse(dayFirst.group(3)!),
        month,
        int.parse(dayFirst.group(1)!),
      );
    }

    return null;
  }

  static DateTime? _build(int year, int month, int day) {
    if (year < 1970 || year > 2999) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final probe = DateTime(year, month, day);
    if (probe.month != month || probe.day != day) return null;
    return probe;
  }

  static int? _parseCents(String raw) {
    var text = raw.trim();
    var negative = false;

    if (text.startsWith('(') && text.endsWith(')')) {
      negative = true;
      text = text.substring(1, text.length - 1);
    }
    if (text.endsWith('-')) {
      negative = true;
      text = text.substring(0, text.length - 1);
    }
    text = text.replaceAll(RegExp(r'[$,\s]'), '');
    if (text.startsWith('-')) {
      negative = true;
      text = text.substring(1);
    }
    if (text.isEmpty) return null;

    final value = double.tryParse(text);
    if (value == null || value.isNaN || value.isInfinite) return null;
    final cents = (value * 100).round();
    return negative ? -cents : cents;
  }
}
