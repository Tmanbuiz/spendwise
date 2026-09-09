import 'package:intl/intl.dart';

/// Money and date formatting used across the app.
abstract final class Fmt {
  /// `$1,249.99`. Cents in, formatted string out — the app never holds an
  /// amount as a double, so rounding cannot drift.
  static String money(int cents, {String currency = 'CAD', bool sign = false}) {
    final format = NumberFormat.currency(
      locale: 'en_CA',
      symbol: _symbolFor(currency),
      decimalDigits: 2,
    );
    final value = cents.abs() / 100.0;
    final text = format.format(value);
    if (!sign) return text;
    return cents < 0 ? '-$text' : '+$text';
  }

  /// `$1,250` — no cents, for headline figures where precision is noise.
  static String moneyCompact(int cents, {String currency = 'CAD'}) {
    final format = NumberFormat.currency(
      locale: 'en_CA',
      symbol: _symbolFor(currency),
      decimalDigits: 0,
    );
    return format.format(cents.abs() / 100.0);
  }

  static String _symbolFor(String currency) {
    switch (currency.toUpperCase()) {
      case 'USD':
        return r'US$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return r'$';
    }
  }

  static String percent(double fraction) =>
      NumberFormat.decimalPercentPattern(decimalDigits: 0).format(fraction);

  /// `Sep 3` for this year, `Sep 3, 2025` otherwise.
  static String shortDate(DateTime when) {
    final now = DateTime.now();
    final pattern = when.year == now.year ? 'MMM d' : 'MMM d, y';
    return DateFormat(pattern).format(when);
  }

  static String time(DateTime when) => DateFormat('h:mm a').format(when);

  static String monthName(DateTime when) => DateFormat('MMMM').format(when);

  /// `Sep`. Takes a month number so a picker wheel does not have to build
  /// a throwaway date for every row it draws.
  static String monthAbbreviation(int month) =>
      DateFormat('MMM').format(DateTime(2000, month));

  static String monthAndYear(DateTime when) =>
      DateFormat('MMMM y').format(when);

  /// `Today`, `Yesterday`, or a short date — used as list section headers.
  static String relativeDay(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(when.year, when.month, when.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7 && difference > 0) {
      return DateFormat('EEEE').format(when);
    }
    return shortDate(when);
  }
}
