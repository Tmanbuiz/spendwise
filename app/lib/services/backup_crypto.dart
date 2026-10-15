import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

/// Portable authenticated backups use a password-derived key, never the
/// device-only storage key. Passwords are not persisted or sent to a server.
abstract final class BackupCrypto {
  static const iterations = 600000;
  static const _scope = 'SpendWise-backup-v1';
  static bool isEncrypted(String text) {
    final value = jsonDecode(text);
    return value is Map && value['app'] == 'SpendWiseEncryptedBackup';
  }
  static Future<SecretKey> _key(String password, List<int> salt) async {
    // Keep the expensive KDF off the UI isolate.
    final bytes = await Isolate.run(() async {
      final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
        .deriveKeyFromPassword(password: password, nonce: salt);
      return key.extractBytes();
    });
    return SecretKey(bytes);
  }
  static Future<String> encrypt(String plaintext, String password) async {
    if (password.length < 12 || password.length > 1024) throw const FormatException('Use a password of 12 to 1024 characters');
    if (utf8.encode(plaintext).length > 20000000) throw const FormatException('Backup too large');
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final box = await AesGcm.with256bits().encrypt(utf8.encode(plaintext),
      secretKey: await _key(password, salt), aad: utf8.encode(_scope));
    return jsonEncode({'app': 'SpendWiseEncryptedBackup', 'version': 1, 'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': iterations, 'salt': base64Encode(salt), 'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText), 'mac': base64Encode(box.mac.bytes)});
  }
  static Future<String> decrypt(String text, String password) async {
    if (text.length > 30000000 || password.isEmpty || password.length > 1024) throw const FormatException('Invalid encrypted backup');
    final value = jsonDecode(text) as Map<String, dynamic>;
    if (value['app'] != 'SpendWiseEncryptedBackup' || value['version'] != 1 ||
        value['kdf'] != 'PBKDF2-HMAC-SHA256' || value['iterations'] != iterations) {
      throw const FormatException('Unsupported backup encryption');
    }
    final salt = base64Decode(value['salt'] as String), nonce = base64Decode(value['nonce'] as String),
      mac = base64Decode(value['mac'] as String), ciphertext = base64Decode(value['ciphertext'] as String);
    if (salt.length != 16 || nonce.length != 12 || mac.length != 16 || ciphertext.length > 20000000) {
      throw const FormatException('Invalid encrypted backup');
    }
    final bytes = await AesGcm.with256bits().decrypt(SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
      secretKey: await _key(password, salt), aad: utf8.encode(_scope));
    return utf8.decode(bytes);
  }
}
