/// Modern theme with glass morphism and vibrant accents.
/// Supports both dark and light modes.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Dark Theme Colors ──────────────────────────────────────
  static const _darkAccent = Color(0xFF7C4DFF);
  static const _darkAccent2 = Color(0xFF00E5FF);
  static const _darkBg = Color(0xFF0B0B1A);
  static const _darkSurface = Color(0xFF16162A);
  static const _darkCard = Color(0xFF1E1E3A);
  static const _danger = Color(0xFFFF5252);
  static const _success = Color(0xFF00E676);
  static const _darkText = Color(0xFFE8E8F0);
  static const _darkTextDim = Color(0xFFB0B0C8);

  // ── Light Theme Colors ─────────────────────────────────────
  static const _lightAccent = Color(0xFF5B3CC4);
  static const _lightAccent2 = Color(0xFF00B8D4);
  static const _lightBg = Color(0xFFF4F4FA);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightCard = Color(0xFFFFFFFF);
  static const _lightText = Color(0xFF1A1A2E);
  static const _lightTextDim = Color(0xFF5A5A70);

  static ThemeData get darkTheme {
    const scheme = ColorScheme.dark(
      primary: _darkAccent,
      secondary: _darkAccent2,
      surface: _darkSurface,
      error: _danger,
      onPrimary: Colors.white,
      onSurface: _darkText,
    );

    final textTheme = GoogleFonts.interTextTheme().copyWith(
      headlineLarge: const TextStyle(
          fontSize: 26, fontWeight: FontWeight.w700, color: _darkText),
      headlineMedium: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700, color: _darkText),
      titleLarge: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, color: _darkText),
      titleMedium: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: _darkText),
      bodyLarge: const TextStyle(fontSize: 13.5, color: _darkTextDim),
      bodyMedium: const TextStyle(fontSize: 12, color: _darkTextDim),
      bodySmall: const TextStyle(fontSize: 11, color: _darkTextDim),
      labelLarge: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
    );

    return _buildTheme(
      scheme: scheme,
      textTheme: textTheme,
      bg: _darkBg,
      surface: _darkSurface,
      card: _darkCard,
      accent: _darkAccent,
      textDim: _darkTextDim,
      border: Colors.white12,
    );
  }

  static ThemeData get lightTheme {
    const scheme = ColorScheme.light(
      primary: _lightAccent,
      secondary: _lightAccent2,
      surface: _lightSurface,
      error: _danger,
      onPrimary: Colors.white,
      onSurface: _lightText,
    );

    final textTheme = GoogleFonts.interTextTheme().copyWith(
      headlineLarge: const TextStyle(
          fontSize: 26, fontWeight: FontWeight.w700, color: _lightText),
      headlineMedium: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700, color: _lightText),
      titleLarge: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, color: _lightText),
      titleMedium: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: _lightText),
      bodyLarge: const TextStyle(fontSize: 13.5, color: _lightTextDim),
      bodyMedium: const TextStyle(fontSize: 12, color: _lightTextDim),
      bodySmall: const TextStyle(fontSize: 11, color: _lightTextDim),
      labelLarge: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
    );

    return _buildTheme(
      scheme: scheme,
      textTheme: textTheme,
      bg: _lightBg,
      surface: _lightSurface,
      card: _lightCard,
      accent: _lightAccent,
      textDim: _lightTextDim,
      border: const Color(0xFFE0E0EC),
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme scheme,
    required TextTheme textTheme,
    required Color bg,
    required Color surface,
    required Color card,
    required Color accent,
    required Color textDim,
    required Color border,
  }) {
    final isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,

      // Card
      cardTheme: CardTheme(
        color: card,
        elevation: isDark ? 0 : 1,
        shadowColor: isDark ? null : Colors.black.withValues(alpha: 0.08),
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16))),
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: isDark ? 4 : 2,
          shadowColor: accent.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: accent.withValues(alpha: 0.25),
        labelStyle: TextStyle(fontSize: 13, color: textDim),
        secondaryLabelStyle: TextStyle(
            fontSize: 13, color: isDark ? _darkText : _lightText),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? surface : const Color(0xFFF0F0F8),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        labelStyle: TextStyle(color: textDim),
      ),

      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: accent.withValues(alpha: 0.15),
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.12),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),

      // Navigation bar
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.2),
        surfaceTintColor: Colors.transparent,
        height: 60,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? accent : textDim)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.selected) ? accent : textDim)),
      ),

      // Dialog
      dialogTheme: DialogTheme(
        backgroundColor: card,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20))),
      ),

      // Snackbar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: isDark ? _darkText : _lightText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return accent;
          return isDark ? Colors.grey : Colors.grey.shade400;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return accent.withValues(alpha: 0.5);
          }
          return isDark ? Colors.white12 : Colors.grey.shade300;
        }),
      ),
    );
  }
}
