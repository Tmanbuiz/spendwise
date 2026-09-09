import 'dart:io';

import 'package:flutter/services.dart';

/// Statements handed to the app by another app.
///
/// Android delivers a shared document as a `content://` URI whose read grant
/// expires with the intent, so the platform side copies each one into the
/// app's cache and this reports the resulting paths. Everything here is a
/// queue the platform fills and Dart empties — the app is never told to do
/// anything with a file, only that one arrived.
class SharedStatements {
  /// [channel] is injectable so the queue can be tested without a device.
  const SharedStatements({this.channel = _defaultChannel});

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.spendwise/shared_files',
  );

  final MethodChannel channel;

  /// Whether a statement is waiting, without taking it.
  ///
  /// Used to decide whether to open the import screen at all; taking the queue
  /// to answer that would lose the files if the navigation then failed.
  Future<bool> hasPending() async {
    try {
      return await channel.invokeMethod<bool>('hasPending') ?? false;
    } on MissingPluginException {
      // No platform side: desktop, tests, or a build without the bridge.
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Takes every waiting statement, clearing the queue.
  ///
  /// Files that no longer exist are dropped rather than returned: the cache
  /// can be cleared by the system between the share and the import, and a
  /// path that cannot be read would fail later with a worse message.
  Future<List<File>> drain() async {
    final List<String> paths;
    try {
      paths =
          (await channel.invokeListMethod<String>('drain')) ?? const <String>[];
    } on MissingPluginException {
      return const <File>[];
    } on PlatformException {
      return const <File>[];
    }

    return <File>[
      for (final path in paths)
        if (File(path).existsSync()) File(path),
    ];
  }
}
