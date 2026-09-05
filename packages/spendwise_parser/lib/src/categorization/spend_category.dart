/// The spending categories SpendWise reports on.
///
/// Fixed set by design: budgets, the dashboard breakdown and the month-over-
/// month comparison all key on these, so they are an enum rather than free
/// text. User customisation happens through merchant rules, which map a
/// merchant to one of these — not by inventing new categories.
enum SpendCategory {
  groceries('groceries', 'Groceries'),
  dining('dining', 'Dining'),
  gas('gas', 'Gas'),
  transportation('transportation', 'Transportation'),
  shopping('shopping', 'Shopping'),
  utilities('utilities', 'Utilities'),
  phoneInternet('phone_internet', 'Phone & Internet'),
  subscriptions('subscriptions', 'Subscriptions'),
  housing('housing', 'Housing'),
  health('health', 'Health'),
  entertainment('entertainment', 'Entertainment'),
  other('other', 'Other');

  const SpendCategory(this.slug, this.displayName);

  /// Stable database value. Never change these — they are persisted.
  final String slug;

  /// Label shown in the UI.
  final String displayName;

  static SpendCategory fromSlug(String slug) {
    for (final category in SpendCategory.values) {
      if (category.slug == slug) return category;
    }
    return SpendCategory.other;
  }
}
