import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendwise/core/theme/app_theme.dart';
import 'package:spendwise/data/ei/ei_hours_engine.dart';
import 'package:spendwise/data/ei/ei_models.dart';
import 'package:spendwise/data/repositories/local_repositories.dart';
import 'package:spendwise/features/leave/ei_calculators_screen.dart';
import 'package:spendwise/features/leave/ei_hours_screen.dart';
import 'package:spendwise/features/leave/ei_widgets.dart';
import 'package:spendwise/features/leave/leave_planner_screen.dart';
import 'package:spendwise/state/ei_providers.dart';
import 'package:spendwise/state/providers.dart';

final today = DateTime.utc(2026, 9, 11);

/// 472 hours entered, 32 a week from here, leave on January 15, 2027.
final example = EiTrackerData(
  plannedClaimStart: DateTime.utc(2027, 1, 15),
  jobs: [
    EiJob(
      id: 'a',
      employerName: 'Harmony Family',
      startDate: DateTime.utc(2026, 5, 1),
      usualWeeklyHours: 32,
    ),
  ],
  records: [
    EiHoursRecord(
      id: 'r',
      jobId: 'a',
      periodStart: DateTime.utc(2026, 5, 1),
      periodEnd: DateTime.utc(2026, 9, 11),
      hoursWorked: 472,
    ),
  ],
);

/// Opens [screen] on a 375 × 812 phone.
Future<void> open(
  WidgetTester tester,
  Widget screen, {
  EiTrackerData? data,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (data != null) EiTrackerNotifier.key: data.encode(),
  });
  final layer = await LocalStore.open();
  tester.view.physicalSize = const Size(1125, 2436);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dataLayerProvider.overrideWithValue(layer),
        eiTodayProvider.overrideWithValue(today),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps the date field labelled [label] rather than its floating label,
/// which can sit under the sheet's top edge once scrolled into view.
Future<void> tapDateField(WidgetTester tester, String label) async {
  final field = find.ancestor(
    of: find.text(label),
    matching: find.byType(InkWell),
  );
  await tester.ensureVisible(field.first);
  await tester.pumpAndSettle();
  await tester.tap(field.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the tracker reads at a glance on a phone', (tester) async {
    await open(tester, const EiHoursScreen(), data: example);

    expect(find.text('EI HOURS'), findsOneWidget);
    expect(find.text('472 / 600', findRichText: true), findsOneWidget);
    expect(find.text('78.7%'), findsOneWidget);
    expect(find.text('128 hours remaining'), findsOneWidget);
    expect(find.text('Projected by Jan 2027:'), findsOneWidget);
    // 472 plus 89 weekdays at 6.4 hours.
    expect(find.text('1,041 hours'), findsOneWidget);
    expect(find.text('Currently on track'), findsOneWidget);

    expect(find.text('Estimated EI insurable hours: 472 / 600'), findsOneWidget);
    expect(
      find.text('You have approximately 128 hours remaining.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'At an average of 32 hours/week, you may reach 600 hours in '
        'approximately 4 weeks.',
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text(EiMessages.disclaimer),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(EiMessages.disclaimer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the leave planner shows EI hours eligibility', (tester) async {
    await open(tester, const LeavePlannerScreen(), data: example);

    expect(find.text('Jan 15, 2027'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('EI Hours Eligibility'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Required'), findsOneWidget);
    expect(find.text('600 hours'), findsOneWidget);
    expect(find.text('472 hours'), findsOneWidget);
    expect(find.text('Projected by leave date'), findsOneWidget);
    expect(find.text('128 hours'), findsOneWidget);
    expect(find.text(EiStatus.onTrack.label), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a previous claim shows its warning', (tester) async {
    await open(
      tester,
      const EiHoursScreen(),
      data: example.copyWith(
        hadPreviousClaim: true,
        previousClaimStart: () => DateTime.utc(2026, 6, 1),
      ),
    );
    await tester.scrollUntilVisible(
      find.text(EiMessages.previousClaim),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(EiMessages.previousClaim), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty tracker asks for what it needs, and adds a job', (
    tester,
  ) async {
    await open(tester, const EiHoursScreen());

    expect(find.text('Insufficient information'), findsOneWidget);
    expect(find.text(EiMissingInfo.claimStart.message), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);

    await tester.tap(find.text('Add your job or jobs'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save job'));
    await tester.tap(find.text('Save job'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the employer name'), findsOneWidget);
    expect(find.text('Choose the date you started this job'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Employer name'),
      'Harmony Family',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Usual hours worked per week'),
      '30',
    );
    await tapDateField(tester, 'Employment start date');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save job'));
    await tester.tap(find.text('Save job'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final saved = EiTrackerData.decode(prefs.getString(EiTrackerNotifier.key)!);
    expect(saved.jobs.single.employerName, 'Harmony Family');
    expect(saved.jobs.single.usualWeeklyHours, 30);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the calculators compare paces and count date ranges', (
    tester,
  ) async {
    await open(tester, const EiCalculatorsScreen(), data: example);

    expect(find.text('20 hours/week'), findsOneWidget);
    expect(find.text('40 hours/week'), findsOneWidget);
    expect(find.textContaining('Reach 600 hours around'), findsWidgets);

    await tester.tap(find.text('Annual'));
    await tester.pumpAndSettle();
    expect(find.text('Annual work hours'), findsOneWidget);

    await tester.tap(find.text('Dates'));
    await tester.pumpAndSettle();
    expect(find.text('Hours between two dates'), findsOneWidget);
    expect(find.textContaining('you would accumulate approximately'), findsOne);
    expect(tester.takeException(), isNull);
  });
}
