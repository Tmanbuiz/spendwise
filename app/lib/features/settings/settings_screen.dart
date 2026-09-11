import '../planning/backup_screen.dart';
import '../planning/bills_screen.dart';
import '../planning/alerts_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/diagnostics.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/bank.dart';
import '../../services/capture_controller.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Who makes SpendWise. Shown in Settings so the owner is always visible.
const String _ownerName = 'WinaTribe Inc';
final Uri _ownerWebsite = Uri.parse('https://www.wiantribe.com');

/// Settings, plus the honest status of everything the app depends on.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final preferences = ref.watch(preferencesProvider).value;
    final access = ref.watch(notificationAccessProvider);
    final granted = ref.watch(notificationPermissionProvider).value ?? false;
    final isRemote = ref.watch(isRemoteProvider);
    final user = ref.watch(authUserProvider).value;

    final selectedBanks = (preferences?.selectedBankIds ?? const <String>{})
        .map(Banks.byId)
        .whereType<Bank>()
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: <Widget>[
          const SectionHeader(title: 'Capture'),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: <Widget>[
                _StatusTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Notification access',
                  subtitle: !access.isSupportedPlatform
                      ? 'Android only — not available on this device'
                      : granted
                      ? 'On — purchases are recorded automatically'
                      : 'Off — nothing is being captured',
                  ok: granted,
                  warn: access.isSupportedPlatform && !granted,
                  onTap: () => context.push(Routes.notificationAccess),
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('Your banks'),
                  subtitle: Text(
                    selectedBanks.isEmpty
                        ? 'None selected'
                        : selectedBanks.map((b) => b.shortName).join(', '),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.banks),
                ),
                _DetectedAppsTile(),
                _CaptureStatsTile(),
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('Test the parser'),
                  subtitle: const Text(
                    'Paste a notification and see how it reads',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.debug),
                ),
                ListenableBuilder(
                  listenable: Diagnostics.instance,
                  builder: (context, _) {
                    final count = Diagnostics.instance.errors.length;
                    return ListTile(
                      leading: Icon(
                        Icons.bug_report_outlined,
                        color: count > 0 ? AppTheme.negative : null,
                      ),
                      title: const Text('Diagnostics'),
                      subtitle: Text(
                        count == 0
                            ? 'No errors recorded'
                            : '$count error${count == 1 ? '' : 's'} recorded — '
                                  'tap to see what failed',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: count > 0
                              ? AppTheme.negative
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push(Routes.diagnostics),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Planning and protection'),
          SectionCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Backup and restore'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BackupScreen(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.event_repeat),
                  title: const Text('Recurring bills'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BillsScreen(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Budget alerts'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AlertsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Your money'),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('Import a statement'),
                  subtitle: Text(
                    'Load a CSV or PDF from your bank for full history',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.importStatement),
                ),
                ListTile(
                  leading: const Icon(Icons.credit_card_outlined),
                  title: const Text('Accounts'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.accounts),
                ),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Categories and rules'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.categories),
                ),
                ListTile(
                  leading: Icon(
                    Icons.account_balance_outlined,
                    color: Env.aggregatorEnabled
                        ? AppTheme.positive
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Linked bank accounts'),
                  subtitle: Text(
                    Env.aggregatorEnabled
                        ? 'Pull full transaction history from your bank'
                        : 'Not set up — SpendWise is reading notifications '
                              'only, so it sees what your bank chooses to '
                              'push.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  isThreeLine: !Env.aggregatorEnabled,
                  enabled: Env.aggregatorEnabled,
                  trailing: Env.aggregatorEnabled
                      ? const Icon(Icons.chevron_right_rounded)
                      : null,
                  onTap: Env.aggregatorEnabled ? () {} : null,
                ),
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Month starts on'),
                  subtitle: Text(
                    'Day ${preferences?.monthStartDay ?? 1} of each month',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _pickMonthStart(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Data and privacy'),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      isRemote
                          ? Icons.cloud_done_outlined
                          : Icons.phone_android_outlined,
                      size: 20,
                      color: isRemote
                          ? AppTheme.positive
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isRemote
                            ? 'Synced to your Supabase account'
                            : 'Stored on this device only',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  isRemote
                      ? 'Row Level Security means only your account can read '
                            'or write your rows.'
                      : 'No Supabase project is configured, so nothing leaves '
                            'this phone and nothing is backed up. Add your '
                            'Supabase URL and key to .env to enable sync.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const Divider(height: 28),
                Text(
                  'SpendWise never stores your online banking password, PIN, '
                  'CVV or full card number. The most it keeps from a card is '
                  'the last four digits. It cannot move money.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (Env.isConfigured) ...<Widget>[
            const SizedBox(height: 20),
            const SectionHeader(title: 'Account'),
            SectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.person_outline_rounded),
                    title: Text(user?.email ?? 'Signed in'),
                    subtitle: const Text('Supabase account'),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.logout_rounded,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Sign out',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () => ref.read(authActionsProvider).signOut(),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          const SectionHeader(title: 'About'),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.business_outlined),
              title: const Text('Made by $_ownerName'),
              subtitle: Text(
                _ownerWebsite.host,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () => _openOwnerWebsite(context),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'SpendWise 1.4.0  ·  © 2026 $_ownerName',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickMonthStart(BuildContext context, WidgetRef ref) async {
    final current = ref.read(preferencesProvider).value?.monthStartDay ?? 1;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: RadioGroup<int>(
          groupValue: current,
          onChanged: (value) => Navigator.of(context).pop(value),
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'Budgets reset on this day each month. Useful if your pay '
                  'cycle is not the 1st.',
                ),
              ),
              for (var day = 1; day <= 28; day++)
                RadioListTile<int>(value: day, title: Text('Day $day')),
            ],
          ),
        ),
      ),
    );

    if (picked != null) {
      await ref.read(preferencesProvider.notifier).setMonthStartDay(picked);
    }
  }

  Future<void> _openOwnerWebsite(BuildContext context) async {
    final opened = await launchUrl(
      _ownerWebsite,
      mode: LaunchMode.externalApplication,
    );
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open ${_ownerWebsite.host}.')),
    );
  }
}

