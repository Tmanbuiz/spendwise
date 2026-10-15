import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/models/financial_document.dart';
import 'package:spendwise/services/financial_vault_service.dart';
import 'package:spendwise/services/local_cipher.dart';

void main() {
  late Directory root;
  late FinancialVaultService vault;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('spendwise-vault-test-');
    vault = FinancialVaultService(isRemote: false, documentsDirectory: root,
      cipherOverride: LocalCipher(SecretKey(List.filled(32, 9))));
  });
  tearDown(() async { await root.delete(recursive: true); });
  test('new files are encrypted and authenticated before replacement', () async {
    final source = File('${root.path}/statement.txt');
    await source.writeAsString('private financial statement');
    final document = await vault.storeFile(source, documentId: 'document');
    final stored = await File(document.storagePath).readAsString();
    expect(stored.startsWith('SWENC1\n'), isTrue);
    expect(stored.contains('private financial statement'), isFalse);
    expect(utf8.decode(await vault.readBytes(document)), 'private financial statement');
    expect(await File('${document.storagePath}.encrypting').exists(), isFalse);
  });
  test('startup migration encrypts unread legacy files in place', () async {
    final directory = await Directory('${root.path}/financial_documents').create();
    final source = File('${directory.path}/legacy.txt');
    await source.writeAsString('legacy private data');
    final document = FinancialDocument(id: 'legacy', fileName: 'legacy.txt', storagePath: source.path,
      storageKind: DocumentStorageKind.local, documentType: FinancialDocumentType.other, addedAt: DateTime(2026));
    expect(await vault.migrateLegacyDocuments([document]), 1);
    expect((await source.readAsString()).startsWith('SWENC1\n'), isTrue);
    expect(utf8.decode(await vault.readBytes(document)), 'legacy private data');
  });
  test('a metadata path cannot read or delete a file outside the vault', () async {
    await Directory('${root.path}/financial_documents').create();
    final source = File('${root.path}/outside.txt');
    await source.writeAsString('outside');
    final document = FinancialDocument(id: 'outside', fileName: 'outside.txt', storagePath: source.path,
      storageKind: DocumentStorageKind.local, documentType: FinancialDocumentType.other, addedAt: DateTime(2026));
    await expectLater(vault.readBytes(document), throwsStateError);
    await expectLater(vault.deleteStoredFile(document), throwsStateError);
    expect(await source.readAsString(), 'outside');
  });
}
