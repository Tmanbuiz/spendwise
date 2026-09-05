/// A timestamp recovered from notification text.
class TimestampResult {
  const TimestampResult(this.value, {required this.isExact});

  final DateTime value;

  /// True when a calendar date was read out of the message. False means the
  /// notification's delivery time is standing in for a missing date.
  final bool isExact;
}

/// Recovers the transaction date/time from notification text.
///
/// Bank alerts are inconsistent: some carry a full `Sep 3, 2026 at 8:14 a.m.`,
/// some carry only a time, most carry nothing at all and rely on the fact that
/// the alert is delivered within seconds of the transaction.
abstract final class TimestampExtractor {
  static const Map<String, int> _months = <String, int>{
    'JANUARY': 1, 'JAN': 1,
    'FEBRUARY': 2, 'FEB': 2,
    'MARCH': 3, 'MAR': 3,
    'APRIL': 4, 'APR': 4,
    'MAY': 5,
    'JUNE': 6, 'JUN': 6,
    'JULY': 7, 'JUL': 7,
    'AUGUST': 8, 'AUG': 8,
    'SEPTEMBER': 9, 'SEPT': 9, 'SEP': 9,
    'OCTOBER': 10, 'OCT': 10,
    'NOVEMBER': 11, 'NOV': 11,
    'DECEMBER': 12, 'DEC': 12,
  };

  // Longest alternatives first so `September` is not truncated to `Sep`.
  static final RegExp _monthName = RegExp(
    r'\b(January|Jan|February|Feb|March|Mar|April|Apr|May|June|Jun|July|Jul|'
    r'August|Aug|September|Sept|Sep|October|Oct|November|Nov|December|Dec)\b'
    r'\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,)?(?:\s+(\d{4}))?',
    caseSensitive: false,
  );

  static final RegExp _isoDate = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b');

  static final RegExp _slashDate =
      RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{2,4})\b');

  static final RegExp _time = RegExp(
    r'\b(\d{1,2}):(\d{2})(?::\d{2})?\s*(a\.?m\.?|p\.?m\.?)?',
    caseSensitive: false,
  );

  /// Reads a timestamp from [text], falling back to [postedAt].
  static TimestampResult extract(String text, DateTime postedAt) {
    final date = _extractDate(text, postedAt);
    final time = _extractTime(text);

    if (date == null && time == null) {
      return TimestampResult(postedAt, isExact: false);
    }

    final base = date ?? DateTime(postedAt.year, postedAt.month, postedAt.day);
    final result = DateTime(
      base.year,
      base.month,
      base.day,
      time?.hour ?? (date == null ? postedAt.hour : 0),
      time?.minute ?? (date == null ? postedAt.minute : 0),
    );
    // A time on its own is real information, but the *date* is still assumed,
    // so only a parsed calendar date earns `isExact`.
    return TimestampResult(result, isExact: date != null);
  }

  static DateTime? _extractDate(String text, DateTime postedAt) {
    final iso = _isoDate.firstMatch(text);
    if (iso != null) {
      final y = int.parse(iso.group(1)!);
      final m = int.parse(iso.group(2)!);
      final d = int.parse(iso.group(3)!);
      if (_isValidDate(y, m, d)) return DateTime(y, m, d);
    }

    final named = _monthName.firstMatch(text);
    if (named != null) {
      final month = _months[named.group(1)!.toUpperCase()];
      final day = int.parse(named.group(2)!);
      final yearText = named.group(3);
      if (month != null && day >= 1 && day <= 31) {
        if (yearText != null) {
          final year = int.parse(yearText);
          if (_isValidDate(year, month, day)) return DateTime(year, month, day);
        } else {
          return _inferYear(month, day, postedAt);
        }
      }
    }

    final slash = _slashDate.firstMatch(text);
    if (slash != null) {
      var first = int.parse(slash.group(1)!);
      var second = int.parse(slash.group(2)!);
      final rawYear = int.parse(slash.group(3)!);
      final year = rawYear < 100 ? 2000 + rawYear : rawYear;
      // Canadian bank alerts use M/D/Y; if the first field cannot be a month
      // the message must be D/M/Y instead.
      if (first > 12 && second <= 12) {
        final swap = first;
        first = second;
        second = swap;
      }
      if (_isValidDate(year, first, second)) return DateTime(year, first, second);
    }

    return null;
  }

  /// A month/day with no year belongs to whichever year puts it in the recent
  /// past relative to delivery — never meaningfully in the future.
  static DateTime? _inferYear(int month, int day, DateTime postedAt) {
    if (!_isValidDate(postedAt.year, month, day)) return null;
    final sameYear = DateTime(postedAt.year, month, day);
    if (sameYear.difference(postedAt).inDays > 2) {
      return DateTime(postedAt.year - 1, month, day);
    }
    return sameYear;
  }

  static ({int hour, int minute})? _extractTime(String text) {
    final m = _time.firstMatch(text);
    if (m == null) return null;
    var hour = int.parse(m.group(1)!);
    final minute = int.parse(m.group(2)!);
    if (minute > 59) return null;

    final meridiem = m.group(3)?.toLowerCase().replaceAll('.', '');
    if (meridiem == 'pm') {
      if (hour < 12) hour += 12;
    } else if (meridiem == 'am') {
      if (hour == 12) hour = 0;
    }
    if (hour > 23) return null;
    return (hour: hour, minute: minute);
  }

  static bool _isValidDate(int year, int month, int day) {
    if (year < 1970 || year > 2999) return false;
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > 31) return false;
    // DateTime rolls over invalid days (Feb 31 -> Mar 3); detect that.
    final probe = DateTime(year, month, day);
    return probe.month == month && probe.day == day;
  }
}
