import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/ei/ei_config.dart';
import '../../data/ei/ei_dates.dart';
import '../../data/ei/ei_models.dart';
import '../../data/ei/ei_payroll_detection.dart';
import '../../data/ei/ei_verification.dart';
import '../../data/models/app_transaction.dart';
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

/// Opens the hours form. [jobId] and [stubPrefill] start a new pay stub
/// entry from what is already known, such as a deposit with no stub.
Future<void> showEiHoursEditor(
  BuildContext context,
  WidgetRef ref, {
  EiHoursRecord? record,
  EiHoursSource? method,
  String? jobId,
  EiPayStubDetails? stubPrefill,
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
    _HoursEditor(
      jobs: data.jobs,
      record: record,
      method: method,
      jobId: jobId,
      stubPrefill: stubPrefill,
    ),
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

int? _parseCents(String text) {
  final value = text.trim().replaceAll(RegExp(r'[$,\s]'), '');
  if (value.isEmpty) return null;
  final parsed = double.tryParse(value);
  return parsed == null ? null : (parsed * 100).round();
}

String _centsText(int? cents) =>
    cents == null ? '' : (cents / 100).toStringAsFixed(2);

final RegExp _moneyPattern = RegExp(
  r'^\$?\s*(\d{1,3}(,\d{3})+|\d+)?(\.\d{1,2})?$',
);

String? _moneyValidator(String? text) {
  final value = text?.trim() ?? '';
  if (value.isEmpty) return null;
  return _moneyPattern.hasMatch(value) && RegExp(r'\d').hasMatch(value)
      ? null
      : 'Enter an amount like 1234.56';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, prefixText: r'$ '),
      keyboardType: _decimalKeyboard,
      validator: _moneyValidator,
      onChanged: (_) => onChanged(),
    );
  }
}

/// Checks on the stub being entered, as it is typed: do its numbers add up,
/// was an EI premium taken, and did its net pay reach the bank.
class _StubCheck extends ConsumerWidget {
  const _StubCheck({
    required this.details,
    required this.draft,
    required this.job,
  });

  final EiPayStubDetails details;

  /// The entry as typed so far; null until it has a date to search from.
  final EiHoursRecord? draft;
  final EiJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    const settings = EiConfig.verification;
    final lines = <(IconData, Color, String)>[];

