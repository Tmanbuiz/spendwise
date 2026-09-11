import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/ei/ei_dates.dart';
import '../../data/ei/ei_hours_engine.dart';
import '../../data/ei/ei_models.dart';
import '../../data/ei/ei_verification.dart';
import '../../state/ei_providers.dart';
import '../../widgets/common.dart';
import 'ei_editors.dart';
import 'ei_widgets.dart';

/// Estimates insurable hours toward EI maternity and parental benefits.
class EiHoursScreen extends ConsumerStatefulWidget {
  const EiHoursScreen({super.key});

  @override
  ConsumerState<EiHoursScreen> createState() => _EiHoursScreenState();
}

class _EiHoursScreenState extends ConsumerState<EiHoursScreen> {
  EiHistoryGranularity _granularity = EiHistoryGranularity.monthly;
  bool _allEntries = false;

  @override
  Widget build(BuildContext context) {
    final tracker = ref.watch(eiTrackerProvider);
    final estimate = ref.watch(eiEstimateProvider);
    final verification = ref.watch(eiVerificationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('EI hours tracker'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Calculators',
            icon: const Icon(Icons.calculate_outlined),
            onPressed: () => context.push(Routes.eiCalculators),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showEiHoursEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add hours'),
      ),
      body: tracker.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Padding(
          padding: EdgeInsets.all(24),
          child: EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load your EI hours',
            message:
                'Your saved hours could not be read. Nothing has been changed.',
          ),
        ),
        data: (data) => estimate == null
            ? const SizedBox.shrink()
            : _content(context, data, estimate, verification),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    EiTrackerData data,
    EiHoursEstimate estimate,
    EiVerification? verification,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
      children: <Widget>[
        EiHoursHero(estimate: estimate, detailedPercent: true),
        const SizedBox(height: 12),
        if (data.plannedClaimStart == null || data.jobs.isEmpty) ...<Widget>[
          _GetStarted(data: data),
          const SizedBox(height: 12),
        ],
        EiResultSummary(estimate: estimate),
        const SizedBox(height: 12),
        EiNotices(estimate: estimate),
        if (verification != null && data.jobs.isNotEmpty) ...<Widget>[
          const SectionHeader(title: 'Accuracy check'),
          _AccuracyCard(verification: verification),
          const SizedBox(height: 16),
        ],
        const SectionHeader(title: 'Your dates'),
        _DatesCard(data: data),
        const SizedBox(height: 16),
        const SectionHeader(title: 'Qualifying period'),
        _PeriodCard(estimate: estimate),
        const SizedBox(height: 16),
        const SectionHeader(title: 'Projection'),
        _ProjectionCard(estimate: estimate),
        const SizedBox(height: 16),
        const SectionHeader(title: 'Details'),
        _DetailsCard(estimate: estimate),
        const SizedBox(height: 16),
        SectionHeader(
          title: 'Jobs',
          action: TextButton.icon(
            onPressed: () => showEiJobEditor(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add job'),
          ),
        ),
        _JobsCard(data: data, estimate: estimate),
        const SizedBox(height: 16),
        SectionHeader(
          title: 'Hours entered',
          action: TextButton.icon(
            onPressed: () => showEiHoursEditor(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add hours'),
          ),
        ),
        _entriesCard(context, data, estimate, verification),
        const SizedBox(height: 16),
        SectionHeader(
          title: 'Gaps and unpaid leave',
          action: TextButton.icon(
            onPressed: () => showEiBreakEditor(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add'),
          ),
        ),
        _BreaksCard(data: data),
        const SizedBox(height: 16),
        const SectionHeader(title: 'History'),
        SegmentedButton<EiHistoryGranularity>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<EiHistoryGranularity>>[
            ButtonSegment(
              value: EiHistoryGranularity.weekly,
              label: Text('Weekly'),
            ),
            ButtonSegment(
              value: EiHistoryGranularity.monthly,
              label: Text('Monthly'),
            ),
          ],
          selected: <EiHistoryGranularity>{_granularity},
          onSelectionChanged: (selection) =>
              setState(() => _granularity = selection.first),
        ),
        const SizedBox(height: 10),
        _HistoryCard(estimate: estimate, granularity: _granularity),
        const SizedBox(height: 16),
        const SectionHeader(title: 'Calculators'),
        _CalculatorsCard(estimate: estimate),
        const SizedBox(height: 16),
        const EiDisclaimer(),
        const SizedBox(height: 10),
        Text(
          'Planning rules: ${EiFmt.whole(estimate.requiredHours)} insurable '
          'hours in a qualifying period of up to '
          '${estimate.rules.qualifyingPeriodWeeks} weeks. Last reviewed '
          '${estimate.rules.lastReviewed}.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _entriesCard(
    BuildContext context,
    EiTrackerData data,
    EiHoursEstimate estimate,
    EiVerification? verification,
  ) {
    final records = <EiHoursRecord>[...data.records]
      ..sort((a, b) => b.periodStart.compareTo(a.periodStart));
    if (records.isEmpty) {
      return const SectionCard(
        child: Text(
          'Enter hours by week, by pay period, or from a pay stub in your '
          'Vault. Weeks you do not enter use each job\'s usual weekly hours, '
          'unless its hours vary.',
        ),
      );
    }
    final shown = _allEntries ? records : records.take(5).toList();
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        children: <Widget>[
          for (final record in shown)
            ListTile(
              title: Text(
                '${EiFmt.hours(record.insurableHours(estimate.rules))} h · '
                '${data.jobById(record.jobId)?.employerName ?? 'Unknown job'}',
              ),
              subtitle: Text(
                <String>[
                  _entryDetail(record),
                  ?_checkSummary(verification?.checkFor(record.id)),
                ].join('\n'),
              ),
              onTap: () => showEiHoursEditor(context, ref, record: record),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  final yes = await confirmEiRemove(
                    context,
                    title: 'Remove these hours?',
                  );
                  if (yes && context.mounted) {
                    await saveEiChange(
                      context,
                      ref,
                      (d) => d.removeRecord(record.id),
                    );
                  }
                },
              ),
            ),
          if (records.length > 5)
            TextButton(
              onPressed: () => setState(() => _allEntries = !_allEntries),
              child: Text(
                _allEntries ? 'Show fewer' : 'Show all ${records.length}',
              ),
            ),
        ],
      ),
    );
  }

