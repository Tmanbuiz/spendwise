import 'dart:convert';
import 'dart:async';

import 'package:sqflite/sqflite.dart';
import '../../services/local_cipher.dart';

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
  LocalStore(this._db, this._cipher);
  final Database _db;
  final LocalCipher _cipher;
  final Object _zoneKey = Object();
  DatabaseExecutor get _executor => Zone.current[_zoneKey] as DatabaseExecutor? ?? _db;
  static const keys = ['spendwise.transactions', 'spendwise.accounts',
    'spendwise.budgets', 'spendwise.rules', 'spendwise.financial_documents',
    'spendwise.financial_rules', 'spendwise.preferences', 'spendwise.recurring_bills'];

  static Future<DataLayer> open({DatabaseFactory? factory, LocalCipher? cipher, String? path}) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      path ?? '${await getDatabasesPath()}/spendwise-v1.db',
      options: OpenDatabaseOptions(version: 1, singleInstance: path != inMemoryDatabasePath, onCreate: (db, _) async {
        await db.execute('CREATE TABLE records (collection TEXT PRIMARY KEY, payload TEXT NOT NULL)');
      }),
    );
    final store = LocalStore(db, cipher ?? await LocalCipher.open());
    final prefs = await SharedPreferences.getInstance();
    // Commit and read back every encrypted payload before removing any legacy
    // row. If interrupted, the next launch resumes without replacing new data.
    await store.atomic(() async {
      for (final key in keys) {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final old = jsonDecode(raw); // Corruption fails closed; never starts empty.
        if (key.endsWith('.preferences') ? old is! Map : old is! List) {
          throw const FormatException('Invalid legacy store');
        }
        if ((await store._executor.query('records', where: 'collection = ?', whereArgs: [key])).isEmpty) {
          await store._write(key, raw);
          if (await store._read(key) != raw) throw StateError('Migration verification failed');
        }
      }
    });
    for (final key in keys) {
      if (prefs.containsKey(key) && !await prefs.remove(key)) throw StateError('Legacy cleanup failed');
    }
    return DataLayer(
      transactions: LocalTransactionRepository(store), accounts: LocalAccountRepository(store),
      budgets: LocalBudgetRepository(store), rules: LocalRuleRepository(store),
      documents: LocalFinancialDocumentRepository(store), financialRules: LocalFinancialRuleRepository(store),
      preferences: LocalPreferencesRepository(store), isRemote: false, atomicWrite: store.atomic,
      readBills: () => store.readList('spendwise.recurring_bills'),
      writeBills: (rows) => store.writeList('spendwise.recurring_bills', rows),
    );
  }
  Future<void> atomic(Future<void> Function() action) async {
    if (Zone.current[_zoneKey] != null) return action();
    await _db.transaction((txn) => runZoned(action, zoneValues: {_zoneKey: txn}));
  }
  Future<String?> _read(String key) async {
    final rows = await _executor.query('records', where: 'collection = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return utf8.decode(await _cipher.decrypt(rows.single['payload'] as String, key));
  }
  Future<void> _write(String key, String raw) async {
    await _executor.insert('records', {'collection': key,
      'payload': await _cipher.encrypt(utf8.encode(raw), key)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<Map<String, Object?>>> readList(String key) async {
    final raw = await _read(key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((r) => Map<String, Object?>.from(r as Map)).toList();
  }
  Future<void> mutateList(String key, List<Map<String, Object?>> Function(List<Map<String, Object?>>) change) =>
    atomic(() async => _write(key, jsonEncode(change(await readList(key)))));
  Future<void> writeList(String key, List<Map<String, Object?>> rows) =>
    atomic(() => _write(key, jsonEncode(rows)));
  Future<Map<String, Object?>> readMap(String key) async {
    final raw = await _read(key);
    return raw == null ? {} : Map<String, Object?>.from(jsonDecode(raw) as Map);
  }
  Future<void> writeMap(String key, Map<String, Object?> value) =>
    atomic(() => _write(key, jsonEncode(value)));
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
    final all = (await _store.readList(_key))
        .map(AppTransaction.fromJson)
        .where((t) => from == null || !t.occurredAt.isBefore(from))
        .where((t) => to == null || t.occurredAt.isBefore(to))
        .toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return all;
  }

  @override
  Future<void> upsert(AppTransaction transaction) async {
    await _store.mutateList(_key, (rows) => _upsertRow(rows, transaction.toJson()));
  }

  @override
  Future<void> delete(String id) async {
    await _store.mutateList(_key, (rows) => rows..removeWhere((r) => r['id'] == id));
  }
}

class LocalAccountRepository implements AccountRepository {
  LocalAccountRepository(this._store);
  static const _key = 'spendwise.accounts';
  final LocalStore _store;

  @override
  Future<List<Account>> list() async =>
      (await _store.readList(_key)).map(Account.fromJson).toList();

  @override
  Future<void> upsert(Account account) async => _store.mutateList(_key, (rows) => _upsertRow(rows, account.toJson()));

  @override
  Future<void> delete(String id) async {
    await _store.mutateList(_key, (rows) => rows..removeWhere((r) => r['id'] == id));
  }
}

class LocalBudgetRepository implements BudgetRepository {
  LocalBudgetRepository(this._store);
  static const _key = 'spendwise.budgets';
  final LocalStore _store;

  @override
  Future<List<Budget>> list() async =>
      (await _store.readList(_key)).map(Budget.fromJson).toList();

  @override
  Future<void> upsert(Budget budget) async => _store.mutateList(_key, (rows) => _upsertRow(rows, budget.toJson()));

  @override
  Future<void> delete(String id) async {
    await _store.mutateList(_key, (rows) => rows..removeWhere((r) => r['id'] == id));
  }
}

class LocalRuleRepository implements MerchantRuleRepository {
  LocalRuleRepository(this._store);
  static const _key = 'spendwise.rules';
  final LocalStore _store;

  @override
  Future<List<MerchantRule>> list() async =>
      (await _store.readList(_key)).map(MerchantRule.fromJson).toList();

  @override
  Future<void> upsert(MerchantRule rule) async => _store.mutateList(_key, (rows) => _upsertRow(rows, rule.toJson()));

  @override
  Future<void> delete(String id) async {
    await _store.mutateList(_key, (rows) => rows..removeWhere((r) => r['id'] == id));
  }
}

class LocalFinancialDocumentRepository implements FinancialDocumentRepository {
  LocalFinancialDocumentRepository(this._store);
  static const _key = 'spendwise.financial_documents';
  final LocalStore _store;

  @override
  Future<List<FinancialDocument>> list() async {
    final documents = (await _store.readList(_key))
        .map(FinancialDocument.fromJson)
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return documents;
  }

  @override
  Future<void> upsert(FinancialDocument document) => _store.mutateList(_key, (rows) => _upsertRow(rows, document.toJson()));

  @override
  Future<void> delete(String id) async {
    await _store.mutateList(_key, (rows) => rows..removeWhere((row) => row['id'] == id));
  }
}

class LocalFinancialRuleRepository implements FinancialRuleRepository {
  LocalFinancialRuleRepository(this._store);
  static const _key = 'spendwise.financial_rules';
  final LocalStore _store;

  @override
  Future<List<FinancialRule>> list() async =>
      (await _store.readList(_key)).map(FinancialRule.fromJson).toList();

  @override
  Future<void> upsert(FinancialRule rule) => _store.mutateList(_key, (rows) => _upsertRow(rows, rule.toJson()));

  @override
  Future<void> delete(String id) async {
    await _store.mutateList(_key, (rows) => rows..removeWhere((row) => row['id'] == id));
  }
}

class LocalPreferencesRepository implements PreferencesRepository {
  LocalPreferencesRepository(this._store);
  static const _key = 'spendwise.preferences';
  final LocalStore _store;

  @override
  Future<UserPreferences> load() async =>
      UserPreferences.fromJson(await _store.readMap(_key));

  @override
  Future<void> save(UserPreferences preferences) =>
      _store.writeMap(_key, preferences.toJson());
}
