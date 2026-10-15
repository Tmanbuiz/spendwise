import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/services/backup_crypto.dart';

void main() {
  test('backup password is portable and authenticated', () async {
    const text = '{"app":"SpendWise","version":1,"private":"financial data"}';
    const password = 'a long private backup phrase';
    final encrypted = await BackupCrypto.encrypt(text, password);
    expect(BackupCrypto.isEncrypted(encrypted), isTrue);
    expect(encrypted.contains('financial data'), isFalse);
    expect(await BackupCrypto.decrypt(encrypted, password), text);
    await expectLater(BackupCrypto.decrypt(encrypted, 'a different long phrase'), throwsA(anything));
    final tampered = jsonDecode(encrypted) as Map<String, dynamic>;
    tampered['iterations'] = 999999999;
    await expectLater(BackupCrypto.decrypt(jsonEncode(tampered), password), throwsA(isA<FormatException>()));
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('short passwords are rejected before exporting data', () async {
    await expectLater(BackupCrypto.encrypt('{}', 'short'), throwsA(isA<FormatException>()));
  });
}
