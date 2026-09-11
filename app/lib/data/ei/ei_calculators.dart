import 'dart:math' as math;

import 'ei_config.dart';
import 'ei_dates.dart';

class EiAnnualHoursInput {
  const EiAnnualHoursInput({
    required this.hoursPerDay,
    required this.daysPerWeek,
    this.weeksPerYear = EiCalendar.weeksPerYear,
    this.vacationWeeks = 0,
    this.vacationIsPaid = true,
    this.unpaidLeaveWeeks = 0,
    this.holidayDays = 0,
    this.holidaysArePaid = true,
    this.overtimeHoursPerWeek = 0,
  });

  final double hoursPerDay;
  final int daysPerWeek;

  /// Weeks employed in the year, including vacation and unpaid leave.
  final double weeksPerYear;
  final double vacationWeeks;
  final bool vacationIsPaid;
  final double unpaidLeaveWeeks;

  /// Holidays falling on working days, in days.
  final double holidayDays;
  final bool holidaysArePaid;
  final double overtimeHoursPerWeek;
}

class EiAnnualHoursResult {
  const EiAnnualHoursResult({
    required this.weeklyHours,
    required this.workingWeeks,
    required this.hoursWorked,
    required this.paidTimeOffHours,
    required this.annualInsurableHours,
    required this.monthlyAverageHours,
    required this.qualifyingPeriodDays,
    required this.qualifyingPeriodHours,
  });

  /// Hours in a normal working week, overtime included.
  final double weeklyHours;
  final double workingWeeks;

  /// Hours actually worked in the year, overtime included.
  final double hoursWorked;

  /// Paid vacation and paid holidays counted as insurable under the rules.
  final double paidTimeOffHours;
  final double annualInsurableHours;
  final double monthlyAverageHours;
  final int qualifyingPeriodDays;

  /// Estimated insurable hours inside one qualifying period of that length.
  final double qualifyingPeriodHours;
}

/// A year of work reduced to hours, and to the share of them one qualifying
/// period would hold.
EiAnnualHoursResult calculateAnnualHours(
  EiAnnualHoursInput input, {
  EiRules rules = EiConfig.rules,
  int? qualifyingPeriodDays,
}) {
  double positive(double value) => math.max(0, value);

  final days = input.daysPerWeek.clamp(0, DateTime.daysPerWeek);
  final perDay = positive(input.hoursPerDay);
  final workingWeeks = positive(
    input.weeksPerYear - input.vacationWeeks - input.unpaidLeaveWeeks,
  );
  final holidayHours = positive(input.holidayDays) * perDay;
  final regular = positive(workingWeeks * days * perDay - holidayHours);
  final overtime = positive(input.overtimeHoursPerWeek) * workingWeeks;
  final worked = regular + overtime;

  final vacation = input.vacationIsPaid && rules.countPaidVacationHours
      ? positive(input.vacationWeeks) * days * perDay
      : 0.0;
  final holidays = input.holidaysArePaid && rules.countPaidLeaveHours
      ? holidayHours
      : 0.0;
  final insurable = worked + vacation + holidays;

  final periodDays = qualifyingPeriodDays ?? rules.qualifyingPeriodDays;
  final yearDays = EiCalendar.weeksPerYear * DateTime.daysPerWeek;
  final share = math.min(1.0, math.max(0, periodDays) / yearDays);

  return EiAnnualHoursResult(
    weeklyHours: days * perDay + positive(input.overtimeHoursPerWeek),
    workingWeeks: workingWeeks,
    hoursWorked: worked,
    paidTimeOffHours: vacation + holidays,
    annualInsurableHours: insurable,
    monthlyAverageHours: insurable / EiCalendar.monthsPerYear,
    qualifyingPeriodDays: periodDays,
    qualifyingPeriodHours: insurable * share,
  );
}

class EiDateRangeResult {
  const EiDateRangeResult({
    required this.totalDays,
    required this.fullWeeks,
    required this.extraDays,
    required this.workingDays,
    required this.hours,
  });

  final int totalDays;
  final int fullWeeks;

  /// Days left over after the full weeks — the partial week.
  final int extraDays;
  final int workingDays;
  final double hours;
}

/// Hours accumulated from [start] to [end], both included, at [weeklyHours]
/// spread evenly over the first [daysPerWeek] days of each week counted from
/// Monday. A partial week contributes only the working days it contains.
EiDateRangeResult hoursBetweenDates({
  required DateTime start,
  required DateTime end,
  required double weeklyHours,
  int daysPerWeek = 5,
}) {
  final days = daysPerWeek.clamp(1, DateTime.daysPerWeek);
  final total = EiDates.inclusiveDays(start, end);
  var working = 0;
  for (var i = 0; i < total; i++) {
    if (EiDates.addDays(start, i).weekday <= days) working++;
  }
  return EiDateRangeResult(
    totalDays: total,
    fullWeeks: total ~/ DateTime.daysPerWeek,
    extraDays: total % DateTime.daysPerWeek,
    workingDays: working,
    hours: math.max(0, weeklyHours) / days * working,
  );
}
