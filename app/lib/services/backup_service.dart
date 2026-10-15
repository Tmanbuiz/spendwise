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
      if (items.length > 100000) throw const FormatException('Too many records');
      final ids = <String>{};
      return items.map((item) {
        final row = Map<String, dynamic>.from(item as Map);
        final id = row['id'];
        if (id is! String || id.isEmpty || id.length > 64 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) || !ids.add(id)) {
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

  /// Default restore preserves newer records. Overwrite is an explicit choice.
  Future<int> restore(DataLayer data, {bool overwrite = false, bool restoreSettings = false}) async {
    final atomic = data.atomicWrite;
    if (atomic == null) throw StateError('Atomic restore is unavailable for this storage.');
    // Round-trip validates programmatically constructed backups as well.
    final validated = BackupData.decode(encode());
    var count = 0;
    await atomic(() async {
      final oldAccounts = await data.accounts.list();
      final accountIds = {...oldAccounts.map((a) => a.id), ...validated.accounts.map((a) => a.id)};
      for (final t in validated.transactions) {
        if (t.accountId != null && !accountIds.contains(t.accountId)) {
          throw const FormatException('Transaction references a missing account');
        }
      }
      for (final a in validated.accounts) {
        if (overwrite || !oldAccounts.any((x) => x.id == a.id)) { await data.accounts.upsert(a); count++; }
      }
      final oldTransactions = await data.transactions.list();
      for (final t in validated.transactions) {
        if (overwrite || !oldTransactions.any((x) => x.id == t.id)) { await data.transactions.upsert(t); count++; }
      }
      final currentBudgets = await data.budgets.list();
      for (final b in validated.budgets) {
        final clashes = currentBudgets.where((x) => x.id == b.id || (x.currency == b.currency && x.category == b.category)).toList();
        if (!overwrite && clashes.isNotEmpty) continue;
        for (final x in clashes) { if (x.id != b.id) await data.budgets.delete(x.id); currentBudgets.remove(x); }
        await data.budgets.upsert(b); currentBudgets.add(b); count++;
      }
      final oldRules = await data.rules.list();
      for (final r in validated.rules) {
        if (overwrite || !oldRules.any((x) => x.id == r.id)) { await data.rules.upsert(r); count++; }
      }
      if (data.readBills != null && data.writeBills != null) {
        final rows = await data.readBills!();
        for (final bill in validated.bills) {
          final index = rows.indexWhere((x) => x['id'] == bill.id);
          if (index < 0) { rows.add(bill.toJson()); count++; }
          else if (overwrite) { rows[index] = bill.toJson(); count++; }
        }
        await data.writeBills!(rows);
      }
      if (restoreSettings) {
        final current = await data.preferences.load();
        await data.preferences.save(current.copyWith(currency: preferences.currency,
          monthStartDay: preferences.monthStartDay, selectedBankIds: preferences.selectedBankIds,
          autoCategorize: preferences.autoCategorize));
      }
    });
    return count;
  }

  Future<Map<String, int>> previewCounts(DataLayer data, {bool overwrite = false}) async {
    var added = 0, replaced = 0, unchanged = 0;
    void compare(Iterable<String> incoming, Set<String> current) {
      for (final id in incoming) {
        if (!current.contains(id)) { added++; } else if (overwrite) { replaced++; } else { unchanged++; }
      }
    }
    compare(accounts.map((x) => x.id), (await data.accounts.list()).map((x) => x.id).toSet());
    compare(transactions.map((x) => x.id), (await data.transactions.list()).map((x) => x.id).toSet());
    compare(rules.map((x) => x.id), (await data.rules.list()).map((x) => x.id).toSet());
    final oldBudgets = await data.budgets.list();
    for (final b in budgets) {
      if (oldBudgets.any((x) => x.id == b.id || (x.currency == b.currency && x.category == b.category))) {
        if (overwrite) { replaced++; } else { unchanged++; }
      } else { added++; }
    }
    final oldBills = await data.readBills?.call() ?? <Map<String, Object?>>[];
    compare(bills.map((x) => x.id), oldBills.map((x) => x['id'] as String).toSet());
    return {'added': added, 'replaced': replaced, 'unchanged': unchanged};
  }
}
