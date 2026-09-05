/// A bank the user can select during onboarding.
class Bank {
  const Bank({
    required this.id,
    required this.name,
    required this.shortName,
    required this.packageNames,
    required this.supportLevel,
  });

  final String id;
  final String name;
  final String shortName;

  /// Android application ids whose notifications belong to this bank.
  final Set<String> packageNames;

  final BankSupport supportLevel;

  bool get hasParser => supportLevel == BankSupport.full;
}

/// How well SpendWise understands a bank's notifications today.
///
/// Stated honestly in the UI rather than hidden: a user who picks a bank with
/// no parser should know their transactions will need manual entry, instead of
/// wondering why nothing appears.
enum BankSupport {
  /// A tested parser exists; notifications are captured automatically.
  full,

  /// Notifications are captured but not yet understood. They are stored as
  /// unparsed samples the user can turn into transactions by hand.
  captureOnly,
}

abstract final class Banks {
  static const Bank cibc = Bank(
    id: 'cibc',
    name: 'CIBC',
    shortName: 'CIBC',
    // Several candidate ids because CIBC's package name is not something we
    // can verify from here. Detection reports which one is actually present,
    // so a wrong guess shows as "app not found" rather than as silence.
    packageNames: <String>{
      'com.cibc.android.mobi',
      'com.cibc.mobile',
      'com.cibc.ca',
    },
    supportLevel: BankSupport.full,
  );

  static const Bank rbc = Bank(
    id: 'rbc',
    name: 'RBC Royal Bank',
    shortName: 'RBC',
    packageNames: <String>{'com.rbc.mobile.android'},
    supportLevel: BankSupport.captureOnly,
  );

  static const Bank td = Bank(
    id: 'td',
    name: 'TD Canada Trust',
    shortName: 'TD',
    packageNames: <String>{'com.td'},
    supportLevel: BankSupport.captureOnly,
  );

  static const Bank scotiabank = Bank(
    id: 'scotiabank',
    name: 'Scotiabank',
    shortName: 'Scotiabank',
    packageNames: <String>{'com.scotiabank.banking'},
    supportLevel: BankSupport.captureOnly,
  );

  static const Bank bmo = Bank(
    id: 'bmo',
    name: 'BMO Bank of Montreal',
    shortName: 'BMO',
    packageNames: <String>{'com.bmo.mobile'},
    supportLevel: BankSupport.captureOnly,
  );

  /// Wealthsimple ships one Android app covering Cash, Trade and Invest.
  /// Package confirmed installed on a real device as `com.wealthsimple.trade`.
  static const Bank wealthsimple = Bank(
    id: 'wealthsimple',
    name: 'Wealthsimple',
    shortName: 'Wealthsimple',
    packageNames: <String>{
      'com.wealthsimple.trade',
      'com.wealthsimple.cash',
    },
    supportLevel: BankSupport.full,
  );

  static const Bank other = Bank(
    id: 'other',
    name: 'Other bank',
    shortName: 'Other',
    packageNames: <String>{},
    supportLevel: BankSupport.captureOnly,
  );

  static const List<Bank> all = <Bank>[
    cibc,
    rbc,
    td,
    scotiabank,
    bmo,
    wealthsimple,
    other,
  ];

  static Bank? byId(String id) {
    for (final bank in all) {
      if (bank.id == id) return bank;
    }
    return null;
  }

  /// Finds the bank that owns an Android notification package.
  static Bank? byPackage(String packageName) {
    for (final bank in all) {
      if (bank.packageNames.contains(packageName)) return bank;
    }
    return null;
  }
}
