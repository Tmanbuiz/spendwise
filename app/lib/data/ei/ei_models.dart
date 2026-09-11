import 'dart:convert';

import 'ei_config.dart';
import 'ei_dates.dart';

/// The kind of work a job is. Shown to the user and kept for their records;
/// the estimate treats every insurable job the same way.
enum EiEmploymentType {
  fullTime('Full-time'),
  partTime('Part-time'),
  casual('Casual or on-call'),
  seasonal('Seasonal'),
  contract('Contract or temporary'),
  other('Other');

  const EiEmploymentType(this.label);
  final String label;

  static EiEmploymentType fromName(Object? name) => EiEmploymentType.values
      .firstWhere((v) => v.name == name, orElse: () => EiEmploymentType.other);
}

enum EiPayFrequency {
  weekly('Weekly'),
  biweekly('Every two weeks'),
  semiMonthly('Twice a month'),
  monthly('Monthly');

  const EiPayFrequency(this.label);
  final String label;

  /// Average length of one pay period in days, used to turn hours per pay
  /// period into hours per week.
  double get averageDays {
    switch (this) {
      case EiPayFrequency.weekly:
        return 7;
      case EiPayFrequency.biweekly:
        return 14;
      case EiPayFrequency.semiMonthly:
        return 365.2425 / 24;
      case EiPayFrequency.monthly:
        return 365.2425 / 12;
    }
  }

  /// The last day of a pay period starting on [start]. Semi-monthly periods
  /// follow the common 1st to 15th and 16th to end-of-month split.
  DateTime periodEnd(DateTime start) {
    final date = EiDates.day(start);
    switch (this) {
      case EiPayFrequency.weekly:
        return EiDates.addDays(date, 6);
      case EiPayFrequency.biweekly:
        return EiDates.addDays(date, 13);
      case EiPayFrequency.semiMonthly:
        return date.day <= 15
            ? DateTime.utc(date.year, date.month, 15)
            : DateTime.utc(
                date.year,
                date.month,
                EiDates.daysInMonth(date.year, date.month),
              );
      case EiPayFrequency.monthly:
        final next = DateTime.utc(date.year, date.month + 1);
        final sameDay = date.day.clamp(
          1,
          EiDates.daysInMonth(next.year, next.month),
        );
        return EiDates.addDays(
          DateTime.utc(next.year, next.month, sameDay),
          -1,
        );
    }
  }

  static EiPayFrequency fromName(Object? name) => EiPayFrequency.values
      .firstWhere((v) => v.name == name, orElse: () => EiPayFrequency.biweekly);
}

/// How a block of hours was entered.
enum EiHoursSource {
  weekly('Weekly hours'),
  payPeriod('Pay period'),
  payStub('Pay stub');

  const EiHoursSource(this.label);
  final String label;

  static EiHoursSource fromName(Object? name) => EiHoursSource.values
      .firstWhere((v) => v.name == name, orElse: () => EiHoursSource.weekly);
}

enum EiBreakKind {
  gap('Employment gap'),
  unpaidLeave('Unpaid leave');

  const EiBreakKind(this.label);
  final String label;

  static EiBreakKind fromName(Object? name) => EiBreakKind.values
      .firstWhere((v) => v.name == name, orElse: () => EiBreakKind.gap);
}

/// Replaces a nullable field in `copyWith`, including with null, which a
/// plain optional parameter cannot express.
typedef EiValue<T> = T Function();

/// One employer. Hours from several jobs are kept apart and combined only in
/// the estimate.
class EiJob {
  const EiJob({
    required this.id,
    required this.employerName,
    required this.startDate,
    this.employmentType = EiEmploymentType.fullTime,
    this.endDate,
    this.usualWeeklyHours = 0,
    this.daysPerWeek = 5,
    this.variableHours = false,
    this.payFrequency = EiPayFrequency.biweekly,
    this.hoursPerPayPeriod,
    this.isInsurable = true,
  });

  final String id;
  final String employerName;
  final EiEmploymentType employmentType;
  final DateTime startDate;

  /// Null while the job is ongoing.
  final DateTime? endDate;

  /// Typical hours in a week. Fills weeks with no hours entered, and drives
  /// the projection forward to the leave date.
  final double usualWeeklyHours;

  /// Days in a normal working week, counted from Monday. Five means Monday
  /// to Friday, so a week that is only partly inside a period is counted by
  /// the working days that fall inside it.
  final int daysPerWeek;

