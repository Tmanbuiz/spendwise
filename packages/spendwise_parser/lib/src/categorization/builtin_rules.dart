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
      'HUSKY', 'ULTRAMAR', 'PIONEER ENERGY', 'MOBIL', 'CHEVRON', 'IRVING OIL',
      'CO OP GAS', 'GAS BAR', 'PETROLEUM', 'CANADIAN TIRE GAS', 'COSTCO GAS',
      'FAS GAS', 'CIRCLE K',
    ])
      _r(name, SpendCategory.gas),
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
      'AMAZON', 'WALMART', 'CANADIAN TIRE', 'HOME DEPOT', 'RONA', 'LOWES',
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

  static final List<MerchantRule> _utilities = <MerchantRule>[
    for (final name in <String>[
      'TORONTO HYDRO', 'HYDRO ONE', 'HYDRO QUEBEC', 'HYDRO-QUEBEC',
      'BC HYDRO', 'ENBRIDGE', 'FORTIS', 'EPCOR', 'ATCO', 'ALECTRA',
      'ELEXICON', 'DIRECT ENERGY', 'JUST ENERGY', 'RELIANCE HOME',
      'HYDRO', 'WATER UTILITY', 'CITY OF', 'REGION OF',
    ])
      _r(name, SpendCategory.utilities),
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
