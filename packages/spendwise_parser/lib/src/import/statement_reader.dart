import '../models/money.dart';
import '../models/transaction_direction.dart';
import '../models/transaction_event_type.dart';
import '../util/merchant_cleaner.dart';
import 'csv_reader.dart';

/// One line of a bank statement, already interpreted.
class StatementRow {
  const StatementRow({
    required this.date,
    required this.description,
    required this.amount,
    required this.eventType,
    required this.lineNumber,
    TransactionDirection? direction,
  }) : _direction = direction;

  final TransactionDirection? _direction;

  final DateTime date;
  final String description;

  /// Always positive. Direction is carried by [eventType], matching the rest
  /// of the app.
  final Money amount;

  final TransactionEventType eventType;

  /// Which way the money moved.
  ///
  /// A reader that can see the running balance knows this for certain and
  /// passes it in. One that cannot falls back to what the event type implies,
  /// which never counts an unknown transfer as money coming in.
  TransactionDirection get direction =>
      _direction ??
      TransactionDirection.infer(
        type: eventType,
        description: description,
      );

  /// 1-based line in the source file, so a rejected row can be pointed at.
  final int lineNumber;

  String? get merchantNormalized => MerchantExtractor.normalize(description);

  bool get countsAsSpending => eventType.countsAsSpending;
}

/// A line that could not be read, and why.
class StatementProblem {
  const StatementProblem(this.lineNumber, this.reason, this.raw);

  final int lineNumber;
  final String reason;
  final String raw;
}

/// How the file's columns were understood.
class StatementLayout {
  const StatementLayout({
    required this.dateColumn,
    required this.descriptionColumn,
    this.amountColumn,
    this.debitColumn,
    this.creditColumn,
    this.hasHeader = false,
    this.headers = const <String>[],
  });

  final int dateColumn;
  final int descriptionColumn;

  /// A single signed amount column, when the file uses one.
  final int? amountColumn;

  /// Separate money-out / money-in columns, which is what CIBC exports.
  final int? debitColumn;
  final int? creditColumn;

  final bool hasHeader;
  final List<String> headers;

  bool get usesDebitCredit => debitColumn != null || creditColumn != null;
  bool get isUsable => dateColumn >= 0 && (amountColumn != null || usesDebitCredit);
}

/// A figure the statement states about itself, measured against what was read.
///
/// Statements total their own sections — "Total payments $900.00". Those
/// figures are the only independent check available on a parse: if the rows
/// do not add up to what the statement itself says, the reading is wrong,
/// whatever it looks like. Every import bug found so far — a running balance
/// read as an amount, a merged file losing 36 of 39 rows — was silent, and
/// each one would have failed a check like this immediately.
class StatementCheck {
  const StatementCheck({
    required this.label,
    required this.declaredCents,
    required this.readCents,
  });

  /// What the statement calls this figure, shown to the user as-is.
  final String label;

  /// The total the statement prints.
  final int declaredCents;

  /// The total of the rows actually read for it.
  final int readCents;

  int get differenceCents => readCents - declaredCents;

  bool get agrees => differenceCents == 0;
}

/// The outcome of reading a statement file.
class StatementImport {
  const StatementImport({
    required this.rows,
    required this.problems,
    required this.layout,
    required this.signConvention,
    this.checks = const <StatementCheck>[],
  });

  final List<StatementRow> rows;
  final List<StatementProblem> problems;
  final StatementLayout? layout;

  /// What the statement said about itself, and whether the parse matches.
  final List<StatementCheck> checks;

  /// Every figure the statement states about itself was reproduced exactly.
  ///
  /// False when a check disagrees *and* when there was nothing to check
  /// against — see [unverifiable]. A caller that treats "not verified" as
  /// "broken" would reject formats that simply print no totals, so the two
  /// cases are kept apart.
  bool get verified =>
      checks.isNotEmpty && checks.every((check) => check.agrees);

  /// The statement offered no total to check the parse against.
  bool get unverifiable => checks.isEmpty;

