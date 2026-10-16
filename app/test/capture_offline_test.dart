import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/services/notification_access.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

/// Fake Android side, so the offline path can be tested without a device.
class _FakePlatform {
  _FakePlatform(this.channel) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, _handle);
  }

  final MethodChannel channel;

  /// What the service has persisted while the app was closed.
  List<Map<String, Object?>> queue = <Map<String, Object?>>[];

  int drainCalls = 0;
  Set<String> watched = <String>{};

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'drainPending':
        drainCalls++;
        return List<Map<String, Object?>>.from(queue);
      case 'ackPending':
        queue.removeWhere((x) => x['envelopeId'] == call.arguments);
        return null;
      case 'captureStats':
        return <String, Object?>{
          'seen': 12,
          'matched': 3,
          'queued': 3,
          'delivered': 0,
          'pending': queue.length,
          'listenerConnected': true,
          'watchedPackages': watched.toList(),
        };
      case 'setWatchedPackages':
        watched = (call.arguments as List<Object?>).whereType<String>().toSet();
        return null;
      case 'isPermissionGranted':
        return true;
    }
    return null;
  }

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}

int _nextEnvelope = 0;
Map<String, Object?> queued({
  String packageName = 'com.cibc.android.mobi',
  String title = 'CIBC',
  String body = r'You spent $12.50 at STARBUCKS with your CIBC card '
      'ending in 4321.',
  int? postedAt,
}) {
  return <String, Object?>{
    'envelopeId': '${DateTime.now().microsecondsSinceEpoch}-${_nextEnvelope++}',
    'packageName': packageName,
    'title': title,
    'body': body,
    'subText': '',
    'postedAt': postedAt ?? DateTime(2026, 9, 4, 9, 30).millisecondsSinceEpoch,
  };
}

void main() {
  const channel = MethodChannel('com.spendwise/notifications');
  late _FakePlatform platform;
  late NotificationAccess access;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    platform = _FakePlatform(channel);
    access = NotificationAccess(
      methodChannel: channel,
      platformOverride: TargetPlatform.android,
    );
  });

  tearDown(() => platform.dispose());

  group('notifications captured while the app was closed', () {
    test('are drained and decoded', () async {
      // The case that was silently broken: an alert arrives in a shop, with no
      // Flutter engine running. It must survive until the app next opens.
      platform.queue = <Map<String, Object?>>[queued()];

      final pending = await access.drainPending();

      expect(pending, hasLength(1));
      expect(pending.first.packageName, 'com.cibc.android.mobi');
      expect(pending.first.body, contains('STARBUCKS'));
    });

    test('parse correctly after being drained', () async {
      platform.queue = <Map<String, Object?>>[queued()];
      final pending = await access.drainPending();

      final parsed = CibcParser().parse(pending.first);
      expect(parsed.eventType, TransactionEventType.purchase);
      expect(parsed.amount!.cents, 1250);
      expect(parsed.merchantNormalized, 'STARBUCKS');
      expect(parsed.countsAsSpending, isTrue);
    });

    test('keep the original delivery time, not the drain time', () async {
      // The transaction happened when the alert arrived, not when the user
      // next opened the app — which could be days later.
      final when = DateTime(2026, 9, 2, 18, 45);
      platform.queue = <Map<String, Object?>>[
        queued(postedAt: when.millisecondsSinceEpoch),
      ];

      final pending = await access.drainPending();
      expect(pending.first.postedAt, when);
    });

    test('draining retains events until explicit acknowledgment', () async {
      platform.queue = <Map<String, Object?>>[queued(), queued()];

      final pending = await access.drainPending();
      expect(pending, hasLength(2));
      expect(await access.drainPending(), hasLength(2));
      for (final message in pending) { await access.acknowledge(message); }
      expect(await access.drainPending(), isEmpty);
      expect(platform.drainCalls, 3);
    });

    test('an empty queue is not an error', () async {
      expect(await access.drainPending(), isEmpty);
    });

    test('a malformed queue entry is skipped, not fatal', () async {
      platform.queue = <Map<String, Object?>>[
        queued(),
        <String, Object?>{'garbage': true},
        queued(),
      ];

      // The bad entry has no packageName, so it decodes to null and is
      // dropped rather than aborting the drain.
      expect(await access.drainPending(), hasLength(2));
    });

    test('many queued alerts all survive', () async {
      platform.queue = List<Map<String, Object?>>.generate(50, (_) => queued());
      expect(await access.drainPending(), hasLength(50));
    });
  });

  group('capture stats', () {
    test('report what the Android side has done', () async {
      final stats = await access.stats();
      expect(stats.available, isTrue);
      expect(stats.seen, 12);
      expect(stats.matched, 3);
      expect(stats.listenerConnected, isTrue);
    });

    test('pending reflects the queue length', () async {
      platform.queue = <Map<String, Object?>>[queued(), queued()];
      expect((await access.stats()).pending, 2);
    });

    test('watched packages are reported back', () async {
      platform.watched = <String>{'com.cibc.android.mobi'};
      expect(
        (await access.stats()).watchedPackages,
        contains('com.cibc.android.mobi'),
      );
    });
  });

  group('non-Android platforms degrade quietly', () {
    test('drain returns empty rather than throwing', () async {
      final ios = NotificationAccess(
        methodChannel: channel,
        platformOverride: TargetPlatform.iOS,
      );
      expect(await ios.drainPending(), isEmpty);
      expect((await ios.stats()).available, isFalse);
    });
  });
}
