import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/ei/ei_hours_engine.dart';
import '../../widgets/common.dart';

/// Wording the tracker shows wherever an estimate appears.
abstract final class EiMessages {
  static const String basis =
      'Estimated insurable hours based on the information entered.';

  static const String disclaimer =
      'This tool is for planning purposes only. Employment Insurance '
      'eligibility and insurable hours are determined by Service Canada '
      'using your Record(s) of Employment and applicable EI rules.';

  static const String previousClaim =
      'Because you had a previous EI claim, your qualifying period may be '
      'shorter. Service Canada should confirm which hours can be used for '
      'your new claim.';

  static const String overlapping =
      'Some entries for the same employer cover the same days. Both are '
      'counted, so check for duplicates.';

  static const String leaveDateReached =
      'Your planned leave date has arrived, so no further hours are '
      'projected.';

  static const String nonInsurable =
      'Jobs marked as not insurable employment are left out of every total.';

  static const String reachAfterLeave =
      'At your usual schedule you may not reach the required hours before '
      'your planned leave date.';

  static const String paidTimeOff =
      'Paid vacation and paid leave count when your employer paid you for '
      'those hours. Your Record of Employment is the final word.';
}

/// Hours and dates as the tracker shows them.
///
/// Progress is never overstated: the current total rounds down and the
/// remainder rounds up, so the two always add back to the requirement and a
/// user one hour short is never shown as finished.
abstract final class EiFmt {
  static final NumberFormat _whole = NumberFormat('#,##0', 'en_CA');
  static final NumberFormat _tenth = NumberFormat('#,##0.#', 'en_CA');

  static String hours(double value) => _tenth.format(value);

  static String hoursDown(double value) =>
      _whole.format((value + 1e-6).floor());

  static String hoursUp(double value) =>
      _whole.format(math.max(0, (value - 1e-6).ceil()));

  static String whole(double value) => _whole.format(value.round());

  /// `78.7%`, held below 100% until the requirement is actually met.
  static String percent(
    double fraction, {
    required bool reached,
    int decimals = 1,
  }) {
    var value = fraction * 100;
    final ceiling = decimals == 0 ? 99.0 : 99.9;
    if (!reached && value > ceiling) value = ceiling;
    return '${value.toStringAsFixed(decimals)}%';
  }

  static String date(DateTime value) => DateFormat('MMM d, y').format(value);

  static String shortDate(DateTime value) => DateFormat('MMM d').format(value);

  static String monthYear(DateTime value) => DateFormat('MMM y').format(value);

  static String weeks(double value) {
    final rounded = value.round();
    return rounded <= 1 ? '1 week' : '$rounded weeks';
  }
}

abstract final class EiStatusStyle {
  static IconData icon(EiStatus status) {
    switch (status) {
      case EiStatus.onTrack:
        return Icons.check_circle_outline_rounded;
      case EiStatus.atRisk:
        return Icons.warning_amber_rounded;
      case EiStatus.requirementReached:
        return Icons.verified_outlined;
      case EiStatus.insufficientInformation:
        return Icons.help_outline_rounded;
    }
  }

