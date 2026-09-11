import '../models/app_transaction.dart';
import 'ei_dates.dart';
import 'ei_models.dart';

/// Pay deposits from one payer, as found in the user's transactions.
class EiPayrollPattern {
  const EiPayrollPattern({
    required this.payerName,
    required this.deposits,
    required this.frequency,
  });

  final String payerName;

  /// The deposits themselves, oldest first.
  final List<AppTransaction> deposits;

  /// Null when the gaps between deposits do not fit a regular schedule.
  final EiPayFrequency? frequency;

  /// Distinct pay days, oldest first.
  List<DateTime> get payDates =>
      <DateTime>{for (final d in deposits) EiDates.day(d.occurredAt)}.toList()
        ..sort();

  DateTime get lastPayDate => EiDates.day(deposits.last.occurredAt);
  int get count => payDates.length;
}

/// Finds payroll deposits in transactions SpendWise already holds.
///
/// Deposits say when someone was paid, by whom and how much reached the
/// bank. That is enough to suggest an employer and a pay frequency, and to
/// confirm a pay stub's net pay. They say nothing reliable about hours, so no
/// hours are ever derived from them.
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

      final payer = payerOf(description);
      byPayer
          .putIfAbsent(payer.toUpperCase(), () => _Group(payer))
          .deposits
          .add(transaction);
    }

    final patterns = <EiPayrollPattern>[];
    for (final group in byPayer.values) {
      final deposits = group.deposits
        ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      final pattern = EiPayrollPattern(
        payerName: group.name,
        deposits: deposits,
        frequency: null,
      );
      final dates = pattern.payDates;
      if (dates.length < 2) continue;
      patterns.add(
        EiPayrollPattern(
          payerName: group.name,
          deposits: deposits,
          frequency: frequencyFromDates(dates),
        ),
      );
    }
    patterns.sort((a, b) => b.lastPayDate.compareTo(a.lastPayDate));
    return patterns;
  }

  /// The payer a deposit description names, without the bank's labels.
  static String payerOf(String description) {
    final payer = description
        .replaceAll(_label, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return payer.isEmpty ? 'Payroll deposit' : payer;
  }

  /// The pattern whose payer and [employer] name each other, if any.
  static EiPayrollPattern? forEmployer(
    List<EiPayrollPattern> patterns,
    String employer,
  ) {
    for (final pattern in patterns) {
      if (_sameName(pattern.payerName, employer)) return pattern;
    }
    return null;
  }

  /// Whether a deposit's [description] names [employer].
  static bool namesEmployer(String? description, String employer) =>
      description != null && _sameName(payerOf(description), employer);

  static bool _sameName(String a, String b) {
    final first = a.trim().toUpperCase();
    final second = b.trim().toUpperCase();
    if (first.isEmpty || second.isEmpty) return false;
    return first.contains(second) || second.contains(first);
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
  final List<AppTransaction> deposits = <AppTransaction>[];
}
