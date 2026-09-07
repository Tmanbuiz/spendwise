import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/budget.dart';
import '../data/models/app_transaction.dart';
import '../data/month_summary.dart';
import '../state/providers.dart';

class BudgetAlert {
  const BudgetAlert(this.key, this.title, this.body);
  final String key, title, body;
}

List<BudgetAlert> budgetAlerts(
  List<Budget> budgets,
  List<AppTransaction> transactions,
  DateTime now,
  int startDay,
) {
  final window = MonthWindow.forDate(now, monthStartDay: startDay);
  return [
    for (final b in budgets)
      if (b.amountCents > 0)
        ...() {
          final spent = transactions
              .where(
                (t) =>
                    t.countsAsSpending &&
                    t.currency == b.currency &&
                    window.contains(t.occurredAt) &&
                    !t.occurredAt.isAfter(now) &&
                    (b.category == null || t.category == b.category),
              )
              .fold<int>(0, (sum, t) => sum + t.amountCents);
          final level = spent >= b.amountCents
              ? 100
              : spent * 100 >= b.amountCents * 80
              ? 80
              : 0;
          return level == 0
              ? <BudgetAlert>[]
              : [
                  BudgetAlert(
                    '${window.start.toIso8601String()}:${b.id}:$level',
                    '${b.category?.displayName ?? 'Monthly budget'}: $level%',
                    '${b.currency} ${(spent / 100).toStringAsFixed(2)} of ${(b.amountCents / 100).toStringAsFixed(2)} spent.',
                  ),
                ];
        }(),
  ];
}

const alertChannel = MethodChannel('com.spendwise/budget_alerts');
final alertsEnabledProvider = AsyncNotifierProvider<AlertsEnabled, bool>(
  AlertsEnabled.new,
);

class AlertsEnabled extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(
        'spendwise.budget_alerts',
      ) ??
      false;
  Future<void> set(bool value) async {
    if (value) {
      final allowed =
          await alertChannel.invokeMethod<bool>('requestPermission') ?? false;
      if (!allowed) {
        throw StateError('Enable notifications in Android settings first.');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool('spendwise.budget_alerts', value)) {
      throw StateError('Could not save preference');
    }
    state = AsyncData(value);
  }
}

final activeBudgetAlertsProvider = Provider<List<BudgetAlert>>(
  (ref) => budgetAlerts(
    ref.watch(budgetsProvider).value ?? [],
    ref.watch(transactionsProvider).value ?? [],
    ref.watch(reportingNowProvider),
    ref.watch(preferencesProvider).value?.monthStartDay ?? 1,
  ),
);
final alertDispatcherProvider = Provider<AlertDispatcher>(
  (ref) => AlertDispatcher(),
);

class AlertDispatcher {
  Future<void> _pending = Future.value();
  Future<void> send(List<BudgetAlert> alerts) {
    _pending = _pending
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          if (!(prefs.getBool('spendwise.budget_alerts') ?? false)) return;
          final sent =
              (prefs.getStringList('spendwise.sent_budget_alerts') ?? [])
                  .toSet();
          for (final alert in alerts) {
            if (sent.contains(alert.key)) continue;
            final delivered =
                await alertChannel.invokeMethod<bool>('show', {
                  'key': alert.key,
                  'title': alert.title,
                  'body': alert.body,
                }) ??
                false;
            if (delivered) {
              sent.add(alert.key);
              // A 100% warning also satisfies the lower threshold for this period.
              if (alert.key.endsWith(':100')) {
                sent.add('${alert.key.substring(0, alert.key.length - 4)}:80');
              }
              await prefs.setStringList(
                'spendwise.sent_budget_alerts',
                sent.toList().reversed.take(500).toList().reversed.toList(),
              );
            }
          }
        })
        .catchError((Object _) {
          /* Retry on next transaction or app opening. */
        });
    return _pending;
  }
}
