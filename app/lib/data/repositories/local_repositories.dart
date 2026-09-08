import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

import '../models/account.dart';
import '../models/app_transaction.dart';
import '../models/budget.dart';
import '../models/financial_document.dart';
import '../models/financial_rule.dart';
import '../models/user_preferences.dart';
import 'repositories.dart';

/// Device-local storage, used until a Supabase project is configured.
///
/// This is not a cache and does not sync. It exists so the app is usable and
/// demoable on day one, and so the UI has something real to render while the
/// backend is being set up. The Settings screen states plainly that data is
/// local only.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<DataLayer> open() async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalStore(prefs);
    return DataLayer(
      transactions: LocalTransactionRepository(store),
      accounts: LocalAccountRepository(store),
      budgets: LocalBudgetRepository(store),
      rules: LocalRuleRepository(store),
      documents: LocalFinancialDocumentRepository(store),
      financialRules: LocalFinancialRuleRepository(store),
      preferences: LocalPreferencesRepository(store),
      isRemote: false,
    );
  }

  List<Map<String, Object?>> readList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return <Map<String, Object?>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, Object?>>[];
      return decoded.whereType<Map<String, Object?>>().toList();
    } on FormatException {
      // Corrupt local data must not brick the app; start clean instead.
      return <Map<String, Object?>>[];
    }
  }

  Future<void> writeList(String key, List<Map<String, Object?>> rows) =>
      _prefs.setString(key, jsonEncode(rows));

  Map<String, Object?> readMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : <String, Object?>{};
    } on FormatException {
      return <String, Object?>{};
    }
  }

  Future<void> writeMap(String key, Map<String, Object?> value) =>
      _prefs.setString(key, jsonEncode(value));
}

/// Replaces the row with a matching `id`, or appends it.
List<Map<String, Object?>> _upsertRow(
  List<Map<String, Object?>> rows,
  Map<String, Object?> row,
) {
  final id = row['id'];
  final index = rows.indexWhere((r) => r['id'] == id);
  final next = List<Map<String, Object?>>.from(rows);
  if (index >= 0) {
    next[index] = row;
  } else {
    next.add(row);
  }
  return next;
}

class LocalTransactionRepository implements TransactionRepository {
  LocalTransactionRepository(this._store);
  static const _key = 'spendwise.transactions';
  final LocalStore _store;

  @override
  Future<List<AppTransaction>> list({DateTime? from, DateTime? to}) async {
    final all = _store
        .readList(_key)
        .map(AppTransaction.fromJson)
        .where((t) => from == null || !t.occurredAt.isBefore(from))
        .where((t) => to == null || t.occurredAt.isBefore(to))
        .toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return all;
  }

  @override
  Future<void> upsert(AppTransaction transaction) async {
    await _store.writeList(
      _key,
      _upsertRow(_store.readList(_key), transaction.toJson()),
    );
  }

  @override
  Future<void> delete(String id) async {
    final rows = _store.readList(_key)..removeWhere((r) => r['id'] == id);
    await _store.writeList(_key, rows);
  }
}

class LocalAccountRepository implements AccountRepository {
  LocalAccountRepository(this._store);
  static const _key = 'spendwise.accounts';
  final LocalStore _store;

  @override
  Future<List<Account>> list() async =>
      _store.readList(_key).map(Account.fromJson).toList();

  @override
  Future<void> upsert(Account account) async => _store.writeList(
        _key,
        _upsertRow(_store.readList(_key), account.toJson()),
      );

  @override
  Future<void> delete(String id) async {
    final rows = _store.readList(_key)..removeWhere((r) => r['id'] == id);
    await _store.writeList(_key, rows);
  }
}

class LocalBudgetRepository implements BudgetRepository {
  LocalBudgetRepository(this._store);
  static const _key = 'spendwise.budgets';
  final LocalStore _store;

  @override
  Future<List<Budget>> list() async =>
      _store.readList(_key).map(Budget.fromJson).toList();

  @override
  Future<void> upsert(Budget budget) async => _store.writeList(
        _key,
        _upsertRow(_store.readList(_key), budget.toJson()),
      );

  @override
  Future<void> delete(String id) async {
    final rows = _store.readList(_key)..removeWhere((r) => r['id'] == id);
    await _store.writeList(_key, rows);
  }
}

class LocalRuleRepository implements MerchantRuleRepository {
  LocalRuleRepository(this._store);
  static const _key = 'spendwise.rules';
  final LocalStore _store;

  @override
  Future<List<MerchantRule>> list() async =>
      _store.readList(_key).map(MerchantRule.fromJson).toList();

  @override
  Future<void> upsert(MerchantRule rule) async => _store.writeList(
        _key,
        _upsertRow(_store.readList(_key), rule.toJson()),
      );

  @override
  Future<void> delete(String id) async {
    final rows = _store.readList(_key)..removeWhere((r) => r['id'] == id);
    await _store.writeList(_key, rows);
  }
}

class LocalFinancialDocumentRepository implements FinancialDocumentRepository {
  LocalFinancialDocumentRepository(this._store);
  static const _key = 'spendwise.financial_documents';
  final LocalStore _store;

  @override
  Future<List<FinancialDocument>> list() async {
    final documents = _store
        .readList(_key)
        .map(FinancialDocument.fromJson)
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return documents;
  }

  @override
  Future<void> upsert(FinancialDocument document) => _store.writeList(
        _key,
        _upsertRow(_store.readList(_key), document.toJson()),
      );

  @override
  Future<void> delete(String id) async {
    final rows = _store.readList(_key)..removeWhere((row) => row['id'] == id);
    await _store.writeList(_key, rows);
  }
}

class LocalFinancialRuleRepository implements FinancialRuleRepository {
  LocalFinancialRuleRepository(this._store);
  static const _key = 'spendwise.financial_rules';
  final LocalStore _store;

  @override
  Future<List<FinancialRule>> list() async =>
      _store.readList(_key).map(FinancialRule.fromJson).toList();

  @override
  Future<void> upsert(FinancialRule rule) => _store.writeList(
        _key,
        _upsertRow(_store.readList(_key), rule.toJson()),
      );

  @override
  Future<void> delete(String id) async {
    final rows = _store.readList(_key)..removeWhere((row) => row['id'] == id);
    await _store.writeList(_key, rows);
  }
}

class LocalPreferencesRepository implements PreferencesRepository {
  LocalPreferencesRepository(this._store);
  static const _key = 'spendwise.preferences';
  final LocalStore _store;

  @override
  Future<UserPreferences> load() async =>
      UserPreferences.fromJson(_store.readMap(_key));

  @override
  Future<void> save(UserPreferences preferences) =>
      _store.writeMap(_key, preferences.toJson());
}
