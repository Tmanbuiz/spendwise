import 'models/notification_message.dart';
import 'models/parsed_transaction.dart';

/// Contract every bank-specific parser implements.
///
/// Keeping this narrow is what makes the future iOS/email importer cheap: an
/// email body can be wrapped in a [NotificationMessage] and run through the
/// exact same parsers with no changes here.
abstract interface class BankNotificationParser {
  /// Stable identifier persisted on every transaction row, e.g. `cibc`.
  String get bankId;

  /// Name shown in bank selection during onboarding.
  String get displayName;

  /// Android application ids that deliver this bank's alerts.
  Set<String> get packageNames;

  /// Whether this parser recognises the message as belonging to its bank.
  bool canHandle(NotificationMessage message);

  /// Always returns a result. An unrecognised message comes back with
  /// `eventType == unknown` rather than null.
  ParsedTransaction parse(NotificationMessage message);
}
