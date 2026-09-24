import 'package:flutter/material.dart';

/// Тема «ТЕЛЕМАСТЕР», портирована с макета сайта.
/// Светлая: тёплая бумага + фирменный красный, лёгкий градиент рисует
/// AppBackground. Тёмная: глубокий navy + приглушённые aurora-свечения.
class AppTheme {
  // Фирменный красный с сайта (кнопки «В корзину», выбранные чипы).
  static const brand = Color(0xFFC8102E);
  static const brandDeep = Color(0xFF9A0B23);
  static const brandSoft = Color(0xFFF9DCE1);

  // Светлая тема «тёплая сепия»: приглушённая, желтоватая —
  // не слепит в темноте. Никакого чистого белого.
  static const paper = Color(0xFFF3E6CC);
  static const cream = Color(0xFFFAF1DE);
  static const sand = Color(0xFFE7D3AC);
  static const cardBorderLight = Color(0xFFD9C69C);
  static const ink = Color(0xFF2A2318);
  static const mutedLight = Color(0xFF8A7A5C);

  // Тёмная тема: почти чёрный navy + приподнятые панели.
  static const night = Color(0xFF0A0F1C);
  static const nightCard = Color(0xFF131B2E);
  static const nightBorder = Color(0xFF273350);

  static const amber = Color(0xFFFFB300);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.light,
    ).copyWith(
      primary: brand,
      onPrimary: Colors.white,
      primaryContainer: brandSoft,
      onPrimaryContainer: brandDeep,
      secondary: brandDeep,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      // Шапка как на сайте: светлая, тёмный текст.
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 1,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: ink,
          letterSpacing: 0.4,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        color: cream,
        shadowColor: const Color(0xFF8A6D3B).withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: cardBorderLight),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 68,
        backgroundColor: cream,
        indicatorColor: brandSoft,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 2,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: brand, width: 1.6),
        ),
        isDense: true,
        filled: true,
        fillColor: cream,
        hintStyle: const TextStyle(color: mutedLight),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      // Пилюли каталога как на сайте: белые, выбранная — красная.
      chipTheme: const ChipThemeData(
        backgroundColor: cream,
        selectedColor: brand,
        checkmarkColor: Colors.white,
        side: BorderSide(color: cardBorderLight),
        shape: StadiumBorder(),
        labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w600),
        secondaryLabelStyle:
            TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? brandSoft
                  : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? brandDeep : mutedLight),
          iconColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? brand : mutedLight),
          side: const WidgetStatePropertyAll(
              BorderSide(color: cardBorderLight)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        dense: true,
      ),
      dividerTheme:
          const DividerThemeData(color: cardBorderLight),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFFE14A5F),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF4A1220),
      onPrimaryContainer: const Color(0xFFFFD9DE),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: night,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: night.withValues(alpha: 0.85),
        foregroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 64,
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.4,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: nightCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: nightBorder.withValues(alpha: 0.7)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 68,
        backgroundColor: Color(0xFF0D1424),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 2,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: nightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: nightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        isDense: true,
        filled: true,
        fillColor: nightCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: nightCard,
        selectedColor: brand,
        checkmarkColor: Colors.white,
        side: BorderSide(color: nightBorder),
        shape: StadiumBorder(),
        labelStyle:
            TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        secondaryLabelStyle:
            TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? brand.withValues(alpha: 0.30)
                  : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? const Color(0xFFFFD9DE)
                  : Colors.white70),
          iconColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? const Color(0xFFFF8A95)
                  : Colors.white54),
          side: const WidgetStatePropertyAll(
              BorderSide(color: nightBorder)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        dense: true,
      ),
      dividerTheme:
          DividerThemeData(color: nightBorder.withValues(alpha: 0.5)),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