  /// Hours change from week to week. Past weeks with no hours entered are
  /// then not guessed from the usual schedule (they count as nothing until
  /// real hours are entered) and the projection uses the average of the
  /// hours that were entered.
  final bool variableHours;

  final EiPayFrequency payFrequency;
  final double? hoursPerPayPeriod;

  /// False for work that is not insurable employment, such as
  /// self-employment. Such a job is kept but excluded from every total.
  final bool isInsurable;

  /// Hours in a normal week: the weekly figure when entered, otherwise
  /// derived from the hours per pay period.
  double get scheduledWeeklyHours {
    if (usualWeeklyHours > 0) return usualWeeklyHours;
    final perPeriod = hoursPerPayPeriod;
    if (perPeriod == null || perPeriod <= 0) return 0;
    return perPeriod * DateTime.daysPerWeek / payFrequency.averageDays;
  }

  bool isEmployedOn(DateTime day) =>
      !day.isBefore(startDate) && (endDate == null || !day.isAfter(endDate!));

  /// Whether [day] is one of the first [daysPerWeek] days counted from
  /// Monday.
  bool worksOn(DateTime day) => day.weekday <= daysPerWeek;

  EiJob copyWith({
    String? employerName,
    EiEmploymentType? employmentType,
    DateTime? startDate,
    EiValue<DateTime?>? endDate,
    double? usualWeeklyHours,
    int? daysPerWeek,
    bool? variableHours,
    EiPayFrequency? payFrequency,
    EiValue<double?>? hoursPerPayPeriod,
    bool? isInsurable,
  }) {
    return EiJob(
      id: id,
      employerName: employerName ?? this.employerName,
      employmentType: employmentType ?? this.employmentType,
      startDate: startDate ?? this.startDate,
      endDate: endDate == null ? this.endDate : endDate(),
      usualWeeklyHours: usualWeeklyHours ?? this.usualWeeklyHours,
      daysPerWeek: daysPerWeek ?? this.daysPerWeek,
      variableHours: variableHours ?? this.variableHours,
      payFrequency: payFrequency ?? this.payFrequency,
      hoursPerPayPeriod: hoursPerPayPeriod == null
          ? this.hoursPerPayPeriod
          : hoursPerPayPeriod(),
      isInsurable: isInsurable ?? this.isInsurable,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'employer_name': employerName,
    'employment_type': employmentType.name,
    'start_date': EiDates.encode(startDate),
    'end_date': endDate == null ? null : EiDates.encode(endDate!),
    'usual_weekly_hours': usualWeeklyHours,
    'days_per_week': daysPerWeek,
    'variable_hours': variableHours,
    'pay_frequency': payFrequency.name,
    'hours_per_pay_period': hoursPerPayPeriod,
    'is_insurable': isInsurable,
  };

  static EiJob fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['employer_name'];
    final start = EiDates.decode(json['start_date']);
    final end = EiDates.decode(json['end_date']);
    final weekly = _number(json['usual_weekly_hours']) ?? 0;
    final days = (json['days_per_week'] as num?)?.toInt() ?? 5;
    final perPeriod = _number(json['hours_per_pay_period']);
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        start == null ||
        (end != null && end.isBefore(start)) ||
        weekly < 0 ||
        weekly > 168 ||
        days < 1 ||
        days > 7 ||
        (perPeriod != null && (perPeriod < 0 || perPeriod > 744))) {
      throw const FormatException('Invalid EI job');
    }
    return EiJob(
      id: id,
      employerName: name.trim(),
      employmentType: EiEmploymentType.fromName(json['employment_type']),
      startDate: start,
      endDate: end,
      usualWeeklyHours: weekly,
      daysPerWeek: days,
      variableHours: (json['variable_hours'] as bool?) ?? false,
      payFrequency: EiPayFrequency.fromName(json['pay_frequency']),
      hoursPerPayPeriod: perPeriod,
      isInsurable: (json['is_insurable'] as bool?) ?? true,
    );
  }
}

/// The money printed on a pay stub, in cents.
///
/// Every field is optional because stubs differ. The checks use whatever is
/// there: gross less deductions against net pay, whether an EI premium was
/// taken, and whether the net pay reached the bank.
class EiPayStubDetails {
  const EiPayStubDetails({
    this.payDate,
    this.grossPayCents,
    this.incomeTaxCents,
    this.cppCents,
    this.eiPremiumCents,
    this.otherDeductionsCents,
    this.netPayCents,
  });

  /// The day the pay was deposited, as printed on the stub.
  final DateTime? payDate;
  final int? grossPayCents;

  /// Federal and provincial income tax together.
  final int? incomeTaxCents;