/// Shows which bank apps were actually found, with their package ids.
///
/// The package id is the thing that has to match for capture to work, and it
/// is the one value neither the developer nor the user can confirm without
/// looking. Showing it turns a silent failure into a diagnosable one.
class _DetectedAppsTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final installed = ref.watch(installedBankAppsProvider);

    return installed.when(
      loading: () => const ListTile(
        leading: Icon(Icons.apps_outlined),
        title: Text('Detected bank apps'),
        subtitle: Text('Checking…'),
      ),
      error: (error, _) => ListTile(
        leading: const Icon(Icons.apps_outlined),
        title: const Text('Detected bank apps'),
        subtitle: Text('Could not check: $error'),
      ),
      data: (found) => ListTile(
        leading: Icon(
          Icons.apps_outlined,
          color: found.isEmpty ? AppTheme.warning : AppTheme.positive,
        ),
        title: const Text('Detected bank apps'),
        subtitle: Text(
          found.isEmpty
              ? 'None found. Without the bank app installed, no alerts can '
                    'reach SpendWise.'
              : found.entries.map((e) => '${e.value}  ·  ${e.key}').join('\n'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: found.isEmpty
                ? AppTheme.warning
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        isThreeLine: found.length > 1,
        onTap: () => ref.invalidate(installedBankAppsProvider),
      ),
    );
  }
}

/// Shows what the Android capture path has done, and lets the user process
/// anything queued right now.
///
/// The counters answer the question the dashboard cannot: is capture working
/// and there was simply nothing to capture, or is it silently broken? Those
/// two look identical without this.
class _CaptureStatsTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats = ref.watch(captureStatsProvider);

    return stats.when(
      loading: () => const ListTile(
        leading: Icon(Icons.podcasts_outlined),
        title: Text('Capture activity'),
        subtitle: Text('Checking…'),
      ),
      error: (error, _) => ListTile(
        leading: const Icon(Icons.podcasts_outlined),
        title: const Text('Capture activity'),
        subtitle: Text('Could not check: $error'),
      ),
      data: (data) {
        if (!data.available) {
          return const ListTile(
            leading: Icon(Icons.podcasts_outlined),
            title: Text('Capture activity'),
            subtitle: Text('Android only'),
          );
        }

        final healthy =
            data.listenerConnected && data.watchedPackages.isNotEmpty;

        return ListTile(
          leading: Icon(
            Icons.podcasts_outlined,
            color: healthy ? AppTheme.positive : AppTheme.warning,
          ),
          title: const Text('Capture activity'),
          subtitle: Text(
            <String>[
              '${data.seen} notifications seen, '
                  '${data.matched} from your banks',
              if (data.pending > 0)
                '${data.pending} waiting — tap to process now',
              if (!data.listenerConnected) 'Listener not connected to Android',
              if (data.watchedPackages.isEmpty)
                'No packages being watched — reselect your banks',
            ].join('\n'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: healthy
                  ? theme.colorScheme.onSurfaceVariant
                  : AppTheme.warning,
            ),
          ),
          isThreeLine: !healthy || data.pending > 0,
          trailing: const Icon(Icons.refresh_rounded),
          onTap: () async {
            final captured = await ref
                .read(captureControllerProvider)
                .drainPending(rescanFirst: true);
            ref.invalidate(captureStatsProvider);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  captured == 0
                      ? 'Nothing waiting to be processed.'
                      : 'Added $captured transaction'
                            '${captured == 1 ? '' : 's'}.',
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ok,
    required this.warn,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool ok;
  final bool warn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ok
        ? AppTheme.positive
        : warn
        ? AppTheme.warning
        : theme.colorScheme.onSurfaceVariant;

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(color: color),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}
