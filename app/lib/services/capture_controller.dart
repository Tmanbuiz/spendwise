import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

import '../state/providers.dart';
import 'ingest_service.dart';

/// Owns the live notification stream and feeds it through the pipeline.
///
/// Single instance for the app's lifetime: notification capture must survive
/// tab switches and screen rebuilds, so it is not tied to any widget.
class CaptureController {
  CaptureController(this._ref);

  final Ref _ref;
  StreamSubscription<NotificationMessage>? _subscription;
  bool _started = false;

  /// The last few results, so Settings can show that capture is really working
  /// instead of the user having to trust a silent toggle.
  final List<IngestResult> _recent = <IngestResult>[];

  List<IngestResult> get recentResults => List.unmodifiable(_recent);

  Future<void> start() async {
    if (_started) return;
    _started = true;

    final access = _ref.read(notificationAccessProvider);
    if (!access.isSupportedPlatform) return;

    await _syncWatchedPackages();

    final ingest = _ref.read(ingestServiceProvider);
    await ingest.warmUp();

    // Drain before subscribing. Almost every real purchase alert arrives while
    // the app is closed, so the queue — not the live stream — is the path that
    // carries the traffic. Draining first also keeps ordering sensible: older
    // queued alerts are processed before anything arriving now.
    _subscription = access.stream().listen(
      _handle,
      // A stream error must not kill capture permanently; the OS may resume
      // delivery, and the subscription stays alive to receive it.
      onError: (Object _) => debugPrint('Notification stream unavailable'),
      cancelOnError: false,
    );
    await drainPending();
  }

  /// Tells the Android service which packages to watch, so notifications from
  /// unselected apps are never read into memory at all.
  Future<void> _syncWatchedPackages() async {
    final packages = _ref.read(watchedPackagesProvider);
    try {
      await const MethodChannel('com.spendwise/notifications')
          .invokeMethod<void>('setWatchedPackages', packages.toList());
    } on PlatformException catch (e) {
      debugPrint('Could not set watched packages: ${e.message}');
    } on MissingPluginException {
      // Not on a device with the plugin registered; nothing to do.
    }
  }

  /// Call after the user changes their bank selection.
  Future<void> refreshWatchedPackages() => _syncWatchedPackages();

  /// Processes everything the Android service captured while the app was shut.
  ///
  /// Returns how many became transactions. Safe to call repeatedly: draining
  /// clears the queue, and the duplicate detector catches anything that
  /// somehow arrives twice.
  Future<int> drainPending({bool rescanFirst = false}) async {
    final access = _ref.read(notificationAccessProvider);

    // Re-reading the shade first picks up alerts that arrived before access
    // was granted. The service writes them to the same queue, so a short wait
    // lets that land before draining.
    if (rescanFirst && await access.rescanActive()) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    final pending = await access.drainPending();
    if (pending.isEmpty) return 0;

    var stored = 0;
    for (final message in pending) {
      try {
        final result = await _ingestOne(message);
        await access.acknowledge(message);
        if (result.wasStored) stored++;
      } on Object {
        await access.acknowledge(message, failed: true);
      }
    }

    if (stored > 0) {
      await _ref.read(transactionsProvider.notifier).refresh();
    }
    return stored;
  }

  Future<IngestResult> _ingestOne(NotificationMessage message) async {
    final selected =
        _ref.read(preferencesProvider).value?.selectedBankIds ?? <String>{};
    final result = await _ref.read(ingestServiceProvider).ingest(
          message,
          selectedBankIds: selected,
        );
    _remember(result);
    return result;
  }

  Future<void> _handle(NotificationMessage message) async {
    IngestResult result;
    final access = _ref.read(notificationAccessProvider);
    try {
      result = await _ingestOne(message);
      await access.acknowledge(message);
    } on Object {
      await access.acknowledge(message, failed: true);
      return;
    }

    // Only a stored transaction changes what the UI shows; refreshing on
    // duplicates or declines would cause pointless rebuilds.
    if (result.wasStored) {
      await _ref.read(transactionsProvider.notifier).refresh();
    }
  }

  void _remember(IngestResult result) {
    _recent.insert(0, result);
    if (_recent.length > 20) _recent.removeLast();
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}

final captureControllerProvider = Provider<CaptureController>((ref) {
  final controller = CaptureController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});