    if (details.isEmpty) {
      lines.add((
        Icons.fact_check_outlined,
        muted,
        'Enter the pay figures and SpendWise checks the stub as you type.',
      ));
    } else {
      final calculated = details.calculatedNetCents;
      final net = details.netPayCents;
      if (calculated != null && net != null) {
        if ((net - calculated).abs() <= settings.netPayToleranceCents) {
          lines.add((
            Icons.check_circle_outline_rounded,
            AppTheme.positive,
            'Gross pay less deductions is ${Fmt.money(calculated)}, which '
                'matches the net pay.',
          ));
        } else {
          lines.add((
            Icons.error_outline_rounded,
            AppTheme.warning,
            'Gross pay less deductions is ${Fmt.money(calculated)}, but the '
                'net pay is ${Fmt.money(net)}. A deduction may be missing or '
                'mistyped.',
          ));
        }
      } else if (calculated != null) {
        lines.add((
          Icons.calculate_outlined,
          muted,
          'Gross pay less deductions: ${Fmt.money(calculated)}. Enter the net '
              'pay to compare.',
        ));
      }

      final premium = details.eiPremiumCents;
      if (premium != null && premium > 0) {
        lines.add((
          Icons.check_circle_outline_rounded,
          AppTheme.positive,
          'An EI premium was deducted, a sign this is insurable employment.',
        ));
      } else if (premium == 0 && (details.grossPayCents ?? 0) > 0) {
        lines.add((
          Icons.error_outline_rounded,
          AppTheme.warning,
          'No EI premium was deducted. These hours may not be insurable, or '
              'this year\'s maximum premium may already have been reached.',
        ));
      }

      final record = draft;
      if (net != null && record != null) {
        final transactions =
            ref.watch(transactionsProvider).value ?? const <AppTransaction>[];
        final verification = ref.watch(eiVerificationProvider);
        final taken = <String>{
          for (final check in verification?.checks ?? const <EiStubCheck>[])
            if (check.record.id != record.id && check.deposit != null)
              check.deposit!.id,
        };
        final deposit = EiVerifier.findDeposit(
          record: record,
          transactions: transactions,
          job: job,
          exclude: taken,
        );
        final payDate = details.payDate;
        if (deposit != null) {
          final from = deposit.merchant == null
              ? ''
              : ' from ${deposit.merchant}';
          lines.add((
            Icons.account_balance_outlined,
            AppTheme.positive,
            'Deposit found: ${Fmt.money(net)} on '
                '${EiFmt.date(deposit.occurredAt)}$from.',
          ));
        } else {
          final where = payDate == null
              ? 'in the ${settings.depositSearchDaysWithoutPayDate} days after '
                    'the period'
              : 'near ${EiFmt.date(payDate)}';
          lines.add((
            Icons.search_off_rounded,
            AppTheme.warning,
            'No deposit of ${Fmt.money(net)} found $where. Import the bank '
                'statement that covers it, or check the amount.',
          ));
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Stub check', style: theme.textTheme.titleSmall),
          for (final (icon, color, text) in lines)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(text, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
        ],
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
  const _HoursEditor({
    required this.jobs,
    this.record,
    this.method,
    this.jobId,
    this.stubPrefill,
  });

  final List<EiJob> jobs;
  final EiHoursRecord? record;
  final EiHoursSource? method;
  final String? jobId;
  final EiPayStubDetails? stubPrefill;

  @override
  ConsumerState<_HoursEditor> createState() => _HoursEditorState();
}

class _HoursEditorState extends ConsumerState<_HoursEditor> {
  final _form = GlobalKey<FormState>();

  // A pay stub is the default because it is the entry SpendWise can check.
  late EiHoursSource _source =
      widget.record?.source ?? widget.method ?? EiHoursSource.payStub;
  late String _jobId =
      widget.record?.jobId ??
      (widget.jobs.any((job) => job.id == widget.jobId)
          ? widget.jobId!
          : widget.jobs.first.id);
  late DateTime? _start = widget.record?.periodStart ?? _defaultStart();
  late DateTime? _end =
      widget.record?.periodEnd ?? (_start == null ? null : _endFor(_start!));
  late final EiPayStubDetails? _initialStub =
      widget.record?.payStub ?? widget.stubPrefill;
  late DateTime? _payDate = _initialStub?.payDate;
  late final _worked = TextEditingController(
    text: _numberText(widget.record?.hoursWorked),
  );
  late final _overtime = TextEditingController(
    text: _numberText(widget.record?.overtimeHours),
  );
  late final _vacation = TextEditingController(
    text: _numberText(widget.record?.vacationHours),
  );
  late final _leave = TextEditingController(
    text: _numberText(widget.record?.paidLeaveHours),
  );
  late final _gross = TextEditingController(
    text: _centsText(_initialStub?.grossPayCents),
  );
  late final _tax = TextEditingController(
    text: _centsText(_initialStub?.incomeTaxCents),
  );
  late final _cpp = TextEditingController(
    text: _centsText(_initialStub?.cppCents),
  );
  late final _eiPremium = TextEditingController(
    text: _centsText(_initialStub?.eiPremiumCents),
  );
  late final _otherDeductions = TextEditingController(
    text: _centsText(_initialStub?.otherDeductionsCents),
  );
  late final _net = TextEditingController(
    text: _centsText(_initialStub?.netPayCents),
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
    for (final controller in <TextEditingController>[
      _worked,
      _overtime,
      _vacation,
      _leave,
      _gross,
      _tax,
      _cpp,
      _eiPremium,
      _otherDeductions,
      _net,
      _note,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  EiPayStubDetails _stubDetails() => EiPayStubDetails(
    payDate: _payDate,
    grossPayCents: _parseCents(_gross.text),
    incomeTaxCents: _parseCents(_tax.text),
    cppCents: _parseCents(_cpp.text),
    eiPremiumCents: _parseCents(_eiPremium.text),
    otherDeductionsCents: _parseCents(_otherDeductions.text),
    netPayCents: _parseCents(_net.text),
  );

  /// The stub as typed so far, for the live check. It needs a period end or
  /// a pay date before there is anywhere to look for the deposit.
  EiHoursRecord? _draft() {
    final end = _end ?? _payDate;
    if (end == null) return null;
    final start = _start;
    return EiHoursRecord(
      id: widget.record?.id ?? '',
      jobId: _jobId,
      periodStart: start == null || start.isAfter(end) ? end : start,
      periodEnd: end,
      hoursWorked: 0,
      source: EiHoursSource.payStub,
      payStub: _stubDetails(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stubs = ref.watch(eiPayStubsProvider);
    final pattern = EiPayrollDetector.forEmployer(
      ref.watch(eiPayrollPatternsProvider),
      _job.employerName,
    );
    final weekly = _source == EiHoursSource.weekly;
    final isStub = _source == EiHoursSource.payStub;
    void changed() => setState(() {});

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
                  value: EiHoursSource.payStub,
                  label: Text('Pay stub'),
                  icon: Icon(Icons.receipt_long_outlined),
                ),
                ButtonSegment(
                  value: EiHoursSource.payPeriod,
                  label: Text('Pay period'),
                  icon: Icon(Icons.date_range_outlined),
                ),
                ButtonSegment(
                  value: EiHoursSource.weekly,
                  label: Text('Week'),
                  icon: Icon(Icons.view_week_outlined),
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
            _Hint(
              isStub
                  ? 'Most accurate: copy the stub line by line, and SpendWise '
                        'checks it against your bank deposit.'
                  : 'Quicker, but unchecked. A pay stub lets SpendWise verify '
                        'the hours.',
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
            if (isStub) ..._stubPicker(stubs),
            if (!weekly && pattern != null) ..._payDates(pattern),
            if (isStub) const _SectionLabel('Pay period'),
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
            if (isStub) ...<Widget>[
              const SizedBox(height: 12),
              _DateField(
                label: 'Pay date',
                value: _payDate,
                onTap: () async {
                  final picked = await pickEiDate(
                    context,
                    initial: _payDate ?? _end,
                  );
                  if (picked != null) setState(() => _payDate = picked);
                },
              ),
            ],
            if (_dateError != null) _ErrorText(_dateError!),
            if (isStub)
              const _SectionLabel('Hours')
            else
              const SizedBox(height: 12),
            TextFormField(
              controller: _worked,
              decoration: InputDecoration(
                labelText: isStub ? 'Regular hours' : 'Hours worked',
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
                    controller: _overtime,
                    decoration: const InputDecoration(
                      labelText: 'Overtime hours',
                    ),
                    keyboardType: _decimalKeyboard,
                    validator: _hoursValidator(max: 744),
                  ),
                ),
                const SizedBox(width: 12),
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
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _leave,
              decoration: const InputDecoration(
                labelText: 'Stat holiday and other paid leave hours',
              ),
              keyboardType: _decimalKeyboard,
              validator: _hoursValidator(max: 744),
            ),
            const _Hint(EiMessages.paidTimeOff),
            if (isStub) ...<Widget>[
              const _SectionLabel('Pay'),
              _MoneyField(
                controller: _gross,
                label: 'Gross pay',
                onChanged: changed,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _MoneyField(
                      controller: _tax,
                      label: 'Income tax',
                      onChanged: changed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MoneyField(
                      controller: _cpp,
                      label: 'CPP or QPP',
                      onChanged: changed,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _MoneyField(
                      controller: _eiPremium,
                      label: 'EI premium',
                      onChanged: changed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MoneyField(
                      controller: _otherDeductions,
                      label: 'Other deductions',
                      onChanged: changed,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _MoneyField(
                controller: _net,
                label: 'Net pay (deposited)',
                onChanged: changed,
              ),
              const SizedBox(height: 12),
              _StubCheck(details: _stubDetails(), draft: _draft(), job: _job),
            ],
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
    final isStub = _source == EiHoursSource.payStub;
    return <Widget>[
      Text(
        'Recent pay from ${pattern.payerName}',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final deposit in pattern.deposits.reversed.take(6))
            ActionChip(
              label: Text(
                '${EiFmt.shortDate(deposit.occurredAt)} · '
                '${Fmt.money(deposit.amountCents)}',
              ),
              onPressed: () => setState(() {
                final day = EiDates.day(deposit.occurredAt);
                if (isStub) {
                  _payDate = day;
                  // Only an empty net pay is filled: overwriting a typed
                  // figure would hide the very mismatch the check exists for.
                  if (_net.text.trim().isEmpty) {
                    _net.text = _centsText(deposit.amountCents);
                  }
                } else {
                  _end = day;
                  _start = _periodEndingOn(day, _job.payFrequency);
                }
              }),
            ),
        ],
      ),
      _Hint(
        isStub
            ? 'Tap the deposit this stub paid to fill in its pay date and net '
                  'pay.'
            : 'A pay period usually ends a few days before payday. Adjust the '
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
    final overtime = _parseHours(_overtime.text) ?? 0;
    final vacation = _parseHours(_vacation.text) ?? 0;
    final leave = _parseHours(_leave.text) ?? 0;
    String? error;
    if (start == null || end == null) {
      error = 'Choose the start and end dates';
    } else if (end.isBefore(start)) {
      error = 'The end date must be on or after the start date';
    } else if (worked + overtime + vacation + leave >
        EiDates.inclusiveDays(start, end) * Duration.hoursPerDay) {
      error = 'That is more hours than the period has';
    }
    setState(() => _dateError = error);
    if (!valid || error != null || start == null || end == null) return;

    final stub = _source == EiHoursSource.payStub ? _stubDetails() : null;
    final note = _note.text.trim();
    Navigator.pop(
      context,
      EiHoursRecord(
        id: widget.record?.id ?? generateId(),
        jobId: _jobId,
        periodStart: start,
        periodEnd: end,
        hoursWorked: worked,
        overtimeHours: overtime,
        vacationHours: vacation,
        paidLeaveHours: leave,
        source: _source,
        payStub: stub == null || stub.isEmpty ? null : stub,
        documentId: _source == EiHoursSource.payStub ? _documentId : null,
        note: note.isEmpty ? null : note,
      ),
    );
  }
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
