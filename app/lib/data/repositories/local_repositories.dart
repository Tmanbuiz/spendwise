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
      options: OpenDatabaseOptions(version: 3, singleInstance: path != inMemoryDatabasePath,
        onCreate: (db, _) => _createSchema(db),
        onUpgrade: (db, old, _) async {
          if (old < 2) { await _createSchema(db); }
          else if (old < 3) {
            await db.execute('ALTER TABLE secure_rows ADD COLUMN identity TEXT');
            await db.execute('CREATE INDEX secure_rows_identity_idx ON secure_rows(collection, identity) WHERE identity IS NOT NULL');
          }
        }),
    );
    final store = LocalStore(db, cipher ?? await LocalCipher.open());
    final prefs = await SharedPreferences.getInstance();
    await store.atomic(() async {
      // Upgrade the initial encrypted collection format without exposing any
      // plaintext on disk. DDL and every row conversion share this transaction.
      final oldTables = await store._executor.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'records'");
      if (oldTables.isNotEmpty) {
        for (final record in await store._executor.query('records')) {
          final key = record['collection'] as String;
          final raw = utf8.decode(await store._cipher.decrypt(record['payload'] as String, key));
          if (await store._read(key) == null) {
            await store._write(key, raw);
            if (jsonEncode(jsonDecode((await store._read(key))!)) != jsonEncode(jsonDecode(raw))) {
              throw StateError('Encrypted migration verification failed');
            }
          }
        }
        await store._executor.execute('DROP TABLE records');
      }
      final indexed = await store._executor.query('secure_collections',
        where: 'collection = ?', whereArgs: ['spendwise.identity_index.v1']);
      if (indexed.isEmpty) {
        final unindexed = await store._executor.query('secure_rows', where: 'collection = ? AND identity IS NULL',
          whereArgs: ['spendwise.transactions']);
        for (final row in unindexed) {
          final key = row['collection'] as String;
          final value = jsonDecode(utf8.decode(await store._cipher.decrypt(row['payload'] as String, "$key:${row['id']}"))) as Map;
          await store._putRow(key, Map<String, Object?>.from(value));
        }
        await store._executor.insert('secure_collections', {'collection': 'spendwise.identity_index.v1'});
      }
      // A committed marker distinguishes an intentionally empty collection
      // from one that has not migrated. Never overwrite a committed collection.
      for (final key in keys) {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final old = jsonDecode(raw);
        _validate(key, old);
        final existing = await store._read(key); // Authenticate before legacy cleanup.
        if (existing == null) {
          await store._write(key, raw);
          final verified = await store._read(key);
          if (verified == null || jsonEncode(jsonDecode(verified)) != jsonEncode(old)) {
            throw StateError('Migration verification failed');
          }
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
  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE secure_collections (collection TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE secure_rows (collection TEXT NOT NULL, id TEXT NOT NULL, '
      'payload TEXT NOT NULL, identity TEXT, PRIMARY KEY (collection, id))');
    await db.execute('CREATE INDEX secure_rows_identity_idx ON secure_rows(collection, identity) WHERE identity IS NOT NULL');
  }
  static void _validate(String key, Object? value) {
    if (key.endsWith('.preferences')) {
      if (value is! Map) throw const FormatException('Invalid preferences');
      return;
    }
    if (value is! List) throw const FormatException('Invalid collection');
    final ids = <String>{};
    for (final row in value) {
      if (row is! Map || row['id'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(row['id'] as String) || !ids.add(row['id'] as String)) {
        throw const FormatException('Invalid or repeated local record ID');
      }
      if (key == 'spendwise.transactions' && (row['amount_cents'] is! int ||
          (row['amount_cents'] as int) < 0 || row['occurred_at'] is! String ||
          DateTime.tryParse(row['occurred_at'] as String) == null)) {
        throw const FormatException('Invalid local transaction');
      }
    }
  }
  Future<void> atomic(Future<void> Function() action) async {
    if (Zone.current[_zoneKey] != null) return action();
    await _db.transaction((txn) => runZoned(action, zoneValues: {_zoneKey: txn}));
  }
  Future<String?> _read(String key) async {
    final marker = await _executor.query('secure_collections', where: 'collection = ?', whereArgs: [key]);
    if (marker.isEmpty) return null;
    if (key.endsWith('.preferences')) {
      final rows = await _executor.query('secure_rows', where: 'collection = ? AND id = ?', whereArgs: [key, '_map']);
      if (rows.length != 1) throw const FormatException('Missing encrypted preferences');
      return utf8.decode(await _cipher.decrypt(rows.single['payload'] as String, '$key:_map'));
    }
    return jsonEncode(await readList(key));
  }
  Future<void> _write(String key, String raw) async {
    final value = jsonDecode(raw);
    _validate(key, value);
    await _executor.delete('secure_rows', where: 'collection = ?', whereArgs: [key]);
    if (key.endsWith('.preferences')) {
      await _executor.insert('secure_rows', {'collection': key, 'id': '_map',
        'payload': await _cipher.encrypt(utf8.encode(raw), '$key:_map')});
    } else {
      for (final row in value as List) {
        await _putRow(key, Map<String, Object?>.from(row as Map));
      }
    }
    await _executor.insert('secure_collections', {'collection': key}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  Future<void> _putRow(String key, Map<String, Object?> row, {bool deduplicate = false}) async {
    _validate(key, [row]);
    final id = row['id'] as String;
    String? identity;
    if (key == 'spendwise.transactions' && row['source'] == 'notification' && row['fingerprint'] != null) {
      identity = await _cipher.indexIdentifier(jsonEncode([row['fingerprint'], row['bank_id'], row['account_last4'],
        DateTime.parse(row['occurred_at'] as String).toUtc().toIso8601String()]));
      if (deduplicate) {
        final sameId = await _executor.query('secure_rows', columns: ['id'], where: 'collection = ? AND id = ?', whereArgs: [key, id]);
        final sameEvent = await _executor.query('secure_rows', columns: ['id'], where: 'collection = ? AND identity = ?', whereArgs: [key, identity], limit: 1);
        if (sameId.isEmpty && sameEvent.isNotEmpty) return;
      }
    }
    await _executor.insert('secure_rows', {'collection': key, 'id': id, 'identity': identity,
      'payload': await _cipher.encrypt(utf8.encode(jsonEncode(row)), '$key:$id')},
      conflictAlgorithm: ConflictAlgorithm.replace);
    await _executor.insert('secure_collections', {'collection': key}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  Future<List<Map<String, Object?>>> readList(String key) async {
    final result = <Map<String, Object?>>[];
    for (final row in await _executor.query('secure_rows', where: 'collection = ?', whereArgs: [key], orderBy: 'rowid')) {
      final raw = utf8.decode(await _cipher.decrypt(row['payload'] as String, "$key:${row['id']}"));
      final value = Map<String, Object?>.from(jsonDecode(raw) as Map);
      if (value['id'] != row['id']) throw const FormatException('Record identity mismatch');
      result.add(value);
    }
    return result;
  }
  Future<void> upsertRow(String key, Map<String, Object?> row) => atomic(() => _putRow(key, row, deduplicate: true));
  Future<void> deleteRow(String key, String id) => atomic(() async {
    await _executor.delete('secure_rows', where: 'collection = ? AND id = ?', whereArgs: [key, id]);
  });
  Future<void> writeList(String key, List<Map<String, Object?>> rows) => atomic(() => _write(key, jsonEncode(rows)));
  Future<Map<String, Object?>> readMap(String key) async {
    final raw = await _read(key);
    return raw == null ? {} : Map<String, Object?>.from(jsonDecode(raw) as Map);
  }
  Future<void> writeMap(String key, Map<String, Object?> value) => atomic(() => _write(key, jsonEncode(value)));

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
    await _store.upsertRow(_key, transaction.toJson());
  }

  @override
  Future<void> delete(String id) async {
    await _store.deleteRow(_key, id);
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
  Future<void> upsert(Account account) async => _store.upsertRow(_key, account.toJson());

  @override
  Future<void> delete(String id) async {
    await _store.deleteRow(_key, id);
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
  Future<void> upsert(Budget budget) async => _store.upsertRow(_key, budget.toJson());

  @override
  Future<void> delete(String id) async {
    await _store.deleteRow(_key, id);
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
  Future<void> upsert(MerchantRule rule) async => _store.upsertRow(_key, rule.toJson());

  @override
  Future<void> delete(String id) async {
    await _store.deleteRow(_key, id);
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
  Future<void> upsert(FinancialDocument document) => _store.upsertRow(_key, document.toJson());

  @override
  Future<void> delete(String id) async {
    await _store.deleteRow(_key, id);
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
  Future<void> upsert(FinancialRule rule) => _store.upsertRow(_key, rule.toJson());

  @override
  Future<void> delete(String id) async {
    await _store.deleteRow(_key, id);
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
