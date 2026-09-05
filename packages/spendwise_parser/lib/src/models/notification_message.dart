/// A single OS-level notification handed to the parsing engine.
///
/// This is the only shape the Android `NotificationListenerService` bridge and
/// the future iOS/email importer both have to produce, which keeps the parsers
/// independent of where the text came from.
class NotificationMessage {
  const NotificationMessage({
    required this.packageName,
    required this.title,
    required this.body,
    required this.postedAt,
    this.subText,
    this.channelId,
  });

  /// Android application id, e.g. `com.cibc.android.mobi`.
  final String packageName;

  final String title;
  final String body;

  /// When the OS delivered the notification. Used as the timestamp fallback
  /// when the message body carries no date of its own.
  final DateTime postedAt;

  /// Optional Android `subText` / summary line; some banks put the card label
  /// there rather than in the body.
  final String? subText;

  final String? channelId;

  /// Title, body and subText joined into one haystack for matching.
  ///
  /// A newline separator (rather than a space) keeps sentence boundaries
  /// intact so merchant capture does not run across from title into body.
  String get combinedText {
    final parts = <String>[
      title.trim(),
      body.trim(),
      if (subText != null && subText!.trim().isNotEmpty) subText!.trim(),
    ]..removeWhere((p) => p.isEmpty);
    return parts.join('\n');
  }

  bool get isEmpty => combinedText.trim().isEmpty;

  NotificationMessage copyWith({
    String? packageName,
    String? title,
    String? body,
    DateTime? postedAt,
    String? subText,
    String? channelId,
  }) {
    return NotificationMessage(
      packageName: packageName ?? this.packageName,
      title: title ?? this.title,
      body: body ?? this.body,
      postedAt: postedAt ?? this.postedAt,
      subText: subText ?? this.subText,
      channelId: channelId ?? this.channelId,
    );
  }
}
