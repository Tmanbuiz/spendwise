/// A card or bank account the user's transactions belong to.
///
/// Created automatically the first time a notification names a card, so the
/// user never types card details in. The only card data held anywhere is the
/// last four digits — never a full number, PIN or CVV.
class Account {
  const Account({
    required this.id,
    required this.bankId,
    required this.label,
    this.last4,
    this.type = AccountType.unknown,
    this.isArchived = false,
  });

  final String id;
  final String bankId;

  /// e.g. `CIBC Dividend Visa Infinite card`.
  final String label;

  final String? last4;
  final AccountType type;
  final bool isArchived;

  String get displayName => last4 == null ? label : '$label ••$last4';

  Account copyWith({String? label, AccountType? type, bool? isArchived}) =>
      Account(
        id: id,
        bankId: bankId,
        label: label ?? this.label,
        last4: last4,
        type: type ?? this.type,
        isArchived: isArchived ?? this.isArchived,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'bank_id': bankId,
        'label': label,
        'last4': last4,
        'type': type.name,
        'is_archived': isArchived,
      };

  static Account fromJson(Map<String, Object?> json) => Account(
        id: (json['id'] as String?) ?? '',
        bankId: (json['bank_id'] as String?) ?? 'other',
        label: (json['label'] as String?) ?? 'Account',
        last4: json['last4'] as String?,
        type: AccountType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => AccountType.unknown,
        ),
        isArchived: (json['is_archived'] as bool?) ?? false,
      );
}

enum AccountType {
  credit('Credit card'),
  debit('Debit card'),
  chequing('Chequing'),
  savings('Savings'),
  lineOfCredit('Line of credit'),
  unknown('Account');

  const AccountType(this.displayName);
  final String displayName;

  /// Infers the account type from a bank's own product label.
  static AccountType fromLabel(String? label) {
    if (label == null) return AccountType.unknown;
    final text = label.toLowerCase();
    if (text.contains('line of credit')) return AccountType.lineOfCredit;
    if (text.contains('debit')) return AccountType.debit;
    if (text.contains('visa') ||
        text.contains('mastercard') ||
        text.contains('credit')) {
      return AccountType.credit;
    }
    if (text.contains('saving')) return AccountType.savings;
    if (text.contains('chequing') || text.contains('checking')) {
      return AccountType.chequing;
    }
    return AccountType.unknown;
  }
}
