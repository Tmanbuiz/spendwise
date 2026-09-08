import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

/// SpendWise's visual language.
///
/// The palette is built around a single deep indigo brand colour with a warm
/// secondary, because a finance app is read at a glance: money-in and
/// money-out need to be distinguishable before any text is parsed, and the
/// category colours need to stay separable in a donut chart in both themes.
abstract final class AppTheme {
  static const Color brand = Color(0xFF087F79);
  static const Color brandBright = Color(0xFF65E2CB);
  static const Color navy = Color(0xFF122D3B);
  static const Color positive = Color(0xFF059669);
  static const Color negative = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);

  static const double radius = 20;
  static const double radiusSmall = 12;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
    );

    final surface = isDark ? const Color(0xFF0D1B24) : const Color(0xFFF3F6F7);
    final card = isDark ? const Color(0xFF172B35) : Colors.white;

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        surface: surface,
        primary: isDark ? brandBright : brand,
        onPrimary: isDark ? navy : Colors.white,
        onSurface: isDark ? const Color(0xFFE7F0F2) : navy,
        onSurfaceVariant: isDark
            ? const Color(0xFFB0C3CC)
            : const Color(0xFF566B76),
      ),
      scaffoldBackgroundColor: surface,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(
            color: isDark ? const Color(0xFF263E49) : const Color(0xFFE3EBED),
          ),
        ),
      ),
      textTheme: base.textTheme
          .apply(fontFamilyFallback: const <String>['SF Pro Display', 'Roboto'])
          .copyWith(
            displaySmall: base.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
            ),
            headlineMedium: base.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall + 2),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall + 2),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: (isDark ? brandBright : brand).withValues(alpha: 0.14),
        elevation: 0,
        height: 76,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        space: 1,
        thickness: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide.none,
      ),
    );
  }

  /// A distinct, order-stable colour per category.
  ///
  /// Hand-picked rather than generated: a donut chart needs neighbouring
  /// slices to stay separable, which a hue rotation does not guarantee.
  static Color categoryColor(SpendCategory category) {
    switch (category) {
      case SpendCategory.groceries:
        return const Color(0xFF16A34A);
      case SpendCategory.dining:
        return const Color(0xFFEA580C);
      case SpendCategory.gas:
        return const Color(0xFF0891B2);
      case SpendCategory.transportation:
        return const Color(0xFF2563EB);
      case SpendCategory.shopping:
        return const Color(0xFFDB2777);
      case SpendCategory.utilities:
        return const Color(0xFF65A30D);
      case SpendCategory.phoneInternet:
        return const Color(0xFF7C3AED);
      case SpendCategory.subscriptions:
        return const Color(0xFF9333EA);
      case SpendCategory.housing:
        return const Color(0xFF0D9488);
      case SpendCategory.health:
        return const Color(0xFFE11D48);
      case SpendCategory.entertainment:
        return const Color(0xFFF59E0B);
      case SpendCategory.other:
        return const Color(0xFF64748B);
    }
  }

  static IconData categoryIcon(SpendCategory category) {
    switch (category) {
      case SpendCategory.groceries:
        return Icons.local_grocery_store_outlined;
      case SpendCategory.dining:
        return Icons.restaurant_outlined;
      case SpendCategory.gas:
        return Icons.local_gas_station_outlined;
      case SpendCategory.transportation:
        return Icons.directions_transit_outlined;
      case SpendCategory.shopping:
        return Icons.shopping_bag_outlined;
      case SpendCategory.utilities:
        return Icons.bolt_outlined;
      case SpendCategory.phoneInternet:
        return Icons.wifi_outlined;
      case SpendCategory.subscriptions:
        return Icons.autorenew_outlined;
      case SpendCategory.housing:
        return Icons.home_outlined;
      case SpendCategory.health:
        return Icons.favorite_outline;
      case SpendCategory.entertainment:
        return Icons.movie_outlined;
      case SpendCategory.other:
        return Icons.category_outlined;
    }
  }

  static IconData eventIcon(TransactionEventType type) {
    switch (type) {
      case TransactionEventType.purchase:
        return Icons.arrow_upward_rounded;
      case TransactionEventType.refund:
        return Icons.arrow_downward_rounded;
      case TransactionEventType.payment:
        return Icons.credit_score_outlined;
      case TransactionEventType.transfer:
        return Icons.swap_horiz_rounded;
      case TransactionEventType.declined:
        return Icons.block_outlined;
      case TransactionEventType.unknown:
        return Icons.help_outline_rounded;
    }
  }
}
