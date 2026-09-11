import 'dart:math' as math;

import '../models/app_transaction.dart';
import 'ei_config.dart';
import 'ei_dates.dart';
import 'ei_hours_engine.dart';
import 'ei_models.dart';
import 'ei_payroll_detection.dart';

/// How well an hour is backed, from strongest to weakest.
enum EiEvidence {
  verified('Verified by a bank deposit'),
  payStub('From pay stubs'),
  entered('Entered by week or pay period'),
  estimated('Estimated from usual hours');

  const EiEvidence(this.label);
  final String label;
}

enum EiDepositMatch {
  /// A deposit of exactly the net pay arrived near the pay date.
  matched,

  /// No deposit of that amount arrived near the pay date.
  notFound,

  /// The stub's net pay was not entered, so there is nothing to look for.
  noNetPay,
}

/// What checking one pay stub found.
class EiStubCheck {
  const EiStubCheck({
    required this.record,
    required this.match,
    required this.netPayMismatchCents,
    required this.eiPremiumMissing,
    this.deposit,
  });

  final EiHoursRecord record;
  final EiDepositMatch match;
  final AppTransaction? deposit;

  /// Net pay entered minus gross pay less deductions, when the two differ by
  /// more than rounding; otherwise null.
  final int? netPayMismatchCents;

  /// The stub shows gross pay but an EI premium of zero.
  final bool eiPremiumMissing;

  bool get hasProblem =>
      match == EiDepositMatch.notFound ||
      netPayMismatchCents != null ||
      eiPremiumMissing;
}

/// A pay deposit from a tracked employer that no pay stub accounts for.
class EiUnmatchedDeposit {
  const EiUnmatchedDeposit({required this.job, required this.deposit});

  final EiJob job;
  final AppTransaction deposit;
}

class EiVerification {
  const EiVerification({
    required this.checks,
    required this.unmatchedDeposits,
    required this.hoursByEvidence,
    required this.totalHours,
  });

  final List<EiStubCheck> checks;

  /// Pay deposits inside the qualifying period with no pay stub entered for
  /// them: the likeliest place for hours to be missing.
  final List<EiUnmatchedDeposit> unmatchedDeposits;

  final Map<EiEvidence, double> hoursByEvidence;
  final double totalHours;

  double hoursFor(EiEvidence evidence) => hoursByEvidence[evidence] ?? 0;

  EiStubCheck? checkFor(String recordId) {
    for (final check in checks) {
      if (check.record.id == recordId) return check;
    }
    return null;
  }

  List<EiStubCheck> get problems =>
      checks.where((check) => check.hasProblem).toList();

  /// Share of the current hours backed by a bank deposit or a pay stub.
  double get documentedFraction => totalHours <= 0
      ? 0
      : (hoursFor(EiEvidence.verified) + hoursFor(EiEvidence.payStub)) /
            totalHours;
}