  static String? _checkSummary(EiStubCheck? check) {
    if (check == null) return null;
    if (check.hasProblem) return '⚠ ${eiProblemText(check)}';
    return check.match == EiDepositMatch.matched
        ? '✓ Matched to a bank deposit'
        : 'Add the net pay to check it against your bank';
  }

  static String _entryDetail(EiHoursRecord record) {
    final parts = <String>[
      '${EiFmt.shortDate(record.periodStart)} to '
          '${EiFmt.date(record.periodEnd)}',
      record.source.label,
      if (record.vacationHours > 0)
        '${EiFmt.hours(record.vacationHours)} h vacation',
      if (record.paidLeaveHours > 0)
        '${EiFmt.hours(record.paidLeaveHours)} h paid leave',
    ];
    return parts.join(' · ');
  }
}

/// What is wrong with a pay stub, in a line.
String eiProblemText(EiStubCheck check) {
  final net = check.record.payStub?.netPayCents;
  final parts = <String>[
    if (check.match == EiDepositMatch.notFound && net != null)
      'No bank deposit of ${Fmt.money(net)} found',
    if (check.netPayMismatchCents case final difference?)
      'Net pay is ${Fmt.money(difference.abs())} '
          '${difference > 0 ? 'more' : 'less'} than gross less deductions',
    if (check.eiPremiumMissing) 'No EI premium deducted',
  ];
  return parts.join(' · ');
}

/// How much of the estimate rests on checked pay stubs, and what to fix.
class _AccuracyCard extends ConsumerWidget {
  const _AccuracyCard({required this.verification});

  final EiVerification verification;

