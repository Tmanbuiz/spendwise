import 'merchant_rule.dart';
import 'spend_category.dart';

/// Built-in merchant knowledge, weighted toward Canadian merchants because
/// that is who CIBC customers pay.
///
/// Ordering in this file does not matter. The categoriser picks the *longest*
/// matching pattern, so `AMAZON PRIME` beats `AMAZON` and `UBER EATS` beats
/// `UBER` without anyone maintaining a priority column by hand.
abstract final class BuiltInRules {
  static MerchantRule _r(String pattern, SpendCategory category) =>
      MerchantRule(pattern: pattern, category: category);

  /// A rule that must match a whole word.
  ///
  /// Needed where a brand name is a prefix of an ordinary word: `MOBIL`, the
  /// fuel brand, is contained in `FIDO Mobile` and in every other phone bill
  /// with "Mobile" in it, and because the longest match wins it beat `FIDO`
  /// and filed the phone bill under Gas.
  static MerchantRule _word(String pattern, SpendCategory category) =>
      MerchantRule(
        pattern: r'\b' + pattern + r'\b',
        category: category,
        match: RuleMatch.regex,
      );

  static final List<MerchantRule> all = <MerchantRule>[
    ..._groceries,
    ..._dining,
    ..._gas,
    ..._transportation,
    ..._shopping,
    ..._utilities,
    ..._phoneInternet,
    ..._subscriptions,
    ..._housing,
    ..._health,
    ..._entertainment,
    ..._insurance,
    ..._education,
    ..._bankFees,
  ];

  /// Tuition, registration and application fees.
  ///
  /// Matched on what the institution calls the charge rather than on school
  /// names, because there are thousands of those and a registrar's line reads
  /// the same everywhere: `UNB REGISTRAR`, `MEMORIAL U-STUDENT REG`,
  /// `SMU - ADMISSIONS`.
  static final List<MerchantRule> _education = <MerchantRule>[
    for (final name in <String>[
      'UNIVERSITY', 'TUITION', 'REGISTRAR', 'ADMISSIONS', 'STUDENT REG',
      'STUDENT FEES', 'SCHOOL BOARD', 'POLYTECHNIC', 'SCHOLARSHIP',
    ])
      _r(name, SpendCategory.education),
  ];

  /// What the bank charges for holding the money.
  ///
  /// Written narrowly on purpose. `CASH ADVANCE/AVANCE DE FONDS` is the
  /// advance itself — the customer's own credit handed over as cash, not a
  /// charge — so a bare `CASH ADV` would file it as a fee. Only the wording
  /// that names a fee is matched.
  ///
  /// `SERVICE CHARGE` deliberately also catches `SERVICE CHARGE DISCOUNT` and
  /// `SERVICE CHARGE REWARDS`, which are rebates: they belong beside the
  /// charges they offset, and the event type already keeps them out of
  /// spending totals.
  static final List<MerchantRule> _bankFees = <MerchantRule>[
    for (final name in <String>[
      'SERVICE CHARGE', 'OVERDRAFT FEE', 'OVERDRAFT INTEREST',
      'OVERLIMIT FEE', 'CONV CHQ FEE', 'NSF FEE', 'MONTHLY PLAN FEE',
      'ANNUAL FEE', 'RECORD KEEPING', 'DISHONOURED', 'STOP PAYMENT',
    ])
      _r(name, SpendCategory.bankFees),
  ];

  static final List<MerchantRule> _groceries = <MerchantRule>[
    for (final name in <String>[
      'LOBLAWS', 'NO FRILLS', 'NOFRILLS', 'FRESHCO', 'SOBEYS', 'METRO',
      'FOOD BASICS', 'ZEHRS', 'REAL CANADIAN SUPERSTORE', 'SUPERSTORE',
      'FARM BOY', 'LONGOS', 'WHOLE FOODS', 'SAVE ON FOODS', 'SAVE-ON-FOODS',
      'IGA', 'PROVIGO', 'MAXI', 'SUPER C', 'ADONIS', 'BULK BARN',
      'YOUR INDEPENDENT GROCER', 'VALU MART', 'FORTINOS', 'COSTCO',
      'T AND T SUPERMARKET', 'GROCERY', 'SUPERMARKET', 'FRUIT MARKET',
      'BUTCHER', 'BAKERY', 'LCBO', 'BEER STORE', 'SAQ', 'WINE RACK',

      // Walmart's Canadian Supercentres are full supermarkets, and the
      // spending pattern says so: a $106 average across weekly visits is a
      // food shop, not discretionary retail. Filed under Shopping it made
      // groceries look smaller than they are and Shopping larger.
      'WALMART SUPERCENTER', 'WAL-MART SUPERCENTER', 'WAL MART SUPERCENTER',
      'WALMART SUPERCENTRE', 'WAL-MART SUPERCENTRE',

      // Independent grocers name themselves after what they sell rather than
      // using a chain's name, and they are where a lot of household food
      // money actually goes — more here than at any chain.
      'MEAT MARKET', 'FRESH MARKET', 'FARMERS MARKET', 'FARMER MARKET',
      'AFRICAN MARKET', 'ASIAN MARKET', 'HALAL', 'CARIBBEAN',
      'PRODUCE', 'FISH MARKET', 'SEAFOOD MARKET',
    ])
      _r(name, SpendCategory.groceries),
  ];

