/// Date-only arithmetic for the EI tracker.
///
/// Every date is normalised to midnight UTC. Local midnights are not safe to
/// subtract: across a daylight-saving change one local day is 23 or 25 hours
/// long, and `Duration.inDays` then drops a day from any span containing the
/// March change.
abstract final class EiDates {
  static DateTime day(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static DateTime addDays(DateTime value, int days) =>
      DateTime.utc(value.year, value.month, value.day + days);

  /// Whole days from [from] to [to]; negative when [to] is earlier.
  static int between(DateTime from, DateTime to) =>
      day(to).difference(day(from)).inDays;

  /// Days in the inclusive range [start]..[end], or zero when [end] is
  /// before [start].
  static int inclusiveDays(DateTime start, DateTime end) {
    final days = between(start, end) + 1;
    return days < 0 ? 0 : days;
  }

  static DateTime earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

  static DateTime later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  /// The Sunday on or before [value]. EI weeks run Sunday to Saturday.
  static DateTime weekStart(DateTime value) {
    final date = day(value);
    return addDays(date, -(date.weekday % DateTime.daysPerWeek));
  }

  static int daysInMonth(int year, int month) =>
      DateTime.utc(year, month + 1, 0).day;

  /// `yyyy-MM-dd`, the storage format for every tracker date.
  static String encode(DateTime value) {
    final date = day(value);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-'
        '${two(date.day)}';
  }

  static DateTime? decode(Object? raw) {
    if (raw is! String) return null;
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? null : day(parsed);
  }
}
