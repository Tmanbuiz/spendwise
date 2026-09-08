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
  ];

  static final List<MerchantRule> _transportation = <MerchantRule>[
    for (final name in <String>[
      'PRESTO', 'TTC', 'GO TRANSIT', 'VIA RAIL', 'OC TRANSPO', 'STM',
      'TRANSLINK', 'CALGARY TRANSIT', 'EDMONTON TRANSIT', 'UBER', 'LYFT',
      'TAXI', 'PARKING', 'GREEN P', 'IMPARK', 'PRECISE PARKLINK',
      'AIR CANADA', 'WESTJET', 'PORTER AIRLINES', 'FLAIR AIRLINES',
      'ENTERPRISE RENT', 'HERTZ', 'AVIS', 'BUDGET RENT', 'COMMUNAUTO',
      'ZIPCAR', '407 ETR', 'BIXI', 'CAR WASH', 'AUTO SERVICE',
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
    ])
      _r(name, SpendCategory.shopping),
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