  static Color color(ThemeData theme, EiStatus status) {
    switch (status) {
      case EiStatus.onTrack:
      case EiStatus.requirementReached:
        return AppTheme.positive;
      case EiStatus.atRisk:
        return AppTheme.warning;
      case EiStatus.insufficientInformation:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  static String headline(EiStatus status) {
    switch (status) {
      case EiStatus.onTrack:
        return 'Currently on track';
      case EiStatus.atRisk:
        return 'At risk';
      case EiStatus.requirementReached:
        return 'Estimated requirement reached';
      case EiStatus.insufficientInformation:
        return 'Insufficient information';
    }
  }
}

/// The prominent progress card: hours so far against the requirement, what
/// is left, the projection to the leave date, and the status.
class EiHoursHero extends StatelessWidget {
  const EiHoursHero({
    super.key,
    required this.estimate,
    this.onTap,
    this.detailedPercent = false,
  });

  final EiHoursEstimate estimate;
  final VoidCallback? onTap;

  /// One decimal place (`78.7%`) instead of a whole number (`79%`).
  final bool detailedPercent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = estimate;
    final status = e.status;
    final color = EiStatusStyle.color(theme, status);
    final muted = theme.colorScheme.onSurfaceVariant;
    final claim = e.claimStart;
    final required = EiFmt.whole(e.requiredHours);
    final current = EiFmt.hoursDown(e.currentHours);

    return SectionCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'EI HOURS',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: muted,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(
            label: '$current of $required hours',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: current, style: theme.textTheme.displaySmall),
                  TextSpan(
                    text: ' / $required',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (e.isProvisionalPeriod)
            Text(
              'In the ${EiFmt.whole(e.period.weeks)} weeks up to today',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: e.fractionComplete.clamp(0.0, 1.0),
                    minHeight: 12,
                    color: color,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                EiFmt.percent(
                  e.fractionComplete,
                  reached: e.requirementReached,
                  decimals: detailedPercent ? 1 : 0,
                ),
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            e.remainingHours > 0
                ? '${EiFmt.hoursUp(e.remainingHours)} hours remaining'
                : 'No hours remaining',
            style: theme.textTheme.titleMedium,
          ),
          if (claim != null &&
              !e.notices.contains(EiNotice.leaveDateReached)) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'Projected by ${EiFmt.monthYear(claim)}:',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            Text(
              '${EiFmt.hoursDown(e.projectedAtLeave)} hours',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Icon(EiStatusStyle.icon(status), color: color, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  EiStatusStyle.headline(status),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          for (final item in e.missing)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 30),
              child: Text(
                item.message,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// The Leave Planner's summary table.
class EiEligibilityCard extends StatelessWidget {
  const EiEligibilityCard({super.key, required this.estimate, this.onTap});

  final EiHoursEstimate estimate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = estimate;
    final muted = theme.colorScheme.onSurfaceVariant;

    Widget row(String label, String value, {Color? valueColor}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return SectionCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('EI Hours Eligibility', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 6),
          row('Required', '${EiFmt.whole(e.requiredHours)} hours'),
          row('Current', '${EiFmt.hoursDown(e.currentHours)} hours'),
          row(
            'Projected by leave date',
            e.claimStart == null
                ? 'Add a leave date'
                : '${EiFmt.hoursDown(e.projectedAtLeave)} hours',
          ),
          row('Remaining', '${EiFmt.hoursUp(e.remainingHours)} hours'),
          row(
            'Status',
            e.status.label,
            valueColor: EiStatusStyle.color(theme, e.status),
          ),
          const SizedBox(height: 6),
          Text(
            EiMessages.basis,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// The result spelled out in sentences.
class EiResultSummary extends StatelessWidget {
  const EiResultSummary({super.key, required this.estimate});

  final EiHoursEstimate estimate;

  static List<String> linesFor(EiHoursEstimate e) {
    final required = EiFmt.whole(e.requiredHours);
    final lines = <String>[
      'Estimated EI insurable hours: ${EiFmt.hoursDown(e.currentHours)} / '
          '$required',
    ];
    if (e.requirementReached) {
      lines.add('Your estimated hours meet the $required-hour requirement.');
      return lines;
    }
    lines.add(
      'You have approximately ${EiFmt.hoursUp(e.remainingHours)} hours '
      'remaining.',
    );
    final pace = e.forwardWeeklyHours;
    final weeks = e.weeksToReach;
    if (pace <= 0) {
      lines.add(
        'Add usual weekly hours for a job to see when you may reach '
        '$required hours.',
      );
    } else if (weeks == null) {
      lines.add(
        'At ${EiFmt.hours(pace)} hours/week, you may not reach $required '
        'hours within the next few years.',
      );
    } else {
      lines.add(
        'At an average of ${EiFmt.hours(pace)} hours/week, you may reach '
        '$required hours in approximately ${EiFmt.weeks(weeks)}.',
      );
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = linesFor(estimate);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: Text(
                lines[i],
                style: i == 0
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class EiBanner extends StatelessWidget {
  const EiBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Warnings that go with an estimate, most important first.
class EiNotices extends StatelessWidget {
  const EiNotices({super.key, required this.estimate});

  final EiHoursEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final notices = estimate.notices;
    final items = <(IconData, String, Color)>[
      if (notices.contains(EiNotice.previousClaimShortensPeriod) ||
          notices.contains(EiNotice.previousClaimDateNeeded))
        (Icons.history_rounded, EiMessages.previousClaim, AppTheme.warning),
      if (estimate.missing.isEmpty && estimate.reachesAfterLeave)
        (
          Icons.trending_down_rounded,
          EiMessages.reachAfterLeave,
          AppTheme.warning,
        ),
      if (notices.contains(EiNotice.overlappingEntries))
        (Icons.content_copy_outlined, EiMessages.overlapping, AppTheme.warning),
      if (notices.contains(EiNotice.leaveDateReached))
        (Icons.event_available_outlined, EiMessages.leaveDateReached, muted),
      if (notices.contains(EiNotice.nonInsurableJobsExcluded))
        (Icons.block_outlined, EiMessages.nonInsurable, muted),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      children: <Widget>[
        for (final (icon, message, color) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: EiBanner(icon: icon, message: message, color: color),
          ),
      ],
    );
  }
}

class EiDisclaimer extends StatelessWidget {
  const EiDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 20, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  EiMessages.basis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  EiMessages.disclaimer,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A label and a value on one line.
class EiValueRow extends StatelessWidget {
  const EiValueRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: emphasis
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.end,
            style: emphasis
                ? theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )
                : theme.textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}
