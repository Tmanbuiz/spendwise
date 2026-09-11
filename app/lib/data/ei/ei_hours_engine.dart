import 'dart:math' as math;

import 'ei_config.dart';
import 'ei_dates.dart';
import 'ei_models.dart';

enum EiStatus {
  onTrack('On track'),
  atRisk('At risk'),
  requirementReached('Estimated requirement reached'),
  insufficientInformation('Insufficient information');

  const EiStatus(this.label);
  final String label;
}

/// Something the estimate cannot be made without.
enum EiMissingInfo {
  claimStart('Add the date your leave and EI claim would start.'),
  employment('Add at least one insurable job.'),
  hours('Add usual weekly hours for a job, or enter hours worked.'),
  previousClaimStart('Add the start date of your previous EI claim.'),
  previousClaimAfterClaim(
    'Your previous claim must have started before your planned claim.',
  );

  const EiMissingInfo(this.message);
  final String message;
}

/// Worth telling the user, without blocking the estimate.
enum EiNotice {
  /// A previous claim started inside the standard qualifying period, so the
  /// period was shortened to begin on that date.
  previousClaimShortensPeriod,

  /// The user had a previous claim but has not said when it started.
  previousClaimDateNeeded,

  /// Two entries for the same job cover some of the same days. Both are
  /// counted, which may double count.
  overlappingEntries,

  /// The planned claim date is today or already past, so nothing further is
  /// projected.
  leaveDateReached,

  /// At least one job is marked as not insurable and is left out.
  nonInsurableJobsExcluded,
}

/// Where a day's hours came from, from most to least certain.
enum EiHoursKind {
  /// Entered by the user.
  recorded,

  /// A past day with nothing entered, filled from the job's usual schedule.
  estimated,

  /// A future day, projected from the usual schedule.
  projected,
}

enum EiHistoryGranularity { weekly, monthly }

/// The window of days whose insurable hours can count toward a claim.
class EiQualifyingPeriod {
  const EiQualifyingPeriod({
    required this.start,
    required this.end,
    required this.standardStart,
    required this.shortenedByPreviousClaim,
  });

  /// Generally the shorter of the standard number of weeks immediately
  /// before the claim starts, or the time since a previous benefit period
  /// began, when that began inside those weeks.
  factory EiQualifyingPeriod.forClaim({
    required DateTime claimStart,
    DateTime? previousClaimStart,
    EiRules rules = EiConfig.rules,
  }) {
    final claim = EiDates.day(claimStart);
    final standardStart = EiDates.addDays(claim, -rules.qualifyingPeriodDays);
    final previous = previousClaimStart == null
        ? null
        : EiDates.day(previousClaimStart);
    final shortened =
        previous != null &&
        previous.isAfter(standardStart) &&
        previous.isBefore(claim);
    return EiQualifyingPeriod(
      start: shortened ? previous : standardStart,
      end: EiDates.addDays(claim, -1),
      standardStart: standardStart,
      shortenedByPreviousClaim: shortened,
    );
  }

  final DateTime start;
  final DateTime end;
  final DateTime standardStart;
  final bool shortenedByPreviousClaim;

  int get days => EiDates.inclusiveDays(start, end);
  double get weeks => days / DateTime.daysPerWeek;

  bool contains(DateTime day) => !day.isBefore(start) && !day.isAfter(end);
}

class EiJobSummary {
  const EiJobSummary({
    required this.job,
    required this.currentHours,
    required this.projectedHours,
  });

  final EiJob job;
  final double currentHours;

  /// Hours still expected before the planned leave date.
  final double projectedHours;

  double get totalAtLeave => currentHours + projectedHours;
}

