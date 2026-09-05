import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../services/capture_controller.dart';
import '../../state/providers.dart';

/// Asks the user to switch on Android notification access.
///
/// Android provides no in-app grant dialog for this permission — the user must
/// toggle it in system settings — so this screen sends them there and then
/// re-checks the real OS state when they come back, rather than assuming the
/// trip succeeded.
class PermissionScreen extends ConsumerStatefulWidget {
  const PermissionScreen({super.key, this.isOnboarding = false});

  /// During onboarding, finishing here completes setup and opens the app.
  /// Opened from Settings it simply returns.
  final bool isOnboarding;

  @override
  ConsumerState<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends ConsumerState<PermissionScreen>
    with WidgetsBindingObserver {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from system settings is the only signal we get that the user
    // may have granted access, so re-read it then.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(notificationPermissionProvider);
    }
  }

  Future<void> _openSettings() async {
    setState(() => _checking = true);
    await ref.read(notificationAccessProvider).openSettings();
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _finish({required bool granted}) async {
    final preferences = ref.read(preferencesProvider.notifier);
    await preferences.setNotificationAccessConfirmed(granted);

    if (widget.isOnboarding) {
      await preferences.completeOnboarding();
      if (mounted) context.go(Routes.dashboard);
      return;
    }

    // Opened from Settings: pick up anything that arrived before access was
    // granted, so turning the permission on has an immediate visible effect.
    if (granted) {
      unawaited(
        ref.read(captureControllerProvider).drainPending(rescanFirst: true),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final access = ref.watch(notificationAccessProvider);
    final permission = ref.watch(notificationPermissionProvider);
    final granted = permission.value ?? false;
    final supported = access.isSupportedPlatform;

    return Scaffold(
      appBar: AppBar(title: const Text('Notification access')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: (granted ? AppTheme.positive : AppTheme.brand)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                ),
                child: Column(
                  children: <Widget>[
                    Icon(
                      granted
                          ? Icons.check_circle_outline_rounded
                          : Icons.notifications_active_outlined,
                      size: 48,
                      color: granted
                          ? AppTheme.positive
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      granted
                          ? 'Notification access is on'
                          : 'One permission to turn on',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      granted
                          ? 'SpendWise will start recording purchases as your '
                              'bank alerts arrive.'
                          : 'SpendWise needs to read notifications to see your '
                              'purchase alerts. Android only lets you grant '
                              'this from system settings.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (!supported)
                _InfoCard(
                  icon: Icons.phone_iphone_rounded,
                  title: 'Not available on this platform',
                  body: 'Automatic capture needs Android. On iPhone you can '
                      'add transactions by hand; email-based import is '
                      'planned.',
                )
              else ...<Widget>[
                Text('How to turn it on',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                const _Step(
                  number: 1,
                  text: 'Tap "Open Android settings" below.',
                ),
                const _Step(
                  number: 2,
                  text: 'Find SpendWise in the list of apps.',
                ),
                const _Step(
                  number: 3,
                  text: 'Switch on notification access and come back here.',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _checking ? null : _openSettings,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open Android settings'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.invalidate(notificationPermissionProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Check again'),
                ),
              ],
              const SizedBox(height: 24),
              const _InfoCard(
                icon: Icons.lock_outline_rounded,
                title: 'What SpendWise can and cannot do',
                body: 'It reads alerts only from the banks you selected. It '
                    'cannot move money, cannot sign in to your bank, and never '
                    'stores your banking password, PIN, CVV or full card '
                    'number.',
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _finish(granted: granted),
                child: Text(widget.isOnboarding ? (granted ? 'Finish setup' : 'Continue anyway') : 'Done'),
              ),
              if (!granted && supported) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  'Without access, transactions must be added by hand. You can '
                  'turn this on later in Settings.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});
  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
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