  /// CPP or QPP contributions.
  final int? cppCents;

  /// The EI premium deducted. A premium is the clearest sign on a stub that
  /// the hours are insurable.
  final int? eiPremiumCents;

  /// Everything else: union dues, benefits, pension, garnishments.
  final int? otherDeductionsCents;
  final int? netPayCents;

  bool get isEmpty =>
      payDate == null &&
      grossPayCents == null &&
      incomeTaxCents == null &&
      cppCents == null &&
      eiPremiumCents == null &&
      otherDeductionsCents == null &&
      netPayCents == null;

  int get totalDeductionsCents =>
      (incomeTaxCents ?? 0) +
      (cppCents ?? 0) +
      (eiPremiumCents ?? 0) +
      (otherDeductionsCents ?? 0);

  /// Gross pay less every deduction entered, or null without a gross figure.
  int? get calculatedNetCents {
    final gross = grossPayCents;
    return gross == null ? null : gross - totalDeductionsCents;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'pay_date': payDate == null ? null : EiDates.encode(payDate!),
    'gross_pay_cents': grossPayCents,
    'income_tax_cents': incomeTaxCents,
    'cpp_cents': cppCents,
    'ei_premium_cents': eiPremiumCents,
    'other_deductions_cents': otherDeductionsCents,
    'net_pay_cents': netPayCents,
  };

  static EiPayStubDetails fromJson(Map<String, Object?> json) {
    int? cents(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! int || value < 0) {
        throw FormatException('Invalid pay stub $key');
      }
      return value;
    }

    return EiPayStubDetails(
      payDate: EiDates.decode(json['pay_date']),
      grossPayCents: cents('gross_pay_cents'),
      incomeTaxCents: cents('income_tax_cents'),
      cppCents: cents('cpp_cents'),
      eiPremiumCents: cents('ei_premium_cents'),
      otherDeductionsCents: cents('other_deductions_cents'),
      netPayCents: cents('net_pay_cents'),
    );
  }
}

/// Hours worked for one job over one stretch of days: a week, a pay period,
/// or the period printed on a pay stub.
class EiHoursRecord {
  const EiHoursRecord({
    required this.id,
    required this.jobId,
    required this.periodStart,
    required this.periodEnd,
    required this.hoursWorked,
    this.overtimeHours = 0,
    this.vacationHours = 0,
    this.paidLeaveHours = 0,
    this.source = EiHoursSource.weekly,
    this.payStub,
    this.documentId,
    this.note,
  });

  final String id;
  final String jobId;
  final DateTime periodStart;
  final DateTime periodEnd;

  /// Regular hours worked in the period.
  final double hoursWorked;

  /// Overtime hours worked, insurable like any other hour worked.
  final double overtimeHours;

  /// Paid vacation taken in the period.
  final double vacationHours;

  /// Other paid leave in the period: statutory holidays, paid sick days.
  final double paidLeaveHours;

  final EiHoursSource source;

  /// Pay, deductions and pay date copied from the stub.
  final EiPayStubDetails? payStub;

  /// The Financial Vault pay stub the hours were read from, if any.
  final String? documentId;
  final String? note;

  int get days => EiDates.inclusiveDays(periodStart, periodEnd);

  bool get hasPayStubDetails => payStub != null && !payStub!.isEmpty;

  /// Hours this entry contributes under [rules]. Paid time off counts only
  /// where the rules say it does.
  double insurableHours(EiRules rules) =>
      hoursWorked +
      overtimeHours +
      (rules.countPaidVacationHours ? vacationHours : 0) +
      (rules.countPaidLeaveHours ? paidLeaveHours : 0);

  bool covers(DateTime day) =>
      !day.isBefore(periodStart) && !day.isAfter(periodEnd);