class EiHistoryRow {
  const EiHistoryRow({
    required this.periodStart,
    required this.periodEnd,
    required this.jobId,
    required this.employerName,
    required this.hours,
    required this.cumulativeHours,
    required this.remainingHours,
    required this.kind,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final String jobId;
  final String employerName;
  final double hours;
  final double cumulativeHours;
  final double remainingHours;

  /// The least certain source among the days in the row.
  final EiHoursKind kind;
}

class EiWhatIfResult {
  const EiWhatIfResult({
    required this.weeklyHours,
    required this.reachDate,
    required this.alreadyReached,
    required this.projectedAtLeave,
  });

  final double weeklyHours;

  /// The day the requirement would be met, or null when it is not met within
  /// the projection horizon.
  final DateTime? reachDate;
  final bool alreadyReached;

  /// Hours in the qualifying period by the planned leave date, when a leave
  /// date is set.
  final double? projectedAtLeave;
}

/// Turns what the user entered into an estimate of insurable hours.
///
/// Days are the unit throughout. Each job contributes hours to each day: an
/// entry spread over the working days it covers or, for days with nothing
/// entered, the job's usual schedule. Totals are sums over days, which is
/// what makes weeks that are only partly inside a period come out right.
class EiHoursEngine {
  const EiHoursEngine({
    this.rules = EiConfig.rules,
    this.planning = EiConfig.planning,
  });

  final EiRules rules;
  final EiPlanningSettings planning;

  EiHoursEstimate estimate(EiTrackerData data, {required DateTime today}) {
    final asOf = EiDates.day(today);
    final missing = <EiMissingInfo>{};
    final notices = <EiNotice>{};

    final claim = data.plannedClaimStart == null
        ? null
        : EiDates.day(data.plannedClaimStart!);
    if (claim == null) missing.add(EiMissingInfo.claimStart);

    final insurable = data.jobs.where((j) => j.isInsurable).toList();
    final insurableIds = insurable.map((j) => j.id).toSet();
    if (insurable.isEmpty) {
      missing.add(EiMissingInfo.employment);
    } else if (!insurable.any((j) => j.scheduledWeeklyHours > 0) &&
        !data.records.any((r) => insurableIds.contains(r.jobId))) {
      missing.add(EiMissingInfo.hours);
    }
    if (data.jobs.length != insurable.length) {
      notices.add(EiNotice.nonInsurableJobsExcluded);
    }

    DateTime? previous;
    if (data.hadPreviousClaim) {
      if (data.previousClaimStart == null) {
        missing.add(EiMissingInfo.previousClaimStart);
        notices.add(EiNotice.previousClaimDateNeeded);
      } else {
        previous = EiDates.day(data.previousClaimStart!);
        if (claim != null && !previous.isBefore(claim)) {
          missing.add(EiMissingInfo.previousClaimAfterClaim);
          previous = null;
        }
      }
    }

    // Without a leave date, show the period for a claim starting tomorrow,
    // so the user sees their hours while the estimate still reads as
    // incomplete.
    final period = EiQualifyingPeriod.forClaim(
      claimStart: claim ?? EiDates.addDays(asOf, 1),
      previousClaimStart: previous,
      rules: rules,
    );
    if (period.shortenedByPreviousClaim) {
      notices.add(EiNotice.previousClaimShortensPeriod);
    }
    if (claim != null && !claim.isAfter(asOf)) {
      notices.add(EiNotice.leaveDateReached);
    }
    if (_hasOverlaps(data.records)) notices.add(EiNotice.overlappingEntries);

    final ledger = _Ledger.build(
      data: data,
      jobs: insurable,
      rules: rules,
      today: asOf,
      from: EiDates.earlier(
        period.start,
        EiDates.addDays(asOf, -rules.qualifyingPeriodDays),
      ),
      to: EiDates.later(
        period.end,
        EiDates.addDays(asOf, planning.projectionHorizonDays),
      ),
    );

    final countedEnd = EiDates.earlier(asOf, period.end);
    final futureStart = EiDates.later(EiDates.addDays(asOf, 1), period.start);
    final summaries = <EiJobSummary>[
      for (final job in insurable)
        EiJobSummary(
          job: job,
          currentHours: ledger.sumJob(job.id, period.start, countedEnd),
          projectedHours: ledger.sumJob(job.id, futureStart, period.end),
        ),
    ];

    return EiHoursEstimate._(
      this,
      data,
      ledger,
      previous,
      asOf: asOf,
      claimStart: claim,
      period: period,
      missing: missing,
      notices: notices,
      jobs: summaries,
    );
  }

  static bool _hasOverlaps(List<EiHoursRecord> records) {
    for (var i = 0; i < records.length; i++) {
      for (var j = i + 1; j < records.length; j++) {
        if (records[i].jobId == records[j].jobId &&
            records[i].overlaps(records[j])) {
          return true;
        }
      }
    }
    return false;
  }
}

class EiHoursEstimate {
  EiHoursEstimate._(
    this._engine,
    this._data,
    this._ledger,
    this._previousClaimStart, {
    required this.asOf,
    required this.claimStart,
    required this.period,
    required Set<EiMissingInfo> missing,
    required Set<EiNotice> notices,
    required this.jobs,
  }) : missing = Set<EiMissingInfo>.unmodifiable(missing),
       notices = Set<EiNotice>.unmodifiable(notices);

  final EiHoursEngine _engine;
  final EiTrackerData _data;
  final _Ledger _ledger;
  final DateTime? _previousClaimStart;

  final DateTime asOf;
  final DateTime? claimStart;

  /// The qualifying period for the planned claim. When no claim date is set
  /// this is the period for a claim starting tomorrow, and
  /// [isProvisionalPeriod] is true.
  final EiQualifyingPeriod period;
  final Set<EiMissingInfo> missing;
  final Set<EiNotice> notices;
  final List<EiJobSummary> jobs;

  EiRules get rules => _engine.rules;

  EiPlanningSettings get planning => _engine.planning;

  bool get isProvisionalPeriod => claimStart == null;

  bool get hasEmployment => jobs.isNotEmpty;

  double get requiredHours => rules.maternityParentalRequiredHours;

  /// Estimated insurable hours in the qualifying period up to and including
  /// today.
  double get currentHours =>
      jobs.fold(0, (sum, job) => sum + job.currentHours);

  /// Hours still expected between tomorrow and the end of the qualifying
  /// period.
  double get projectedFutureHours =>
      jobs.fold(0, (sum, job) => sum + job.projectedHours);

  double get projectedAtLeave => currentHours + projectedFutureHours;

  double get remainingHours => math.max(0, requiredHours - currentHours);

  double get projectedRemainingHours =>
      math.max(0, requiredHours - projectedAtLeave);

  /// Progress toward the requirement. Can exceed 1.
  double get fractionComplete =>
      requiredHours <= 0 ? 1 : currentHours / requiredHours;

  bool get requirementReached =>
      currentHours >= requiredHours - _Ledger.epsilon;

  EiStatus get status {
    if (missing.isNotEmpty) return EiStatus.insufficientInformation;
    if (requirementReached) return EiStatus.requirementReached;
    final target =
        requiredHours * (1 + _engine.planning.onTrackBufferFraction);
    return projectedAtLeave >= target - _Ledger.epsilon
        ? EiStatus.onTrack
        : EiStatus.atRisk;
  }

  /// Average insurable hours per week since counting began: the later of the
  /// period start and the first day of work.
  double? get averageWeeklyHours {
    final firstWork = _firstWorkDay;
    if (firstWork == null) return null;
    final from = EiDates.later(period.start, firstWork);
    final to = EiDates.earlier(asOf, period.end);
    final days = EiDates.inclusiveDays(from, to);
    if (days <= 0) return null;
    return currentHours / days * DateTime.daysPerWeek;
  }

  /// Days from tomorrow to the last day of the qualifying period.
  int get daysUntilLeave => claimStart == null
      ? 0
      : EiDates.inclusiveDays(EiDates.addDays(asOf, 1), period.end);

  double get weeksUntilLeave => daysUntilLeave / DateTime.daysPerWeek;

  /// Hours a week needed from tomorrow to reach the requirement by the leave
  /// date, or null when it is reached or no weeks remain.
  double? get requiredWeeklyHours {
    if (requirementReached || daysUntilLeave <= 0) return null;
    return remainingHours / weeksUntilLeave;
  }

  /// The combined weekly pace the projection assumes from tomorrow, across
  /// the jobs still held then.
  double get forwardWeeklyHours {
    final tomorrow = EiDates.addDays(asOf, 1);
    var total = 0.0;
    for (final summary in jobs) {
      if (summary.job.isEmployedOn(tomorrow)) {
        total += _ledger.futureWeeklyRate(summary.job.id);
      }
    }
    return total;
  }

  /// The day the requirement is, or was, met.
  ///
  /// Once reached, the day the running total inside the period crossed the
  /// requirement. Otherwise the last day before the earliest claim start
  /// whose own qualifying period would hold enough hours. That search lets
  /// the window slide, because hours from more than a period back stop
  /// counting as new ones are added.
  DateTime? get estimatedReachDate {
    if (requirementReached) {
      return _ledger.crossingDay(
        period.start,
        EiDates.earlier(asOf, period.end),
        requiredHours,
      );
    }
    return _ledger.reachDate(
      totals: _ledger.totals,
      asOf: asOf,
      required: requiredHours,
      periodDays: rules.qualifyingPeriodDays,
      previousClaimStart: _previousClaimStart,
      horizonDays: _engine.planning.projectionHorizonDays,
    );
  }

  /// Weeks from today to [estimatedReachDate], or null.
  double? get weeksToReach {
    if (requirementReached) return null;
    final reach = estimatedReachDate;
    if (reach == null) return null;
    return EiDates.between(asOf, reach) / DateTime.daysPerWeek;
  }

  /// True when, at the projected pace, the requirement is met only after the
  /// planned leave date, or not at all.
  bool get reachesAfterLeave {
    if (claimStart == null || requirementReached) return false;
    final reach = estimatedReachDate;
    return reach == null || reach.isAfter(period.end);
  }

  DateTime? get _firstWorkDay {
    DateTime? first;
    for (final summary in jobs) {
      final start = summary.job.startDate;
      if (first == null || start.isBefore(first)) first = start;
    }
    final ids = jobs.map((s) => s.job.id).toSet();
    for (final record in _data.records) {
      if (!ids.contains(record.jobId)) continue;
      if (first == null || record.periodStart.isBefore(first)) {
        first = record.periodStart;
      }
    }
    return first;
  }

  /// Hours per week or per month inside the qualifying period, one row per
  /// employer, with a running total across all of them.
  List<EiHistoryRow> history(EiHistoryGranularity granularity) {
    final rows = <EiHistoryRow>[];
    var cumulative = 0.0;
    var bucketStart = period.start;
    while (!bucketStart.isAfter(period.end)) {
      final DateTime naturalEnd;
      final DateTime nextStart;
      if (granularity == EiHistoryGranularity.weekly) {
        final weekStart = EiDates.weekStart(bucketStart);
        naturalEnd = EiDates.addDays(weekStart, DateTime.daysPerWeek - 1);
        nextStart = EiDates.addDays(weekStart, DateTime.daysPerWeek);
      } else {
        naturalEnd = DateTime.utc(
          bucketStart.year,
          bucketStart.month,
          EiDates.daysInMonth(bucketStart.year, bucketStart.month),
        );
        nextStart = DateTime.utc(bucketStart.year, bucketStart.month + 1);
      }
      final bucketEnd = EiDates.earlier(naturalEnd, period.end);

      for (final summary in jobs) {
        final id = summary.job.id;
        final hours = _ledger.sumJob(id, bucketStart, bucketEnd);
        final kind = _ledger.weakestKind(id, bucketStart, bucketEnd);
        if (hours <= 0 || kind == null) continue;
        cumulative += hours;
        rows.add(
          EiHistoryRow(
            periodStart: bucketStart,
            periodEnd: bucketEnd,
            jobId: id,
            employerName: summary.job.employerName,
            hours: hours,
            cumulativeHours: cumulative,
            remainingHours: math.max(0, requiredHours - cumulative),
            kind: kind,
          ),
        );
      }
      bucketStart = nextStart;
    }
    return rows;
  }

  /// What happens if, from tomorrow, the user works [weeklyHours] a week in
  /// total across all jobs, in place of their usual schedules.
  ///
  /// Hours already counted stay as they are. Breaks that apply to every job
  /// are still respected.
  EiWhatIfResult whatIf(double weeklyHours, {int daysPerWeek = 5}) {
    final days = daysPerWeek.clamp(1, DateTime.daysPerWeek);
    final totals = List<double>.of(_ledger.totals);
    final firstFuture = _ledger.indexOf(EiDates.addDays(asOf, 1));
    for (var i = math.max(0, firstFuture); i < totals.length; i++) {
      final day = _ledger.dateAt(i);
      final onBreak = _data.breaks.any(
        (b) =>
            b.jobId == null && !day.isBefore(b.start) && !day.isAfter(b.end),
      );
      totals[i] = !onBreak && day.weekday <= days && weeklyHours > 0
          ? weeklyHours / days
          : 0;
    }

    double? atLeave;
    if (claimStart != null) {
      atLeave = _Ledger.sumRange(
        totals,
        _ledger.indexOf(period.start),
        _ledger.indexOf(period.end),
      );
    }
    final reached = requirementReached;
    return EiWhatIfResult(
      weeklyHours: weeklyHours,
      alreadyReached: reached,
      projectedAtLeave: atLeave,
      reachDate: reached
          ? estimatedReachDate
          : _ledger.reachDate(
              totals: totals,
              asOf: asOf,
              required: requiredHours,
              periodDays: rules.qualifyingPeriodDays,
              previousClaimStart: _previousClaimStart,
              horizonDays: _engine.planning.projectionHorizonDays,
            ),
    );
  }
}

/// Hours per job per day across a range of dates.
class _Ledger {
  _Ledger._({
    required this.from,
    required this.hours,
    required this.kinds,
    required this.futureRates,
    required this.totals,
  });

  factory _Ledger.build({
    required EiTrackerData data,
    required List<EiJob> jobs,
    required EiRules rules,
    required DateTime today,
    required DateTime from,
    required DateTime to,
  }) {
    final length = EiDates.inclusiveDays(from, to);
    final hours = <String, List<double>>{};
    final kinds = <String, List<EiHoursKind?>>{};
    final futureRates = <String, double>{};
    final totals = List<double>.filled(length, 0);

    for (final job in jobs) {
      final jobHours = List<double>.filled(length, 0);
      final jobKinds = List<EiHoursKind?>.filled(length, null);
      final covered = List<bool>.filled(length, false);
      final entries = data.records.where((r) => r.jobId == job.id).toList();

      for (final record in entries) {
        final total = record.insurableHours(rules);
        final span = record.days;
        if (span <= 0) continue;
        var working = 0;
        for (var d = 0; d < span; d++) {
          if (job.worksOn(EiDates.addDays(record.periodStart, d))) working++;
        }
        for (var d = 0; d < span; d++) {
          final day = EiDates.addDays(record.periodStart, d);
          final index = EiDates.between(from, day);
          if (index < 0 || index >= length) continue;
          // Spread over the working days the entry covers, so a Monday to
          // Friday week that straddles a period boundary splits by the
          // weekdays on each side. An entry with no working days in it is
          // spread over every day instead of being lost.
          final share = working > 0
              ? (job.worksOn(day) ? total / working : 0.0)
              : total / span;
          jobHours[index] += share;
          covered[index] = true;
          jobKinds[index] = EiHoursKind.recorded;
        }
      }

      final pastRate = job.variableHours ? 0.0 : job.scheduledWeeklyHours;
      final futureRate = job.variableHours
          ? (_averageRecordedWeekly(entries, rules, today) ??
                job.scheduledWeeklyHours)
          : job.scheduledWeeklyHours;
      futureRates[job.id] = futureRate;

      for (var i = 0; i < length; i++) {
        if (covered[i]) continue;
        final day = EiDates.addDays(from, i);
        if (!job.isEmployedOn(day) || !job.worksOn(day)) continue;
        if (data.breaks.any((b) => b.appliesTo(job.id, day))) continue;
        final future = day.isAfter(today);
        final rate = future ? futureRate : pastRate;
        if (rate <= 0) continue;
        jobHours[i] = rate / job.daysPerWeek;
        jobKinds[i] = future ? EiHoursKind.projected : EiHoursKind.estimated;
      }

      for (var i = 0; i < length; i++) {
        totals[i] += jobHours[i];
      }
      hours[job.id] = jobHours;
      kinds[job.id] = jobKinds;
    }

    return _Ledger._(
      from: from,
      hours: hours,
      kinds: kinds,
      futureRates: futureRates,
      totals: totals,
    );
  }

  /// Floating-point slack when comparing summed fractions of hours.
  static const double epsilon = 1e-6;

  final DateTime from;
  final Map<String, List<double>> hours;
  final Map<String, List<EiHoursKind?>> kinds;
  final Map<String, double> futureRates;

  /// Hours per day across every job.
  final List<double> totals;

  int indexOf(DateTime day) => EiDates.between(from, day);
  DateTime dateAt(int index) => EiDates.addDays(from, index);

  double futureWeeklyRate(String jobId) => futureRates[jobId] ?? 0;

  double sumJob(String jobId, DateTime start, DateTime end) {
    final values = hours[jobId];
    if (values == null) return 0;
    return sumRange(values, indexOf(start), indexOf(end));
  }

  static double sumRange(List<double> values, int start, int end) {
    final first = math.max(0, start);
    final last = math.min(values.length - 1, end);
    var sum = 0.0;
    for (var i = first; i <= last; i++) {
      sum += values[i];
    }
    return sum;
  }

  EiHoursKind? weakestKind(String jobId, DateTime start, DateTime end) {
    final values = kinds[jobId];
    if (values == null) return null;
    EiHoursKind? weakest;
    final last = math.min(values.length - 1, indexOf(end));
    for (var i = math.max(0, indexOf(start)); i <= last; i++) {
      final kind = values[i];
      if (kind == null) continue;
      if (weakest == null || kind.index > weakest.index) weakest = kind;
    }
    return weakest;
  }

  /// The day the running total from [start] first reaches [required].
  DateTime? crossingDay(DateTime start, DateTime end, double required) {
    var sum = 0.0;
    final last = math.min(totals.length - 1, indexOf(end));
    for (var i = math.max(0, indexOf(start)); i <= last; i++) {
      sum += totals[i];
      if (sum >= required - epsilon) return dateAt(i);
    }
    return null;
  }

  /// The last day before the earliest claim start after [asOf] whose
  /// qualifying period holds at least [required] hours of [totals].
  DateTime? reachDate({
    required List<double> totals,
    required DateTime asOf,
    required double required,
    required int periodDays,
    required DateTime? previousClaimStart,
    required int horizonDays,
  }) {
    final prefix = List<double>.filled(totals.length + 1, 0);
    for (var i = 0; i < totals.length; i++) {
      prefix[i + 1] = prefix[i] + totals[i];
    }
    final previousIndex = previousClaimStart == null
        ? null
        : indexOf(previousClaimStart);
    final first = indexOf(EiDates.addDays(asOf, 1));
    final last = math.min(totals.length, first + horizonDays);
    for (var claim = math.max(1, first); claim <= last; claim++) {
      var windowStart = math.max(0, claim - periodDays);
      if (previousIndex != null && previousIndex > windowStart) {
        windowStart = math.min(previousIndex, claim);
      }
      final sum = prefix[claim] - prefix[windowStart];
      if (sum >= required - epsilon) return dateAt(claim - 1);
    }
    return null;
  }

  static double? _averageRecordedWeekly(
    List<EiHoursRecord> entries,
    EiRules rules,
    DateTime today,
  ) {
    var hours = 0.0;
    var days = 0;
    for (final record in entries) {
      if (record.periodStart.isAfter(today)) continue;
      hours += record.insurableHours(rules);
      days += record.days;
    }
    if (days == 0) return null;
    return hours / days * DateTime.daysPerWeek;
  }
}
