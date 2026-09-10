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

  /// Home, auto, tenant and life premiums.
  ///
  /// Its own category rather than folded into Housing or Transportation,
  /// because a premium is a fixed recurring cost that belongs to neither: home
  /// and auto policies are routinely bought from one insurer on one schedule,
  /// and burying them in two different categories hides a bill that is often
  /// among the largest a household pays.
  insurance('insurance', 'Insurance'),

  /// Tuition, registration and application fees.
  ///
  /// Universities charge in a handful of large, irregular amounts rather than
  /// the steady rhythm the other categories assume, so folding them into
  /// Shopping or Health both misstates those and hides the education spend
  /// itself — which for a household applying to schools is one of the larger
  /// lines of the year.
  education('education', 'Education'),

  /// What the bank charges for holding the money.
  ///
  /// Service charges, overdraft and cash-advance fees are real money leaving,
  /// so they count as spending — but they are worth seeing apart from it,
  /// because unlike groceries they are usually avoidable. Mixed into Other
  /// they are invisible; on their own they are an argument for changing
  /// account plan.
  bankFees('bank_fees', 'Bank fees'),

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