  /// The checks that did not reproduce.
  List<StatementCheck> get failedChecks =>
      checks.where((check) => !check.agrees).toList();

  /// Which sign meant "money out" in a single-amount file.
  final AmountSign signConvention;

  bool get isEmpty => rows.isEmpty;

  int get spendingTotalCents => rows
      .where((r) => r.countsAsSpending)
      .fold<int>(0, (sum, r) => sum + r.amount.cents);
}

/// Which sign a single-amount column uses for money leaving the account.
///
/// Banks disagree, and guessing wrong turns every deposit into spending. The
/// reader picks the likelier reading and the UI shows a preview so the user
/// can flip it before anything is stored.
enum AmountSign {
  /// `-45.67` means money out. Most common.
  negativeIsSpending,

  /// `45.67` means money out, deposits are negative.
  positiveIsSpending,

  /// Not applicable: the file has separate debit and credit columns.
  debitCreditColumns,
}

/// Reads a bank statement CSV into transactions.
///
/// Deliberately format-agnostic. Every Canadian bank exports something
/// different — CIBC ships headerless rows with separate debit and credit
/// columns, others ship a header and one signed amount — and the formats
/// change without notice. Rather than hard-coding per-bank layouts that would
/// silently break, this detects the layout and reports what it decided so the
/// user can correct it.
abstract final class StatementReader {
  static final RegExp _isoDate = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');
  static final RegExp _slashDate = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$');
  static final RegExp _textDate = RegExp(
    r'^(\d{1,2})\s+([A-Za-z]{3,9})\.?\s+(\d{4})$|'
    r'^([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})$',
  );
  static final RegExp _money = RegExp(r'^\(?-?[$€£]?\s?-?[\d,]+(?:\.\d{1,2})?\)?$');

