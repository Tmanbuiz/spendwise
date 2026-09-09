import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/services/shared_statements.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/shared_files');
  const shared = SharedStatements(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Directory? temp;

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    temp?.deleteSync(recursive: true);
    temp = null;
  });

  group('asking whether a statement is waiting', () {
    test('reports what the platform says', () async {
      answer((_) => true);
      expect(await shared.hasPending(), isTrue);
    });

    // Every non-Android surface — desktop, widget tests, a build without the
    // bridge — has no handler at all. That is an ordinary state, not an error
    // worth crashing the shell over on first frame.
    test('a missing platform side is not an error', () async {
      answer((_) => throw MissingPluginException());
      expect(await shared.hasPending(), isFalse);
    });

    test('a platform failure is not an error', () async {
      answer((_) => throw PlatformException(code: 'BOOM'));
      expect(await shared.hasPending(), isFalse);
    });
  });

  group('taking the queue', () {
    test('returns the files the platform copied', () async {
      temp = Directory.systemTemp.createTempSync('shared');
      final a = File('${temp!.path}/one.pdf')..writeAsStringSync('a');
      final b = File('${temp!.path}/two.pdf')..writeAsStringSync('b');

      answer((_) => <String>[a.path, b.path]);

      final files = await shared.drain();
      expect(files.map((f) => f.path), <String>[a.path, b.path]);
    });

    // The system can clear the cache between the share and the import. A path
    // that no longer resolves would otherwise fail deep inside the reader,
    // with a message about an unreadable statement rather than a missing one.
    test('drops paths that no longer exist', () async {
      temp = Directory.systemTemp.createTempSync('shared');
      final real = File('${temp!.path}/real.pdf')..writeAsStringSync('a');

      answer((_) => <String>[real.path, '${temp!.path}/gone.pdf']);

      final files = await shared.drain();
      expect(files, hasLength(1));
      expect(files.single.path, real.path);
    });

    test('an empty queue is an empty list, not null', () async {
      answer((_) => null);
      expect(await shared.drain(), isEmpty);
    });

    test('a missing platform side yields nothing', () async {
      answer((_) => throw MissingPluginException());
      expect(await shared.drain(), isEmpty);
    });
  });
}
