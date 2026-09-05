import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/formatters.dart';
import 'package:spendwise/core/theme/app_theme.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

void main() {
  group('money formatting', () {
    test('formats cents without floating point drift', () {
      expect(Fmt.money(1999), r'$19.99');
      expect(Fmt.money(0), r'$0.00');
      expect(Fmt.money(124999), r'$1,249.99');
    });

    test('formats foreign currency with a distinguishable symbol', () {
      expect(Fmt.money(1000, currency: 'USD'), contains(r'US$'));
      expect(Fmt.money(1000, currency: 'EUR'), contains('€'));
    });

    test('compact form drops the cents', () {
      expect(Fmt.moneyCompact(124999), r'$1,250');
    });

    test('signed form marks direction', () {
      expect(Fmt.money(500, sign: true), startsWith('+'));
      expect(Fmt.money(-500, sign: true), startsWith('-'));
    });
  });

  group('relative day labels', () {
    test('today and yesterday are named', () {
      final now = DateTime.now();
      expect(Fmt.relativeDay(now), 'Today');
      expect(
        Fmt.relativeDay(now.subtract(const Duration(days: 1))),
        'Yesterday',
      );
    });
  });

  group('theme', () {
    test('every category has a distinct colour', () {
      final colours = SpendCategory.values
          .map(AppTheme.categoryColor)
          .map((c) => c.toARGB32())
          .toSet();
      expect(colours.length, SpendCategory.values.length);
    });

    test('every category and event type has an icon', () {
      for (final category in SpendCategory.values) {
        expect(AppTheme.categoryIcon(category), isNotNull);
      }
      for (final type in TransactionEventType.values) {
        expect(AppTheme.eventIcon(type), isNotNull);
      }
    });

    test('light and dark themes both build', () {
      expect(AppTheme.light().brightness, Brightness.light);
      expect(AppTheme.dark().brightness, Brightness.dark);
    });
  });
}
