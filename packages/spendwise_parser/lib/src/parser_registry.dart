import 'bank_notification_parser.dart';
import 'banks/cibc_parser.dart';
import 'banks/wealthsimple_parser.dart';
import 'models/notification_message.dart';
import 'models/parsed_transaction.dart';

/// Routes an incoming notification to the parser that understands it.
class ParserRegistry {
  ParserRegistry(List<BankNotificationParser> parsers)
      : _parsers = List<BankNotificationParser>.unmodifiable(parsers);

  /// The parsers shipped today.
  ///
  /// CIBC is the only fully-supported bank in this MVP. RBC, TD, Scotiabank
  /// and BMO parsers slot in here without touching any other file; until then
  /// their notifications fall through to [parse]'s null result and the user
  /// can still add the transaction by hand.
  factory ParserRegistry.standard() =>
      ParserRegistry(<BankNotificationParser>[
        CibcParser(),
        WealthsimpleParser(),
      ]);

  final List<BankNotificationParser> _parsers;

  List<BankNotificationParser> get parsers => _parsers;

  BankNotificationParser? parserFor(NotificationMessage message) {
    for (final parser in _parsers) {
      if (parser.canHandle(message)) return parser;
    }
    return null;
  }

  BankNotificationParser? parserForBankId(String bankId) {
    for (final parser in _parsers) {
      if (parser.bankId == bankId) return parser;
    }
    return null;
  }

  /// Parses [message], or returns null when no registered bank claims it.
  ParsedTransaction? parse(NotificationMessage message) =>
      parserFor(message)?.parse(message);
}
