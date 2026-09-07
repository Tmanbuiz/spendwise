import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise/data/models/budget.dart';
import 'package:spendwise/features/budgets/budgets_screen.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/state/providers.dart';
import 'package:spendwise/widgets/insight_widgets.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

import 'screens_test.dart' as fixtures;

final previewNow = DateTime(2026, 9, 15, 18);
final sampleRows = [
  for (var day = 1; day <= 15; day++)
    fixtures.sample(
      id: 'd$day',
      cents: day % 3 == 0 ? 7890 : 1250 + day * 63,
      merchant: day % 3 == 0 ? 'Whole Foods Market' : 'Blue Bottle Coffee',
      when: DateTime(2026, 9, day, 9),
      category: day % 3 == 0 ? SpendCategory.groceries : SpendCategory.dining,
    ),
  fixtures.sample(
    id: 'rent',
    cents: 120000,
    merchant: 'Monthly rent',
    when: DateTime(2026, 9, 1),
    category: SpendCategory.housing,
  ),
  fixtures.sample(
    id: 'train',
    cents: 7800,
    merchant: 'Transit pass',
    when: DateTime(2026, 9, 3),
    category: SpendCategory.transportation,
  ),
  for (var month = 4; month <= 8; month++)
    fixtures.sample(
      id: 'p$month',
      cents: 180000 + month * 10300,
      merchant: 'Previous period',
      when: DateTime(2026, month, 3),
      category: SpendCategory.groceries,
    ),
];
const sampleBudgets = [
  Budget(id: 'all', amountCents: 320000),
  Budget(id: 'food', amountCents: 65000, category: SpendCategory.groceries),
  Budget(id: 'dining', amountCents: 30000, category: SpendCategory.dining),
  Budget(id: 'home', amountCents: 150000, category: SpendCategory.housing),
];

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.spendwise/notifications/stream'),
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.spendwise/notifications/stream'),
          null,
        );
  });
  setUpAll(() async {
    final fontPath = Platform.environment['SPENDWISE_PREVIEW_FONT'];
    if (fontPath != null) {
      for (final family in ['Roboto', 'Ahem']) {
        final loader = FontLoader(family)
          ..addFont(
            Future.value(
              ByteData.sublistView(File(fontPath).readAsBytesSync()),
            ),
          );
        await loader.load();
      }
      final iconPath =
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
      if (File(iconPath).existsSync()) {
        final loader = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(
              ByteData.sublistView(File(iconPath).readAsBytesSync()),
            ),
          );
        await loader.load();
      }
    }
  });

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    final output = Platform.environment['SPENDWISE_PREVIEW_DIR'];
    if (output == null) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('phone navigation, populated screens and light/dark previews', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: fixtures.harness(
          const SpendWiseApp(),
          now: previewNow,
          fullApp: true,
          transactions: sampleRows,
          budgets: sampleBudgets,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'spendwise-home');
    await tester.tap(find.widgetWithText(NavigationDestination, 'Insights'));
    await tester.pumpAndSettle();
    expect(find.text('Average purchase'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'spendwise-insights');
    await tester.scrollUntilVisible(find.byType(DailySpendingChart), 300, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(DailySpendingChart), matching: find.byType(GestureDetector)).first);
    await tester.pumpAndSettle();
    expect(find.text(r'$1,213.13'), findsOneWidget);
    await tester.drag(
      find.byType(ListView).hitTestable().last,
      const Offset(0, -560),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Budgets'));
    await tester.pumpAndSettle();
    expect(find.text('Daily budget left'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'spendwise-budgets');
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Home'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'spendwise-dark');
  });

  testWidgets('budget edits preserve cents and reject malformed amounts', (
    tester,
  ) async {
    await tester.pumpWidget(
      fixtures.harness(
        const BudgetsScreen(),
        budgets: const [Budget(id: 'b', amountCents: 12345)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly budget'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '123.45'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '12.3.4');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
      expect(find.text('Enter an amount greater than zero'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '123.45');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(BudgetsScreen)));
      expect(container.read(budgetsProvider).value!.single.amountCents, 12345);
  });

  testWidgets('compact phone and large text keep budget guidance usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      fixtures.harness(
        const BudgetsScreen(),
        transactions: sampleRows,
        budgets: sampleBudgets,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

