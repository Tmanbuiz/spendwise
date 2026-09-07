import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/spending_changes.dart';
import 'package:spendwise/widgets/spending_changes_card.dart';
import 'package:spendwise_parser/spendwise_parser.dart';
import 'spending_insights_test.dart' as fixtures;

void main() {
  test('category changes reconcile to total change across matching days', () {
    final data = fixtures.insights(DateTime(2026, 9, 7), [
      fixtures.purchase(DateTime(2026, 8, 2), 2000),
      fixtures.purchase(DateTime(2026, 9, 2), 5000),
      fixtures.purchase(DateTime(2026, 8, 4), 4000).copyWith(category: SpendCategory.other),
      fixtures.purchase(DateTime(2026, 8, 12), 99999),
      fixtures.purchase(DateTime(2026, 9, 12), 99999),
      fixtures.purchase(DateTime(2026, 9, 2), 99999, currency: 'USD'),
      fixtures.purchase(DateTime(2026, 9, 2), 99999, excluded: true),
    ]);
    final changes = data.categoryChanges;
    expect(changes.first.differenceCents, -4000);
    expect(changes.last.differenceCents, 3000);
    expect(changes.fold<int>(0, (s, c) => s + c.differenceCents), data.comparable.differenceCents);
  });
  test('new categories do not invent percentage growth from zero', () {
    final data = fixtures.insights(DateTime(2026, 9, 7), [fixtures.purchase(DateTime(2026, 9, 2), 5000)]);
    expect(data.categoryChanges.single.percentChange, isNull);
  });
  testWidgets('category drilldown includes the matching purchases from both periods', (tester) async {
    final data = fixtures.insights(DateTime(2026, 9, 7), [
      fixtures.purchase(DateTime(2026, 8, 2), 2000, merchant: 'Prior shop'),
      fixtures.purchase(DateTime(2026, 9, 2), 5000, merchant: 'Current shop'),
      fixtures.purchase(DateTime(2026, 8, 12), 99999, merchant: 'Outside comparison'),
    ]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SpendingChangesCard(data: data)))));
    await tester.tap(find.text('Groceries')); await tester.pumpAndSettle();
    expect(find.text('Current shop'), findsOneWidget);
    expect(find.text('Prior shop'), findsOneWidget);
    expect(find.text('Outside comparison'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('missing prior history asks for statements instead of claiming savings', (tester) async {
    final data = fixtures.insights(DateTime(2026, 9, 7), [fixtures.purchase(DateTime(2026, 9, 2), 5000)]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SpendingChangesCard(data: data))));
    expect(find.text('Build your comparison'), findsOneWidget);
    expect(find.text('Largest increases'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
