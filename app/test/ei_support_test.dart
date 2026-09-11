import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/ei/ei_calculators.dart';
import 'package:spendwise/data/ei/ei_config.dart';
import 'package:spendwise/data/ei/ei_dates.dart';
import 'package:spendwise/data/ei/ei_models.dart';
import 'package:spendwise/data/ei/ei_payroll_detection.dart';
import 'package:spendwise/data/models/app_transaction.dart';
import 'package:spendwise/data/models/user_preferences.dart';
import 'package:spendwise/services/backup_service.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

DateTime d(int year, int month, int day) => DateTime.utc(year, month, day);

AppTransaction deposit(String id, DateTime when, String merchant) =>
    AppTransaction(
      id: id,
      eventType: TransactionEventType.transfer,
      amountCents: 185000,
      currency: 'CAD',
      occurredAt: DateTime(when.year, when.month, when.day, 9),
      category: SpendCategory.other,
      source: TransactionSource.statement,
      merchant: merchant,
    );

void main() {
  group('hours between two dates', () {
    test('March 1, 2026 to January 10, 2027 at 30 hours a week', () {
      final result = hoursBetweenDates(
        start: d(2026, 3, 1),
        end: d(2027, 1, 10),
        weeklyHours: 30,
      );
      expect(result.totalDays, 316);
      expect(result.fullWeeks, 45);
      expect(result.extraDays, 1);
      // The leftover day is a Sunday, so it adds no working day.
      expect(result.workingDays, 225);
      expect(result.hours, closeTo(1350, 1e-9));
    });

    test('a partial week counts only its working days', () {
      // Thursday to the following Tuesday: Thu, Fri, Mon, Tue.
      final result = hoursBetweenDates(
        start: d(2026, 9, 10),
        end: d(2026, 9, 15),
        weeklyHours: 40,
      );
      expect(result.workingDays, 4);
      expect(result.hours, closeTo(32, 1e-9));

      final everyDay = hoursBetweenDates(
        start: d(2026, 3, 1),
        end: d(2027, 1, 10),
        weeklyHours: 30,
        daysPerWeek: 7,
      );
      expect(everyDay.hours, closeTo(30 / 7 * 316, 1e-9));
    });

    test('days are counted across the March clock change', () {
      expect(
        hoursBetweenDates(
          start: DateTime(2026, 3, 1),
          end: DateTime(2026, 3, 14),
          weeklyHours: 35,
        ).totalDays,
        14,
      );
    });

    test('an end before the start is nothing', () {
      final result = hoursBetweenDates(
        start: d(2026, 5, 1),
        end: d(2026, 4, 1),
        weeklyHours: 40,
      );
      expect(result.totalDays, 0);
      expect(result.hours, 0);
    });
  });

  group('annual work hours', () {
    const input = EiAnnualHoursInput(
      hoursPerDay: 7.5,
      daysPerWeek: 5,
      vacationWeeks: 3,
      unpaidLeaveWeeks: 1,
      holidayDays: 10,
      overtimeHoursPerWeek: 2,
    );

    test('turns a working pattern into weekly, monthly and annual hours', () {
      final result = calculateAnnualHours(input);
      expect(result.weeklyHours, closeTo(39.5, 1e-9));
      expect(result.workingWeeks, closeTo(48, 1e-9));
      // 48 weeks of 37.5 hours, less 10 holidays, plus 96 hours overtime.
      expect(result.hoursWorked, closeTo(1821, 1e-9));
      // Three weeks of paid vacation and ten paid holidays.
      expect(result.paidTimeOffHours, closeTo(187.5, 1e-9));
      expect(result.annualInsurableHours, closeTo(2008.5, 1e-9));
      expect(result.monthlyAverageHours, closeTo(2008.5 / 12, 1e-9));
      expect(result.qualifyingPeriodHours, closeTo(2008.5, 1e-9));
    });

    test('a shorter qualifying period holds a share of the year', () {
      final result = calculateAnnualHours(input, qualifyingPeriodDays: 182);
      expect(result.qualifyingPeriodHours, closeTo(2008.5 / 2, 1e-9));
    });

    test('unpaid time off adds no insurable hours', () {
      final result = calculateAnnualHours(
        const EiAnnualHoursInput(
          hoursPerDay: 8,
          daysPerWeek: 5,
          vacationWeeks: 2,
          vacationIsPaid: false,
          holidayDays: 5,
          holidaysArePaid: false,
        ),
      );
      expect(result.paidTimeOffHours, 0);
      expect(result.annualInsurableHours, closeTo(50 * 40 - 40, 1e-9));
    });
  });

  group('payroll deposits', () {
    test('a regular payer is found with its pay frequency', () {
      final patterns = EiPayrollDetector.detect([
        for (var i = 0; i < 4; i++)
          deposit(
            'p$i',
            EiDates.addDays(d(2026, 7, 3), 14 * i),
            'PAY HARMONY FAMILY',
          ),
        deposit('card', d(2026, 7, 10), 'PAYMENT THANK YOU'),
      ]);
      expect(patterns, hasLength(1));
      expect(patterns.single.payerName, 'HARMONY FAMILY');
      expect(patterns.single.count, 4);
      expect(patterns.single.frequency, EiPayFrequency.biweekly);
      expect(patterns.single.lastPayDate, d(2026, 8, 14));
    });

    test('pay schedules are read from the gaps between pay days', () {
      List<DateTime> every(int days) => [
        for (var i = 0; i < 5; i++) EiDates.addDays(d(2026, 1, 2), days * i),
      ];
      expect(
        EiPayrollDetector.frequencyFromDates(every(7)),
        EiPayFrequency.weekly,
      );
      expect(
        EiPayrollDetector.frequencyFromDates([
          d(2026, 1, 15),
          d(2026, 1, 31),
          d(2026, 2, 15),
          d(2026, 2, 28),
          d(2026, 3, 15),
        ]),
        EiPayFrequency.semiMonthly,
      );
      expect(
        EiPayrollDetector.frequencyFromDates([
          d(2026, 1, 30),
          d(2026, 2, 27),
          d(2026, 3, 31),
        ]),
        EiPayFrequency.monthly,
      );
      expect(EiPayrollDetector.frequencyFromDates(every(45)), isNull);
    });
  });

  group('pay periods', () {
    test('each frequency ends its period on the expected day', () {
      expect(EiPayFrequency.weekly.periodEnd(d(2026, 9, 6)), d(2026, 9, 12));
      expect(EiPayFrequency.biweekly.periodEnd(d(2026, 9, 6)), d(2026, 9, 19));
      expect(
        EiPayFrequency.semiMonthly.periodEnd(d(2026, 9, 1)),
        d(2026, 9, 15),
      );
      expect(
        EiPayFrequency.semiMonthly.periodEnd(d(2026, 2, 16)),
        d(2026, 2, 28),
      );
      expect(EiPayFrequency.monthly.periodEnd(d(2026, 1, 31)), d(2026, 2, 27));
    });

    test('hours per pay period become hours per week', () {
      final perPeriod = EiJob(
        id: 'a',
        employerName: 'A',
        startDate: d(2026, 1, 1),
        payFrequency: EiPayFrequency.biweekly,
        hoursPerPayPeriod: 70,
      );
      expect(perPeriod.scheduledWeeklyHours, closeTo(35, 1e-9));
    });
  });

  group('saved data', () {
    final data = EiTrackerData(
      plannedClaimStart: d(2027, 1, 15),
      hadPreviousClaim: true,
      previousClaimStart: d(2026, 6, 1),
      jobs: [
        EiJob(
          id: 'a',
          employerName: 'Harmony Family',
          startDate: d(2025, 4, 1),
          employmentType: EiEmploymentType.partTime,
          usualWeeklyHours: 28,
          daysPerWeek: 4,
          variableHours: true,
          payFrequency: EiPayFrequency.semiMonthly,
          hoursPerPayPeriod: 60,
        ),
      ],
      records: [
        EiHoursRecord(
          id: 'r',
          jobId: 'a',
          periodStart: d(2026, 8, 1),
          periodEnd: d(2026, 8, 15),
          hoursWorked: 55,
          vacationHours: 4,
          source: EiHoursSource.payStub,
          documentId: 'doc-1',
        ),
      ],
      breaks: [
        EiBreak(
          id: 'b',
          start: d(2026, 3, 1),
          end: d(2026, 3, 20),
          kind: EiBreakKind.unpaidLeave,
          jobId: 'a',
        ),
      ],
    );

    test('round-trips through its stored form', () {
      final restored = EiTrackerData.decode(data.encode());
      expect(restored.encode(), data.encode());
      expect(restored.records.single.source, EiHoursSource.payStub);
      expect(restored.jobs.single.payFrequency, EiPayFrequency.semiMonthly);
    });

    test('rejects an entry for a job that does not exist', () {
      final json = data.toJson();
      (json['jobs']! as List).clear();
      expect(() => EiTrackerData.fromJson(json), throwsFormatException);
    });

    test('rejects more hours than the period has', () {
      final json = data.toJson();
      final records = json['records']! as List;
      (records.single as Map)['hours_worked'] = 400;
      expect(() => EiTrackerData.fromJson(json), throwsFormatException);
    });

    test('travels in a SpendWise backup, which still reads without it', () {
      BackupData backup({EiTrackerData? eiHours}) => BackupData(
        transactions: const [],
        accounts: const [],
        budgets: const [],
        rules: const [],
        bills: const [],
        preferences: const UserPreferences(),
        eiHours: eiHours,
      );
      final restored = BackupData.decode(backup(eiHours: data).encode());
      expect(restored.eiHours!.encode(), data.encode());
      expect(BackupData.decode(backup().encode()).eiHours, isNull);
    });

    test('removing a job removes what belongs to it', () {
      final removed = data.removeJob('a');
      expect(removed.jobs, isEmpty);
      expect(removed.records, isEmpty);
      expect(removed.breaks, isEmpty);
    });

    test('merging keeps what is here and adds what is missing', () {
      final other = EiTrackerData(
        plannedClaimStart: d(2027, 3, 1),
        jobs: [EiJob(id: 'z', employerName: 'Z', startDate: d(2026, 1, 1))],
      );
      final merged = data.mergeMissing(other);
      expect(merged.plannedClaimStart, d(2027, 1, 15));
      expect(merged.jobs.map((j) => j.id), ['a', 'z']);
    });
  });

  test('regulatory values live in one place', () {
    expect(EiConfig.rules.country, 'CA');
    expect(EiConfig.rules.maternityParentalRequiredHours, 600);
    expect(EiConfig.rules.qualifyingPeriodWeeks, 52);
    expect(EiConfig.rules.qualifyingPeriodDays, 364);
  });
}
