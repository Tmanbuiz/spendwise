import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendwise/services/backup_service.dart';
import 'package:spendwise/services/budget_alerts.dart';
import 'package:spendwise/services/recurring_bills.dart';
import 'package:spendwise/data/models/app_transaction.dart';
import 'package:spendwise/data/models/budget.dart';
import 'package:spendwise/data/models/user_preferences.dart';
import 'package:spendwise/data/repositories/local_repositories.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

AppTransaction tx(
  int cents, {
  String currency = 'CAD',
  DateTime? date,
  bool excluded = false,
}) => AppTransaction(
  id: 'one',
  eventType: TransactionEventType.purchase,
  amountCents: cents,
  currency: currency,
  occurredAt: date ?? DateTime(2026, 9, 7),
  category: SpendCategory.other,
  source: TransactionSource.manual,
  excludedByUser: excluded,
);
RecurringBill bill(DateTime date, {String frequency = 'monthly'}) =>
    RecurringBill(
      id: 'bill',
      name: 'Rent',
      cents: 100000,
      currency: 'CAD',
      due: date,
      frequency: frequency,
      anchorDay: date.day,
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'backup round trip and repeated merge retain existing edits and budgets',
    () async {
      final original = await LocalStore.open();
      await original.transactions.upsert(tx(900));
      await original.budgets.upsert(
        const Budget(id: 'budget', amountCents: 10000),
      );
      final backup = await BackupData.capture(original, [
        bill(DateTime(2026, 1, 31)),
      ]);
      final decoded = BackupData.decode(backup.encode());
      expect(decoded.bills.single.advance().due, DateTime(2026, 2, 28));
      SharedPreferences.setMockInitialValues({});
      final destination = await LocalStore.open();
      expect(await decoded.restore(destination), 2);
      await destination.transactions.upsert(tx(1200));
      expect(await decoded.restore(destination), 0);
      expect((await destination.transactions.list()).single.amountCents, 1200);
      final clash = BackupData(
        transactions: [],
        accounts: [],
        rules: [],
        bills: [],
        preferences: const UserPreferences(),
        budgets: [const Budget(id: 'another', amountCents: 20000)],
      );
      expect(await clash.restore(destination), 0);
      expect((await destination.budgets.list()).single.amountCents, 10000);
    },
  );
  test('reject invalid backups before writing any records', () {
    expect(
      () => BackupData.decode('{"app":"Other","version":1}'),
      throwsA(isA<FormatException>()),
    );
    final data = BackupData(
      transactions: [tx(1)],
      accounts: [],
      budgets: [],
      rules: [],
      bills: [],
      preferences: const UserPreferences(),
    );
    final json = jsonDecode(data.encode()) as Map<String, dynamic>;
    json['transactions'][0]['occurred_at'] = 'invalid';
    expect(
      () => BackupData.decode(jsonEncode(json)),
      throwsA(isA<FormatException>()),
    );
  });
  test(
    'notification thresholds are sent once and denied notifications can retry',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('spendwise.budget_alerts', true);
      var permitted = false;
      var sends = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(alertChannel, (call) async {
            if (permitted) sends++;
            return permitted;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(alertChannel, null),
      );
      final dispatcher = AlertDispatcher();
      const full = BudgetAlert('period:budget:100', 'Full', 'Body');
      const warning = BudgetAlert('period:budget:80', 'Warning', 'Body');
      await dispatcher.send([full]);
      expect(sends, 0);
      permitted = true;
      await dispatcher.send([full]);
      await dispatcher.send([full, warning]);
      expect(sends, 1);
    },
  );
  test('month end and leap day recurrence preserve original due day', () {
    expect(
      bill(DateTime(2026, 1, 31)).advance().advance().due,
      DateTime(2026, 3, 31),
    );
    expect(
      bill(DateTime(2024, 2, 29), frequency: 'yearly').advance().due,
      DateTime(2025, 2, 28),
    );
    expect(
      bill(DateTime(2026, 12, 29), frequency: 'weekly').advance().due,
      DateTime(2027, 1, 5),
    );
  });
  test('alerts use exact thresholds, current period, currency and spending exclusions', () {
    const budgets = [Budget(id: 'budget', amountCents: 10000)];
    final now = DateTime(2026, 9, 7, 12);
    expect(budgetAlerts(budgets, [tx(7999)], now, 1), isEmpty);
    expect(
      budgetAlerts(budgets, [tx(8000)], now, 1).single.key,
      endsWith(':80'),
    );
    expect(
      budgetAlerts(budgets, [tx(10000)], now, 1).single.key,
      endsWith(':100'),
    );
    expect(
      budgetAlerts(budgets, [tx(10000, currency: 'USD')], now, 1),
      isEmpty,
    );
    expect(budgetAlerts(budgets, [tx(10000, excluded: true)], now, 1), isEmpty);
    expect(
      budgetAlerts(budgets, [tx(10000, date: DateTime(2026, 9, 8))], now, 1),
      isEmpty,
    );
    expect(
      budgetAlerts(budgets, [tx(10000, date: DateTime(2026, 8, 15))], now, 5),
      isEmpty,
    );
  });
}
