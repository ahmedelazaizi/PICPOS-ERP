import 'package:flutter/material.dart';

import 'tokens.dart';

/// Material 3 colour roles from the DESIGN.md tokens (lifted from
/// mobile/lib/theme/brand_theme.dart).
ColorScheme picposColorScheme(Brightness b) {
  final light = b == Brightness.light;
  return ColorScheme.fromSeed(seedColor: PicPosTokens.brandBlue, brightness: b).copyWith(
    primary: light ? PicPosTokens.brandBlue : PicPosTokens.brandInkDark,
    onPrimary: light ? PicPosTokens.card : PicPosTokens.brandNavy,
    secondary: light ? PicPosTokens.brandNavy : PicPosTokens.brandSky,
    surface: light ? PicPosTokens.card : PicPosTokens.cardDark,
    onSurface: light ? PicPosTokens.ink : PicPosTokens.inkDark,
    onSurfaceVariant: light ? PicPosTokens.inkSecondary : PicPosTokens.inkMutedDark,
    surfaceContainerLowest: light ? PicPosTokens.card : PicPosTokens.canvasDark,
    surfaceContainerLow: light ? PicPosTokens.canvas : PicPosTokens.canvasDark,
    surfaceContainer: light ? PicPosTokens.canvas : PicPosTokens.cardDark,
    surfaceContainerHighest: light ? PicPosTokens.fieldFill : PicPosTokens.fieldFillDark,
    outline: light ? PicPosTokens.inkMuted : PicPosTokens.inkMutedDark,
    outlineVariant: light ? PicPosTokens.hairline : PicPosTokens.hairlineDark,
    error: PicPosTokens.errorDeep,
  );
}

/// Material type roles mapped to the DESIGN.md Cairo scale (600 body, 700
/// headings and labels).
TextTheme picposTextTheme(Color ink) {
  TextStyle s(double size, FontWeight w, [double? h]) =>
      TextStyle(fontFamily: PicPosFonts.ui, fontSize: size, fontWeight: w, height: h, color: ink);
  return TextTheme(
    displayLarge: s(30, FontWeight.w700),
    displayMedium: s(25, FontWeight.w700),
    displaySmall: s(21, FontWeight.w700),
    headlineLarge: s(21, FontWeight.w700),
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

ThemeData buildPicPosTheme(Brightness b) {
  final cs = picposColorScheme(b);
  final light = b == Brightness.light;
  final radius10 = BorderRadius.circular(PicPosRadii.field);
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: cs,
    fontFamily: PicPosFonts.ui,
    textTheme: picposTextTheme(cs.onSurface),
    scaffoldBackgroundColor: light ? PicPosTokens.canvas : PicPosTokens.canvasDark,
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PicPosRadii.card),
        side: BorderSide(color: cs.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: radius10, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius10, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: radius10, borderSide: BorderSide(color: cs.primary, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PicPosRadii.button)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: light ? PicPosTokens.brandNavy : PicPosTokens.inkDark,
        side: BorderSide(color: cs.outlineVariant, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PicPosRadii.button)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: light ? PicPosTokens.brandBlue : PicPosTokens.brandSky,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: picposTextTheme(cs.onSurface).headlineSmall,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: cs.primary.withValues(alpha: 0.14),
      labelTextStyle: WidgetStatePropertyAll(picposTextTheme(cs.onSurface).labelSmall),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: cs.surface,
      indicatorColor: cs.primary.withValues(alpha: 0.14),
      selectedLabelTextStyle: picposTextTheme(cs.primary).labelMedium,
      unselectedLabelTextStyle: picposTextTheme(cs.onSurfaceVariant).labelMedium,
    ),
    dividerTheme: DividerThemeData(color: cs.outlineVariant, space: 1, thickness: 1),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? cs.primary : (light ? PicPosTokens.switchTrackOff : cs.outlineVariant),
      ),
    ),
  );
}

/// The PicPos surface/text getters (DESIGN.md: `context.picposCard/Field/
/// Hairline/Text/Muted/BrandInk`), resolved for the current brightness.
extension PicPosContext on BuildContext {
  bool get picposIsDark => Theme.of(this).brightness == Brightness.dark;
  Color get picposCanvas => picposIsDark ? PicPosTokens.canvasDark : PicPosTokens.canvas;
  Color get picposCard => picposIsDark ? PicPosTokens.cardDark : PicPosTokens.card;
  Color get picposField => picposIsDark ? PicPosTokens.fieldFillDark : PicPosTokens.fieldFill;
  Color get picposHairline => picposIsDark ? PicPosTokens.hairlineDark : PicPosTokens.hairline;
  Color get picposText => picposIsDark ? PicPosTokens.inkDark : PicPosTokens.ink;
  Color get picposMuted => picposIsDark ? PicPosTokens.inkMutedDark : PicPosTokens.inkMuted;
  Color get picposBrandInk => picposIsDark ? PicPosTokens.brandInkDark : PicPosTokens.brandBlue;
}
