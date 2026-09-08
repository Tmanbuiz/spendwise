import 'dart:convert';

import 'package:spendwise_parser/spendwise_parser.dart';

import '../data/models/app_transaction.dart';
import '../data/models/account.dart';
import '../data/models/budget.dart';
import '../data/models/user_preferences.dart';
import '../data/repositories/repositories.dart';
import 'recurring_bills.dart';

class BackupData {
  BackupData({
    required this.transactions,
    required this.accounts,
    required this.budgets,
    required this.rules,
    required this.preferences,
    required this.bills,
  });
  final List<AppTransaction> transactions;
  final List<Account> accounts;
  final List<Budget> budgets;
  final List<MerchantRule> rules;
  final UserPreferences preferences;
  final List<RecurringBill> bills;
  String encode() => jsonEncode({
    'app': 'SpendWise',
    'version': 1,
    'created': DateTime.now().toUtc().toIso8601String(),
    'transactions': transactions.map((x) => x.toJson()).toList(),
    'accounts': accounts.map((x) => x.toJson()).toList(),
    'budgets': budgets.map((x) => x.toJson()).toList(),
    'rules': rules.map((x) => x.toJson()).toList(),
    'preferences': preferences.toJson(),
    'bills': bills.map((x) => x.toJson()).toList(),
  });
  static BackupData decode(String text) {
    if (text.length > 20000000) {
      throw const FormatException('Backup is too large');
    }
    final root = jsonDecode(text) as Map<String, dynamic>;
    if (root['app'] != 'SpendWise' || root['version'] != 1) {
      throw const FormatException('Not a supported SpendWise backup');
    }
    List<T> rows<T>(String key, T Function(Map<String, dynamic>) parse) {
      final items = root[key] as List;
      final ids = <String>{};
      return items.map((item) {
        final row = Map<String, dynamic>.from(item as Map);
        final id = row['id'];
        if (id is! String || id.isEmpty || !ids.add(id)) {
          throw FormatException('Invalid or repeated ID in $key');
        }
        if (key == 'transactions') {
          if (row['occurred_at'] is! String ||
              DateTime.tryParse(row['occurred_at']) == null ||
              row['amount_cents'] is! int ||
              (row['amount_cents'] as int) < 0) {
            throw const FormatException('Invalid transaction');
          }
        }
        if (key == 'budgets' &&
            (row['amount_cents'] is! int ||
                (row['amount_cents'] as int) <= 0)) {
          throw const FormatException('Invalid budget');
        }
        return parse(row);
      }).toList();
    }

    return BackupData(
      transactions: rows('transactions', AppTransaction.fromJson),
      accounts: rows('accounts', Account.fromJson),
      budgets: rows('budgets', Budget.fromJson),
      rules: rows('rules', MerchantRule.fromJson),
      preferences: UserPreferences.fromJson(
        Map<String, dynamic>.from(root['preferences'] as Map),
      ),
      bills: rows('bills', RecurringBill.fromJson),
    );
  }

  static Future<BackupData> capture(
    DataLayer data,
    List<RecurringBill> bills,
  ) async => BackupData(
    transactions: await data.transactions.list(),
    accounts: await data.accounts.list(),
    budgets: await data.budgets.list(),
    rules: await data.rules.list(),
    preferences: await data.preferences.load(),
    bills: bills,
  );

  /// Writes the backup over what is on the device, by id.
  ///
  /// This used to add missing ids only, which meant a restore could never
  /// repair a row that already existed — it silently skipped it. That made the
  /// feature useless in the situation it exists for: data on the device is
  /// wrong, and a known-good copy is available. Restoring a corrected backup
  /// appeared to succeed and changed nothing.
  ///
  /// So a row present in both is now overwritten from the backup. The cost is
  /// that an edit made after the backup was taken is lost for that row, which
  /// is the ordinary meaning of restoring: the file is the version being
  /// asked for. Rows absent from the backup are left alone rather than
  /// deleted, so restoring an older file adds history back without discarding
  /// anything newer.
  ///
  /// Returns the number of rows written.
  Future<int> restore(DataLayer data) async {
    var count = 0;

    for (final x in accounts) {
      await data.accounts.upsert(x);
      count++;
    }
    for (final x in transactions) {
      await data.transactions.upsert(x);
      count++;
    }

    // Budgets match on identity *or* on the pair the app treats as unique, so
    // restoring cannot leave two budgets competing for one category.
    final currentBudgets = await data.budgets.list();
    for (final x in budgets) {
      final clash = currentBudgets.where(
        (b) =>
            b.id != x.id &&
            b.currency == x.currency &&
            b.category == x.category,
      );
      for (final duplicate in clash.toList()) {
        await data.budgets.delete(duplicate.id);
        currentBudgets.remove(duplicate);
      }
      await data.budgets.upsert(x);
      count++;
    }

    for (final x in rules) {
      await data.rules.upsert(x);
      count++;
    }
    return count;
  }
}
