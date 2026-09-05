import 'builtin_rules.dart';
import 'merchant_rule.dart';
import 'spend_category.dart';

/// Assigns a spending category to a merchant.
///
/// Two tiers, and the order between them is the point: a rule the user wrote
/// always beats built-in knowledge, however specific the built-in looks.
/// Within a tier the longest matching pattern wins, so `AMAZON PRIME` beats
/// `AMAZON` and `UBER EATS` beats `UBER` with no hand-maintained ordering.
class Categorizer {
  Categorizer({List<MerchantRule> userRules = const <MerchantRule>[]})
      : _userRules = List<MerchantRule>.unmodifiable(userRules);

  final List<MerchantRule> _userRules;

  List<MerchantRule> get userRules => _userRules;

  /// Returns a categoriser with [rules] replacing the current user rules.
  Categorizer withUserRules(List<MerchantRule> rules) =>
      Categorizer(userRules: rules);

  /// Categorises [merchantNormalized], which is the upper-cased,
  /// store-number-stripped form the parser produces.
  CategoryMatch categorize(String? merchantNormalized) {
    if (merchantNormalized == null || merchantNormalized.trim().isEmpty) {
      return CategoryMatch.unmatched;
    }

    final fromUser = _best(_userRules, merchantNormalized);
    if (fromUser != null) {
      return CategoryMatch(
        category: fromUser.category,
        source: RuleSource.user,
        matchedRule: fromUser,
      );
    }

    final fromBuiltIn = _best(BuiltInRules.all, merchantNormalized);
    if (fromBuiltIn != null) {
      return CategoryMatch(
        category: fromBuiltIn.category,
        source: RuleSource.builtIn,
        matchedRule: fromBuiltIn,
      );
    }

    return CategoryMatch.unmatched;
  }

  /// Convenience for callers that only need the category.
  SpendCategory categoryFor(String? merchantNormalized) =>
      categorize(merchantNormalized).category;

  /// The most specific rule in [rules] that matches, or null.
  MerchantRule? _best(List<MerchantRule> rules, String merchant) {
    MerchantRule? best;
    for (final rule in rules) {
      if (!rule.matches(merchant)) continue;
      if (best == null || rule.specificity > best.specificity) best = rule;
    }
    return best;
  }
}
