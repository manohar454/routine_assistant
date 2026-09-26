import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Color tokens ────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Light palette
  static const canvas      = Color(0xFFF5F3EE);
  static const ink         = Color(0xFF1A1F1C);
  static const deep        = Color(0xFF2B4459);
  static const deepLight   = Color(0xFF4F7A8A);
  static const moss        = Color(0xFF5A8A60);
  static const mossLight   = Color(0xFFDDF0DF);
  static const amber       = Color(0xFFC08A3E);
  static const amberLight  = Color(0xFFFBF0E0);
  static const clay        = Color(0xFFB5502A);
  static const clayLight   = Color(0xFFFBE8E2);
  static const mist        = Color(0xFFE2DFD6);
  static const mistDark    = Color(0xFFCCC9C0);
  static const cardSurface = Color(0xFFFFFFFF);
  static const inkSubtle   = Color(0xFF8A8A80);

  // Dark palette
  static const darkCanvas      = Color(0xFF111614);
  static const darkSurface     = Color(0xFF1C2220);
  static const darkCard        = Color(0xFF232B28);
  static const darkBorder      = Color(0xFF2E3A37);
  static const darkInk         = Color(0xFFECEAE4);
  static const darkInkSubtle   = Color(0xFF8A9490);
  static const darkDeep        = Color(0xFF6BAAC0);
  static const darkMoss        = Color(0xFF7AB880);
  static const darkAmber       = Color(0xFFD4A055);
  static const darkClay        = Color(0xFFE07050);

  // Semantic
  static Color taskFixed(bool dark)    => dark ? const Color(0xFF3A2A18) : amberLight;
  static Color taskFlexible(bool dark) => dark ? const Color(0xFF1A2E1E) : mossLight;
  static Color burnoutLow(bool dark)   => dark ? const Color(0xFF1A2E1E) : mossLight;
  static Color burnoutMid(bool dark)   => dark ? const Color(0xFF3A2A18) : amberLight;
  static Color burnoutHigh(bool dark)  => dark ? const Color(0xFF3A1A14) : clayLight;
}

// ─── Spacing ──────────────────────────────────────────────────────────────────

class AppSpacing {
  AppSpacing._();
  static const xs  = 4.0;
  static const sm  = 8.0;
  static const md  = 16.0;
  static const lg  = 24.0;
  static const xl  = 32.0;
  static const xxl = 48.0;
  static const pagePad = EdgeInsets.fromLTRB(20, 12, 20, 100);
}

// ─── Radius ───────────────────────────────────────────────────────────────────

class AppRadius {
  AppRadius._();
  static const sm  = Radius.circular(10);
  static const md  = Radius.circular(16);
  static const lg  = Radius.circular(20);
  static const xl  = Radius.circular(28);
  static const pill = Radius.circular(100);
}

// ─── Typography ───────────────────────────────────────────────────────────────

class AppText {
  AppText._();

  static TextTheme textTheme(Brightness b) {
    final base = b == Brightness.light ? AppColors.ink : AppColors.darkInk;
    final subtle = b == Brightness.light ? AppColors.inkSubtle : AppColors.darkInkSubtle;

    return TextTheme(
      // Hero numbers / big date
      displayLarge: GoogleFonts.fraunces(
        fontSize: 40, fontWeight: FontWeight.w700, color: base, height: 1.1,
      ),
      displayMedium: GoogleFonts.fraunces(
        fontSize: 32, fontWeight: FontWeight.w600, color: base, height: 1.15,
      ),
      displaySmall: GoogleFonts.fraunces(
        fontSize: 26, fontWeight: FontWeight.w600, color: base, height: 1.2,
      ),
      // Section titles
      headlineMedium: GoogleFonts.fraunces(
        fontSize: 22, fontWeight: FontWeight.w600, color: base,
      ),
      headlineSmall: GoogleFonts.fraunces(
        fontSize: 18, fontWeight: FontWeight.w600, color: base,
      ),
      titleLarge: GoogleFonts.fraunces(
        fontSize: 18, fontWeight: FontWeight.w600, color: base,
      ),
      titleMedium: GoogleFonts.manrope(
        fontSize: 15, fontWeight: FontWeight.w700, color: base,
      ),
      titleSmall: GoogleFonts.manrope(
        fontSize: 13, fontWeight: FontWeight.w700, color: base,
      ),
      // Body
      bodyLarge: GoogleFonts.manrope(
        fontSize: 15, fontWeight: FontWeight.w500, color: base, height: 1.5,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 13, fontWeight: FontWeight.w400, color: subtle, height: 1.5,
      ),
      bodySmall: GoogleFonts.manrope(
        fontSize: 11, fontWeight: FontWeight.w400, color: subtle, height: 1.4,
      ),
      // Labels / chips
      labelLarge: GoogleFonts.manrope(
        fontSize: 14, fontWeight: FontWeight.w700, color: base, letterSpacing: 0.1,
      ),
      labelMedium: GoogleFonts.manrope(
        fontSize: 12, fontWeight: FontWeight.w600, color: subtle, letterSpacing: 0.2,
      ),
      labelSmall: GoogleFonts.manrope(
        fontSize: 10, fontWeight: FontWeight.w700, color: subtle, letterSpacing: 0.5,
      ),
    );
  }
}

