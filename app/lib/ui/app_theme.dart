import 'package:flutter/material.dart';

/// Forest-ink utility theme — cool mist surfaces, deep green, muted gold.
/// Avoids purple-on-white, cream+terracotta, and broadsheet looks.
///
/// Typography uses bundled Fraunces + Source Sans 3 (no runtime font fetch).
class ChesshihiTheme {
  static const Color forest = Color(0xFF1A4A3A);
  static const Color forestDeep = Color(0xFF0E2F26);
  static const Color mist = Color(0xFFE6EEEC);
  static const Color mistMid = Color(0xFFD2E0DB);
  static const Color ink = Color(0xFF1C2422);
  static const Color gold = Color(0xFFB08D3A);

  static const String displayFont = 'Fraunces';
  static const String bodyFont = 'SourceSans3';

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: forest,
      brightness: Brightness.light,
      primary: forest,
      onPrimary: Colors.white,
      secondary: gold,
      onSecondary: ink,
      surface: mist,
      onSurface: ink,
      error: const Color(0xFF8B2E2E),
    );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: mist,
      fontFamily: bodyFont,
    );

    TextStyle display(TextStyle? s) => (s ?? const TextStyle()).copyWith(
          fontFamily: displayFont,
          fontWeight: FontWeight.w700,
          color: forestDeep,
          letterSpacing: -0.5,
        );

    TextStyle body(TextStyle? s) => (s ?? const TextStyle()).copyWith(
          fontFamily: bodyFont,
          color: ink,
        );

    final textTheme = base.textTheme.copyWith(
      displaySmall: display(base.textTheme.displaySmall),
      headlineMedium: display(base.textTheme.headlineMedium),
      headlineSmall: display(base.textTheme.headlineSmall).copyWith(
            fontWeight: FontWeight.w600,
          ),
      titleLarge: display(base.textTheme.titleLarge).copyWith(
            fontWeight: FontWeight.w600,
          ),
      titleMedium: body(base.textTheme.titleMedium).copyWith(
            fontWeight: FontWeight.w600,
          ),
      titleSmall: body(base.textTheme.titleSmall),
      bodyLarge: body(base.textTheme.bodyLarge),
      bodyMedium: body(base.textTheme.bodyMedium),
      bodySmall: body(base.textTheme.bodySmall),
      labelLarge: body(base.textTheme.labelLarge).copyWith(
            fontWeight: FontWeight.w700,
          ),
      labelMedium: body(base.textTheme.labelMedium),
      labelSmall: body(base.textTheme.labelSmall),
    );

    return base.copyWith(
      textTheme: textTheme,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: bodyFont,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return forest;
          return null;
        }),
      ),
    );
  }

  static BoxDecoration atmosphere(ColorScheme scheme) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          mist,
          mistMid.withValues(alpha: 0.95),
          scheme.primaryContainer.withValues(alpha: 0.28),
          mist,
        ],
        stops: const [0.0, 0.35, 0.7, 1.0],
      ),
    );
  }
}
