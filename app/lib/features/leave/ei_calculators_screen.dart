import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/ei/ei_calculators.dart';
import '../../data/ei/ei_config.dart';
import '../../data/ei/ei_dates.dart';
import '../../data/ei/ei_hours_engine.dart';
import '../../state/ei_providers.dart';
import '../../widgets/common.dart';
import 'ei_editors.dart';
import 'ei_widgets.dart';

/// What if I work…, annual work hours, and hours between two dates.
class EiCalculatorsScreen extends StatelessWidget {
  const EiCalculatorsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('EI hours calculators'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'What if'),
              Tab(text: 'Annual'),
              Tab(text: 'Dates'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[_WhatIfTab(), _AnnualTab(), _DatesTab()],
        ),
      ),
    );
  }
}

double? _parse(String text) {
  final value = text.trim().replaceAll(',', '.');
  return value.isEmpty ? null : double.tryParse(value);
}

const _decimalKeyboard = TextInputType.numberWithOptions(decimal: true);

class _WhatIfTab extends ConsumerStatefulWidget {
  const _WhatIfTab();

  @override
  ConsumerState<_WhatIfTab> createState() => _WhatIfTabState();
}

class _WhatIfTabState extends ConsumerState<_WhatIfTab> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estimate = ref.watch(eiEstimateProvider);
    if (estimate == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    final presets = estimate.planning.whatIfWeeklyHours;
    final custom = _parse(_custom.text);
    final rates = <double>[
      ...presets,
      if (custom != null &&
          custom > 0 &&
          custom <= 168 &&
          !presets.contains(custom))
        custom,
    ];
    final required = EiFmt.whole(estimate.requiredHours);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Text('What if I work…', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'When you would reach $required hours working a steady number of '
          'hours each week from tomorrow. Hours you have already built up '
          'stay counted.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'You have ${EiFmt.hoursDown(estimate.currentHours)} of $required '
          'hours so far.',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _custom,
          keyboardType: _decimalKeyboard,
          decoration: const InputDecoration(
            labelText: 'Custom hours per week',
            suffixText: 'h/week',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            children: <Widget>[
              for (final rate in rates)
                _WhatIfRow(
                  estimate: estimate,
                  result: estimate.whatIf(rate),
                  isCustom: !presets.contains(rate),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const EiDisclaimer(),
      ],
    );
  }
}

class _WhatIfRow extends StatelessWidget {
  const _WhatIfRow({
    required this.estimate,
    required this.result,
    required this.isCustom,
  });

  final EiHoursEstimate estimate;
  final EiWhatIfResult result;
  final bool isCustom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final required = estimate.requiredHours;
    final reach = result.reachDate;
    final String detail;
    if (result.alreadyReached) {
      detail = 'Requirement already reached';
    } else if (reach == null) {
      detail = 'Not reached in the time looked ahead';
    } else {
      final weeks = EiDates.between(estimate.asOf, reach) / 7;
      detail =
          'Reach ${EiFmt.whole(required)} hours around ${EiFmt.date(reach)} '
          '(${EiFmt.weeks(weeks)})';
    }
    final atLeave = result.projectedAtLeave;

    return ListTile(
      title: Text(
        '${EiFmt.hours(result.weeklyHours)} hours/week'
        '${isCustom ? ' (custom)' : ''}',
      ),
      subtitle: Text(detail),
      trailing: atLeave == null
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  '${EiFmt.hoursDown(atLeave)} h',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: atLeave >= required
                        ? AppTheme.positive
                        : AppTheme.warning,
                  ),
                ),
                Text(
                  'by leave date',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

class _AnnualTab extends ConsumerStatefulWidget {
  const _AnnualTab();

  @override
  ConsumerState<_AnnualTab> createState() => _AnnualTabState();
}

class _AnnualTabState extends ConsumerState<_AnnualTab> {
  final _hoursPerDay = TextEditingController(text: '7.5');
  final _weeksPerYear = TextEditingController(
    text: EiCalendar.weeksPerYear.toStringAsFixed(0),
  );
  final _vacationWeeks = TextEditingController(text: '2');
  final _unpaidWeeks = TextEditingController(text: '0');
  final _holidays = TextEditingController(text: '0');
  final _overtime = TextEditingController(text: '0');
  int _days = 5;
  bool _vacationPaid = true;
  bool _holidaysPaid = true;

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _hoursPerDay,
      _weeksPerYear,
      _vacationWeeks,
      _unpaidWeeks,
      _holidays,
      _overtime,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: _decimalKeyboard,
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => setState(() {}),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estimate = ref.watch(eiEstimateProvider);
    final rules = ref.watch(eiEngineProvider).rules;
    final result = calculateAnnualHours(
      EiAnnualHoursInput(
        hoursPerDay: _parse(_hoursPerDay.text) ?? 0,
        daysPerWeek: _days,
        weeksPerYear: _parse(_weeksPerYear.text) ?? 0,
        vacationWeeks: _parse(_vacationWeeks.text) ?? 0,
        vacationIsPaid: _vacationPaid,
        unpaidLeaveWeeks: _parse(_unpaidWeeks.text) ?? 0,
        holidayDays: _parse(_holidays.text) ?? 0,
        holidaysArePaid: _holidaysPaid,
        overtimeHoursPerWeek: _parse(_overtime.text) ?? 0,
      ),
      rules: rules,
      qualifyingPeriodDays: estimate?.period.days,
    );
    final periodWeeks = result.qualifyingPeriodDays / DateTime.daysPerWeek;
    final meets =
        result.qualifyingPeriodHours >= rules.maternityParentalRequiredHours;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Text('Annual work hours', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(child: _field(_hoursPerDay, 'Hours per day')),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _days,
                decoration: const InputDecoration(labelText: 'Days per week'),
                items: <DropdownMenuItem<int>>[
                  for (var day = 1; day <= DateTime.daysPerWeek; day++)
                    DropdownMenuItem(value: day, child: Text('$day')),
                ],
                onChanged: (value) => setState(() => _days = value ?? _days),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(child: _field(_weeksPerYear, 'Weeks worked per year')),
            const SizedBox(width: 12),
            Expanded(child: _field(_vacationWeeks, 'Vacation weeks')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(child: _field(_unpaidWeeks, 'Unpaid leave (weeks)')),
            const SizedBox(width: 12),
            Expanded(child: _field(_holidays, 'Holidays (days)')),
          ],
        ),
        const SizedBox(height: 12),
        _field(_overtime, 'Overtime hours per week'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Vacation is paid'),
          value: _vacationPaid,
          onChanged: (value) => setState(() => _vacationPaid = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Holidays are paid'),
          value: _holidaysPaid,
          onChanged: (value) => setState(() => _holidaysPaid = value),
        ),
        const SizedBox(height: 8),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              EiValueRow(
                label: 'Weekly hours',
                value: EiFmt.hours(result.weeklyHours),
              ),
              EiValueRow(
                label: 'Monthly average hours',
                value: EiFmt.hours(result.monthlyAverageHours),
              ),
              EiValueRow(
                label: 'Annual hours worked',
                value: EiFmt.hoursDown(result.hoursWorked),
              ),
              EiValueRow(
                label: 'Annual insurable hours (estimated)',
                value: EiFmt.hoursDown(result.annualInsurableHours),
              ),
              const Divider(height: 16),
              EiValueRow(
                label:
                    'Estimated insurable hours in your '
                    '${EiFmt.hours(periodWeeks)}-week qualifying period',
                value: EiFmt.hoursDown(result.qualifyingPeriodHours),
                emphasis: true,
              ),
              const SizedBox(height: 4),
              Text(
                meets
                    ? 'Enough for the '
                          '${EiFmt.whole(rules.maternityParentalRequiredHours)}'
                          '-hour requirement, if every hour is insurable.'
                    : 'Short of the '
                          '${EiFmt.whole(rules.maternityParentalRequiredHours)}'
                          '-hour requirement.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: meets ? AppTheme.positive : AppTheme.warning,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const EiDisclaimer(),
      ],
    );
  }
}

class _DatesTab extends ConsumerStatefulWidget {
  const _DatesTab();

  @override
  ConsumerState<_DatesTab> createState() => _DatesTabState();
}

class _DatesTabState extends ConsumerState<_DatesTab> {
  final _weekly = TextEditingController(text: '30');
  DateTime? _start;
  DateTime? _end;
  int _days = 5;

  @override
  void dispose() {
    _weekly.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = ref.watch(eiTodayProvider);
    final claim = ref.watch(eiEstimateProvider)?.claimStart;
    final start = _start ?? today;
    final end =
        _end ??
        (claim != null && claim.isAfter(today)
            ? EiDates.addDays(claim, -1)
            : EiDates.addDays(today, 90));
    final weekly = _parse(_weekly.text) ?? 0;
    final result = hoursBetweenDates(
      start: start,
      end: end,
      weeklyHours: weekly,
      daysPerWeek: _days,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Text('Hours between two dates', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.play_arrow_outlined),
                title: const Text('From'),
                subtitle: Text(EiFmt.date(start)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final picked = await pickEiDate(context, initial: start);
                  if (picked != null) setState(() => _start = picked);
                },
              ),
              ListTile(
                leading: const Icon(Icons.stop_outlined),
                title: const Text('To'),
                subtitle: Text(EiFmt.date(end)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final picked = await pickEiDate(context, initial: end);
                  if (picked != null) setState(() => _end = picked);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _weekly,
                keyboardType: _decimalKeyboard,
                decoration: const InputDecoration(labelText: 'Hours per week'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _days,
                decoration: const InputDecoration(labelText: 'Days per week'),
                items: <DropdownMenuItem<int>>[
                  for (var day = 1; day <= DateTime.daysPerWeek; day++)
                    DropdownMenuItem(value: day, child: Text('$day')),
                ],
                onChanged: (value) => setState(() => _days = value ?? _days),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                result.totalDays == 0
                    ? 'Choose an end date on or after the start date.'
                    : 'From ${EiFmt.date(start)} to ${EiFmt.date(end)}, '
                          'working ${EiFmt.hours(weekly)} hours/week, you '
                          'would accumulate approximately '
                          '${EiFmt.hoursDown(result.hours)} hours.',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              EiValueRow(label: 'Total days', value: '${result.totalDays}'),
              EiValueRow(
                label: 'Full weeks and extra days',
                value: '${result.fullWeeks} weeks, ${result.extraDays} days',
              ),
              EiValueRow(
                label: 'Working days counted',
                value: '${result.workingDays}',
              ),
              EiValueRow(
                label: 'Approximate hours',
                value: EiFmt.hours(result.hours),
                emphasis: true,
              ),
              const SizedBox(height: 4),
              Text(
                'Hours are spread over the first $_days days of each week, '
                'starting Monday. A partial week counts only the working days '
                'inside the range.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const EiDisclaimer(),
      ],
    );
  }
}
