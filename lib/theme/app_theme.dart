import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens: a warm, paper-like background instead of stark white,
/// a slate-teal primary instead of default Material blue, and a muted
/// amber used sparingly (streaks/highlights only).
class AppColors {
  AppColors._();

  static const canvas = Color(0xFFF6F4EF);
  static const ink = Color(0xFF1F2421);
  static const deep = Color(0xFF2F4858);
  static const deepLight = Color(0xFF4A6A7C);
  static const moss = Color(0xFF6B8F71);
  static const amber = Color(0xFFC08A3E);
  static const mist = Color(0xFFE4E1D8);
  static const clay = Color(0xFFB5651D);
  static const cardSurface = Color(0xFFFFFFFF);
}

class AppText {
  AppText._();

  static TextTheme textTheme(Brightness brightness) {
    final baseColor =
        brightness == Brightness.light ? AppColors.ink : AppColors.canvas;

    return TextTheme(
      displaySmall: GoogleFonts.fraunces(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: baseColor,
        height: 1.15,
      ),
      titleLarge: GoogleFonts.fraunces(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      bodyLarge: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: baseColor,
        height: 1.4,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: baseColor.withValues(alpha: 0.75),
        height: 1.4,
      ),
      labelLarge: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      labelSmall: GoogleFonts.manrope(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: baseColor.withValues(alpha: 0.6),
        letterSpacing: 0.4,
      ),
    );
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final textTheme = AppText.textTheme(Brightness.light);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.canvas,
      colorScheme: const ColorScheme.light(
        primary: AppColors.deep,
        secondary: AppColors.moss,
        tertiary: AppColors.amber,
        surface: AppColors.cardSurface,
        error: AppColors.clay,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: const IconThemeData(color: AppColors.deep),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.mist, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.deep,
          foregroundColor: AppColors.canvas,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.deep,
          textStyle: textTheme.labelLarge,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.deep,
        foregroundColor: AppColors.canvas,
        elevation: 1,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.mist,
        thickness: 1,
        space: 32,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardSurface,
        hintStyle: TextStyle(
          color: AppColors.ink.withValues(alpha: 0.35),
          fontWeight: FontWeight.w400,
          fontSize: 15,
        ),
        labelStyle: const TextStyle(
          color: AppColors.deepLight,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        floatingLabelStyle: const TextStyle(
          color: AppColors.deepLight,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.mist),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.mist),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.deep, width: 1.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
