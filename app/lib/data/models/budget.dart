import 'package:spendwise_parser/spendwise_parser.dart';

/// A monthly spending limit, either overall or for one category.
class Budget {
  const Budget({
    required this.id,
    required this.amountCents,
    this.category,
    this.currency = 'CAD',
  });

  final String id;

  /// Null means this is the overall monthly budget.
  final SpendCategory? category;

  final int amountCents;
  final String currency;

  bool get isOverall => category == null;

  double get amount => amountCents / 100.0;

  Budget copyWith({int? amountCents, SpendCategory? category}) => Budget(
        id: id,
        amountCents: amountCents ?? this.amountCents,
        category: category ?? this.category,
        currency: currency,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'category': category?.slug,
        'amount_cents': amountCents,
        'currency': currency,
      };

  static Budget fromJson(Map<String, Object?> json) {
    final slug = json['category'] as String?;
    return Budget(
      id: (json['id'] as String?) ?? '',
      category: slug == null ? null : SpendCategory.fromSlug(slug),
      amountCents: (json['amount_cents'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] as String?) ?? 'CAD',
    );
  }
}

/// Budget plus the spending measured against it.
class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.spentCents,
  });

  final Budget budget;
  final int spentCents;

  int get remainingCents => budget.amountCents - spentCents;

  bool get isOverBudget => spentCents > budget.amountCents;

  /// 0..1 for the bar; values over budget clamp so the bar cannot overflow,
  /// while [isOverBudget] still drives the colour change.
  double get fraction {
    if (budget.amountCents <= 0) return 0;
    return (spentCents / budget.amountCents).clamp(0.0, 1.0);
  }
}