/// Checks pay stubs against themselves and against the bank.
///
/// A stub proves itself three ways: its gross pay less deductions equals its
/// net pay; it shows an EI premium, which is only taken on insurable
/// employment; and its net pay reached the bank near its pay date. Hours on
/// a stub that passes all three are as close to confirmed as SpendWise can
/// get without the Record of Employment.
abstract final class EiVerifier {
  static EiVerification verify({
    required EiTrackerData data,
    required EiHoursEstimate estimate,
    required Iterable<AppTransaction> transactions,
    EiVerificationSettings settings = EiConfig.verification,
  }) {
    final claimed = <String>{};
    final stubs = data.records.where((r) => r.hasPayStubDetails).toList()
      ..sort((a, b) => _anchor(a).compareTo(_anchor(b)));

    final checks = <EiStubCheck>[];
    for (final record in stubs) {
      final details = record.payStub!;
      final calculated = details.calculatedNetCents;
      final net = details.netPayCents;
      int? mismatch;
      if (calculated != null &&
          net != null &&
          (net - calculated).abs() > settings.netPayToleranceCents) {
        mismatch = net - calculated;
      }

      AppTransaction? deposit;
      var match = EiDepositMatch.noNetPay;
      if (net != null) {
        deposit = findDeposit(
          record: record,
          transactions: transactions,
          job: data.jobById(record.jobId),
          exclude: claimed,
          settings: settings,
        );
        match = deposit == null
            ? EiDepositMatch.notFound
            : EiDepositMatch.matched;
        if (deposit != null) claimed.add(deposit.id);
      }

      checks.add(
        EiStubCheck(
          record: record,
          match: match,
          deposit: deposit,
          netPayMismatchCents: mismatch,
          eiPremiumMissing:
              details.eiPremiumCents == 0 && (details.grossPayCents ?? 0) > 0,
        ),
      );
    }

    final countedEnd = EiDates.earlier(estimate.asOf, estimate.period.end);
    final patterns = EiPayrollDetector.detect(transactions);
    final unmatched = <EiUnmatchedDeposit>[];
    for (final summary in estimate.jobs) {
      final pattern = EiPayrollDetector.forEmployer(
        patterns,
        summary.job.employerName,
      );
      if (pattern == null) continue;
      for (final deposit in pattern.deposits) {
        final day = EiDates.day(deposit.occurredAt);
        if (day.isBefore(estimate.period.start) || day.isAfter(countedEnd)) {
          continue;
        }
        if (claimed.contains(deposit.id)) continue;
        unmatched.add(EiUnmatchedDeposit(job: summary.job, deposit: deposit));
      }
    }
    unmatched.sort(
      (a, b) => b.deposit.occurredAt.compareTo(a.deposit.occurredAt),
    );

    final matchedIds = <String>{
      for (final check in checks)
        if (check.match == EiDepositMatch.matched) check.record.id,
    };
    final byEvidence = <EiEvidence, double>{};
    var fromEntries = 0.0;
    for (final record in data.records) {
      final hours = estimate.recordHours[record.id] ?? 0;
      if (hours <= 0) continue;
      fromEntries += hours;
      final evidence = matchedIds.contains(record.id)
          ? EiEvidence.verified
          : record.hasPayStubDetails || record.source == EiHoursSource.payStub
          ? EiEvidence.payStub
          : EiEvidence.entered;
      byEvidence[evidence] = (byEvidence[evidence] ?? 0) + hours;
    }
    final estimated = math.max(0.0, estimate.currentHours - fromEntries);
    if (estimated > 0) byEvidence[EiEvidence.estimated] = estimated;

    return EiVerification(
      checks: checks,
      unmatchedDeposits: unmatched,
      hoursByEvidence: byEvidence,
      totalHours: estimate.currentHours,
    );
  }

  /// The deposit of exactly [record]'s net pay nearest its pay date, or —
  /// without a pay date — in the days after its period ends.
  ///
  /// When two deposits are equally near, the one whose description names
  /// the employer wins.
  static AppTransaction? findDeposit({
    required EiHoursRecord record,
    required Iterable<AppTransaction> transactions,
    EiJob? job,
    Set<String> exclude = const <String>{},
    EiVerificationSettings settings = EiConfig.verification,
  }) {
    final net = record.payStub?.netPayCents;
    if (net == null) return null;
    final payDate = record.payStub?.payDate;
    final anchor = payDate ?? record.periodEnd;
    final from = payDate == null
        ? record.periodEnd
        : EiDates.addDays(payDate, -settings.depositDaysBeforePayDate);
    final to = payDate == null
        ? EiDates.addDays(
            record.periodEnd,
            settings.depositSearchDaysWithoutPayDate,
          )
        : EiDates.addDays(payDate, settings.depositDaysAfterPayDate);

    AppTransaction? best;
    var bestDistance = 0;
    var bestNamed = false;
    for (final transaction in transactions) {
      if (!transaction.isInbound ||
          transaction.excludedByUser ||
          transaction.amountCents != net ||
          exclude.contains(transaction.id)) {
        continue;
      }
      final day = EiDates.day(transaction.occurredAt);
      if (day.isBefore(from) || day.isAfter(to)) continue;
      final distance = EiDates.between(anchor, day).abs();
      final named =
          job != null &&
          EiPayrollDetector.namesEmployer(
            transaction.merchant,
            job.employerName,
          );
      if (best == null ||
          distance < bestDistance ||
          (distance == bestDistance && named && !bestNamed)) {
        best = transaction;
        bestDistance = distance;
        bestNamed = named;
      }
    }
    return best;
  }

  static DateTime _anchor(EiHoursRecord record) =>
      record.payStub?.payDate ?? record.periodEnd;
}