  bool overlaps(EiHoursRecord other) =>
      !other.periodEnd.isBefore(periodStart) &&
      !other.periodStart.isAfter(periodEnd);

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'job_id': jobId,
    'period_start': EiDates.encode(periodStart),
    'period_end': EiDates.encode(periodEnd),
    'hours_worked': hoursWorked,
    'overtime_hours': overtimeHours,
    'vacation_hours': vacationHours,
    'paid_leave_hours': paidLeaveHours,
    'source': source.name,
    'pay_stub': payStub?.toJson(),
    'document_id': documentId,
    'note': note,
  };

  static EiHoursRecord fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final jobId = json['job_id'];
    final start = EiDates.decode(json['period_start']);
    final end = EiDates.decode(json['period_end']);
    final worked = _number(json['hours_worked']);
    final overtime = _number(json['overtime_hours']) ?? 0;
    final vacation = _number(json['vacation_hours']) ?? 0;
    final leave = _number(json['paid_leave_hours']) ?? 0;
    final stub = json['pay_stub'];
    if (id is! String ||
        id.isEmpty ||
        jobId is! String ||
        jobId.isEmpty ||
        start == null ||
        end == null ||
        end.isBefore(start) ||
        worked == null ||
        worked < 0 ||
        overtime < 0 ||
        vacation < 0 ||
        leave < 0 ||
        worked + overtime + vacation + leave >
            EiDates.inclusiveDays(start, end) * Duration.hoursPerDay ||
        (stub != null && stub is! Map)) {
      throw const FormatException('Invalid EI hours entry');
    }
    return EiHoursRecord(
      id: id,
      jobId: jobId,
      periodStart: start,
      periodEnd: end,
      hoursWorked: worked,
      overtimeHours: overtime,
      vacationHours: vacation,
      paidLeaveHours: leave,
      source: EiHoursSource.fromName(json['source']),
      payStub: stub is Map
          ? EiPayStubDetails.fromJson(Map<String, Object?>.from(stub))
          : null,
      documentId: json['document_id'] as String?,
      note: json['note'] as String?,
    );
  }
}

/// A stretch with no insurable hours: between jobs, or on unpaid leave.
class EiBreak {
  const EiBreak({
    required this.id,
    required this.start,
    required this.end,
    this.kind = EiBreakKind.gap,
    this.jobId,
    this.note,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final EiBreakKind kind;

  /// The job the break belongs to, or null when it applies to every job.
  final String? jobId;
  final String? note;

  bool appliesTo(String job, DateTime day) =>
      (jobId == null || jobId == job) &&
      !day.isBefore(start) &&
      !day.isAfter(end);

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'start': EiDates.encode(start),
    'end': EiDates.encode(end),
    'kind': kind.name,
    'job_id': jobId,
    'note': note,
  };

  static EiBreak fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final start = EiDates.decode(json['start']);
    final end = EiDates.decode(json['end']);
    if (id is! String ||
        id.isEmpty ||
        start == null ||
        end == null ||
        end.isBefore(start)) {
      throw const FormatException('Invalid EI break');
    }
    return EiBreak(
      id: id,
      start: start,
      end: end,
      kind: EiBreakKind.fromName(json['kind']),
      jobId: json['job_id'] as String?,
      note: json['note'] as String?,
    );
  }
}

/// Everything the user has told the tracker.
class EiTrackerData {
  const EiTrackerData({
    this.plannedClaimStart,
    this.hadPreviousClaim = false,
    this.previousClaimStart,
    this.jobs = const <EiJob>[],
    this.records = const <EiHoursRecord>[],
    this.breaks = const <EiBreak>[],
  });

  static const int schemaVersion = 1;

  /// The day leave, and the EI claim, is planned to start. Shared with the
  /// Leave Planner, which is where the user usually sets it.
  final DateTime? plannedClaimStart;

  /// The user said they had an EI claim before this one.
  final bool hadPreviousClaim;
  final DateTime? previousClaimStart;

  final List<EiJob> jobs;
  final List<EiHoursRecord> records;
  final List<EiBreak> breaks;

  bool get isEmpty =>
      plannedClaimStart == null &&
      !hadPreviousClaim &&
      previousClaimStart == null &&
      jobs.isEmpty &&
      records.isEmpty &&
      breaks.isEmpty;

