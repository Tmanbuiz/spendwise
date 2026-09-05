import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:test/test.dart';

void main() {
  group('raw notification retention', () {
    test('a complete parse discards the raw text', () {
      final result = parseCibcText(
        r'A transaction of $45.67 was made on your CIBC Dividend Visa card '
        'ending in 1234 at TIM HORTONS on Sep 3, 2026 at 8:14 AM.',
      );
      expect(result.rawRetention, RawRetention.discard);
      expect(result.redactedRaw, isNull);
      expect(result.toJson().containsKey('redacted_raw'), isFalse);
    });

    test('a parse missing the amount keeps a redacted sample', () {
      final result = parseCibcText(
        'A transaction was made at TIM HORTONS with your CIBC card.',
      );
      expect(result.rawRetention, RawRetention.keepRedactedForReview);
      expect(result.redactedRaw, isNotNull);
    });

    test('a parse missing the merchant keeps a redacted sample', () {
      final result = parseCibcText(
        r'A transaction of $18.40 was made on your CIBC card ending in 1234.',
      );
      expect(result.rawRetention, RawRetention.keepRedactedForReview);
      expect(result.redactedRaw, isNotNull);
    });

    test('unrecognised wording is kept so the rules can be extended', () {
      final result = parseCibcText('Your CIBC statement is ready.');
      expect(result.eventType, TransactionEventType.unknown);
      expect(result.rawRetention, RawRetention.keepRedactedForReview);
      expect(result.redactedRaw, isNotNull);
    });

    test('a retained sample carries no digits at all', () {
      final result = parseCibcText(
        r'A transaction of $18.40 was made on your CIBC card ending in 1234.',
      );
      expect(result.redactedRaw, isNotNull);
      expect(
        RegExp(r'\d').hasMatch(result.redactedRaw!),
        isFalse,
        reason: 'redacted sample still contains digits: ${result.redactedRaw}',
      );
    });

    test('a retained sample keeps the wording so rules can be improved', () {
      final result = parseCibcText(
        r'A transaction of $18.40 was made on your CIBC card ending in 1234.',
      );
      expect(result.redactedRaw, contains('transaction'));
      expect(result.redactedRaw, contains('CIBC'));
    });

    test('the retention window is bounded', () {
      expect(RawRetention.reviewTtl, const Duration(days: 30));
      expect(RawRetention.discard.keepsAnything, isFalse);
      expect(RawRetention.keepRedactedForReview.keepsAnything, isTrue);
    });
  });

  group('redaction', () {
    test('masks a card-number shaped run', () {
      final out = Redactor.redact('card 4519 1234 5678 9012 was used');
      expect(out, isNot(contains('4519')));
      expect(RegExp(r'\d').hasMatch(out), isFalse);
    });

    test('masks amounts and last-four digits', () {
      final out = Redactor.redact(r'You spent $45.67 on card ending in 1234');
      expect(out, isNot(contains('45.67')));
      expect(out, isNot(contains('1234')));
      expect(out, contains('You spent'));
    });
  });

  group('sensitive data is never extracted', () {
    test('no full card number reaches the parsed result', () {
      final result = parseCibcText(
        r'A transaction of $45.67 was made on card 4519 1234 5678 9012 '
        'at TIM HORTONS.',
      );
      expect(result.accountLast4, isNull);
      final serialised = result.toJson().toString();
      expect(serialised, isNot(contains('4519')));
      expect(serialised, isNot(contains('9012')));
    });

    test('the serialised row exposes no field for secrets', () {
      final json = parseCibcText(r'You spent $5.00 at METRO.').toJson();
      for (final key in json.keys) {
        expect(
          key,
          isNot(matches(RegExp('password|pin|cvv|card_number|full_card'))),
        );
      }
    });
  });
}
