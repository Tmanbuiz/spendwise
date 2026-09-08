import 'package:spendwise_parser/spendwise_parser.dart';

import 'spending_insights.dart';

class CategoryChange {
  const CategoryChange(this.category, this.currentCents, this.previousCents);
  final SpendCategory category;
  final int currentCents, previousCents;
  int get differenceCents => currentCents - previousCents;
  double? get percentChange =>
      previousCents == 0 ? null : differenceCents / previousCents;
}

extension SpendingChanges on SpendingInsights {
  List<CategoryChange> get categoryChanges {
    final currentTotals = {
      for (final c in comparable.current.byCategory) c.category: c.amountCents,
    };
    final priorTotals = {
      for (final c in comparable.previous.byCategory) c.category: c.amountCents,
    };
    final changes = {...currentTotals.keys, ...priorTotals.keys}
        .map(
          (category) => CategoryChange(
            category,
            currentTotals[category] ?? 0,
            priorTotals[category] ?? 0,
          ),
        )
        .toList();
    changes.sort((a, b) {
      final magnitude = b.differenceCents.abs().compareTo(
        a.differenceCents.abs(),
      );
      return magnitude != 0
          ? magnitude
          : a.category.slug.compareTo(b.category.slug);
    });
    return changes;
  }
}
