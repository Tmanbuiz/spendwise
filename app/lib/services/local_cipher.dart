import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// AES-GCM authenticates every payload. The key never goes in preferences,
/// SQLite, exported backups, or application logs.
class LocalCipher {
  LocalCipher(this.key);
  final SecretKey key;
  static final algorithm = AesGcm.with256bits();
  static Future<LocalCipher>? _opening;
  static Future<LocalCipher> open() => _opening ??= _open();
  static Future<LocalCipher> _open() async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(resetOnError: false, migrateWithBackup: true),
      iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ));
    const name = 'spendwise.local.aes256.v1';
    var encoded = await storage.read(key: name);
    if (encoded == null) {
      final key = await algorithm.newSecretKey();
      encoded = base64Encode(await key.extractBytes());
      await storage.write(key: name, value: encoded);
      if (await storage.read(key: name) != encoded) throw StateError('Secure key verification failed');
    }
    final bytes = base64Decode(encoded);
    if (bytes.length != 32) throw const FormatException('Invalid local storage key');
    return LocalCipher(SecretKey(bytes));
  }
  Future<String> indexIdentifier(String value) async {
    final mac = await Hmac.sha256().calculateMac(utf8.encode(value), secretKey: key);
    return base64Encode(mac.bytes);
  }
  Future<String> encrypt(List<int> bytes, String scope) async {
    final box = await algorithm.encrypt(bytes, secretKey: key, aad: utf8.encode(scope));
    return jsonEncode({'v': 1, 'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText), 'm': base64Encode(box.mac.bytes)});
  }
  Future<List<int>> decrypt(String text, String scope) async {
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['v'] != 1) throw const FormatException('Unsupported encrypted payload');
    return algorithm.decrypt(SecretBox(base64Decode(j['c'] as String),
      nonce: base64Decode(j['n'] as String), mac: Mac(base64Decode(j['m'] as String))),
      secretKey: key, aad: utf8.encode(scope));
  }
}
