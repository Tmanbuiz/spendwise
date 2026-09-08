/// A persistent household rule that teaches SpendWise how the user wants a
/// merchant or description treated in analysis.
///
/// This is intentionally separate from category rules. A category answers
/// "what kind of expense is this?" while a financial rule answers the more
/// fundamental question "is this spending, income, an investment, or an
/// internal transfer?".
class FinancialRule {
  const FinancialRule({
    required this.id,
    required this.pattern,
    required this.kind,
    this.match = FinancialRuleMatch.contains,
    this.ownerLabel,
    this.note,
    this.enabled = true,
  });

  final String id;
  final String pattern;
  final FinancialRuleKind kind;
  final FinancialRuleMatch match;
  final String? ownerLabel;
  final String? note;
  final bool enabled;

  bool matches(String value) {
    if (!enabled) return false;
    final input = value.trim();
    final needle = pattern.trim();
    if (input.isEmpty || needle.isEmpty) return false;

    switch (match) {
      case FinancialRuleMatch.exact:
        return input.toUpperCase() == needle.toUpperCase();
      case FinancialRuleMatch.contains:
        return input.toUpperCase().contains(needle.toUpperCase());
      case FinancialRuleMatch.startsWith:
        return input.toUpperCase().startsWith(needle.toUpperCase());
      case FinancialRuleMatch.regex:
        try {
          return RegExp(needle, caseSensitive: false).hasMatch(input);
        } on FormatException {
          return false;
        }
    }
  }

  FinancialRule copyWith({
    String? pattern,
    FinancialRuleKind? kind,
    FinancialRuleMatch? match,
    String? ownerLabel,
    String? note,
    bool? enabled,
  }) {
    return FinancialRule(
      id: id,
      pattern: pattern ?? this.pattern,
      kind: kind ?? this.kind,
      match: match ?? this.match,
      ownerLabel: ownerLabel ?? this.ownerLabel,
      note: note ?? this.note,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'pattern': pattern,
        'kind': kind.name,
        'match_type': match.name,
        'owner_label': ownerLabel,
        'note': note,
        'enabled': enabled,
      };

  static FinancialRule fromJson(Map<String, Object?> json) {
    return FinancialRule(
      id: (json['id'] as String?) ?? '',
      pattern: (json['pattern'] as String?) ?? '',
      kind: FinancialRuleKind.values.firstWhere(
        (value) => value.name == json['kind'],
        orElse: () => FinancialRuleKind.expense,
      ),
      match: FinancialRuleMatch.values.firstWhere(
        (value) => value.name == json['match_type'],
        orElse: () => FinancialRuleMatch.contains,
      ),
      ownerLabel: json['owner_label'] as String?,
      note: json['note'] as String?,
      enabled: (json['enabled'] as bool?) ?? true,
    );
  }
}

enum FinancialRuleKind {
  expense('Expense'),
  investment('Investment / savings'),
  income('Income'),
  internalTransfer('Internal household transfer'),
  exclude('Ignore in analysis');

  const FinancialRuleKind(this.displayName);
  final String displayName;
}

enum FinancialRuleMatch {
  contains('Contains'),
  exact('Exact match'),
  startsWith('Starts with'),
  regex('Regular expression');

  const FinancialRuleMatch(this.displayName);
  final String displayName;
}
