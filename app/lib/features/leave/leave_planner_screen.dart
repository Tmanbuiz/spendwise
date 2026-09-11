import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/ei/ei_dates.dart';
import '../../state/ei_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/insight_widgets.dart';
import 'ei_editors.dart';
import 'ei_widgets.dart';

/// Maternity and parental leave planning: when leave starts, and whether
/// insurable hours are on track for EI benefits by then.
///
/// The planned leave date lives in the EI tracker's data, so the planner and
/// the tracker can never disagree about it.
class LeavePlannerScreen extends ConsumerWidget {
  const LeavePlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tracker = ref.watch(eiTrackerProvider);
    final estimate = ref.watch(eiEstimateProvider);
    final patterns = ref.watch(eiPayrollPatternsProvider);
    final today = ref.watch(eiTodayProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Leave planner')),
      body: tracker.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Padding(
          padding: EdgeInsets.all(24),
          child: EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load your leave plan',
            message:
                'Your saved plan could not be read. Nothing has been changed.',
          ),
        ),
        data: (data) {
          final e = estimate;
          if (e == null) return const SizedBox.shrink();
          final claim = data.plannedClaimStart;
          final weeksAway = claim == null
              ? null
              : EiDates.between(today, claim) / DateTime.daysPerWeek;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: <Widget>[
              Text(
                'Maternity and parental leave',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Plan when your leave starts and check whether your insurable '
                'hours are on track for EI maternity and parental benefits.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
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
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.event_outlined,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Planned leave start',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            claim == null ? 'Choose a date' : EiFmt.date(claim),
                            style: theme.textTheme.titleLarge,
                          ),
                          if (weeksAway != null)
                            Text(
                              weeksAway <= 0
                                  ? 'Leave has started'
                                  : 'In about ${EiFmt.weeks(weeksAway)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.edit_calendar_outlined),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              EiHoursHero(
                estimate: e,
                onTap: () => context.push(Routes.eiHours),
              ),
              const SizedBox(height: 14),
              EiEligibilityCard(
                estimate: e,
                onTap: () => context.push(Routes.eiHours),
              ),
              if (data.jobs.isEmpty && patterns.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                InsightNote(
                  title: 'Pay deposits found',
                  message:
                      'SpendWise found pay from '
                      '${patterns.first.payerName} in your transactions. '
                      'Add it as a job to start tracking hours.',
                  icon: Icons.payments_outlined,
                  onTap: () => showEiJobEditor(
                    context,
                    ref,
                    suggestion: patterns.first,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.push(Routes.eiHours),
                icon: const Icon(Icons.schedule_rounded),
                label: const Text('Open EI hours tracker'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => context.push(Routes.eiCalculators),
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('What if I work…'),
              ),
              const SizedBox(height: 16),
              const EiDisclaimer(),
            ],
          );
        },
      ),
    );
  }
}
