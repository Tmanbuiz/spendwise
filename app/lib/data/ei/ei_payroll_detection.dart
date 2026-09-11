import '../models/app_transaction.dart';
import 'ei_dates.dart';
import 'ei_models.dart';

/// Pay deposits from one payer, as found in the user's transactions.
class EiPayrollPattern {
  const EiPayrollPattern({
    required this.payerName,
    required this.payDates,
    required this.frequency,
  });

  final String payerName;

  /// Distinct pay days, oldest first.
  final List<DateTime> payDates;

  /// Null when the gaps between deposits do not fit a regular schedule.
  final EiPayFrequency? frequency;

  DateTime get lastPayDate => payDates.last;
  int get count => payDates.length;
}

/// Finds payroll deposits in transactions SpendWise already holds.
///
/// Deposits say when someone was paid and by whom, which is enough to
/// suggest an employer and a pay frequency. They say nothing reliable about
/// hours — a deposit is net of deductions — so no hours are ever derived
/// from them.
abstract final class EiPayrollDetector {
  /// Wording banks use only for pay: "PAY HARMONY FAMILY", "PAYROLL",
  /// "DIRECT DEPOSIT". The word boundary keeps PAYMENT out.
  static final RegExp _payroll = RegExp(
    r'^\s*pay\b|\bpayroll\b|\bdirect\s+deposit\b',
    caseSensitive: false,
  );

  static final RegExp _label = RegExp(
    r'^\s*pay\b|\bpayroll\b|\bdirect\s+deposit\b|\bdeposit\b|[:/#-]',
    caseSensitive: false,
  );

  static List<EiPayrollPattern> detect(
    Iterable<AppTransaction> transactions, {
    DateTime? since,
  }) {
    final byPayer = <String, _Group>{};
    for (final transaction in transactions) {
      if (!transaction.isInbound || transaction.excludedByUser) continue;
      final description = transaction.merchant;
      if (description == null || !_payroll.hasMatch(description)) continue;
      final day = EiDates.day(transaction.occurredAt);
      if (since != null && day.isBefore(EiDates.day(since))) continue;

      var payer = description
          .replaceAll(_label, ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (payer.isEmpty) payer = 'Payroll deposit';
      byPayer
          .putIfAbsent(payer.toUpperCase(), () => _Group(payer))
          .days
          .add(day);
    }

    final patterns = <EiPayrollPattern>[];
    for (final group in byPayer.values) {
      final dates = group.days.toList()..sort();
      if (dates.length < 2) continue;
      patterns.add(
        EiPayrollPattern(
          payerName: group.name,
          payDates: dates,
          frequency: frequencyFromDates(dates),
        ),
      );
    }
    patterns.sort((a, b) => b.lastPayDate.compareTo(a.lastPayDate));
    return patterns;
  }

  /// The schedule the median gap between pay days fits, if any.
  static EiPayFrequency? frequencyFromDates(List<DateTime> sortedDates) {
    if (sortedDates.length < 2) return null;
    final gaps = <int>[
      for (var i = 1; i < sortedDates.length; i++)
        EiDates.between(sortedDates[i - 1], sortedDates[i]),
    ]..sort();
    final middle = gaps.length ~/ 2;
    final median = gaps.length.isOdd
        ? gaps[middle].toDouble()
        : (gaps[middle - 1] + gaps[middle]) / 2;
    if (median >= 5 && median <= 9) return EiPayFrequency.weekly;
    if (median >= 12 && median <= 14.5) return EiPayFrequency.biweekly;
    if (median > 14.5 && median <= 17) return EiPayFrequency.semiMonthly;
    if (median >= 26 && median <= 33) return EiPayFrequency.monthly;
    return null;
  }
}

class _Group {
  _Group(this.name);
  final String name;
  final Set<DateTime> days = <DateTime>{};
}
