/// SpendWise transaction notification parsing engine.
///
/// Pure Dart on purpose: no Flutter import appears anywhere in this package,
/// so the rules can be unit-tested without a device and reused later by the
/// planned iOS email importer.
library;

export 'src/bank_notification_parser.dart';
export 'src/banks/cibc_parser.dart';
export 'src/banks/cibc_rules.dart';
export 'src/banks/cibc_terse_alert.dart';
export 'src/banks/wealthsimple_parser.dart';
export 'src/banks/wealthsimple_rules.dart';
export 'src/categorization/builtin_rules.dart';
export 'src/categorization/categorizer.dart';
export 'src/categorization/merchant_rule.dart';
export 'src/categorization/spend_category.dart';
export 'src/duplicate_detector.dart';
export 'src/import/card_statement_reader.dart';
export 'src/import/csv_reader.dart';
export 'src/import/statement_reader.dart';
export 'src/import/text_statement_reader.dart';
export 'src/models/money.dart';
export 'src/models/notification_message.dart';
export 'src/models/parsed_transaction.dart';
export 'src/models/raw_retention.dart';
export 'src/models/transaction_event_type.dart';
export 'src/parser_registry.dart';
export 'src/util/account_extractor.dart';
export 'src/util/amount_parser.dart';
export 'src/util/datetime_parser.dart';
export 'src/util/fingerprint.dart';
export 'src/util/merchant_cleaner.dart';
