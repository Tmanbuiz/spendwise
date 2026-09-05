import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/bank.dart';
import '../../services/capture_controller.dart';
import '../../state/providers.dart';

/// Bank selection.
///
/// Support level is shown honestly per bank: CIBC has a tested parser, the
/// others capture notifications but cannot yet read them. A user who picks an
/// unsupported bank should know their transactions need manual entry rather
/// than wondering why nothing appears.
class BankSelectionScreen extends ConsumerStatefulWidget {
  const BankSelectionScreen({super.key, this.isOnboarding = false});

  /// During onboarding this continues to the permission step; opened from
  /// Settings it simply saves and returns.
  final bool isOnboarding;

  @override
  ConsumerState<BankSelectionScreen> createState() =>
      _BankSelectionScreenState();
}

class _BankSelectionScreenState extends ConsumerState<BankSelectionScreen> {
  Set<String>? _selection;

  Set<String> get _selected =>
      _selection ??
      ref.read(preferencesProvider).value?.selectedBankIds ??
      const <String>{};

  void _toggle(String bankId) {
    setState(() {
      final next = Set<String>.from(_selected);
      if (!next.remove(bankId)) next.add(bankId);
      _selection = next;
    });
  }

  Future<void> _continue() async {
    await ref.read(preferencesProvider.notifier).setBanks(_selected);

    // The Android service filters by package from its own persisted list, so
    // it has to be told about the change — otherwise a newly added bank's
    // alerts keep being ignored until the app is next restarted.
    //
    // Deliberately not awaited: this is a best-effort platform call, and
    // blocking navigation on it means a slow or wedged channel leaves the user
    // stuck on a screen whose button appears to do nothing.
    unawaited(ref.read(captureControllerProvider).refreshWatchedPackages());

    if (!mounted) return;
    if (widget.isOnboarding) {
      context.go(Routes.permission);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;

    return Scaffold(
      appBar: AppBar(title: const Text('Your banks')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Pick every bank whose alerts you want SpendWise to read. '
                'Notifications from any other app are ignored entirely.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: Banks.all.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final bank = Banks.all[index];
                  return _BankTile(
                    bank: bank,
                    selected: selected.contains(bank.id),
                    detection: ref.watch(bankDetectionProvider(bank.id)),
                    onTap: () => _toggle(bank.id),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: <Widget>[
                  if (selected.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Choose at least one bank to continue.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: selected.isEmpty ? null : _continue,
                    child: Text(widget.isOnboarding ? 'Continue' : 'Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BankTile extends StatelessWidget {
  const _BankTile({
    required this.bank,
    required this.selected,
    required this.detection,
    required this.onTap,
  });

  final Bank bank;
  final bool selected;
  final BankDetection detection;
  final VoidCallback onTap;

  /// Only says something when it knows something. `unknown` and
  /// `notApplicable` render nothing rather than implying the app is missing.
  Widget? _detectionLine(ThemeData theme) {
    switch (detection) {
      case BankDetection.installed:
        return _line(theme, Icons.check_circle_outline_rounded,
            'App found on this phone', AppTheme.positive);
      case BankDetection.notInstalled:
        return _line(theme, Icons.info_outline_rounded,
            'App not found — alerts cannot arrive', AppTheme.warning);
      case BankDetection.checking:
      case BankDetection.unknown:
      case BankDetection.notApplicable:
        return null;
    }
  }

  Widget _line(ThemeData theme, IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : theme.cardTheme.color,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  bank.shortName.characters.take(2).toString().toUpperCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(bank.name, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 4),
                    Text(
                      bank.hasParser
                          ? 'Automatic — alerts are read and categorised'
                          : 'Capture only — add these by hand for now',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: bank.hasParser
                            ? AppTheme.positive
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    ?_detectionLine(theme),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
