import 'spend_category.dart';

/// How a rule's pattern is compared against a normalised merchant name.
enum RuleMatch {
  /// The whole merchant equals the pattern.
  exact,

  /// The pattern appears anywhere in the merchant.
  contains,

  /// The merchant begins with the pattern.
  startsWith,

  /// The pattern is a regular expression.
  regex,
}

/// Where a rule came from. User rules always beat built-in ones.
enum RuleSource { builtIn, user }

/// A merchant to category mapping.
class MerchantRule {
  const MerchantRule({
    required this.pattern,
    required this.category,
    this.match = RuleMatch.contains,
    this.source = RuleSource.builtIn,
    this.id,
  });

  /// Compared against `merchantNormalized` (upper case, store numbers and
  /// processor prefixes already stripped), so patterns are written upper case.
  final String pattern;

  final SpendCategory category;
  final RuleMatch match;
  final RuleSource source;

  /// Database id for user rules; null for built-ins.
  final String? id;

  /// How specific this rule is. Longer patterns are more specific, so
  /// `AMAZON PRIME` wins over `AMAZON` and `UBER EATS` over `UBER` without
  /// anyone having to hand-order the table.
  int get specificity => pattern.length;

  bool matches(String merchantNormalized) {
    final subject = merchantNormalized.toUpperCase();
    final needle = pattern.toUpperCase();
    switch (match) {
      case RuleMatch.exact:
        return subject == needle;
      case RuleMatch.contains:
        return subject.contains(needle);
      case RuleMatch.startsWith:
        return subject.startsWith(needle);
      case RuleMatch.regex:
        // A user-authored pattern must never crash categorisation.
        try {
          return RegExp(pattern, caseSensitive: false).hasMatch(subject);
        } on FormatException {
          return false;
        }
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        if (id != null) 'id': id,
        'pattern': pattern,
        'category': category.slug,
        'match_type': match.name,
        'source': source.name,
      };

  static MerchantRule fromJson(Map<String, Object?> json) {
    return MerchantRule(
      id: json['id'] as String?,
      pattern: (json['pattern'] as String?) ?? '',
      category: SpendCategory.fromSlug((json['category'] as String?) ?? 'other'),
      match: RuleMatch.values.firstWhere(
        (m) => m.name == json['match_type'],
        orElse: () => RuleMatch.contains,
      ),
      source: RuleSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => RuleSource.user,
      ),
    );
  }
}

/// The outcome of categorising a merchant.
class CategoryMatch {
  const CategoryMatch({
    required this.category,
    required this.source,
    this.matchedRule,
  });

  /// Nothing matched: fall back to Other, and let the user correct it.
  static const CategoryMatch unmatched = CategoryMatch(
    category: SpendCategory.other,
    source: null,
  );

  final SpendCategory category;

  /// Null when nothing matched.
  final RuleSource? source;
  final MerchantRule? matchedRule;

  bool get isConfident => source != null;

  /// User corrections are certain; built-in guesses are good but not certain.
  double get confidence {
    switch (source) {
      case RuleSource.user:
        return 1.0;
      case RuleSource.builtIn:
        return 0.8;
      case null:
        return 0.0;
    }
  }
}
