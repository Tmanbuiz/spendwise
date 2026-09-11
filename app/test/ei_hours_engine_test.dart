import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/ei/ei_config.dart';
import 'package:spendwise/data/ei/ei_hours_engine.dart';
import 'package:spendwise/data/ei/ei_models.dart';

DateTime d(int year, int month, int day) => DateTime.utc(year, month, day);

EiJob job(
  String id, {
  String? name,
  DateTime? start,
  DateTime? end,
  double weekly = 0,
  int days = 5,
  bool variable = false,
  bool insurable = true,
}) => EiJob(
  id: id,
  employerName: name ?? 'Employer $id',
  startDate: start ?? d(2025, 1, 1),
  endDate: end,
  usualWeeklyHours: weekly,
  daysPerWeek: days,
  variableHours: variable,
  isInsurable: insurable,
);

EiHoursRecord entry(
  String id,
  String jobId,
  DateTime start,
  DateTime end,
  double hours, {
  double vacation = 0,
  double paidLeave = 0,
}) => EiHoursRecord(
  id: id,
  jobId: jobId,
  periodStart: start,
  periodEnd: end,
  hoursWorked: hours,
  vacationHours: vacation,
  paidLeaveHours: paidLeave,
);

const engine = EiHoursEngine();

/// A claim on January 15, 2027, looked at after it has started, so nothing
/// is projected and the totals are exactly what was entered.
EiHoursEstimate settled(List<EiHoursRecord> records, {List<EiJob>? jobs}) =>
    engine.estimate(
      EiTrackerData(
        plannedClaimStart: d(2027, 1, 15),
        jobs: jobs ?? <EiJob>[job('a', variable: true)],
        records: records,
      ),
      today: d(2027, 1, 20),
    );

