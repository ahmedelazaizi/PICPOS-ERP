import 'package:flutter/material.dart';

/// Brand tokens from DESIGN.md, expressed through Material 3 colour roles,
/// the Material type scale (Cairo), and shape — per the Android reference:
/// Material governs structure; brand comes in through theming.
class Brand {
  static const blue = Color(0xFF0250D3);
  static const navy = Color(0xFF012258);
  static const sky = Color(0xFF4A80E8);
  static const inkDark = Color(0xFF7DA6F5);
  static const canvas = Color(0xFFF2F5FA);
  static const card = Color(0xFFFFFFFF);
  static const fieldFill = Color(0xFFF4F7FC);
  static const hairline = Color(0xFFDCE3EE);
  static const inkSecondary = Color(0xFF374151);
  static const inkMuted = Color(0xFF6B7280);
  static const canvasDark = Color(0xFF0A1220);
  static const cardDark = Color(0xFF121C2E);
  static const fieldFillDark = Color(0xFF18243A);
  static const hairlineDark = Color(0xFF243247);
  static const inkMutedDark = Color(0xFF94A3B8);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const error = Color(0xFFDC2626);
}

ColorScheme _scheme(Brightness b) {
  final light = b == Brightness.light;
  return ColorScheme.fromSeed(seedColor: Brand.blue, brightness: b).copyWith(
    primary: light ? Brand.blue : Brand.inkDark,
    onPrimary: light ? Colors.white : Brand.navy,
    secondary: light ? Brand.navy : Brand.sky,
    surface: light ? Brand.card : Brand.cardDark,
    onSurface: light ? Colors.black : Colors.white,
    onSurfaceVariant: light ? Brand.inkSecondary : Brand.inkMutedDark,
    surfaceContainerLowest: light ? Brand.card : Brand.canvasDark,
    surfaceContainerLow: light ? Brand.canvas : Brand.canvasDark,
    surfaceContainerHighest: light ? Brand.fieldFill : Brand.fieldFillDark,
    outline: light ? Brand.inkMuted : Brand.inkMutedDark,
    outlineVariant: light ? Brand.hairline : Brand.hairlineDark,
    error: Brand.error,
  );
}

/// Material type roles mapped to the DESIGN.md Cairo scale (sizes in sp via
/// the framework's text scaling).
TextTheme _text(Color ink) {
  TextStyle s(double size, FontWeight w, [double? h]) =>
      TextStyle(fontFamily: 'Cairo', fontSize: size, fontWeight: w, height: h, color: ink);
  return TextTheme(
    displayLarge: s(30, FontWeight.w700),
    displayMedium: s(25, FontWeight.w700),
    displaySmall: s(21, FontWeight.w700),
    headlineMedium: s(19, FontWeight.w700),
    headlineSmall: s(17, FontWeight.w700),
    titleLarge: s(16, FontWeight.w700),
    titleMedium: s(15, FontWeight.w700),
    titleSmall: s(14, FontWeight.w700),
    bodyLarge: s(15, FontWeight.w600, 1.65),
    bodyMedium: s(14, FontWeight.w600, 1.65),
    bodySmall: s(13, FontWeight.w600, 1.6),
    labelLarge: s(14, FontWeight.w700),
    labelMedium: s(13, FontWeight.w700),
    labelSmall: s(12, FontWeight.w700),
  );
}

ThemeData buildTheme(Brightness b) {
  final cs = _scheme(b);
  final light = b == Brightness.light;
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    fontFamily: 'Cairo',
    textTheme: _text(cs.onSurface),
    scaffoldBackgroundColor: light ? Brand.canvas : Brand.canvasDark,
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    dividerTheme: DividerThemeData(color: cs.outlineVariant, space: 1),
  );
}
