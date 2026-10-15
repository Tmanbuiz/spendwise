import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

/// What the Android capture path has actually done.
///
/// Exists so "nothing was captured" can be distinguished from "nothing was
/// spent". Without these counters the two look identical from the UI, which is
/// exactly the ambiguity that hid a broken capture path.
class CaptureStats {
  const CaptureStats({
    required this.seen,
    required this.matched,
    required this.queued,
    required this.delivered,
    required this.pending,
    required this.listenerConnected,
    required this.watchedPackages,
    required this.available,
  });

  static const CaptureStats unavailable = CaptureStats(
    seen: 0,
    matched: 0,
    queued: 0,
    delivered: 0,
    pending: 0,
    listenerConnected: false,
    watchedPackages: <String>[],
    available: false,
  );

  /// Every notification Android delivered, from any app.
  final int seen;

  /// Those from a bank the user selected.
  final int matched;

  /// Those persisted because the app was closed.
  final int queued;

  /// Those handed straight to a running app.
  final int delivered;

  /// Still waiting to be processed.
  final int pending;

  final bool listenerConnected;
  final List<String> watchedPackages;

  /// False off Android, or when the channel could not be reached.
  final bool available;

  static CaptureStats fromMap(Map<Object?, Object?> map) {
    int read(String key) => (map[key] as num?)?.toInt() ?? 0;
    return CaptureStats(
      seen: read('seen'),
      matched: read('matched'),
      queued: read('queued'),
      delivered: read('delivered'),
      pending: read('pending'),
      listenerConnected: (map['listenerConnected'] as bool?) ?? false,
      watchedPackages: (map['watchedPackages'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const <String>[],
      available: true,
    );
  }
}

/// Bridge to Android's `NotificationListenerService`.
///
/// Android only. Notification capture is not possible on iOS at all — there is
/// no equivalent API — which is why the architecture keeps parsing in a
/// platform-free package and why the iOS path is planned as email import
/// instead. On iOS and in tests every method here degrades quietly rather than
/// throwing, so the rest of the app needs no platform checks.
class NotificationAccess {
  NotificationAccess({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    TargetPlatform? platformOverride,
  })  : _method = methodChannel ?? const MethodChannel(_methodChannelName),
        _events = eventChannel ?? const EventChannel(_eventChannelName),
        _platform = platformOverride ?? defaultTargetPlatform;

  static const String _methodChannelName = 'com.spendwise/notifications';
  static const String _eventChannelName = 'com.spendwise/notifications/stream';

  final MethodChannel _method;
  final EventChannel _events;
  final TargetPlatform _platform;

  bool get isSupportedPlatform => _platform == TargetPlatform.android;

  /// Whether the user has granted notification access in Android settings.
  ///
  /// Always re-read from the OS rather than cached: the user can revoke it at
  /// any time from system settings, and a stale "granted" would leave the app
  /// silently capturing nothing.
  Future<bool> isGranted() async {
    if (!isSupportedPlatform) return false;
    try {
      final granted = await _method.invokeMethod<bool>('isPermissionGranted');
      return granted ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the Android "Notification access" settings page. Android gives no
  /// in-app grant dialog for this permission — the user must toggle it there.
  Future<void> openSettings() async {
    if (!isSupportedPlatform) return;
    try {
      await _method.invokeMethod<void>('openNotificationSettings');
    } on PlatformException {
      // Nothing to recover: the screen explains the manual path as a fallback.
    } on MissingPluginException {
      // Not running on a device with the plugin registered.
    }
  }

  /// Which of [packageNames] are installed on this device.
  ///
  /// Used to verify bank detection rather than assume it. If CIBC ships under
  /// a package id SpendWise did not predict, the user is told plainly instead
  /// of alerts silently going nowhere.
  ///
  /// Returns an empty map off Android, or when the platform channel is
  /// unavailable — the caller treats "unknown" and "not installed" the same
  /// way, which is to say nothing about the bank rather than claiming it is
  /// missing.
  Future<Map<String, String>> findInstalledApps(
    Iterable<String> packageNames,
  ) async {
    if (!isSupportedPlatform) return const <String, String>{};
    try {
      final found = await _method.invokeMethod<List<Object?>>(
        'findInstalledApps',
        packageNames.toList(),
      );
      if (found == null) return const <String, String>{};

      final result = <String, String>{};
      for (final entry in found) {
        if (entry is! Map) continue;
        final map = Map<Object?, Object?>.from(entry);
        final packageName = map['packageName'] as String?;
        if (packageName == null || packageName.isEmpty) continue;
        result[packageName] = (map['label'] as String?) ?? packageName;
      }
      return result;
    } on PlatformException {
      return const <String, String>{};
    } on MissingPluginException {
      return const <String, String>{};
    }
  }

  /// Asks the Android service to re-read notifications already in the shade.
  ///
  /// Covers alerts that arrived before access was granted, or before the app
  /// was installed. Safe to repeat: duplicates are caught by fingerprint, so a
  /// re-scan cannot double-count.
  Future<bool> rescanActive() async {
    if (!isSupportedPlatform) return false;
    try {
      return await _method.invokeMethod<bool>('rescanActive') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Notifications captured while the app was closed.
  ///
  /// This is the path that carries almost all real traffic. A purchase alert
  /// arrives while the user is in a shop, with no Flutter engine running, so
  /// the Android service persists it and the app drains it on next launch.
  /// Entries remain durable until acknowledged after processing commits.
  Future<List<NotificationMessage>> drainPending() async {
    if (!isSupportedPlatform) return const <NotificationMessage>[];
    try {
      final pending = await _method.invokeMethod<List<Object?>>('drainPending');
      if (pending == null) return const <NotificationMessage>[];
      return pending
          .map(_decode)
          .whereType<NotificationMessage>()
          .toList();
    } on PlatformException {
      return const <NotificationMessage>[];
    } on MissingPluginException {
      return const <NotificationMessage>[];
    }
  }

  Future<void> acknowledge(NotificationMessage message, {bool failed = false}) async {
    if (!isSupportedPlatform || message.envelopeId == null) return;
    await _method.invokeMethod<void>(failed ? 'failPending' : 'ackPending', message.envelopeId);
  }

  /// Counters describing what the capture path has actually done, so a silent
  /// failure can be told apart from "no purchases yet".
  Future<CaptureStats> stats() async {
    if (!isSupportedPlatform) return CaptureStats.unavailable;
    try {
      final raw = await _method.invokeMethod<Map<Object?, Object?>>(
        'captureStats',
      );
      if (raw == null) return CaptureStats.unavailable;
      return CaptureStats.fromMap(Map<Object?, Object?>.from(raw));
    } on PlatformException {
      return CaptureStats.unavailable;
    } on MissingPluginException {
      return CaptureStats.unavailable;
    }
  }

  Future<void> resetStats() async {
    if (!isSupportedPlatform) return;
    try {
      await _method.invokeMethod<void>('resetCaptureStats');
    } on PlatformException {
      // Counters are diagnostic only; failing to reset them is not an error
      // worth surfacing.
    } on MissingPluginException {
      // Not on a device with the plugin registered.
    }
  }

  /// Live stream of captured notifications.
  Stream<NotificationMessage> stream() {
    if (!isSupportedPlatform) return const Stream<NotificationMessage>.empty();
    return _events
        .receiveBroadcastStream()
        .map(_decode)
        .where((message) => message != null)
        .cast<NotificationMessage>();
  }

  /// Converts the platform payload into a [NotificationMessage].
  ///
  /// Returns null for anything malformed rather than throwing, because a
  /// single bad payload must not tear down the capture stream.
  static NotificationMessage? _decode(Object? event) {
    if (event is! Map) return null;
    final map = Map<Object?, Object?>.from(event);

    String read(String key) => (map[key] as String?)?.trim() ?? '';

    final packageName = read('packageName');
    if (packageName.isEmpty) return null;

    final postedAtMillis = (map['postedAt'] as num?)?.toInt();
    final postedAt = postedAtMillis == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(postedAtMillis);

    final subText = read('subText');
    return NotificationMessage(
      packageName: packageName,
      envelopeId: read('envelopeId').isEmpty ? null : read('envelopeId'),
      title: read('title'),
      body: read('body'),
      postedAt: postedAt,
      subText: subText.isEmpty ? null : subText,
    );
  }
}
