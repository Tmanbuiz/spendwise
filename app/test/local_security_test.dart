import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendwise/data/repositories/local_repositories.dart';
import 'package:spendwise/services/local_cipher.dart';
import 'package:spendwise/services/backup_service.dart';
import 'package:spendwise/data/models/account.dart';

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
