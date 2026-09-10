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

  group('bills that were landing in Other', () {
    final categorizer = Categorizer();

    SpendCategory of(String merchant) =>
        categorizer.categoryFor(merchant.toUpperCase());

    test('provincial power utilities outside Ontario are recognised', () {
      // The list covered Ontario, Quebec, BC and Alberta, so an Atlantic or
      // Prairie customer's largest recurring bill went uncategorised. These
      // are monopolies: in New Brunswick the bill says ENERGIE NB POWER and
      // nothing else ever will.
      const power = <String>[
        'PREAUTHORIZED DEBIT ENERGIENB POWER',
        'NB POWER',
        'SAINT JOHN ENERGY',
        'NOVA SCOTIA POWER',
        'MARITIME ELECTRIC',
        'NEWFOUNDLAND POWER',
        'SASKPOWER',
        'MANITOBA HYDRO',
      ];
      for (final merchant in power) {
        expect(of(merchant), SpendCategory.utilities, reason: merchant);
      }
    });

    test('the Ontario and western utilities still work', () {
      expect(of('TORONTO HYDRO'), SpendCategory.utilities);
      expect(of('BC HYDRO'), SpendCategory.utilities);
      expect(of('ENBRIDGE GAS'), SpendCategory.utilities);
    });

    test('insurers are recognised as insurance', () {
      const insurers = <String>[
        'SONNET INSURANCE COMPANY WATERLOO ON',
        'INTACT INSURANCE',
        'BELAIRDIRECT',
        'TD INSURANCE',
        'CO-OPERATORS',
        'WAWANESA',
        'MANULIFE',
        'BLUE CROSS',
      ];
      for (final merchant in insurers) {
        expect(of(merchant), SpendCategory.insurance, reason: merchant);
      }
    });

    test('insurance does not swallow a merchant that merely says insurance',
        () {
      // A user rule always outranks built-in knowledge, so someone who calls
      // their broker something else can still override this.
      final withRule = Categorizer(userRules: <MerchantRule>[
        const MerchantRule(
          pattern: 'SONNET INSURANCE',
          category: SpendCategory.housing,
        ),
      ]);
      expect(
        withRule.categoryFor('SONNET INSURANCE COMPANY WATERLOO ON'),
        SpendCategory.housing,
      );
    });

    test('Insurance is a real category, not a relabelled Other', () {
      expect(SpendCategory.fromSlug('insurance'), SpendCategory.insurance);
      expect(SpendCategory.insurance.displayName, 'Insurance');
      expect(SpendCategory.values, contains(SpendCategory.insurance));
    });
  });

  group('brand names that are prefixes of ordinary words', () {
    final categorizer = Categorizer();

    SpendCategory of(String merchant) =>
        categorizer.categoryFor(merchant.toUpperCase());

    test('a phone bill containing "Mobile" is not filed as fuel', () {
      // MOBIL, the fuel brand, is a substring of "Mobile", and because the
      // longest match wins it beat FIDO — so every Fido, Koodo and Bell
      // Mobility bill was categorised as Gas.
      expect(of('FIDO Mobile ******1582 888-481-3436 ON'),
          SpendCategory.phoneInternet);
      expect(of('BELL MOBILITY'), SpendCategory.phoneInternet);
      expect(of('PUBLIC MOBILE'), SpendCategory.phoneInternet);
      expect(of('VIRGIN MOBILE'), SpendCategory.phoneInternet);
    });

    test('the fuel brand itself still matches as a whole word', () {
      expect(of('MOBIL'), SpendCategory.gas);
      expect(of('MOBIL 12345 TORONTO ON'), SpendCategory.gas);
    });

    test('Walmart is recognised however it is spelled', () {
      // Card statements print it hyphenated; the plain spelling matched none
      // of them, leaving every Walmart purchase uncategorised.
      expect(of('WALMART'), SpendCategory.shopping);
      expect(of('WAL MART'), SpendCategory.shopping);
      expect(of('WAL-MART'), SpendCategory.shopping);
    });
  });

  group('where the money actually goes', () {
    final categorizer = Categorizer();

    SpendCategory of(String merchant) =>
        categorizer.categoryFor(merchant.toUpperCase());

    test('a Walmart Supercentre is a grocery shop, a Walmart is a shop', () {
      // The spending pattern settles it: $106 average across weekly visits is
      // a food shop. Longest-match-wins does the rest — the Supercentre
      // pattern is longer than the bare brand, so the two coexist.
      expect(of('WAL-MART SUPERCENTER#1067FREDERICTON NB'),
          SpendCategory.groceries);
      expect(of('WALMART SUPERCENTRE'), SpendCategory.groceries);
      expect(of('WALMART'), SpendCategory.shopping);
    });

    test('independent grocers are groceries, not Other', () {
      // Named after what they sell rather than a chain, and collectively
      // larger than any chain in this household's spending.
      const grocers = <String>[
        'VICTORY MEAT MARKET FREDERICTON NB',
        'DIVINE AFRICAN MARKET FREDERICTON NB',
        'MANGO FRESH MARKET FREDERICTON NB',
        'ATLANTIC AFRO-CARIBBEANS FREDERICTON NB',
        'ST MARYS SUPERMARKET FREDERICTON NB',
        'ATLANTIC SUPERSTORE FR FREDERICTON NB',
      ];
      for (final merchant in grocers) {
        expect(of(merchant), SpendCategory.groceries, reason: merchant);
      }
    });

    test('a Caribbean restaurant is still dining, not groceries', () {
      // `CARIBBEAN` earns groceries a market, but must not outrank the
      // longer dining patterns.
      expect(of('CARIBBEAN RESTAURANT TORONTO ON'), SpendCategory.dining);
    });

    test('discount and thrift shops stay Shopping', () {
      expect(of('DOLLARAMA # 161 FREDERICTON NB'), SpendCategory.shopping);
      expect(of('VALUE VILLAGE # 2104 FREDERICTON NB'), SpendCategory.shopping);
      expect(of('GIANT TIGER'), SpendCategory.shopping);
    });
  });

  group('education and bank fees', () {
    final categorizer = Categorizer();

    SpendCategory of(String merchant) =>
        categorizer.categoryFor(MerchantExtractor.normalize(merchant) ?? '');

    test('registrars and admissions offices are education', () {
      // Strings exactly as the statements print them.
      const schools = <String>[
        'UNB REGISTRAR FREDERICTON NB',
        "MEMORIAL U-STUDENT REG ST-JOHN'S NL",
        'SMU - ADMISSIONS ONLINE HALIFAX NS',
        'UNIVERSITY OF TORONTO',
      ];
      for (final merchant in schools) {
        expect(of(merchant), SpendCategory.education, reason: merchant);
      }
    });

    test('bank charges are bank fees', () {
      const fees = <String>[
        'SERVICE CHARGE CAPPED MONTHLY FEE\$16.95 RECORD-KEEPING N/A',
        'OVERDRAFT FEE',
        'OVERDRAFT INTEREST CHARGE',
        'OVERLIMIT FEE',
        'CASH ADV/BT/CONV CHQ FEE',
      ];
      for (final merchant in fees) {
        expect(of(merchant), SpendCategory.bankFees, reason: merchant);
      }
    });

    test('a cash advance itself is not filed as a fee', () {
      // The advance is the customer's own credit paid out as cash. Only the
      // charge for taking it is a fee — a bare "CASH ADV" pattern would have
      // swept the advance up too.
      expect(of('CASH ADVANCE/AVANCE DE FONDS'),
          isNot(SpendCategory.bankFees));
    });

    test('service charge rebates sit beside the charges they offset', () {
      expect(of('SERVICE CHARGE DISCOUNT'), SpendCategory.bankFees);
      expect(of('SERVICE CHARGE REWARDS'), SpendCategory.bankFees);
    });

    test('regional rideshare, dealerships and fuel chains', () {
      expect(of('URIDE THUNDER BAY NON'), SpendCategory.transportation);
      expect(of('FREDERICTON MITSUBISHI FREDERICTON NB'),
          SpendCategory.transportation);
      expect(of('FREDERICTON NISSAN FREDERICTON NB'),
          SpendCategory.transportation);
      expect(of('KWIKWAY #109930 FREDERICTON NB'), SpendCategory.gas);
    });

    test('new categories round-trip through their slugs', () {
      expect(SpendCategory.fromSlug('education'), SpendCategory.education);
      expect(SpendCategory.fromSlug('bank_fees'), SpendCategory.bankFees);
    });
  });
}
