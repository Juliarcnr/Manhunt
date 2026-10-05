import 'package:flutter/material.dart';

/// Dark-first look (R-UI-01, R-UI-02). The map itself stays a normal light OSM map (R-UI-03).
abstract final class AppColors {
  static const background = Color(0xFF0B0D12);
  static const surface = Color(0xFF151922);
  static const surfaceHigh = Color(0xFF1F2430);
  static const outline = Color(0xFF2C3242);
  static const textMuted = Color(0xFF9AA3B5);

  /// Hunters: hot neon orange-red.
  static const hunter = Color(0xFFFF4D2E);

  /// Players: electric teal.
  static const player = Color(0xFF1DE9B6);

  /// One colour per hunter: warm tones, clearly apart from the players.
  static const hunterPalette = [
    Color(0xFFFF4D2E), // hunter red-orange
    Color(0xFFFF9100), // orange
    Color(0xFFE040FB), // magenta
    Color(0xFFFF1744), // red
    Color(0xFFFF6E40), // deep orange
    Color(0xFFF50057), // pink-red
  ];

  /// One distinct colour per player on the hunters' map (field test feedback).
  /// Avoids the hunter red and the speedhunt yellow.
  static const playerPalette = [
    Color(0xFF1DE9B6), // teal
    Color(0xFF40C4FF), // light blue
    Color(0xFFB388FF), // purple
    Color(0xFFFF80AB), // pink
    Color(0xFFC6FF00), // lime
    Color(0xFF8C9EFF), // indigo
    Color(0xFFFFFFFF), // white
    Color(0xFFFFAB91), // peach
    Color(0xFF64FFDA), // aqua
    Color(0xFFA1887F), // brown
  ];

  /// Speedhunt alert.
  static const speedhunt = Color(0xFFFFC400);
}

abstract final class AppTheme {
  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.hunter,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.hunter,
          onPrimary: Colors.white,
          secondary: AppColors.player,
          onSecondary: Colors.black,
          tertiary: AppColors.speedhunt,
          surface: AppColors.surface,
          surfaceContainerHighest: AppColors.surfaceHigh,
          outline: AppColors.outline,
        );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: shape,
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: shape,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: shape,
          side: const BorderSide(color: AppColors.outline, width: 1.5),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface.withValues(alpha: 0.92),
        selectedColor: AppColors.hunter,
        shape: const StadiumBorder(side: BorderSide(color: AppColors.outline)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: shape,
      ),
    );
  }
}