// ─── Theme builder ────────────────────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark()  => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;
    final text   = AppText.textTheme(b);

    final colorScheme = isDark
        ? const ColorScheme.dark(
            primary:          AppColors.darkDeep,
            onPrimary:        AppColors.darkCanvas,
            secondary:        AppColors.darkMoss,
            onSecondary:      AppColors.darkCanvas,
            tertiary:         AppColors.darkAmber,
            surface:          AppColors.darkCard,
            onSurface:        AppColors.darkInk,
            error:            AppColors.darkClay,
            outline:          AppColors.darkBorder,
          )
        : const ColorScheme.light(
            primary:          AppColors.deep,
            onPrimary:        AppColors.cardSurface,
            secondary:        AppColors.moss,
            onSecondary:      AppColors.cardSurface,
            tertiary:         AppColors.amber,
            surface:          AppColors.cardSurface,
            onSurface:        AppColors.ink,
            error:            AppColors.clay,
            outline:          AppColors.mist,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? AppColors.darkCanvas : AppColors.canvas,
      textTheme: text,

      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? AppColors.darkCanvas : AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(
          color: isDark ? AppColors.darkDeep : AppColors.deep,
        ),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        color: isDark ? AppColors.darkCard : AppColors.cardSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.mist,
          ),
        ),
        margin: EdgeInsets.zero,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor:
              isDark ? AppColors.darkDeep : AppColors.deep,
          foregroundColor:
              isDark ? AppColors.darkCanvas : AppColors.cardSurface,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor:
              isDark ? AppColors.darkInk : AppColors.ink,
          side: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.mist,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: text.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor:
              isDark ? AppColors.darkDeep : AppColors.deep,
          textStyle: text.labelLarge,
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor:
            isDark ? AppColors.darkDeep : AppColors.deep,
        foregroundColor:
            isDark ? AppColors.darkCanvas : AppColors.cardSurface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.darkBorder : AppColors.mist,
        thickness: 1,
        space: 32,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkSurface : AppColors.cardSurface,
        hintStyle: TextStyle(
          color: isDark
              ? AppColors.darkInkSubtle
              : AppColors.ink.withValues(alpha: 0.35),
          fontWeight: FontWeight.w400,
          fontSize: 15,
        ),
        labelStyle: TextStyle(
          color: isDark ? AppColors.darkDeep : AppColors.deepLight,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        floatingLabelStyle: TextStyle(
          color: isDark ? AppColors.darkDeep : AppColors.deepLight,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.mist,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.mist,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkDeep : AppColors.deep,
            width: 1.5,
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.cardSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        elevation: 0,
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.zero,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium,
        iconColor: isDark ? AppColors.darkDeep : AppColors.deepLight,
      ),

      chipTheme: ChipThemeData(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.canvas,
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.mist,
        ),
        shape: const StadiumBorder(),
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            isDark ? AppColors.darkCard : AppColors.ink,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: isDark ? AppColors.darkInk : AppColors.cardSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─── Convenience extensions ───────────────────────────────────────────────────

extension ThemeX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  ThemeData get theme => Theme.of(this);
  TextTheme get text => Theme.of(this).textTheme;
  ColorScheme get colors => Theme.of(this).colorScheme;
}
