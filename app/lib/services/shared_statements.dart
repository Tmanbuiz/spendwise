import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Statements handed to the app by another app.
///
/// Android delivers a shared document as a `content://` URI whose read grant
/// expires with the intent, so the platform side copies each one into the
/// app's cache and this reports the resulting paths. Everything here is a
/// queue the platform fills and Dart empties — the app is never told to do
/// anything with a file, only that one arrived.
///
/// iPhone needs no platform side. SpendWise declares that it opens PDF, CSV
/// and text files without editing them in place, so iOS copies a file opened
/// with "Open in SpendWise" into the app's own inbox folder before handing it
/// over. The queue there is simply what the inbox holds, and taking it moves
/// the files out so none is imported twice.
class SharedStatements {
  /// Everything is injectable so the queue can be tested without a device.
  const SharedStatements({
    this.channel = _defaultChannel,
    this.platform,
    this.inboxes = _defaultInboxes,
    this.workspace = getTemporaryDirectory,
  });

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.spendwise/shared_files',
  );

  /// The file types the importer reads, matching the Android bridge.
  static const Set<String> _extensions = <String>{'pdf', 'csv', 'txt'};

  final MethodChannel channel;

  /// Defaults to the platform the app is running on.
  final TargetPlatform? platform;

  /// Where iOS puts files opened in SpendWise.
  final Future<List<Directory>> Function() inboxes;

  /// Where statements taken from an inbox are moved to.
  final Future<Directory> Function() workspace;

  bool get _isIos => (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;

  /// Whether a statement is waiting, without taking it.
  ///
  /// Used to decide whether to open the import screen at all; taking the queue
  /// to answer that would lose the files if the navigation then failed.
  Future<bool> hasPending() async {
    if (_isIos) return (await _inboxStatements()).isNotEmpty;
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
    if (_isIos) return _takeFromInboxes();
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

  Future<List<File>> _inboxStatements() async {
    final found = <File>[];
    try {
      for (final inbox in await inboxes()) {
        if (!await inbox.exists()) continue;
        await for (final entity in inbox.list(followLinks: false)) {
          if (entity is File && _extensions.contains(_extension(entity.path))) {
            found.add(entity);
          }
        }
      }
    } on FileSystemException {
      // An inbox that cannot be listed right now is looked at again on the
      // next resume.
    } on MissingPluginException {
      return const <File>[];
    } on PlatformException {
      return const <File>[];
    }
    return found;
  }

  Future<List<File>> _takeFromInboxes() async {
    final waiting = await _inboxStatements();
    if (waiting.isEmpty) return const <File>[];

    final Directory target;
    try {
      target = Directory(
        '${(await workspace()).path}${Platform.pathSeparator}shared_statements',
      );
      await target.create(recursive: true);
    } on FileSystemException {
      return const <File>[];
    } on MissingPluginException {
      return const <File>[];
    }

    final taken = <File>[];
    for (final file in waiting) {
      final moved = await _move(file, target);
      if (moved != null) taken.add(moved);
    }
    return taken;
  }

  /// Moves [file] into [target], numbering the name if one is already there
  /// so a second statement with the same name never replaces the first.
  static Future<File?> _move(File file, Directory target) async {
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    final separator = Platform.pathSeparator;

    var destination = File('${target.path}$separator$name');
    for (var copy = 2; await destination.exists(); copy++) {
      destination = File('${target.path}$separator$stem ($copy)$extension');
    }

    try {
      return await file.rename(destination.path);
    } on FileSystemException {
      // Rename cannot cross volumes; copy and remove instead.
      try {
        final copied = await file.copy(destination.path);
        await file.delete();
        return copied;
      } on FileSystemException {
        return null;
      }
    }
  }

  static String _extension(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}

/// Where iOS copies a file opened in SpendWise: the Inbox folder inside the
/// app's documents, or on some iOS versions a folder in the temporary
/// directory whose name ends in `-Inbox`. Both are checked.
Future<List<Directory>> _defaultInboxes() async {
  final documents = await getApplicationDocumentsDirectory();
  final temporary = await getTemporaryDirectory();
  final found = <Directory>[
    Directory('${documents.path}${Platform.pathSeparator}Inbox'),
  ];
  if (await temporary.exists()) {
    await for (final entity in temporary.list(followLinks: false)) {
      if (entity is Directory && entity.path.endsWith('-Inbox')) {
        found.add(entity);
      }
    }
  }
  return found;
}
