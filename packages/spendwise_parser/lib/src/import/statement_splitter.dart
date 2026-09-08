/// Cuts a file holding several statements into one segment per statement.
///
/// People merge their statements before importing — a year of them in one PDF
/// is easier to hand over than twelve files. Read as a single document that
/// fails badly and silently: one layout is chosen for the whole file, a
/// statement's running balance carries into the next, and every date resolves
/// against one inferred year. Measured against a statement read on its own, a
/// real merged file lost 36 of its 39 transactions and misreported the three
/// that survived.
///
/// Splitting is only safe because each segment can be checked afterwards
/// against the totals its own statement prints. A segment that does not
/// reproduce them is rejected rather than imported, so a bad cut shows up as a
/// refusal instead of as plausible-looking numbers.
abstract final class StatementSplitter {
  /// Where a statement announces its own period.
  ///
  /// The distinction that matters is against a *continuation page*, which
  /// repeats the title and the period but not this line:
  ///
  ///     CIBC Account Statement          CIBC Account Statement
  ///     OLUBUKOLA ADESO OYEBANJI        Jul 1 to Jul 31, 2026
  ///     The names shown are based …     Account number: 87-72932
  ///     For Jul 1 to Jul 31, 2026       ← only on the first page
  ///
  /// Anchoring on the header alone would cut a three-page statement into
  /// three, so the period line is what identifies a genuine start.
  static final RegExp _accountPeriod = RegExp(
    r'^For\s+[A-Z][a-z]{2,8}\.?\s+\d{1,2}\s+to\s+[A-Z][a-z]{2,8}\.?\s+\d{1,2},?\s+\d{4}$',
  );

  /// The card equivalent: "August statement period", printed once in the
  /// account summary of the first page.
  static final RegExp _cardPeriod =
      RegExp(r'^[A-Z][a-z]{2,8}\s+statement\s+period$');

  /// The line a statement opens with, searched for above a period marker so a
  /// segment begins at the top of its statement rather than partway down the
  /// summary. Cutting at the period itself would leave a card statement's
  /// opening balances and section totals attached to the statement before it,
  /// where they read as transactions that were never made.
  static final RegExp _title = RegExp(
    r'^CIBC\s+(?:Account\s+Statement|Dividend|Adapta|Aventura|Aeroplan|Costco|'
    r'Select|Classic|Smart)\b',
    caseSensitive: false,
  );

  /// How far above a period marker to look for the statement's title.
  ///
  /// A card statement carries a long account summary between the two, so this
  /// is generous; anything not found within it falls back to cutting at the
  /// marker, which is worse but still bounded.
  static const int _titleLookback = 80;

  /// Splits [text] into one string per statement, in the order they appear.
  ///
  /// Returns a single-element list when only one statement is present, so
  /// callers can treat the ordinary case as the ordinary case.
  static List<String> split(String text) {
    final lines = text.split(RegExp(r'\r\n|\r|\n'));
    final starts = <int>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!_accountPeriod.hasMatch(line) && !_cardPeriod.hasMatch(line)) {
        continue;
      }
      starts.add(_titleAbove(lines, i));
    }

    if (starts.length <= 1) return <String>[text];

    // Everything before the first statement is a cover page or a preamble.
    // It is kept with the first statement rather than dropped, because a
    // statement's own header lives there.
    starts[0] = 0;

    final segments = <String>[];
    for (var s = 0; s < starts.length; s++) {
      final end = s + 1 < starts.length ? starts[s + 1] : lines.length;
      if (end <= starts[s]) continue;
      segments.add(lines.sublist(starts[s], end).join('\n'));
    }
    return segments;
  }

  /// How many statements [text] appears to hold.
  static int count(String text) => split(text).length;

  static int _titleAbove(List<String> lines, int periodIndex) {
    final floor =
        periodIndex - _titleLookback < 0 ? 0 : periodIndex - _titleLookback;
    for (var i = periodIndex; i >= floor; i--) {
      if (_title.hasMatch(lines[i].trim())) return i;
    }
    return periodIndex;
  }
}
