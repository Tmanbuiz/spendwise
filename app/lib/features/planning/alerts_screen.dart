import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/budget_alerts.dart';
import '../../widgets/common.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(alertsEnabledProvider);
    final alerts = ref.watch(activeBudgetAlertsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Budget alerts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Budget notifications'),
                  subtitle: const Text('Warn at 80% and 100% of each budget'),
                  value: enabled.value ?? false,
                  onChanged: enabled.isLoading
                      ? null
                      : (v) async {
                          try {
                            await ref
                                .read(alertsEnabledProvider.notifier)
                                .set(v);
                          } on Object catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Notifications are unavailable. Allow SpendWise notifications in Android settings and try again.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                ),
                const Text(
                  'Checked when SpendWise processes transactions, including when you reopen the app. Each threshold sends once per budget period. This does not run a separate background spending check.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Current budget status',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (alerts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'No budgets have reached 80%. Add budgets in the Budgets tab to start tracking.',
              ),
            ),
          for (final alert in alerts)
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(alert.title),
              subtitle: Text(alert.body),
            ),
        ],
      ),
    );
  }
}
