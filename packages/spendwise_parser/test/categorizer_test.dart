import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:test/test.dart';

void main() {
  final categorizer = Categorizer();

  group('built-in categorisation', () {
    const expectations = <String, SpendCategory>{
      'LOBLAWS': SpendCategory.groceries,
      'NO FRILLS': SpendCategory.groceries,
      'COSTCO': SpendCategory.groceries,
      'TIM HORTONS': SpendCategory.dining,
      'STARBUCKS': SpendCategory.dining,
      'BLUE DOOR CAFE': SpendCategory.dining,
      'PETRO CANADA': SpendCategory.gas,
      'ESSO': SpendCategory.gas,
      'PRESTO': SpendCategory.transportation,
      'AIR CANADA': SpendCategory.transportation,
      'BEST BUY': SpendCategory.shopping,
      'DOLLARAMA': SpendCategory.shopping,
      'TORONTO HYDRO': SpendCategory.utilities,
      'ENBRIDGE': SpendCategory.utilities,
      'ROGERS': SpendCategory.phoneInternet,
      'FREEDOM MOBILE': SpendCategory.phoneInternet,
      'NETFLIX': SpendCategory.subscriptions,
      'APPLE COM BILL': SpendCategory.subscriptions,
      'MORTGAGE': SpendCategory.housing,
      'SHOPPERS DRUG MART': SpendCategory.health,
      'GOODLIFE': SpendCategory.health,
      'CINEPLEX': SpendCategory.entertainment,
    };

    expectations.forEach((merchant, category) {
      test('$merchant maps to ${category.displayName}', () {
        expect(categorizer.categoryFor(merchant), category);
      });
    });

    test('an unknown merchant falls back to Other', () {
      final match = categorizer.categorize('SOME LOCAL SHOP XYZ');
      expect(match.category, SpendCategory.other);
      expect(match.isConfident, isFalse);
      expect(match.confidence, 0.0);
    });

    test('a null or blank merchant falls back to Other', () {
      expect(categorizer.categoryFor(null), SpendCategory.other);
      expect(categorizer.categoryFor('   '), SpendCategory.other);
    });
  });

  group('the longest matching pattern wins', () {
    test('AMAZON PRIME is a subscription, AMAZON is shopping', () {
      expect(categorizer.categoryFor('AMAZON PRIME'),
          SpendCategory.subscriptions);
      expect(categorizer.categoryFor('AMAZON CA'), SpendCategory.shopping);
    });

    test('UBER EATS is dining, UBER is transportation', () {
      expect(categorizer.categoryFor('UBER EATS'), SpendCategory.dining);
      expect(categorizer.categoryFor('UBER TRIP'),
          SpendCategory.transportation);
    });

    test('CANADIAN TIRE GAS is gas, CANADIAN TIRE is shopping', () {
      expect(categorizer.categoryFor('CANADIAN TIRE GAS'), SpendCategory.gas);
      expect(categorizer.categoryFor('CANADIAN TIRE'), SpendCategory.shopping);
    });

    test('COSTCO GAS is gas, COSTCO is groceries', () {
      expect(categorizer.categoryFor('COSTCO GAS'), SpendCategory.gas);
      expect(categorizer.categoryFor('COSTCO WHOLESALE'),
          SpendCategory.groceries);
    });
  });

  group('user rules override built-in knowledge', () {
    test('a user rule beats a longer built-in pattern', () {
      final custom = Categorizer(
        userRules: <MerchantRule>[
          const MerchantRule(
            pattern: 'COSTCO',
            category: SpendCategory.shopping,
            source: RuleSource.user,
          ),
        ],
      );
      // Built-in says groceries, and 'COSTCO WHOLESALE' would match the
      // longer built-in pattern too — the user still wins.
      expect(custom.categoryFor('COSTCO WHOLESALE'), SpendCategory.shopping);
      expect(custom.categorize('COSTCO').source, RuleSource.user);
      expect(custom.categorize('COSTCO').confidence, 1.0);
    });

    test('the most specific user rule wins among user rules', () {
      final custom = Categorizer(
        userRules: <MerchantRule>[
          const MerchantRule(
            pattern: 'THE KEG',
            category: SpendCategory.dining,
            source: RuleSource.user,
          ),
          const MerchantRule(
            pattern: 'THE KEG STEAKHOUSE',
            category: SpendCategory.entertainment,
            source: RuleSource.user,
          ),
        ],
      );
      expect(custom.categoryFor('THE KEG STEAKHOUSE'),
          SpendCategory.entertainment);
      expect(custom.categoryFor('THE KEG'), SpendCategory.dining);
    });

    test('exact match rules do not fire on a substring', () {
      final custom = Categorizer(
        userRules: <MerchantRule>[
          const MerchantRule(
            pattern: 'METRO',
            category: SpendCategory.transportation,
            match: RuleMatch.exact,
            source: RuleSource.user,
          ),
        ],
      );
      expect(custom.categoryFor('METRO'), SpendCategory.transportation);
      // Falls through to the built-in grocery rule.
      expect(custom.categoryFor('METRO PLUS GROCERY'), SpendCategory.groceries);
    });

    test('startsWith rules anchor at the front', () {
      final custom = Categorizer(
        userRules: <MerchantRule>[
          const MerchantRule(
            pattern: 'SQ',
            category: SpendCategory.dining,
            match: RuleMatch.startsWith,
            source: RuleSource.user,
          ),
        ],
      );
      expect(custom.categoryFor('SQ SOMETHING'), SpendCategory.dining);
      expect(custom.categoryFor('A SQ SHOP'), SpendCategory.other);
    });

    test('regex rules work', () {
      final custom = Categorizer(
        userRules: <MerchantRule>[
          const MerchantRule(
            pattern: r'^PARKING\s+LOT\s+\d+$',
            category: SpendCategory.transportation,
            match: RuleMatch.regex,
            source: RuleSource.user,
          ),
        ],
      );
      expect(custom.categoryFor('PARKING LOT 42'),
          SpendCategory.transportation);
    });

    test('an invalid user regex never crashes categorisation', () {
      final custom = Categorizer(
        userRules: <MerchantRule>[
          const MerchantRule(
            pattern: '[unclosed(',
            category: SpendCategory.dining,
            match: RuleMatch.regex,
            source: RuleSource.user,
          ),
        ],
      );
      expect(() => custom.categoryFor('ANYTHING'), returnsNormally);
      expect(custom.categoryFor('LOBLAWS'), SpendCategory.groceries);
    });
  });

  group('end to end with the parser', () {
    test('a parsed CIBC purchase gets a category', () {
      final parsed = parseCibcText(
        r'You spent $12.50 at STARBUCKS with your CIBC card ending in 4321.',
      );
      expect(categorizer.categoryFor(parsed.merchantNormalized),
          SpendCategory.dining);
    });

    test('a store-numbered merchant still categorises', () {
      final parsed = parseCibcText(
        r'Your CIBC card was used for a purchase of $23.10 at LOBLAWS #456.',
      );
      expect(categorizer.categoryFor(parsed.merchantNormalized),
          SpendCategory.groceries);
    });

    test('a bill payment to a utility categorises as Utilities', () {
      final parsed = parseCibcText(
        r'A bill payment of $142.08 to TORONTO HYDRO was made from your '
        'CIBC Smart Account ending in 3344.',
      );
      expect(parsed.countsAsSpending, isTrue);
      expect(categorizer.categoryFor(parsed.merchantNormalized),
          SpendCategory.utilities);
    });

    test('a pre-authorized debit to a carrier is Phone & Internet', () {
      final parsed = parseCibcText(
        r'A pre-authorized debit of $79.00 to ROGERS was processed on your '
        'CIBC Smart Account ending in 3344.',
      );
      expect(categorizer.categoryFor(parsed.merchantNormalized),
          SpendCategory.phoneInternet);
    });
  });

  group('serialisation', () {
    test('a rule round-trips through JSON', () {
      const rule = MerchantRule(
        id: 'rule-1',
        pattern: 'MY CORNER STORE',
        category: SpendCategory.groceries,
        match: RuleMatch.startsWith,
        source: RuleSource.user,
      );
      final restored = MerchantRule.fromJson(rule.toJson());
      expect(restored.pattern, rule.pattern);
      expect(restored.category, rule.category);
      expect(restored.match, rule.match);
      expect(restored.source, rule.source);
    });

    test('category slugs are stable', () {
      expect(SpendCategory.phoneInternet.slug, 'phone_internet');
      expect(SpendCategory.fromSlug('phone_internet'),
          SpendCategory.phoneInternet);
      expect(SpendCategory.fromSlug('nonsense'), SpendCategory.other);
    });
  });
}