void main() {
  group('the requirement', () {
    test('exactly 600 hours meets it', () {
      final estimate = settled([
        entry('r1', 'a', d(2026, 2, 1), d(2026, 2, 28), 600),
      ]);
      expect(estimate.currentHours, closeTo(600, 1e-9));
      expect(estimate.remainingHours, 0);
      expect(estimate.fractionComplete, closeTo(1, 1e-9));
      expect(estimate.status, EiStatus.requirementReached);
      // February 2026 has 20 weekdays; the 600th hour lands on the last one.
      expect(estimate.estimatedReachDate, d(2026, 2, 27));
    });

    test('599 hours does not, and with no time left it is at risk', () {
      final estimate = settled([
        entry('r1', 'a', d(2026, 2, 1), d(2026, 2, 28), 599),
      ]);
      expect(estimate.requirementReached, isFalse);
      expect(estimate.remainingHours, closeTo(1, 1e-9));
      expect(estimate.projectedFutureHours, 0);
      expect(estimate.notices, contains(EiNotice.leaveDateReached));
      expect(estimate.status, EiStatus.atRisk);
    });

    test('more than 600 hours reports nothing remaining', () {
      final estimate = settled([
        entry('r1', 'a', d(2026, 3, 1), d(2026, 3, 31), 750),
      ]);
      expect(estimate.remainingHours, 0);
      expect(estimate.fractionComplete, closeTo(1.25, 1e-9));
      expect(estimate.status, EiStatus.requirementReached);
    });

    test('a user already over the requirement sees when it was reached', () {
      final estimate = engine.estimate(
        EiTrackerData(
          plannedClaimStart: d(2027, 1, 15),
          jobs: [job('a', start: d(2026, 2, 1), weekly: 32)],
          records: [entry('r1', 'a', d(2026, 2, 1), d(2026, 9, 11), 820)],
        ),
        today: d(2026, 9, 11),
      );
      expect(estimate.status, EiStatus.requirementReached);
      expect(estimate.remainingHours, 0);
      expect(estimate.estimatedReachDate!.isAfter(d(2026, 9, 11)), isFalse);
      expect(estimate.weeksToReach, isNull);
      expect(estimate.requiredWeeklyHours, isNull);
      expect(estimate.reachesAfterLeave, isFalse);
    });

    test('the threshold comes from the rules, not the code', () {
      const lower = EiHoursEngine(
        rules: EiRules(
          country: 'CA',
          maternityParentalRequiredHours: 420,
          qualifyingPeriodWeeks: 52,
          countPaidVacationHours: true,
          countPaidLeaveHours: true,
          lastReviewed: '2026-09-11',
        ),
      );
      final estimate = lower.estimate(
        EiTrackerData(
          plannedClaimStart: d(2027, 1, 15),
          jobs: [job('a', variable: true)],
          records: [entry('r1', 'a', d(2026, 3, 1), d(2026, 3, 31), 450)],
        ),
        today: d(2027, 1, 20),
      );
      expect(estimate.requiredHours, 420);
      expect(estimate.status, EiStatus.requirementReached);
      expect(EiConfig.rules.maternityParentalRequiredHours, 600);
    });
  });

  group('the qualifying period', () {
    test('a January 2027 leave start looks back 52 weeks', () {
      final period = EiQualifyingPeriod.forClaim(claimStart: d(2027, 1, 15));
      expect(period.start, d(2026, 1, 16));
      expect(period.end, d(2027, 1, 14));
      expect(period.days, 364);
      expect(period.weeks, 52);
      expect(period.shortenedByPreviousClaim, isFalse);
    });

    test('its length comes from the rules', () {
      final period = EiQualifyingPeriod.forClaim(
        claimStart: d(2027, 1, 15),
        rules: EiConfig.rules.copyWith(qualifyingPeriodWeeks: 26),
      );
      expect(period.days, 182);
    });

    test('a previous claim inside it shortens it and says so', () {
      final estimate = engine.estimate(
        EiTrackerData(
          plannedClaimStart: d(2027, 1, 15),
          hadPreviousClaim: true,
          previousClaimStart: d(2026, 6, 1),
          jobs: [job('a', variable: true)],
          records: [
            // Before the previous claim: already used, so not counted.
            entry('r1', 'a', d(2026, 3, 1), d(2026, 3, 31), 300),
            entry('r2', 'a', d(2026, 7, 1), d(2026, 7, 31), 250),
          ],
        ),
        today: d(2027, 1, 20),
      );
      expect(estimate.period.start, d(2026, 6, 1));
      expect(estimate.period.shortenedByPreviousClaim, isTrue);
      expect(estimate.notices, contains(EiNotice.previousClaimShortensPeriod));
      expect(estimate.currentHours, closeTo(250, 1e-9));
    });

    test('a previous claim with no date is insufficient information', () {
      final estimate = engine.estimate(
        EiTrackerData(
          plannedClaimStart: d(2027, 1, 15),
          hadPreviousClaim: true,
          jobs: [job('a', weekly: 30)],
        ),
        today: d(2026, 9, 11),
      );
      expect(estimate.missing, contains(EiMissingInfo.previousClaimStart));
      expect(estimate.notices, contains(EiNotice.previousClaimDateNeeded));
      expect(estimate.status, EiStatus.insufficientInformation);
    });

    test('a previous claim older than the period changes nothing', () {
      final estimate = engine.estimate(
        EiTrackerData(
          plannedClaimStart: d(2027, 1, 15),
          hadPreviousClaim: true,
          previousClaimStart: d(2025, 6, 1),
          jobs: [job('a', weekly: 30)],
        ),
        today: d(2026, 9, 11),
      );
      expect(estimate.period.start, d(2026, 1, 16));
      expect(
        estimate.notices,
        isNot(contains(EiNotice.previousClaimShortensPeriod)),
      );
    });

    test('a previous claim after the planned claim is rejected', () {
      final estimate = engine.estimate(
        EiTrackerData(
          plannedClaimStart: d(2027, 1, 15),
          hadPreviousClaim: true,
          previousClaimStart: d(2027, 2, 1),
          jobs: [job('a', weekly: 30)],
        ),
        today: d(2026, 9, 11),
      );
      expect(estimate.missing, contains(EiMissingInfo.previousClaimAfterClaim));
    });
  });

  group('entering hours', () {
    test('several employers are kept apart and combined', () {
      final estimate = settled(
        [
          entry('r1', 'a', d(2026, 3, 1), d(2026, 3, 31), 350),
          entry('r2', 'b', d(2026, 4, 1), d(2026, 4, 30), 210),
        ],
        jobs: [
          job('a', name: 'Employer A', variable: true),
          job('b', name: 'Employer B', variable: true),
        ],
      );
      expect(estimate.jobs.map((j) => j.currentHours).toList(), [
        closeTo(350, 1e-9),
        closeTo(210, 1e-9),
      ]);
      expect(estimate.currentHours, closeTo(560, 1e-9));
      expect(estimate.remainingHours, closeTo(40, 1e-9));
    });

    test('variable hours count only what was entered, and project the '
        'average of it', () {
      EiHoursEstimate run({required bool variable}) => engine.estimate(
        EiTrackerData(
          plannedClaimStart: d(2026, 7, 27),
          jobs: [
            job('a', start: d(2026, 6, 1), weekly: 30, variable: variable),
          ],
          records: [
            entry('w1', 'a', d(2026, 6, 1), d(2026, 6, 7), 20),
            // The week of June 8 was never entered.
            entry('w3', 'a', d(2026, 6, 15), d(2026, 6, 21), 35),
            entry('w4', 'a', d(2026, 6, 22), d(2026, 6, 28), 28),
          ],
        ),
        today: d(2026, 6, 28),
      );

      final variable = run(variable: true);
      expect(variable.currentHours, closeTo(83, 1e-9));
      // 83 hours over 21 entered days is 27.67 a week; June 29 to July 26
      // holds 20 weekdays.
      expect(variable.forwardWeeklyHours, closeTo(83 / 21 * 7, 1e-9));
      expect(variable.projectedFutureHours, closeTo(83 / 21 * 7 / 5 * 20, 1e-9));

      // A steady schedule fills the missing week from the usual 30 hours.
      final steady = run(variable: false);
      expect(steady.currentHours, closeTo(113, 1e-9));
    });

    test('paid vacation and paid leave count, as the rules say', () {
      final estimate = settled([
        entry(
          'r1',
          'a',
          d(2026, 3, 2),
          d(2026, 3, 8),
          24,
          vacation: 8,
          paidLeave: 8,
        ),
      ]);
      expect(estimate.currentHours, closeTo(40, 1e-9));

      final strict = EiHoursEngine(
        rules: EiConfig.rules.copyWith(
          countPaidVacationHours: false,
          countPaidLeaveHours: false,
        ),
      ).estimate(
        EiTrackerData(
          plannedClaimStart: d(2027, 1, 15),
          jobs: [job('a', variable: true)],
          records: [
            entry('r1', 'a', d(2026, 3, 2), d(2026, 3, 8), 24,
                vacation: 8, paidLeave: 8),
          ],
        ),
        today: d(2027, 1, 20),
      );
      expect(strict.currentHours, closeTo(24, 1e-9));
    });

    test('employment gaps and unpaid leave remove scheduled hours', () {
      EiHoursEstimate run(List<EiBreak> breaks) => engine.estimate(
        EiTrackerData(
          plannedClaimStart: d(2026, 12, 1),
          jobs: [
            job('a', start: d(2026, 1, 5), weekly: 40),
            job('b', start: d(2026, 1, 5), weekly: 10),
          ],
          breaks: breaks,
        ),
        today: d(2026, 3, 1),
      );
      double hoursFor(EiHoursEstimate e, String id) =>
          e.jobs.firstWhere((j) => j.job.id == id).currentHours;

      // January 5 to February 27: eight Monday-to-Friday weeks.
      expect(hoursFor(run(const []), 'a'), closeTo(320, 1e-9));

      final gap = EiBreak(
        id: 'gap',
        start: d(2026, 2, 2),
        end: d(2026, 2, 13),
        jobId: 'a',
      );
      final unpaid = EiBreak(
        id: 'leave',
        start: d(2026, 1, 19),
        end: d(2026, 1, 23),
        kind: EiBreakKind.unpaidLeave,
      );
      expect(hoursFor(run([gap]), 'a'), closeTo(240, 1e-9));
      // A break for one job leaves the other alone.
      expect(hoursFor(run([gap]), 'b'), closeTo(80, 1e-9));
      // Unpaid leave with no job applies to every job.
      final both = run([gap, unpaid]);
      expect(hoursFor(both, 'a'), closeTo(200, 1e-9));
      expect(hoursFor(both, 'b'), closeTo(70, 1e-9));
    });

    test('a week partly inside the period counts its working days inside', () {
      final weekdays = settled(
        [entry('r1', 'a', d(2026, 1, 12), d(2026, 1, 18), 40)],
        jobs: [job('a', variable: true)],
      );
      // The period opens on Friday, January 16: one of five working days.
      expect(weekdays.currentHours, closeTo(8, 1e-9));

      final everyDay = settled(
        [entry('r1', 'a', d(2026, 1, 12), d(2026, 1, 18), 40)],
        jobs: [job('a', variable: true, days: 7)],
      );
      // Friday to Sunday: three of seven days.
      expect(everyDay.currentHours, closeTo(40 * 3 / 7, 1e-9));
    });

    test('overlapping entries for one job are flagged', () {
      final estimate = settled([
        entry('r1', 'a', d(2026, 3, 2), d(2026, 3, 8), 40),
        entry('r2', 'a', d(2026, 3, 1), d(2026, 3, 14), 80),
      ]);
      expect(estimate.notices, contains(EiNotice.overlappingEntries));
    });

    test('a job marked not insurable is left out', () {
      final estimate = settled(
        [
          entry('r1', 'a', d(2026, 3, 1), d(2026, 3, 31), 300),
          entry('r2', 'b', d(2026, 3, 1), d(2026, 3, 31), 300),
        ],
        jobs: [job('a', variable: true), job('b', insurable: false)],
      );
      expect(estimate.currentHours, closeTo(300, 1e-9));
      expect(estimate.notices, contains(EiNotice.nonInsurableJobsExcluded));
    });
  });

  group('projection', () {
    EiHoursEstimate example({double past = 472, double weekly = 32}) =>
        engine.estimate(
          EiTrackerData(
            plannedClaimStart: d(2027, 1, 15),
            jobs: [job('a', start: d(2026, 5, 1), weekly: weekly)],
            records: [entry('r1', 'a', d(2026, 5, 1), d(2026, 9, 11), past)],
          ),
          today: d(2026, 9, 11),
        );

    test('current plus projected future hours is the total at leave', () {
      final estimate = example(past: 420, weekly: 30);
      expect(estimate.currentHours, closeTo(420, 1e-9));
      // September 12, 2026 to January 14, 2027 holds 89 weekdays, at six
      // hours each.
      expect(estimate.projectedFutureHours, closeTo(534, 1e-9));
      expect(
        estimate.projectedAtLeave,
        closeTo(estimate.currentHours + estimate.projectedFutureHours, 1e-9),
      );
      expect(estimate.status, EiStatus.onTrack);
    });

    test('472 of 600 at 32 hours a week is about four weeks away', () {
      final estimate = example();
      expect(estimate.remainingHours, closeTo(128, 1e-9));
      expect(estimate.fractionComplete, closeTo(472 / 600, 1e-9));
      expect(estimate.forwardWeeklyHours, 32);
      // 128 hours at 6.4 a weekday is 20 weekdays: Friday, October 9.
      expect(estimate.estimatedReachDate, d(2026, 10, 9));
      expect(estimate.weeksToReach, closeTo(4, 1e-9));
      expect(estimate.daysUntilLeave, 125);
      expect(estimate.requiredWeeklyHours, closeTo(128 / (125 / 7), 1e-9));
    });

    test('a slow pace that misses the leave date is at risk', () {
      final estimate = example(past: 100, weekly: 5);
      expect(estimate.reachesAfterLeave, isTrue);
      expect(estimate.status, EiStatus.atRisk);
    });

    test('what if compares weekly paces', () {
      final estimate = example();
      final slow = estimate.whatIf(20);
      final fast = estimate.whatIf(40);
      expect(fast.reachDate!.isBefore(slow.reachDate!), isTrue);
      expect(estimate.whatIf(32).reachDate, estimate.estimatedReachDate);
      expect(estimate.whatIf(0).reachDate, isNull);
      expect(fast.projectedAtLeave!, greaterThan(slow.projectedAtLeave!));
    });
  });

  group('history', () {
    test('monthly rows run a total across employers', () {
      final estimate = settled(
        [
          entry('r1', 'a', d(2026, 3, 1), d(2026, 3, 31), 350),
          entry('r2', 'b', d(2026, 4, 1), d(2026, 4, 30), 210),
        ],
        jobs: [
          job('a', name: 'Employer A', variable: true),
          job('b', name: 'Employer B', variable: true),
        ],
      );
      final rows = estimate.history(EiHistoryGranularity.monthly);
      expect(rows, hasLength(2));
      expect(rows[0].employerName, 'Employer A');
      expect(rows[0].periodStart, d(2026, 3, 1));
      expect(rows[0].cumulativeHours, closeTo(350, 1e-9));
      expect(rows[0].remainingHours, closeTo(250, 1e-9));
      expect(rows[1].cumulativeHours, closeTo(560, 1e-9));
      expect(rows[1].remainingHours, closeTo(40, 1e-9));
      expect(rows.every((r) => r.kind == EiHoursKind.recorded), isTrue);

      final weekly = estimate.history(EiHistoryGranularity.weekly);
      expect(weekly.last.cumulativeHours, closeTo(560, 1e-9));
      // Weeks start on Sunday, and never before the period.
      expect(weekly.first.periodStart.weekday, DateTime.sunday);
    });

    test('projected weeks are marked as projected', () {
      final estimate = engine.estimate(
        EiTrackerData(
          plannedClaimStart: d(2026, 10, 1),
          jobs: [job('a', start: d(2026, 9, 1), weekly: 30)],
        ),
        today: d(2026, 9, 11),
      );
      final rows = estimate.history(EiHistoryGranularity.weekly);
      expect(rows.first.kind, EiHoursKind.estimated);
      expect(rows.last.kind, EiHoursKind.projected);
    });
  });

  group('missing information', () {
    test('no employment data is insufficient, without failing', () {
      final estimate = engine.estimate(
        EiTrackerData(plannedClaimStart: d(2027, 1, 15)),
        today: d(2026, 9, 11),
      );
      expect(estimate.status, EiStatus.insufficientInformation);
      expect(estimate.missing, contains(EiMissingInfo.employment));
      expect(estimate.currentHours, 0);
      expect(estimate.averageWeeklyHours, isNull);
      expect(estimate.history(EiHistoryGranularity.weekly), isEmpty);
    });

    test('nothing entered at all asks for the leave date too', () {
      final estimate = engine.estimate(
        const EiTrackerData(),
        today: d(2026, 9, 11),
      );
      expect(estimate.missing, containsAll(<EiMissingInfo>[
        EiMissingInfo.claimStart,
        EiMissingInfo.employment,
      ]));
      expect(estimate.isProvisionalPeriod, isTrue);
    });

    test('a job with no hours at all asks for hours', () {
      final estimate = engine.estimate(
        EiTrackerData(plannedClaimStart: d(2027, 1, 15), jobs: [job('a')]),
        today: d(2026, 9, 11),
      );
      expect(estimate.missing, contains(EiMissingInfo.hours));
    });
  });
}
