import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/ei/ei_dates.dart';
import '../../data/ei/ei_models.dart';
import '../../data/ei/ei_payroll_detection.dart';
import '../../data/models/financial_document.dart';
import '../../state/ei_providers.dart';
import '../../state/providers.dart';
import 'ei_widgets.dart';

/// Opens a date picker and returns the chosen day as a tracker date.
Future<DateTime?> pickEiDate(
  BuildContext context, {
  DateTime? initial,
  String? help,
}) async {
  final first = DateTime(2000);
  final last = DateTime(2100);
  final now = DateTime.now();
  var start = initial == null
      ? DateTime(now.year, now.month, now.day)
      : DateTime(initial.year, initial.month, initial.day);
  if (start.isBefore(first)) start = first;
  if (start.isAfter(last)) start = last;
  final picked = await showDatePicker(
    context: context,
    initialDate: start,
    firstDate: first,
    lastDate: last,
    helpText: help,
  );
  return picked == null ? null : EiDates.day(picked);
}

/// Saves a change to the tracker, telling the user if it could not be saved.
Future<bool> saveEiChange(
  BuildContext context,
  WidgetRef ref,
  EiTrackerData Function(EiTrackerData) update,
) async {
  try {
    await ref.read(eiTrackerProvider.notifier).change(update);
    return true;
  } on Object catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your EI hours. Please try again.'),
        ),
      );
    }
    return false;
  }
}

Future<bool> confirmEiRemove(
  BuildContext context, {
  required String title,
  String? message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Future<void> showEiJobEditor(
  BuildContext context,
  WidgetRef ref, {
  EiJob? job,
  EiPayrollPattern? suggestion,
}) async {
  final result = await _showSheet<EiJob>(
    context,
    _JobEditor(job: job, suggestion: suggestion),
  );
  if (result == null || !context.mounted) return;
  await saveEiChange(context, ref, (data) => data.upsertJob(result));
}

Future<void> showEiHoursEditor(
  BuildContext context,
  WidgetRef ref, {
  EiHoursRecord? record,
  EiHoursSource? method,
}) async {
  final data = await ref.read(eiTrackerProvider.future);
  if (!context.mounted) return;
  if (data.jobs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add the job first, then enter its hours.')),
    );
    await showEiJobEditor(context, ref);
    return;
  }
  final result = await _showSheet<EiHoursRecord>(
    context,
    _HoursEditor(jobs: data.jobs, record: record, method: method),
  );
  if (result == null || !context.mounted) return;
  await saveEiChange(context, ref, (d) => d.upsertRecord(result));
}

Future<void> showEiBreakEditor(
  BuildContext context,
  WidgetRef ref, {
  EiBreak? value,
}) async {
  final data = await ref.read(eiTrackerProvider.future);
  if (!context.mounted) return;
  final result = await _showSheet<EiBreak>(
    context,
    _BreakEditor(jobs: data.jobs, value: value),
  );
  if (result == null || !context.mounted) return;
  await saveEiChange(context, ref, (d) => d.upsertBreak(result));
}

Future<T?> _showSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => child,
    );

double? _parseHours(String text) {
  final value = text.trim().replaceAll(',', '.');
  if (value.isEmpty) return null;
  return double.tryParse(value);
}

