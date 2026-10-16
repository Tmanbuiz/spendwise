import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendwise/features/planning/bills_screen.dart';
import 'package:spendwise/features/planning/backup_screen.dart';
import 'package:spendwise/features/planning/alerts_screen.dart';

import 'screens_test.dart' as fixtures;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> open(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(fixtures.harness(screen));
    await tester.pumpAndSettle();
  }

  testWidgets('bill editor validates and saves a recurring bill', (
    tester,
  ) async {
    await open(tester, const BillsScreen());
    await tester.tap(find.text('Add bill'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'Internet');
    await tester.enterText(find.byType(TextFormField).at(1), '59.99');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Internet'), findsOneWidget);
    expect(find.text('CAD 59.99 · monthly'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('backup has save and preview restore controls', (tester) async {
    await open(tester, const BackupScreen());
    expect(find.text('Save backup'), findsOneWidget);
    expect(find.text('Choose backup to restore'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('alerts explain capture timing and start disabled', (
    tester,
  ) async {
    await open(tester, const AlertsScreen());
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.textContaining('when you reopen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