  static const Map<String, int> _months = <String, int>{
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Reads [content], detecting layout automatically.
  ///
  /// [signOverride] forces the money-out convention when the user corrects it
  /// from the preview.
  static StatementImport read(
    String content, {
    String currency = 'CAD',
    AmountSign? signOverride,
  }) {
    final delimiter = CsvReader.detectDelimiter(content);
    final table = CsvReader.parse(content, delimiter: delimiter);

    if (table.isEmpty) {
      return const StatementImport(
        rows: <StatementRow>[],
        problems: <StatementProblem>[],
        layout: null,
        signConvention: AmountSign.negativeIsSpending,
      );
    }

    final layout = _detectLayout(table);
    if (layout == null || !layout.isUsable) {
      return StatementImport(
        rows: const <StatementRow>[],
        problems: <StatementProblem>[
          StatementProblem(1, 'Could not tell which columns hold the date and '
              'the amount', table.first.join(delimiter)),
        ],
        layout: layout,
        signConvention: AmountSign.negativeIsSpending,
      );
    }

    final body = layout.hasHeader ? table.skip(1).toList() : table;
    final sign = signOverride ??
        (layout.usesDebitCredit
            ? AmountSign.debitCreditColumns
            : _detectSign(body, layout));

    final rows = <StatementRow>[];
    final problems = <StatementProblem>[];

    for (var i = 0; i < body.length; i++) {
      final lineNumber = i + (layout.hasHeader ? 2 : 1);
      final record = body[i];
      final parsed = _readRow(record, layout, sign, currency, lineNumber);
      if (parsed is StatementRow) {
        rows.add(parsed);
      } else if (parsed is StatementProblem) {
        problems.add(parsed);
      }
    }

    return StatementImport(
      rows: rows,
      problems: problems,
      layout: layout,
      signConvention: sign,
    );
  }

  static Object? _readRow(
    List<String> record,
    StatementLayout layout,
    AmountSign sign,
    String currency,
    int lineNumber,
  ) {
    String cell(int? index) {
      if (index == null || index < 0 || index >= record.length) return '';
      return record[index];
    }

    final date = _parseDate(cell(layout.dateColumn));
    if (date == null) {
      return StatementProblem(
        lineNumber,
        'No readable date',
        record.join(', '),
      );
    }

    final description = cell(layout.descriptionColumn);

    int? cents;
    TransactionEventType type;

    if (layout.usesDebitCredit) {
      final debit = _parseCents(cell(layout.debitColumn));
      final credit = _parseCents(cell(layout.creditColumn));
      if (debit != null && debit != 0) {
        cents = debit.abs();
        type = TransactionEventType.purchase;
      } else if (credit != null && credit != 0) {
        cents = credit.abs();
        type = _creditType(description);
      } else {
        return StatementProblem(
          lineNumber,
          'No amount in either column',
          record.join(', '),
        );
      }
    } else {
      final raw = _parseCents(cell(layout.amountColumn));
      if (raw == null || raw == 0) {
        return StatementProblem(
          lineNumber,
          'No readable amount',
          record.join(', '),
        );
      }
      final outward = sign == AmountSign.negativeIsSpending ? raw < 0 : raw > 0;
      cents = raw.abs();
      type = outward ? TransactionEventType.purchase : _creditType(description);
    }

    final money = Money(cents, currency);
    return StatementRow(
      date: date,
      description: description,
      amount: money,
      eventType: type,
      lineNumber: lineNumber,
    );
  }

  /// Money arriving is a refund only when the description says so; otherwise
  /// it is a transfer. Either way it is not spending, so the conservative
  /// reading costs nothing.
  static TransactionEventType _creditType(String description) {
    final text = description.toLowerCase();
    if (text.contains('refund') ||
        text.contains('return') ||
        text.contains('reversal')) {
      return TransactionEventType.refund;
    }
    if (text.contains('payment') &&
        (text.contains('card') || text.contains('thank you'))) {
      return TransactionEventType.payment;
    }
    return TransactionEventType.transfer;
  }

  /// Works out which column is which, with or without a header row.
  static StatementLayout? _detectLayout(List<List<String>> table) {
    final first = table.first;
    final looksLikeHeader = _isHeaderRow(first);

    if (looksLikeHeader) {
      final headers = first.map((h) => h.toLowerCase().trim()).toList();
      int find(List<String> names) => headers.indexWhere(
            (h) => names.any((n) => h.contains(n)),
          );

      final dateColumn = find(<String>['date', 'posted', 'transaction date']);
      final descriptionColumn =
          find(<String>['description', 'details', 'merchant', 'payee', 'name']);
      final debitColumn =
          find(<String>['debit', 'withdrawal', 'money out', 'charge']);
      final creditColumn =
          find(<String>['credit', 'deposit', 'money in']);
      final amountColumn = find(<String>['amount', 'value']);

      if (dateColumn >= 0) {
        return StatementLayout(
          dateColumn: dateColumn,
          descriptionColumn:
              descriptionColumn >= 0 ? descriptionColumn : dateColumn + 1,
          amountColumn: (debitColumn < 0 && creditColumn < 0 && amountColumn >= 0)
              ? amountColumn
              : null,
          debitColumn: debitColumn >= 0 ? debitColumn : null,
          creditColumn: creditColumn >= 0 ? creditColumn : null,
          hasHeader: true,
          headers: first,
        );
      }
    }

    // Headerless — CIBC's export. Infer from the shape of the data instead.
    return _inferFromData(table);
  }

  static StatementLayout? _inferFromData(List<List<String>> table) {
    final sample = table.take(10).toList();
    if (sample.isEmpty) return null;
    final width = sample.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    if (width < 2) return null;

    var dateColumn = -1;
    final moneyColumns = <int>[];
    var descriptionColumn = -1;

    for (var column = 0; column < width; column++) {
      final values = sample
          .map((r) => column < r.length ? r[column] : '')
          .where((v) => v.isNotEmpty)
          .toList();
      if (values.isEmpty) {
        // An always-empty column is still a candidate money column: CIBC
        // leaves credit blank on a statement with no deposits.
        moneyColumns.add(column);
        continue;
      }

      final dateHits = values.where((v) => _parseDate(v) != null).length;
      if (dateColumn < 0 && dateHits >= (values.length * 0.6)) {
        dateColumn = column;
        continue;
      }

      final moneyHits = values.where(_money.hasMatch).length;
      if (moneyHits >= (values.length * 0.6)) {
        moneyColumns.add(column);
        continue;
      }

      if (descriptionColumn < 0) descriptionColumn = column;
    }

    if (dateColumn < 0) return null;
    if (descriptionColumn < 0) descriptionColumn = dateColumn + 1;

    // Two adjacent money columns after the description is the debit/credit
    // shape; a single one is a signed amount.
    final usable = moneyColumns.where((c) => c != dateColumn).toList();
    if (usable.length >= 2) {
      return StatementLayout(
        dateColumn: dateColumn,
        descriptionColumn: descriptionColumn,
        debitColumn: usable[0],
        creditColumn: usable[1],
      );
    }
    if (usable.length == 1) {
      return StatementLayout(
        dateColumn: dateColumn,
        descriptionColumn: descriptionColumn,
        amountColumn: usable.first,
      );
    }
    return null;
  }

  static bool _isHeaderRow(List<String> row) {
    // A header has no parseable date and no parseable amount anywhere.
    final hasDate = row.any((c) => _parseDate(c) != null);
    final hasMoney = row.any((c) => c.isNotEmpty && _money.hasMatch(c));
    return !hasDate && !hasMoney;
  }

  /// Picks the likelier money-out convention for a single-amount file.
  ///
  /// A statement is mostly spending, so whichever sign dominates is almost
  /// certainly the outgoing one.
  static AmountSign _detectSign(
    List<List<String>> body,
    StatementLayout layout,
  ) {
    var negatives = 0;
    var positives = 0;

    for (final record in body.take(50)) {
      final index = layout.amountColumn;
      if (index == null || index >= record.length) continue;
      final cents = _parseCents(record[index]);
      if (cents == null || cents == 0) continue;
      if (cents < 0) {
        negatives++;
      } else {
        positives++;
      }
    }

    if (negatives == 0 && positives == 0) return AmountSign.negativeIsSpending;
    return negatives >= positives
        ? AmountSign.negativeIsSpending
        : AmountSign.positiveIsSpending;
  }

  /// Parses a money cell into signed cents, or null.
  ///
  /// Accepts `$1,234.56`, `(45.67)` for negatives as accounting software
  /// writes them, and a trailing minus.
  static int? _parseCents(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    var negative = false;
    if (text.startsWith('(') && text.endsWith(')')) {
      negative = true;
      text = text.substring(1, text.length - 1);
    }
    if (text.endsWith('-')) {
      negative = true;
      text = text.substring(0, text.length - 1);
    }

    text = text.replaceAll(RegExp(r'[$€£,\s]'), '');
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

  static DateTime? _parseDate(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final iso = _isoDate.firstMatch(text);
    if (iso != null) {
      return _build(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }

    final slash = _slashDate.firstMatch(text);
    if (slash != null) {
      var first = int.parse(slash.group(1)!);
      var second = int.parse(slash.group(2)!);
      final rawYear = int.parse(slash.group(3)!);
      final year = rawYear < 100 ? 2000 + rawYear : rawYear;
      // M/D/Y unless the first field cannot be a month.
      if (first > 12 && second <= 12) {
        final swap = first;
        first = second;
        second = swap;
      }
      return _build(year, first, second);
    }

    final text_ = _textDate.firstMatch(text);
    if (text_ != null) {
      if (text_.group(1) != null) {
        final month = _months[text_.group(2)!.toLowerCase().substring(0, 3)];
        if (month == null) return null;
        return _build(
          int.parse(text_.group(3)!),
          month,
          int.parse(text_.group(1)!),
        );
      }
      final month = _months[text_.group(4)!.toLowerCase().substring(0, 3)];
      if (month == null) return null;
      return _build(
        int.parse(text_.group(6)!),
        month,
        int.parse(text_.group(5)!),
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
}