  static final List<MerchantRule> _dining = <MerchantRule>[
    for (final name in <String>[
      'TIM HORTONS', 'TIM HORTON', 'STARBUCKS', 'MCDONALDS', 'A AND W',
      'WENDYS', 'BURGER KING', 'SUBWAY', 'HARVEYS', 'SWISS CHALET',
      'BOSTON PIZZA', 'PIZZA PIZZA', 'DOMINOS', 'PIZZA HUT', 'KFC',
      'POPEYES', 'CHIPOTLE', 'FIVE GUYS', 'MARY BROWNS', 'SECOND CUP',
      'COUNTRY STYLE', 'DAIRY QUEEN', 'TACO BELL', 'ST HUBERT', 'THE KEG',
      'EARLS', 'MOXIES', 'MILESTONES', 'THAI EXPRESS', 'FRESHII',
      'UBER EATS', 'DOORDASH', 'SKIPTHEDISHES', 'SKIP THE DISHES',
      'RESTAURANT', 'CAFE', 'COFFEE', 'BISTRO', 'GRILL', 'SUSHI', 'PUB',
      'DINER', 'EATERY', 'BAR AND GRILL', 'BREWERY', 'TAVERN',
    ])
      _r(name, SpendCategory.dining),
  ];

  static final List<MerchantRule> _gas = <MerchantRule>[
    for (final name in <String>[
      'PETRO CANADA', 'PETRO-CANADA', 'PETROCANADA', 'ESSO', 'SHELL',
      'HUSKY', 'ULTRAMAR', 'PIONEER ENERGY', 'CHEVRON', 'IRVING OIL',
      'CO OP GAS', 'GAS BAR', 'PETROLEUM', 'CANADIAN TIRE GAS', 'COSTCO GAS',
      'FAS GAS', 'CIRCLE K',
    ])
      _r(name, SpendCategory.gas),

    // Whole-word only: see [_word]. As a substring this matched every phone
    // bill containing "Mobile".
    _word('MOBIL', SpendCategory.gas),

    // Atlantic convenience-and-fuel chains, absent from a list that was
    // written around Ontario brands.
    _r('KWIKWAY', SpendCategory.gas),
    _r('NEEDS CONVENIENCE', SpendCategory.gas),
    _r('ON THE RUN', SpendCategory.gas),
  ];

  static final List<MerchantRule> _transportation = <MerchantRule>[
    for (final name in <String>[
      'PRESTO', 'TTC', 'GO TRANSIT', 'VIA RAIL', 'OC TRANSPO', 'STM',
      'TRANSLINK', 'CALGARY TRANSIT', 'EDMONTON TRANSIT', 'UBER', 'LYFT',
      'TAXI', 'PARKING', 'GREEN P', 'IMPARK', 'PRECISE PARKLINK',
      'AIR CANADA', 'WESTJET', 'PORTER AIRLINES', 'FLAIR AIRLINES',
      'ENTERPRISE RENT', 'HERTZ', 'AVIS', 'BUDGET RENT', 'COMMUNAUTO',
      'ZIPCAR', '407 ETR', 'BIXI', 'CAR WASH', 'AUTO SERVICE',

      // Regional rideshare. Uber and Lyft do not cover much of Atlantic
      // Canada and the Prairies, where URide and Kabu carry the same trips.
      'URIDE', 'KABU RIDE',

      // Dealerships: servicing, parts and payments all arrive under the
      // marque, which is distinctive enough to match on its own.
      'MITSUBISHI', 'NISSAN', 'TOYOTA', 'HONDA CANADA', 'HYUNDAI', 'KIA ',
      'SUBARU', 'VOLKSWAGEN', 'MAZDA', 'CHEVROLET', 'DEALERSHIP',
    ])
      _r(name, SpendCategory.transportation),
  ];

