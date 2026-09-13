import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/services/shared_statements.dart';

void main() {
  late Directory root;
  late Directory documentsInbox;
  late Directory tempInbox;
  late Directory workspace;

  String join(Directory directory, String name) =>
      '${directory.path}${Platform.pathSeparator}$name';

  SharedStatements onIphone() => SharedStatements(
    platform: TargetPlatform.iOS,
    inboxes: () async => <Directory>[documentsInbox, tempInbox],
    workspace: () async => workspace,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('ios_inbox');
    documentsInbox = Directory(join(root, 'Inbox'));
    tempInbox = Directory(join(root, 'com.wiantribe.spendwise-Inbox'));
    workspace = Directory(join(root, 'tmp'))..createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('a statement opened in SpendWise on iPhone', () {
    test('nothing is waiting when the inboxes do not exist yet', () async {
      final shared = onIphone();
      expect(await shared.hasPending(), isFalse);
      expect(await shared.drain(), isEmpty);
    });

    test('a PDF copied into the inbox is waiting; other files are not', () async {
      documentsInbox.createSync();
      File(join(documentsInbox, 'photo.png')).writeAsStringSync('x');
      final shared = onIphone();
      expect(await shared.hasPending(), isFalse);

      File(join(documentsInbox, 'September.pdf')).writeAsStringSync('pdf');
      expect(await shared.hasPending(), isTrue);
    });

    test('taking the queue moves statements out of both inboxes', () async {
      documentsInbox.createSync();
      tempInbox.createSync();
      File(join(documentsInbox, 'September.pdf')).writeAsStringSync('pdf');
      File(join(tempInbox, 'visa.csv')).writeAsStringSync('csv');
      final shared = onIphone();

      final files = await shared.drain();
      expect(
        files.map((f) => f.uri.pathSegments.last).toSet(),
        <String>{'September.pdf', 'visa.csv'},
      );
      expect(files.every((f) => f.existsSync()), isTrue);
      expect(files.every((f) => f.path.startsWith(workspace.path)), isTrue);

      // Moved, not copied: the same file is never imported twice.
      expect(documentsInbox.listSync(), isEmpty);
      expect(tempInbox.listSync(), isEmpty);
      expect(await shared.hasPending(), isFalse);
      expect(await shared.drain(), isEmpty);
    });

    test('a second file with the same name does not overwrite the first',
        () async {
      documentsInbox.createSync();
      final shared = onIphone();

      File(join(documentsInbox, 'statement.pdf')).writeAsStringSync('first');
      final first = await shared.drain();
      File(join(documentsInbox, 'statement.pdf')).writeAsStringSync('second');
      final second = await shared.drain();

      expect(first.single.path, isNot(second.single.path));
      expect(first.single.readAsStringSync(), 'first');
      expect(second.single.readAsStringSync(), 'second');
    });
  });
}