  static Color colorFor(ThemeData theme, EiEvidence evidence) {
    switch (evidence) {
      case EiEvidence.verified:
        return AppTheme.positive;
      case EiEvidence.payStub:
        return theme.colorScheme.primary;
      case EiEvidence.entered:
        return AppTheme.warning;
      case EiEvidence.estimated:
        return theme.colorScheme.outlineVariant;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final v = verification;
    final total = v.totalHours;
    final problems = v.problems;
    final unmatched = v.unmatchedDeposits;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            total <= 0
                ? 'No hours counted yet'
                : '${EiFmt.hoursDown(total)} hours, by what backs them',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          if (total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: <Widget>[
                    for (final evidence in EiEvidence.values)
                      if (v.hoursFor(evidence) > 0)
                        Expanded(
                          flex: math.max(1, (v.hoursFor(evidence) * 100).round()),
                          child: ColoredBox(color: colorFor(theme, evidence)),
                        ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          for (final evidence in EiEvidence.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorFor(theme, evidence),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      evidence.label,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '${EiFmt.hoursDown(v.hoursFor(evidence))} h',
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            total <= 0
                ? 'Add pay stubs to build hours SpendWise can check.'
                : v.documentedFraction >= 0.9
                ? 'Nearly all of your hours come from pay stubs.'
                : 'Add a pay stub for each pay period to replace estimates '
                      'with hours SpendWise can check.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          if (problems.isNotEmpty || unmatched.isNotEmpty) ...<Widget>[
            const Divider(height: 24),
            for (final check in problems)
              _IssueRow(
                icon: Icons.error_outline_rounded,
                color: AppTheme.warning,
                title:
                    'Pay stub for ${EiFmt.shortDate(check.record.periodStart)} '
                    'to ${EiFmt.date(check.record.periodEnd)}',
                message: eiProblemText(check),
                actionLabel: 'Fix',
                onAction: () =>
                    showEiHoursEditor(context, ref, record: check.record),
              ),
            for (final item in unmatched.take(6))
              _IssueRow(
                icon: Icons.receipt_long_outlined,
                color: theme.colorScheme.primary,
                title:
                    'Pay of ${Fmt.money(item.deposit.amountCents)} on '
                    '${EiFmt.date(item.deposit.occurredAt)}',
                message:
                    'No pay stub entered for this deposit from '
                    '${item.job.employerName}.',
                actionLabel: 'Add stub',
                onAction: () => showEiHoursEditor(
                  context,
                  ref,
                  method: EiHoursSource.payStub,
                  jobId: item.job.id,
                  stubPrefill: EiPayStubDetails(
                    payDate: EiDates.day(item.deposit.occurredAt),
                    netPayCents: item.deposit.amountCents,
                  ),
                ),
              ),
            if (unmatched.length > 6)
              Text(
                'And ${unmatched.length - 6} more pay deposits without a stub.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
          ],
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _GetStarted extends ConsumerWidget {
  const _GetStarted({required this.data});

  final EiTrackerData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Widget step(bool done, String title, VoidCallback onTap) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
        color: done ? AppTheme.positive : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(title),
      trailing: done ? null : const Icon(Icons.chevron_right_rounded),
      onTap: done ? null : onTap,
    );

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Get started', style: theme.textTheme.titleMedium),
          step(
            data.plannedClaimStart != null,
            'Set your planned leave start date',
            () async {
              final picked = await pickEiDate(
                context,
                help: 'Planned leave start',
              );
              if (picked != null && context.mounted) {
                await saveEiChange(
                  context,
                  ref,
                  (d) => d.copyWith(plannedClaimStart: () => picked),
                );
              }
            },
          ),
          step(
            data.jobs.isNotEmpty,
            'Add your job or jobs',
            () => showEiJobEditor(context, ref),
          ),
          step(
            data.records.isNotEmpty,
            'Enter hours, or rely on usual weekly hours',
            () => showEiHoursEditor(context, ref),
          ),
        ],
      ),
    );
  }
}

class _DatesCard extends ConsumerWidget {
  const _DatesCard({required this.data});

  final EiTrackerData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claim = data.plannedClaimStart;
    final previous = data.previousClaimStart;
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: const Text('Planned EI claim / leave start'),
            subtitle: Text(claim == null ? 'Not set' : EiFmt.date(claim)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () async {
              final picked = await pickEiDate(
                context,
                initial: claim,
                help: 'Planned leave start',
              );
              if (picked != null && context.mounted) {
                await saveEiChange(
                  context,
                  ref,
                  (d) => d.copyWith(plannedClaimStart: () => picked),
                );
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.history_rounded),
            title: const Text('I had a previous EI claim'),
            subtitle: const Text('Any EI benefit period in the last year'),
            value: data.hadPreviousClaim,
            onChanged: (value) => saveEiChange(
              context,
              ref,
              (d) => d.copyWith(hadPreviousClaim: value),
            ),
          ),
          if (data.hadPreviousClaim)
            ListTile(
              leading: const Icon(Icons.event_repeat_outlined),
              title: const Text('Previous benefit period start'),
              subtitle: Text(
                previous == null
                    ? 'Add the date. It may shorten your qualifying period.'
                    : EiFmt.date(previous),
              ),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () async {
                final picked = await pickEiDate(
                  context,
                  initial: previous,
                  help: 'Previous claim start',
                );
                if (picked != null && context.mounted) {
                  await saveEiChange(
                    context,
                    ref,
                    (d) => d.copyWith(previousClaimStart: () => picked),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.estimate});

  final EiHoursEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final period = estimate.period;
    final muted = theme.colorScheme.onSurfaceVariant;
    final notes = <String>[
      '${EiFmt.hours(period.weeks)} weeks',
      if (period.shortenedByPreviousClaim) 'shortened by your previous claim',
      if (estimate.isProvisionalPeriod) 'ending today until you add a leave date',
    ];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${EiFmt.date(period.start)} to ${EiFmt.date(period.end)}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(notes.join(' · '), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            'Generally the shorter of the '
            '${estimate.rules.qualifyingPeriodWeeks} weeks immediately before '
            'your claim starts, or the time since a previous benefit period '
            'began.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

class _ProjectionCard extends StatelessWidget {
  const _ProjectionCard({required this.estimate});

  final EiHoursEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = estimate;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          EiValueRow(
            label: 'Current hours',
            value: EiFmt.hoursDown(e.currentHours),
          ),
          EiValueRow(
            label: '+ Projected future hours',
            value: EiFmt.hoursDown(e.projectedFutureHours),
          ),
          const Divider(height: 16),
          EiValueRow(
            label: '= Projected hours at leave date',
            value: EiFmt.hoursDown(e.projectedAtLeave),
            emphasis: true,
          ),
          const SizedBox(height: 6),
          Text(
            e.claimStart == null
                ? 'Add a leave date to project hours ahead.'
                : 'Future hours use each job\'s usual weekly hours from '
                      'tomorrow to ${EiFmt.date(e.period.end)}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.estimate});

  final EiHoursEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final e = estimate;
    final required = EiFmt.whole(e.requiredHours);
    final average = e.averageWeeklyHours;
    final needed = e.requiredWeeklyHours;
    final reach = e.estimatedReachDate;
    return SectionCard(
      child: Column(
        children: <Widget>[
          EiValueRow(label: 'Required hours', value: required),
          EiValueRow(
            label: 'Total estimated insurable hours',
            value: EiFmt.hoursDown(e.currentHours),
          ),
          EiValueRow(
            label: 'Hours remaining',
            value: EiFmt.hoursUp(e.remainingHours),
          ),
          EiValueRow(
            label: 'Percentage completed',
            value: EiFmt.percent(
              e.fractionComplete,
              reached: e.requirementReached,
            ),
          ),
          EiValueRow(
            label: 'Average hours per week so far',
            value: average == null ? '—' : EiFmt.hours(average),
          ),
          EiValueRow(
            label: 'Weeks until leave',
            value: e.claimStart == null ? '—' : EiFmt.hours(e.weeksUntilLeave),
          ),
          EiValueRow(
            label: 'Hours per remaining week to reach $required',
            value: e.requirementReached
                ? 'Reached'
                : needed == null
                ? '—'
                : EiFmt.hours(needed),
          ),
          EiValueRow(
            label: e.requirementReached
                ? 'Date the requirement was reached'
                : 'Estimated date you reach $required hours',
            value: reach == null
                ? (e.requirementReached ? '—' : 'Not in view')
                : EiFmt.date(reach),
          ),
        ],
      ),
    );
  }
}

class _JobsCard extends ConsumerWidget {
  const _JobsCard({required this.data, required this.estimate});

  final EiTrackerData data;
  final EiHoursEstimate estimate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.jobs.isEmpty) {
      return const SectionCard(
        child: EmptyState(
          icon: Icons.work_outline_rounded,
          title: 'No jobs yet',
          message:
              'Add each employer you have worked for in the last year. Hours '
              'from several jobs are combined.',
        ),
      );
    }
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        children: <Widget>[
          for (final job in data.jobs)
            _JobTile(job: job, summary: _summaryFor(job.id)),
          if (estimate.jobs.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Total estimated insurable hours',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    EiFmt.hoursDown(estimate.currentHours),
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  EiJobSummary? _summaryFor(String id) {
    for (final summary in estimate.jobs) {
      if (summary.job.id == id) return summary;
    }
    return null;
  }
}

class _JobTile extends ConsumerWidget {
  const _JobTile({required this.job, required this.summary});

  final EiJob job;
  final EiJobSummary? summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekly = job.scheduledWeeklyHours;
    final counted = summary;
    final lines = <String>[
      <String>[
        job.employmentType.label,
        if (weekly > 0) '${EiFmt.hours(weekly)} h/week',
        if (job.variableHours) 'hours vary',
      ].join(' · '),
      counted == null
          ? 'Not insurable, so not counted'
          : '${EiFmt.hoursDown(counted.currentHours)} h counted · '
                '+${EiFmt.hoursDown(counted.projectedHours)} projected',
    ];
    return ListTile(
      title: Text(job.employerName),
      subtitle: Text(lines.join('\n')),
      isThreeLine: true,
      onTap: () => showEiJobEditor(context, ref, job: job),
      trailing: PopupMenuButton<String>(
        tooltip: 'Job options',
        onSelected: (choice) async {
          if (choice == 'edit') {
            await showEiJobEditor(context, ref, job: job);
            return;
          }
          final yes = await confirmEiRemove(
            context,
            title: 'Remove ${job.employerName}?',
            message: 'Its hours, gaps and unpaid leave are removed too.',
          );
          if (yes && context.mounted) {
            await saveEiChange(context, ref, (d) => d.removeJob(job.id));
          }
        },
        itemBuilder: (_) => const <PopupMenuEntry<String>>[
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'remove', child: Text('Remove')),
        ],
      ),
    );
  }
}

class _BreaksCard extends ConsumerWidget {
  const _BreaksCard({required this.data});

  final EiTrackerData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.breaks.isEmpty) {
      return const SectionCard(
        child: Text(
          'Add time between jobs or unpaid leave so usual weekly hours are '
          'not counted for those days.',
        ),
      );
    }
    final breaks = [...data.breaks]..sort((a, b) => b.start.compareTo(a.start));
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        children: <Widget>[
          for (final value in breaks)
            ListTile(
              title: Text(value.kind.label),
              subtitle: Text(
                '${EiFmt.shortDate(value.start)} to ${EiFmt.date(value.end)} · '
                '${value.jobId == null ? 'All jobs' : data.jobById(value.jobId!)?.employerName ?? 'Unknown job'}',
              ),
              onTap: () => showEiBreakEditor(context, ref, value: value),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  final yes = await confirmEiRemove(
                    context,
                    title: 'Remove this ${value.kind.label.toLowerCase()}?',
                  );
                  if (yes && context.mounted) {
                    await saveEiChange(
                      context,
                      ref,
                      (d) => d.removeBreak(value.id),
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.estimate, required this.granularity});

  final EiHoursEstimate estimate;
  final EiHistoryGranularity granularity;

  @override
  Widget build(BuildContext context) {
    final rows = estimate.history(granularity);
    if (rows.isEmpty) {
      return const SectionCard(
        child: Text(
          'Hours appear here once a job has hours in the qualifying period.',
        ),
      );
    }
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Date · Employer',
                    style: theme.textTheme.labelMedium?.copyWith(color: muted),
                  ),
                ),
                const SizedBox(width: 8),
                // Flexible on both sides: at a large text size neither label
                // fits a phone's width on one line, and they must wrap
                // rather than push past the edge.
                Flexible(
                  child: Text(
                    'Hours · Cumulative · Remaining',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelMedium?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          granularity == EiHistoryGranularity.weekly
                              ? 'Week of ${EiFmt.date(row.periodStart)}'
                              : EiFmt.monthYear(row.periodStart),
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          <String>[
                            row.employerName,
                            if (row.kind == EiHoursKind.estimated) 'estimated',
                            if (row.kind == EiHoursKind.projected) 'projected',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          '+${EiFmt.hours(row.hours)} h',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          '${EiFmt.hoursDown(row.cumulativeHours)} · '
                          '${EiFmt.hoursUp(row.remainingHours)} left',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
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

class _CalculatorsCard extends StatelessWidget {
  const _CalculatorsCard({required this.estimate});

  final EiHoursEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final presets = estimate.planning.whatIfWeeklyHours;
    final range = presets.isEmpty
        ? 'a steady weekly pace'
        : '${EiFmt.whole(presets.first)} to ${EiFmt.whole(presets.last)} '
              'hours a week';
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.speed_outlined),
            title: const Text('What if I work…'),
            subtitle: Text('When $range gets you there'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('${Routes.eiCalculators}?tab=0'),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_view_month_outlined),
            title: const Text('Annual work hours'),
            subtitle: const Text('Weekly, monthly and yearly hours'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('${Routes.eiCalculators}?tab=1'),
          ),
          ListTile(
            leading: const Icon(Icons.date_range_outlined),
            title: const Text('Hours between two dates'),
            subtitle: const Text('Counts partial weeks by their working days'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('${Routes.eiCalculators}?tab=2'),
          ),
        ],
      ),
    );
  }
}