  static final List<MerchantRule> _shopping = <MerchantRule>[
    for (final name in <String>[
      // Walmart prints itself hyphenated on a card statement
      // (`WAL-MART SUPERCENTER#1067`), so the unhyphenated spelling alone
      // matched none of them.
      'AMAZON', 'WALMART', 'WAL-MART', 'WAL MART',
      'CANADIAN TIRE', 'HOME DEPOT', 'RONA', 'LOWES',
      'IKEA', 'BEST BUY', 'HUDSONS BAY', 'THE BAY', 'WINNERS', 'MARSHALLS',
      'HOMESENSE', 'DOLLARAMA', 'GIANT TIGER', 'SPORT CHEK', 'MEC',
      'ALTITUDE SPORTS', 'INDIGO', 'CHAPTERS', 'STAPLES', 'TOYS R US',
      'ARDENE', 'H AND M', 'ZARA', 'UNIQLO', 'OLD NAVY', 'ROOTS',
      'LULULEMON', 'SIMONS', 'SHEIN', 'TEMU', 'ETSY', 'EBAY', 'WAYFAIR',
      'STRUCTUBE', 'LEONS', 'THE BRICK', 'PRINCESS AUTO', 'PRINCESS AUTO',
      'BED BATH AND BEYOND', 'MICHAELS', 'SEPHORA', 'BATH AND BODY WORKS',
      'VALUE VILLAGE', 'GOODWILL', 'TALIZE', 'SALVATION ARMY THRIFT',
    ])
      _r(name, SpendCategory.shopping),

    // Apple's Atlantic reseller. Whole-word only: as a substring `JUMP` would
    // also match Canadian Tire Jumpstart and anything else that jumps.
    _word('JUMP', SpendCategory.shopping),
  ];

  /// Power, gas and water.
  ///
  /// The provincial utilities are listed by name because most are monopolies:
  /// if a customer lives in New Brunswick, their electricity bill says
  /// `ENERGIE NB POWER` and nothing else ever will. The list previously
  /// covered Ontario, Quebec, BC and Alberta only, so every Atlantic and
  /// Prairie customer's largest recurring bill landed in `other`.
  static final List<MerchantRule> _utilities = <MerchantRule>[
    for (final name in <String>[
      // Ontario, Quebec, BC, Alberta
      'TORONTO HYDRO', 'HYDRO ONE', 'HYDRO QUEBEC', 'HYDRO-QUEBEC',
      'BC HYDRO', 'ENBRIDGE', 'FORTIS', 'EPCOR', 'ATCO', 'ALECTRA',
      'ELEXICON', 'DIRECT ENERGY', 'JUST ENERGY', 'RELIANCE HOME',
      // Atlantic
      'NB POWER', 'ENERGIE NB', 'ENERGIENB', 'SAINT JOHN ENERGY',
      'NOVA SCOTIA POWER', 'MARITIME ELECTRIC', 'NEWFOUNDLAND POWER',
      'NEWFOUNDLAND AND LABRADOR HYDRO', 'LIBERTY UTILITIES',
      // Prairies and the North
      'SASKPOWER', 'SASKENERGY', 'MANITOBA HYDRO', 'YUKON ENERGY',
      'NORTHWEST TERRITORIES POWER', 'QULLIQ ENERGY',
      // Generic, last resort
      'HYDRO', 'WATER UTILITY', 'CITY OF', 'REGION OF',
    ])
      _r(name, SpendCategory.utilities),
  ];

