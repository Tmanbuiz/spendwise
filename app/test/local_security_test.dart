import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendwise/data/repositories/local_repositories.dart';
import 'package:spendwise/data/repositories/repositories.dart';
import 'package:spendwise/services/local_cipher.dart';
import 'package:spendwise/services/backup_service.dart';
import 'package:spendwise/data/models/account.dart';
import 'package:spendwise/data/models/app_transaction.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final cipher = LocalCipher(SecretKey(List.filled(32, 8)));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('authenticated payload rejects tampering, wrong key and wrong scope', () async {
    final encrypted = await cipher.encrypt(utf8.encode('financial data'), 'ledger');
    expect(utf8.decode(await cipher.decrypt(encrypted, 'ledger')), 'financial data');
    await expectLater(cipher.decrypt(encrypted, 'vault'), throwsA(isA<SecretBoxAuthenticationError>()));
    final other = LocalCipher(SecretKey(List.filled(32, 9)));
    await expectLater(other.decrypt(encrypted, 'ledger'), throwsA(isA<SecretBoxAuthenticationError>()));
  });
  test('legacy migration preserves data and removes plaintext preferences', () async {
    SharedPreferences.setMockInitialValues({'spendwise.accounts': jsonEncode([
      const Account(id: 'a', bankId: 'cibc', label: 'Private account').toJson()])});
    final data = await LocalStore.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath, cipher: cipher);
    expect((await data.accounts.list()).single.label, 'Private account');
    expect((await SharedPreferences.getInstance()).containsKey('spendwise.accounts'), isFalse);
  });
  test('a failure after a staged write rolls back all rows', () async {
    final data = await LocalStore.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath, cipher: cipher);
    await data.accounts.upsert(const Account(id: 'a', bankId: 'cibc', label: 'Before'));
    await expectLater(data.atomicWrite!(() async {
      await data.accounts.upsert(const Account(id: 'a', bankId: 'cibc', label: 'After'));
      await data.accounts.upsert(const Account(id: 'b', bankId: 'cibc', label: 'New'));
      throw StateError('Injected crash');
    }), throwsStateError);
    expect((await data.accounts.list()).single.label, 'Before');
  });
  test('version-one encrypted collections upgrade to indexed rows without plaintext', () async {
    final root = await Directory.systemTemp.createTemp('spendwise-db-test-');
    final path = '${root.path}/ledger.db';
    final old = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: 1,
      onCreate: (db, _) async { await db.execute('CREATE TABLE records (collection TEXT PRIMARY KEY, payload TEXT NOT NULL)'); }));
    final source = jsonEncode([const Account(id: 'legacy', bankId: 'cibc', label: 'Private legacy label').toJson()]);
    await old.insert('records', {'collection': 'spendwise.accounts', 'payload': await cipher.encrypt(utf8.encode(source), 'spendwise.accounts')});
    await old.close();
    final data = await LocalStore.open(factory: databaseFactoryFfi, path: path, cipher: cipher);
    expect((await data.accounts.list()).single.label, 'Private legacy label');
    final db = await databaseFactoryFfi.openDatabase(path);
    final stored = (await db.query('secure_rows')).single;
    expect(stored['id'], 'legacy');
    expect((stored['payload'] as String).contains('Private legacy label'), isFalse);
    expect(await db.rawQuery("SELECT name FROM sqlite_master WHERE name = 'records'"), isEmpty);
    await db.close();
    final reopened = await LocalStore.open(factory: databaseFactoryFfi, path: path, cipher: cipher);
    expect((await reopened.accounts.list()).single.id, 'legacy');
    await (await databaseFactoryFfi.openDatabase(path)).close();
    await root.delete(recursive: true);
  });
  test('duplicate legacy IDs fail migration without deleting the source', () async {
    final row = const Account(id: 'same', bankId: 'cibc', label: 'Original').toJson();
    SharedPreferences.setMockInitialValues({'spendwise.accounts': jsonEncode([row, row])});
    await expectLater(LocalStore.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath, cipher: cipher),
      throwsA(isA<FormatException>()));
    expect((await SharedPreferences.getInstance()).containsKey('spendwise.accounts'), isTrue);
  });
  test('overlapping saves cannot insert the same notification twice', () async {
    final data = await LocalStore.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath, cipher: cipher);
    AppTransaction event(String id) => AppTransaction(id: id, eventType: TransactionEventType.purchase,
      amountCents: 1200, currency: 'CAD', occurredAt: DateTime(2026, 10, 15), category: SpendCategory.other,
      source: TransactionSource.notification, fingerprint: 'one-alert', bankId: 'cibc', accountLast4: '1234');
    await Future.wait([data.transactions.upsert(event('one')), data.transactions.upsert(event('two'))]);
    expect(await data.transactions.list(), hasLength(1));
  });
  test('a restore failing on its tenth transaction preserves the committed ledger', () async {
    final source = await LocalStore.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath, cipher: cipher);
    AppTransaction row(String id, int cents) => AppTransaction(id: id, eventType: TransactionEventType.purchase,
      amountCents: cents, currency: 'CAD', occurredAt: DateTime(2026), category: SpendCategory.other, source: TransactionSource.manual);
    for (var i = 0; i < 12; i++) { await source.transactions.upsert(row('backup-$i', i + 1)); }
    final backup = await BackupData.capture(source, []);
    final destination = await LocalStore.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath, cipher: cipher);
    await destination.transactions.upsert(row('original', 900));
    final failing = DataLayer(transactions: _FailOnTenthWrite(destination.transactions), accounts: destination.accounts,
      budgets: destination.budgets, rules: destination.rules, preferences: destination.preferences,
      isRemote: false, atomicWrite: destination.atomicWrite, readBills: destination.readBills, writeBills: destination.writeBills);
    await expectLater(backup.restore(failing), throwsStateError);
    final remaining = await destination.transactions.list();
    expect(remaining.single.id, 'original');
    expect(remaining.single.amountCents, 900);
  });
  test('default restore preserves a more recent record and is idempotent', () async {
    final data = await LocalStore.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath, cipher: cipher);
    await data.accounts.upsert(const Account(id: 'a', bankId: 'cibc', label: 'Backup'));
    final backup = await BackupData.capture(data, []);
    await data.accounts.upsert(const Account(id: 'a', bankId: 'cibc', label: 'Recent edit'));
    expect(await backup.restore(data), 0);
    expect(await backup.restore(data), 0);
    expect((await data.accounts.list()).single.label, 'Recent edit');
  });
}

class _FailOnTenthWrite implements TransactionRepository {
  _FailOnTenthWrite(this.delegate);
  final TransactionRepository delegate;
  int writes = 0;
  @override
  Future<List<AppTransaction>> list({DateTime? from, DateTime? to}) => delegate.list(from: from, to: to);
  @override
  Future<void> delete(String id) => delegate.delete(id);
  @override
  Future<void> upsert(AppTransaction value) async {
    if (++writes == 10) throw StateError('Injected storage failure');
    await delegate.upsert(value);
  }
}
