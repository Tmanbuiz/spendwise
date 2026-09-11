/// The Canadian Employment Insurance values the hours tracker depends on.
///
/// Every regulatory number the tracker uses lives in this file and nowhere
/// else. When Service Canada changes a rule, this is the one place to edit,
/// and the tests that pin each rule will say what moved.
///
/// Nothing here is an official determination. Service Canada decides
/// eligibility from the claimant's Records of Employment; these values only
/// let SpendWise produce a planning estimate.
class EiRules {
  const EiRules({
    required this.country,
    required this.maternityParentalRequiredHours,
    required this.qualifyingPeriodWeeks,
    required this.countPaidVacationHours,
    required this.countPaidLeaveHours,
    required this.lastReviewed,
  });

  /// ISO country code the rules apply to.
  final String country;

  /// Insurable hours needed in the qualifying period for maternity or
  /// parental benefits.
  final double maternityParentalRequiredHours;

  /// Length of the standard qualifying period. It is shortened when a
  /// previous benefit period started inside it.
  final int qualifyingPeriodWeeks;

  /// Whether hours of paid vacation are counted. Employers usually report
  /// paid time off as insurable hours on the Record of Employment.
  final bool countPaidVacationHours;

  /// Whether other paid leave (statutory holidays, paid sick days) is
  /// counted, for the same reason.
  final bool countPaidLeaveHours;

  /// When these values were last checked against Service Canada's
  /// published rules, as `yyyy-MM-dd`. Shown so a stale rule set is visible.
  final String lastReviewed;

  int get qualifyingPeriodDays => qualifyingPeriodWeeks * DateTime.daysPerWeek;

  EiRules copyWith({
    String? country,
    double? maternityParentalRequiredHours,
    int? qualifyingPeriodWeeks,
    bool? countPaidVacationHours,
    bool? countPaidLeaveHours,
    String? lastReviewed,
  }) {
    return EiRules(
      country: country ?? this.country,
      maternityParentalRequiredHours:
          maternityParentalRequiredHours ?? this.maternityParentalRequiredHours,
      qualifyingPeriodWeeks:
          qualifyingPeriodWeeks ?? this.qualifyingPeriodWeeks,
      countPaidVacationHours:
          countPaidVacationHours ?? this.countPaidVacationHours,
      countPaidLeaveHours: countPaidLeaveHours ?? this.countPaidLeaveHours,
      lastReviewed: lastReviewed ?? this.lastReviewed,
    );
  }
}

/// How the tracker turns an estimate into a status. Product judgement, not
/// law — kept apart from [EiRules] so the two are never confused.
class EiPlanningSettings {
  const EiPlanningSettings({
    required this.onTrackBufferFraction,
    required this.projectionHorizonDays,
    required this.whatIfWeeklyHours,
  });

  /// A projection has to clear the requirement by this fraction to read as
  /// "On track". Projections are estimates, so landing exactly on the line
  /// is shown as "At risk" rather than as a promise.
  final double onTrackBufferFraction;

  /// How far ahead the reach-date search looks before giving up.
  final int projectionHorizonDays;

  /// The preset rates offered by the "What if I work…" calculator.
  final List<double> whatIfWeeklyHours;
}

/// How pay stubs are checked against the bank. Product judgement, not law.
class EiVerificationSettings {
  const EiVerificationSettings({
    required this.depositDaysBeforePayDate,
    required this.depositDaysAfterPayDate,
    required this.depositSearchDaysWithoutPayDate,
    required this.netPayToleranceCents,
  });

  /// Payroll sometimes lands a day or two before the date on the stub.
  final int depositDaysBeforePayDate;

  /// Or a few days after it, across a weekend or a holiday.
  final int depositDaysAfterPayDate;

  /// Without a pay date, how long after the period ends to look.
  final int depositSearchDaysWithoutPayDate;

  /// Rounding slack when gross pay less deductions is compared with net pay.
  final int netPayToleranceCents;
}

/// Calendar arithmetic shared by the calculators. Not an EI rule.
abstract final class EiCalendar {
  static const double weeksPerYear = 52;
  static const int monthsPerYear = 12;
}

/// The rule set in force. Swap or copy this to model a rule change.
abstract final class EiConfig {
  static const EiRules rules = EiRules(
    country: 'CA',
    maternityParentalRequiredHours: 600,
    qualifyingPeriodWeeks: 52,
    countPaidVacationHours: true,
    countPaidLeaveHours: true,
    lastReviewed: '2026-09-11',
  );

  static const EiPlanningSettings planning = EiPlanningSettings(
    onTrackBufferFraction: 0.05,
    projectionHorizonDays: 1095,
    whatIfWeeklyHours: <double>[20, 25, 30, 35, 40],
  );

  static const EiVerificationSettings verification = EiVerificationSettings(
    depositDaysBeforePayDate: 2,
    depositDaysAfterPayDate: 4,
    depositSearchDaysWithoutPayDate: 10,
    netPayToleranceCents: 1,
  );
}