  /// Home, auto, tenant and life premiums.
  ///
  /// Worth naming individually because an insurer's charge carries only its
  /// own name — nothing in `SONNET INSURANCE COMPANY WATERLOO ON` says which
  /// kind of policy it is, or that it is a bill at all.
  static final List<MerchantRule> _insurance = <MerchantRule>[
    for (final name in <String>[
      'SONNET INSURANCE', 'SONNET', 'INTACT INSURANCE', 'BELAIRDIRECT',
      'BELAIR DIRECT', 'AVIVA', 'TD INSURANCE', 'DESJARDINS INSURANCE',
      'CO-OPERATORS', 'COOPERATORS', 'WAWANESA', 'ECONOMICAL INSURANCE',
      'JOHNSON INSURANCE', 'ONLIA', 'SQUARE ONE INSURANCE', 'ALLSTATE',
      'STATE FARM', 'RSA INSURANCE', 'GORE MUTUAL', 'PEMBRIDGE',
      'MANULIFE', 'SUN LIFE', 'CANADA LIFE', 'GREAT-WEST LIFE',
      'BLUE CROSS', 'INSURANCE',
    ])
      _r(name, SpendCategory.insurance),
  ];

  static final List<MerchantRule> _phoneInternet = <MerchantRule>[
    for (final name in <String>[
      'ROGERS', 'BELL CANADA', 'BELL MOBILITY', 'TELUS', 'FIDO', 'KOODO',
      'VIRGIN PLUS', 'VIRGIN MOBILE', 'FREEDOM MOBILE', 'PUBLIC MOBILE',
      'CHATR', 'LUCKY MOBILE', 'TEKSAVVY', 'DISTRIBUTEL', 'EBOX',
      'VIDEOTRON', 'SHAW', 'COGECO', 'EASTLINK', 'SASKTEL', 'XPLORNET',
      'STARLINK',
    ])
      _r(name, SpendCategory.phoneInternet),
  ];

  static final List<MerchantRule> _subscriptions = <MerchantRule>[
    for (final name in <String>[
      'NETFLIX', 'SPOTIFY', 'APPLE COM BILL', 'ITUNES', 'GOOGLE PLAY',
      'YOUTUBE PREMIUM', 'DISNEY PLUS', 'CRAVE', 'AMAZON PRIME',
      'PRIME VIDEO', 'ADOBE', 'MICROSOFT', 'OPENAI', 'ANTHROPIC', 'CLAUDE',
      'DROPBOX', 'NOTION', 'FIGMA', 'GITHUB', 'PATREON', 'AUDIBLE',
      'PARAMOUNT PLUS', 'HBO', 'APPLE MUSIC', 'ICLOUD', 'XBOX GAME PASS',
      'PLAYSTATION NETWORK', 'NINTENDO SWITCH ONLINE', 'DAZN',
      'SUBSCRIPTION',
    ])
      _r(name, SpendCategory.subscriptions),
  ];

  static final List<MerchantRule> _housing = <MerchantRule>[
    for (final name in <String>[
      'RENT PAYMENT', 'MORTGAGE', 'PROPERTY MANAGEMENT', 'CONDO FEE',
      'PROPERTY TAX', 'REALTY', 'APARTMENTS', 'PROPERTIES', 'LANDLORD',
      'STORAGE',
    ])
      _r(name, SpendCategory.housing),
  ];

  static final List<MerchantRule> _health = <MerchantRule>[
    for (final name in <String>[
      'SHOPPERS DRUG MART', 'REXALL', 'PHARMASAVE', 'PHARMAPRIX',
      'LONDON DRUGS', 'JEAN COUTU', 'PHARMACY', 'DENTAL', 'DENTIST',
      'CLINIC', 'MEDICAL', 'PHYSIO', 'OPTOMETRIST', 'LENSCRAFTERS',
      'HAKIM OPTICAL', 'GOODLIFE', 'FIT4LESS', 'ANYTIME FITNESS',
      'PLANET FITNESS', 'ORANGETHEORY', 'YMCA', 'MASSAGE', 'CHIROPRAC',
      'THERAPY', 'WELL CA', 'HOSPITAL', 'LIFELABS', 'DYNACARE', 'FITNESS',
    ])
      _r(name, SpendCategory.health),
  ];

  static final List<MerchantRule> _entertainment = <MerchantRule>[
    for (final name in <String>[
      'CINEPLEX', 'LANDMARK CINEMAS', 'IMAX', 'TICKETMASTER', 'STUBHUB',
      'LIVE NATION', 'STEAM GAMES', 'STEAMGAMES', 'EPIC GAMES', 'GOLF',
      'BOWLING', 'MUSEUM', 'GALLERY', 'AQUARIUM', 'THEATRE', 'CASINO',
      'CINEMA', 'CONCERT', 'ARCADE', 'SKI RESORT', 'AMUSEMENT',
    ])
      _r(name, SpendCategory.entertainment),
  ];
}