String _numberText(double? value) {
  if (value == null || value == 0) return '';
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

FormFieldValidator<String> _hoursValidator({
  required double max,
  bool optional = true,
}) {
  return (text) {
    final value = text?.trim() ?? '';
    if (value.isEmpty) return optional ? null : 'Enter the hours';
    final parsed = _parseHours(value);
    if (parsed == null || parsed < 0 || parsed > max) {
      return 'Enter a number from 0 to ${max.toStringAsFixed(0)}';
    }
    return null;
  };
}

const _decimalKeyboard = TextInputType.numberWithOptions(decimal: true);

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = value;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.event_outlined),
        ),
        child: Text(
          date == null ? 'Choose a date' : EiFmt.date(date),
          style: date == null
              ? theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : theme.textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _JobEditor extends ConsumerStatefulWidget {
  const _JobEditor({this.job, this.suggestion});

  final EiJob? job;
  final EiPayrollPattern? suggestion;

  @override
  ConsumerState<_JobEditor> createState() => _JobEditorState();
}

class _JobEditorState extends ConsumerState<_JobEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.job?.employerName ?? widget.suggestion?.payerName ?? '',
  );
  late final _weekly = TextEditingController(
    text: _numberText(widget.job?.usualWeeklyHours),
  );
  late final _perPeriod = TextEditingController(
    text: _numberText(widget.job?.hoursPerPayPeriod),
  );
  late EiEmploymentType _type =
      widget.job?.employmentType ?? EiEmploymentType.fullTime;
  late DateTime? _start = widget.job?.startDate;
  late DateTime? _end = widget.job?.endDate;
  late bool _ongoing = widget.job?.endDate == null;
  late int _days = widget.job?.daysPerWeek ?? 5;
  late bool _variable = widget.job?.variableHours ?? false;
  late EiPayFrequency _frequency =
      widget.job?.payFrequency ??
      widget.suggestion?.frequency ??
      EiPayFrequency.biweekly;
  late bool _insurable = widget.job?.isInsurable ?? true;
  String? _dateError;

  @override
  void dispose() {
    _name.dispose();
    _weekly.dispose();
    _perPeriod.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final patterns = widget.job == null
        ? ref.watch(eiPayrollPatternsProvider)
        : const <EiPayrollPattern>[];

    return _SheetBody(
      title: widget.job == null ? 'Add a job' : 'Edit job',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Employer name'),
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              validator: (text) => text == null || text.trim().isEmpty
                  ? 'Enter the employer name'
                  : null,
            ),
            if (patterns.isNotEmpty) ...<Widget>[
              Text(
                'Found in your pay deposits',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final pattern in patterns.take(4))
                    ActionChip(
                      avatar: const Icon(Icons.payments_outlined, size: 18),
                      label: Text(
                        pattern.frequency == null
                            ? pattern.payerName
                            : '${pattern.payerName} · '
                                  '${pattern.frequency!.label.toLowerCase()}',
                      ),
                      onPressed: () => setState(() {
                        _name.text = pattern.payerName;
                        final frequency = pattern.frequency;
                        if (frequency != null) _frequency = frequency;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            DropdownButtonFormField<EiEmploymentType>(
              isExpanded: true,
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Employment type'),
              items: <DropdownMenuItem<EiEmploymentType>>[
                for (final type in EiEmploymentType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 12),
            _DateField(
              label: 'Employment start date',
              value: _start,
              onTap: () async {
                final picked = await pickEiDate(context, initial: _start);
                if (picked != null) setState(() => _start = picked);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('I still work here'),
              value: _ongoing,
              onChanged: (value) => setState(() {
                _ongoing = value;
                if (value) _end = null;
              }),
            ),
            if (!_ongoing)
              _DateField(
                label: 'Employment end date',
                value: _end,
                onTap: () async {
                  final picked = await pickEiDate(
                    context,
                    initial: _end ?? _start,
                  );
                  if (picked != null) setState(() => _end = picked);
                },
              ),
            if (_dateError != null) _ErrorText(_dateError!),
            const SizedBox(height: 12),
            TextFormField(
              controller: _weekly,
              decoration: const InputDecoration(
                labelText: 'Usual hours worked per week',
                helperText: 'Fills weeks you do not enter and projects ahead',
              ),
              keyboardType: _decimalKeyboard,
              validator: _hoursValidator(max: 168),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _days,
              decoration: const InputDecoration(
                labelText: 'Days worked per week',
              ),
              items: <DropdownMenuItem<int>>[
                for (var day = 1; day <= DateTime.daysPerWeek; day++)
                  DropdownMenuItem(
                    value: day,
                    child: Text(day == 5 ? '5 (Monday to Friday)' : '$day'),
                  ),
              ],
              onChanged: (value) => setState(() => _days = value ?? _days),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('My hours vary week to week'),
              subtitle: const Text(
                'Past weeks count only the hours you enter',
              ),
              value: _variable,
              onChanged: (value) => setState(() => _variable = value),
            ),
            DropdownButtonFormField<EiPayFrequency>(
              isExpanded: true,
              initialValue: _frequency,
              decoration: const InputDecoration(
                labelText: 'Pay period frequency',
              ),
              items: <DropdownMenuItem<EiPayFrequency>>[
                for (final frequency in EiPayFrequency.values)
                  DropdownMenuItem(
                    value: frequency,
                    child: Text(frequency.label),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _frequency = value ?? _frequency),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _perPeriod,
              decoration: const InputDecoration(
                labelText: 'Hours worked per pay period (optional)',
                helperText: 'Used when usual weekly hours are blank',
              ),
              keyboardType: _decimalKeyboard,
              validator: _hoursValidator(max: 744),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Insurable employment'),
              subtitle: const Text(
                'Turn off for self-employment or other work where no EI '
                'premiums are deducted',
              ),
              value: _insurable,
              onChanged: (value) => setState(() => _insurable = value),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Save job')),
          ],
        ),
      ),
    );
  }

  void _save() {
    final valid = _form.currentState!.validate();
    final start = _start;
    final end = _end;
    String? error;
    if (start == null) {
      error = 'Choose the date you started this job';
    } else if (!_ongoing && end == null) {
      error = 'Choose the date this job ended';
    } else if (!_ongoing && end != null && end.isBefore(start)) {
      error = 'The end date must be after the start date';
    }
    setState(() => _dateError = error);
    if (!valid || error != null || start == null) return;

    Navigator.pop(
      context,
      EiJob(
        id: widget.job?.id ?? generateId(),
        employerName: _name.text.trim(),
        employmentType: _type,
        startDate: start,
        endDate: _ongoing ? null : end,
        usualWeeklyHours: _parseHours(_weekly.text) ?? 0,
        daysPerWeek: _days,
        variableHours: _variable,
        payFrequency: _frequency,
        hoursPerPayPeriod: _parseHours(_perPeriod.text),
        isInsurable: _insurable,
      ),
    );
  }
}

class _HoursEditor extends ConsumerStatefulWidget {
  const _HoursEditor({required this.jobs, this.record, this.method});

  final List<EiJob> jobs;
  final EiHoursRecord? record;
  final EiHoursSource? method;

  @override
  ConsumerState<_HoursEditor> createState() => _HoursEditorState();
}

class _HoursEditorState extends ConsumerState<_HoursEditor> {
  final _form = GlobalKey<FormState>();
  late EiHoursSource _source =
      widget.record?.source ?? widget.method ?? EiHoursSource.weekly;
  late String _jobId = widget.record?.jobId ?? widget.jobs.first.id;
  late DateTime? _start = widget.record?.periodStart ?? _defaultStart();
  late DateTime? _end =
      widget.record?.periodEnd ?? (_start == null ? null : _endFor(_start!));
  late final _worked = TextEditingController(
    text: _numberText(widget.record?.hoursWorked),
  );
  late final _vacation = TextEditingController(
    text: _numberText(widget.record?.vacationHours),
  );
  late final _leave = TextEditingController(
    text: _numberText(widget.record?.paidLeaveHours),
  );
  late final _note = TextEditingController(text: widget.record?.note ?? '');
  late String? _documentId = widget.record?.documentId;
  String? _dateError;

  EiJob get _job => widget.jobs.firstWhere(
    (job) => job.id == _jobId,
    orElse: () => widget.jobs.first,
  );

  /// Last week's Sunday for a weekly entry; nothing for a pay period, whose
  /// dates come from the stub or the user.
  DateTime? _defaultStart() {
    if (_source != EiHoursSource.weekly) return null;
    return EiDates.addDays(EiDates.weekStart(DateTime.now()), -7);
  }

  DateTime _endFor(DateTime start) => _source == EiHoursSource.weekly
      ? EiDates.addDays(start, 6)
      : _job.payFrequency.periodEnd(start);

  @override
  void dispose() {
    _worked.dispose();
    _vacation.dispose();
    _leave.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stubs = ref.watch(eiPayStubsProvider);
    final pattern = _patternFor(
      ref.watch(eiPayrollPatternsProvider),
      _job.employerName,
    );
    final weekly = _source == EiHoursSource.weekly;

    return _SheetBody(
      title: widget.record == null ? 'Add hours' : 'Edit hours',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SegmentedButton<EiHoursSource>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<EiHoursSource>>[
                ButtonSegment(
                  value: EiHoursSource.weekly,
                  label: Text('Week'),
                  icon: Icon(Icons.view_week_outlined),
                ),
                ButtonSegment(
                  value: EiHoursSource.payPeriod,
                  label: Text('Pay period'),
                  icon: Icon(Icons.date_range_outlined),
                ),
                ButtonSegment(
                  value: EiHoursSource.payStub,
                  label: Text('Pay stub'),
                  icon: Icon(Icons.receipt_long_outlined),
                ),
              ],
              selected: <EiHoursSource>{_source},
              onSelectionChanged: (selection) => setState(() {
                _source = selection.first;
                final start = _start;
                if (start != null) _end = _endFor(start);
                if (_source != EiHoursSource.payStub) _documentId = null;
              }),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _jobId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Employer'),
              items: <DropdownMenuItem<String>>[
                for (final job in widget.jobs)
                  DropdownMenuItem(
                    value: job.id,
                    child: Text(
                      job.employerName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _jobId = value ?? _jobId;
                final start = _start;
                if (start != null && _source != EiHoursSource.payStub) {
                  _end = _endFor(start);
                }
              }),
            ),
            const SizedBox(height: 12),
            if (_source == EiHoursSource.payStub) ..._stubPicker(stubs),
            if (_source == EiHoursSource.payPeriod && pattern != null)
              ..._payDates(pattern),
            _DateField(
              label: weekly ? 'Week starting' : 'Period start',
              value: _start,
              onTap: () async {
                final picked = await pickEiDate(context, initial: _start);
                if (picked == null) return;
                setState(() {
                  _start = picked;
                  _end = _endFor(picked);
                });
              },
            ),
            const SizedBox(height: 12),
            _DateField(
              label: weekly ? 'Week ending' : 'Period end',
              value: _end,
              onTap: () async {
                final picked = await pickEiDate(
                  context,
                  initial: _end ?? _start,
                );
                if (picked != null) setState(() => _end = picked);
              },
            ),
            if (_dateError != null) _ErrorText(_dateError!),
            const SizedBox(height: 12),
            TextFormField(
              controller: _worked,
              decoration: InputDecoration(
                labelText: 'Hours worked',
                helperText: weekly
                    ? 'Hours worked that week'
                    : 'Hours worked in the whole period',
              ),
              keyboardType: _decimalKeyboard,
              validator: _hoursValidator(max: 744, optional: false),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _vacation,
                    decoration: const InputDecoration(
                      labelText: 'Vacation hours',
                    ),
                    keyboardType: _decimalKeyboard,
                    validator: _hoursValidator(max: 744),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _leave,
                    decoration: const InputDecoration(
                      labelText: 'Paid leave hours',
                    ),
                    keyboardType: _decimalKeyboard,
                    validator: _hoursValidator(max: 744),
                  ),
                ),
              ],
            ),
            const _Hint(EiMessages.paidTimeOff),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              maxLength: 120,
            ),
            const SizedBox(height: 4),
            FilledButton(onPressed: _save, child: const Text('Save hours')),
          ],
        ),
      ),
    );
  }

  List<Widget> _stubPicker(List<FinancialDocument> stubs) {
    if (stubs.isEmpty) {
      return <Widget>[
        const _Hint(
          'No pay stubs in your Vault yet. Add one there to link it to these '
          'hours, or enter the dates and hours from the stub below.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.pop(context);
              router.push(Routes.vault);
            },
            icon: const Icon(Icons.folder_copy_outlined),
            label: const Text('Open Vault'),
          ),
        ),
        const SizedBox(height: 8),
      ];
    }
    return <Widget>[
      DropdownButtonFormField<String>(
        initialValue: stubs.any((s) => s.id == _documentId)
            ? _documentId
            : null,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Pay stub from your Vault',
        ),
        items: <DropdownMenuItem<String>>[
          for (final stub in stubs)
            DropdownMenuItem(
              value: stub.id,
              child: Text(_stubLabel(stub), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (id) {
          final stub = stubs.firstWhere((s) => s.id == id);
          setState(() {
            _documentId = id;
            final start = stub.periodStart;
            final end = stub.periodEnd;
            if (start != null) _start = EiDates.day(start);
            if (end != null) _end = EiDates.day(end);
            final match = _jobNamed(stub.institution);
            if (match != null) _jobId = match.id;
          });
        },
      ),
      const _Hint(
        'Enter the hours printed on the stub. SpendWise does not read hours '
        'from the file.',
      ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _payDates(EiPayrollPattern pattern) {
    final theme = Theme.of(context);
    return <Widget>[
      Text(
        'Recent pay dates from ${pattern.payerName}',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final date in pattern.payDates.reversed.take(6))
            ActionChip(
              label: Text(EiFmt.shortDate(date)),
              onPressed: () => setState(() {
                _end = date;
                _start = _periodEndingOn(date, _job.payFrequency);
              }),
            ),
        ],
      ),
      const _Hint(
        'A pay period usually ends a few days before payday. Adjust the '
        'dates to match your pay stub.',
      ),
      const SizedBox(height: 12),
    ];
  }

  String _stubLabel(FinancialDocument stub) {
    final start = stub.periodStart;
    final end = stub.periodEnd;
    if (start == null) return stub.fileName;
    final range = end == null
        ? EiFmt.date(start)
        : '${EiFmt.shortDate(start)} to ${EiFmt.date(end)}';
    return '${stub.fileName} · $range';
  }

  EiJob? _jobNamed(String? name) {
    final wanted = name?.trim().toUpperCase();
    if (wanted == null || wanted.isEmpty) return null;
    for (final job in widget.jobs) {
      final employer = job.employerName.toUpperCase();
      if (employer.contains(wanted) || wanted.contains(employer)) return job;
    }
    return null;
  }

  void _save() {
    final valid = _form.currentState!.validate();
    final start = _start;
    final end = _end;
    final worked = _parseHours(_worked.text) ?? 0;
    final vacation = _parseHours(_vacation.text) ?? 0;
    final leave = _parseHours(_leave.text) ?? 0;
    String? error;
    if (start == null || end == null) {
      error = 'Choose the start and end dates';
    } else if (end.isBefore(start)) {
      error = 'The end date must be on or after the start date';
    } else if (worked + vacation + leave >
        EiDates.inclusiveDays(start, end) * Duration.hoursPerDay) {
      error = 'That is more hours than the period has';
    }
    setState(() => _dateError = error);
    if (!valid || error != null || start == null || end == null) return;

    final note = _note.text.trim();
    Navigator.pop(
      context,
      EiHoursRecord(
        id: widget.record?.id ?? generateId(),
        jobId: _jobId,
        periodStart: start,
        periodEnd: end,
        hoursWorked: worked,
        vacationHours: vacation,
        paidLeaveHours: leave,
        source: _source,
        documentId: _source == EiHoursSource.payStub ? _documentId : null,
        note: note.isEmpty ? null : note,
      ),
    );
  }
}

/// The payroll pattern whose payer matches [employer], if any.
EiPayrollPattern? _patternFor(
  List<EiPayrollPattern> patterns,
  String employer,
) {
  final name = employer.trim().toUpperCase();
  if (name.isEmpty) return null;
  for (final pattern in patterns) {
    final payer = pattern.payerName.toUpperCase();
    if (payer.contains(name) || name.contains(payer)) return pattern;
  }
  return null;
}

/// The start of a pay period that ends on [end].
DateTime _periodEndingOn(DateTime end, EiPayFrequency frequency) {
  switch (frequency) {
    case EiPayFrequency.weekly:
      return EiDates.addDays(end, -6);
    case EiPayFrequency.biweekly:
      return EiDates.addDays(end, -13);
    case EiPayFrequency.semiMonthly:
      return end.day <= 15
          ? DateTime.utc(end.year, end.month, 1)
          : DateTime.utc(end.year, end.month, 16);
    case EiPayFrequency.monthly:
      return EiDates.addDays(DateTime.utc(end.year, end.month - 1, end.day), 1);
  }
}

class _BreakEditor extends StatefulWidget {
  const _BreakEditor({required this.jobs, this.value});

  final List<EiJob> jobs;
  final EiBreak? value;

  @override
  State<_BreakEditor> createState() => _BreakEditorState();
}

class _BreakEditorState extends State<_BreakEditor> {
  late EiBreakKind _kind = widget.value?.kind ?? EiBreakKind.gap;
  late String? _jobId = widget.value?.jobId;
  late DateTime? _start = widget.value?.start;
  late DateTime? _end = widget.value?.end;
  late final _note = TextEditingController(text: widget.value?.note ?? '');
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetBody(
      title: widget.value == null ? 'Add a gap or unpaid leave' : 'Edit',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SegmentedButton<EiBreakKind>(
            showSelectedIcon: false,
            segments: <ButtonSegment<EiBreakKind>>[
              for (final kind in EiBreakKind.values)
                ButtonSegment(value: kind, label: Text(kind.label)),
            ],
            selected: <EiBreakKind>{_kind},
            onSelectionChanged: (selection) =>
                setState(() => _kind = selection.first),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: _jobId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Applies to'),
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem(value: null, child: Text('All jobs')),
              for (final job in widget.jobs)
                DropdownMenuItem(
                  value: job.id,
                  child: Text(
                    job.employerName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _jobId = value),
          ),
          const SizedBox(height: 12),
          _DateField(
            label: 'First day',
            value: _start,
            onTap: () async {
              final picked = await pickEiDate(context, initial: _start);
              if (picked != null) setState(() => _start = picked);
            },
          ),
          const SizedBox(height: 12),
          _DateField(
            label: 'Last day',
            value: _end,
            onTap: () async {
              final picked = await pickEiDate(
                context,
                initial: _end ?? _start,
              );
              if (picked != null) setState(() => _end = picked);
            },
          ),
          if (_error != null) _ErrorText(_error!),
          const _Hint(
            'No hours are counted for these days, even where a usual weekly '
            'schedule would have added some. Hours you enter for these days '
            'still count.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
            maxLength: 120,
          ),
          const SizedBox(height: 4),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }

  void _save() {
    final start = _start;
    final end = _end;
    if (start == null || end == null) {
      setState(() => _error = 'Choose the first and last day');
      return;
    }
    if (end.isBefore(start)) {
      setState(() => _error = 'The last day must be on or after the first');
      return;
    }
    final note = _note.text.trim();
    Navigator.pop(
      context,
      EiBreak(
        id: widget.value?.id ?? generateId(),
        start: start,
        end: end,
        kind: _kind,
        jobId: _jobId,
        note: note.isEmpty ? null : note,
      ),
    );
  }
}
