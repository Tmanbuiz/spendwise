/// Splits CSV text into rows and fields.
///
/// Hand-written rather than pulled from a package because bank exports break
/// the naive `split(',')` in ways that matter: merchant names contain commas,
/// descriptions contain quoted quotes, and files arrive with either line
/// ending. Getting any of those wrong shifts every column by one and silently
/// imports garbage amounts.
abstract final class CsvReader {
  /// Parses [input] into rows of fields.
  ///
  /// Handles quoted fields, embedded delimiters and newlines, doubled quotes
  /// as an escape (`""` inside a quoted field), and CRLF or LF line endings.
  /// Blank lines are dropped — trailing newlines are near-universal in
  /// exports and an empty final row is never meaningful.
  static List<List<String>> parse(String input, {String delimiter = ','}) {
    final rows = <List<String>>[];
    var fields = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var index = 0;

    void endField() {
      fields.add(field.toString().trim());
      field.clear();
    }

    void endRow() {
      endField();
      if (fields.any((f) => f.isNotEmpty)) rows.add(fields);
      fields = <String>[];
    }

    while (index < input.length) {
      final char = input[index];

      if (inQuotes) {
        if (char == '"') {
          final isEscapedQuote =
              index + 1 < input.length && input[index + 1] == '"';
          if (isEscapedQuote) {
            field.write('"');
            index += 2;
            continue;
          }
          inQuotes = false;
          index++;
          continue;
        }
        field.write(char);
        index++;
        continue;
      }

      if (char == '"') {
        inQuotes = true;
        index++;
        continue;
      }
      if (char == delimiter) {
        endField();
        index++;
        continue;
      }
      if (char == '\r') {
        // Swallow CRLF as one break; a lone CR also ends the row.
        if (index + 1 < input.length && input[index + 1] == '\n') index++;
        endRow();
        index++;
        continue;
      }
      if (char == '\n') {
        endRow();
        index++;
        continue;
      }

      field.write(char);
      index++;
    }

    if (field.isNotEmpty || fields.isNotEmpty) endRow();
    return rows;
  }

  /// Guesses the delimiter from the first few lines.
  ///
  /// European exports use `;` and some use tabs. Picking the character that
  /// appears most consistently across lines is more reliable than assuming a
  /// comma, and a wrong guess would collapse every row into one field.
  static String detectDelimiter(String input) {
    const candidates = <String>[',', ';', '\t', '|'];
    final lines = input
        .split(RegExp(r'\r\n|\r|\n'))
        .where((l) => l.trim().isNotEmpty)
        .take(5)
        .toList();
    if (lines.isEmpty) return ',';

    var best = ',';
    var bestScore = -1;

    for (final candidate in candidates) {
      final counts =
          lines.map((l) => candidate.allMatches(l).length).toList();
      if (counts.first == 0) continue;
      // Consistent counts across lines mean it really is the delimiter.
      final consistent = counts.every((c) => c == counts.first);
      final score = counts.first * (consistent ? 10 : 1);
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }
}