  EiJob? jobById(String id) {
    for (final job in jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  EiTrackerData copyWith({
    EiValue<DateTime?>? plannedClaimStart,
    bool? hadPreviousClaim,
    EiValue<DateTime?>? previousClaimStart,
    List<EiJob>? jobs,
    List<EiHoursRecord>? records,
    List<EiBreak>? breaks,
  }) {
    return EiTrackerData(
      plannedClaimStart: plannedClaimStart == null
          ? this.plannedClaimStart
          : plannedClaimStart(),
      hadPreviousClaim: hadPreviousClaim ?? this.hadPreviousClaim,
      previousClaimStart: previousClaimStart == null
          ? this.previousClaimStart
          : previousClaimStart(),
      jobs: jobs ?? this.jobs,
      records: records ?? this.records,
      breaks: breaks ?? this.breaks,
    );
  }

  EiTrackerData upsertJob(EiJob job) =>
      copyWith(jobs: _upsert(jobs, job, (j) => j.id));

  /// Removes a job along with the hours and breaks that belong only to it,
  /// so no entry is left pointing at an employer that no longer exists.
  EiTrackerData removeJob(String id) => copyWith(
    jobs: jobs.where((j) => j.id != id).toList(),
    records: records.where((r) => r.jobId != id).toList(),
    breaks: breaks.where((b) => b.jobId != id).toList(),
  );

  EiTrackerData upsertRecord(EiHoursRecord record) =>
      copyWith(records: _upsert(records, record, (r) => r.id));

  EiTrackerData removeRecord(String id) =>
      copyWith(records: records.where((r) => r.id != id).toList());

  EiTrackerData upsertBreak(EiBreak value) =>
      copyWith(breaks: _upsert(breaks, value, (b) => b.id));

  EiTrackerData removeBreak(String id) =>
      copyWith(breaks: breaks.where((b) => b.id != id).toList());

  /// Adds whatever [other] holds that this does not, by id. Existing rows
  /// and dates win, matching how a SpendWise restore treats everything else.
  EiTrackerData mergeMissing(EiTrackerData other) {
    List<T> merged<T>(List<T> mine, List<T> theirs, String Function(T) id) {
      final known = mine.map(id).toSet();
      return <T>[...mine, ...theirs.where((row) => !known.contains(id(row)))];
    }

    return EiTrackerData(
      plannedClaimStart: plannedClaimStart ?? other.plannedClaimStart,
      hadPreviousClaim: hadPreviousClaim || other.hadPreviousClaim,
      previousClaimStart: previousClaimStart ?? other.previousClaimStart,
      jobs: merged(jobs, other.jobs, (j) => j.id),
      records: merged(records, other.records, (r) => r.id),
      breaks: merged(breaks, other.breaks, (b) => b.id),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': schemaVersion,
    'planned_claim_start': plannedClaimStart == null
        ? null
        : EiDates.encode(plannedClaimStart!),
    'had_previous_claim': hadPreviousClaim,
    'previous_claim_start': previousClaimStart == null
        ? null
        : EiDates.encode(previousClaimStart!),
    'jobs': jobs.map((j) => j.toJson()).toList(),
    'records': records.map((r) => r.toJson()).toList(),
    'breaks': breaks.map((b) => b.toJson()).toList(),
  };

  /// Rejects anything malformed rather than guessing, so a bad backup or a
  /// corrupted save is reported instead of silently becoming wrong hours.
  static EiTrackerData fromJson(Map<String, Object?> json) {
    if (json['version'] != schemaVersion) {
      throw const FormatException('Unsupported EI tracker data');
    }
    List<T> rows<T>(
      String key,
      T Function(Map<String, Object?>) parse,
      String Function(T) id,
    ) {
      final raw = json[key];
      if (raw == null) return <T>[];
      if (raw is! List) throw FormatException('Invalid $key');
      final seen = <String>{};
      return raw.map((item) {
        if (item is! Map) throw FormatException('Invalid $key');
        final row = parse(Map<String, Object?>.from(item));
        if (!seen.add(id(row))) throw FormatException('Repeated id in $key');
        return row;
      }).toList();
    }

    final jobs = rows('jobs', EiJob.fromJson, (j) => j.id);
    final jobIds = jobs.map((j) => j.id).toSet();
    final records = rows('records', EiHoursRecord.fromJson, (r) => r.id);
    final breaks = rows('breaks', EiBreak.fromJson, (b) => b.id);
    if (records.any((r) => !jobIds.contains(r.jobId)) ||
        breaks.any((b) => b.jobId != null && !jobIds.contains(b.jobId))) {
      throw const FormatException('EI entry refers to a missing job');
    }
    return EiTrackerData(
      plannedClaimStart: EiDates.decode(json['planned_claim_start']),
      hadPreviousClaim: (json['had_previous_claim'] as bool?) ?? false,
      previousClaimStart: EiDates.decode(json['previous_claim_start']),
      jobs: jobs,
      records: records,
      breaks: breaks,
    );
  }

  String encode() => jsonEncode(toJson());

  static EiTrackerData decode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('Invalid EI tracker data');
    }
    return fromJson(Map<String, Object?>.from(decoded));
  }
}

List<T> _upsert<T>(List<T> rows, T row, String Function(T) id) {
  final index = rows.indexWhere((r) => id(r) == id(row));
  final next = List<T>.from(rows);
  if (index >= 0) {
    next[index] = row;
  } else {
    next.add(row);
  }
  return next;
}

double? _number(Object? value) => value is num ? value.toDouble() : null;
