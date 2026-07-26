import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/brand.dart';
import 'app_colors.dart';
import 'picpos_theme.dart';

/// App theme configuration with RTL Arabic support
/// Optimized for compact, readable interface
///
/// ── طبقة العلامة ──────────────────────────────────────────────────────────
/// المنتجان بيشاركوا نفس الـ٣٠ شاشة (١٨٥٠٠ سطر)، فنسخها لكل علامة مستحيل
/// صيانته وتعديلها في مكانها بيغيّر شكل UralCash عند كل عميل قايم. الحل إن
/// كل الشكل بيتحدد من `ThemeData` واحدة، والفرع هنا.
///
/// `Brand.isPicPos` **ثابت وقت الترجمة**، فالشرط بيتحسم في البناء: نسخة
/// UralCash مبتشوفش `PicPosTheme` أصلاً، وThemeData بتاعتها هي بالحرف نفس
/// الكود اللي كان موجود قبل الطبقة دي — الفروع الـ`_uralCash*` تحت اتنقلت
/// كما هي بدون تغيير سطر واحد.
class AppTheme {
  AppTheme._();

  /// أي لغة تصميم البناء ده شغّال بيها. موجودة عشان الاختبارات تتحقق من
  /// الفرع من غير ما تبني `ThemeData` — بناؤها بيستدعي `GoogleFonts` لأوزان
  /// مش مضمّنة في الـ assets، فبيرمي في بيئة الاختبار.
  ///
  /// الفرع هو الحاجة الوحيدة اللي ممكن تنكسر هنا: قيم UralCash نفسها اتنقلت
  /// حرفياً لـ [_uralCashLightTheme] و[_uralCashDarkTheme] من غير تغيير سطر.
  static String get designLanguage => Brand.isPicPos ? 'picpos' : 'uralcash';

  static ThemeData get lightTheme =>
      Brand.isPicPos ? PicPosTheme.lightTheme : _uralCashLightTheme;

  static ThemeData get darkTheme =>
      Brand.isPicPos ? PicPosTheme.darkTheme : _uralCashDarkTheme;

  static ThemeData get _uralCashLightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        error: AppColors.error,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.surface,
      textTheme: _buildTextTheme(Brightness.light),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 48, // Reduced from default 56
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 16, // Reduced from 20
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 1, // Reduced from 2
        shadowColor: Colors.black.withValues(alpha: 0.08),
        margin: const EdgeInsets.all(4), // Reduced margin
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ), // Reduced from 12
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 1, // Reduced from 2
          minimumSize: const Size(64, 36), // Compact button size
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ), // Reduced from 24x12
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ), // Reduced from 8
          textStyle: GoogleFonts.cairo(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ), // Reduced from 16
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          minimumSize: const Size(64, 36), // Compact button size
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ), // Reduced from 24x12
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ), // Reduced from 8
          textStyle: GoogleFonts.cairo(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ), // Reduced from 16
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 32), // Compact
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          textStyle: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ), // Reduced from 14
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true, // Makes inputs more compact
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ), // Reduced from 16x12
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6), // Reduced from 8
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 1.5,
          ), // Reduced from 2
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: GoogleFonts.cairo(
          color: AppColors.textMuted,
          fontSize: 12,
        ), // Added smaller font
        labelStyle: GoogleFonts.cairo(
          color: AppColors.textSecondary,
          fontSize: 12,
        ), // Smaller labels
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        sizeConstraints: BoxConstraints.tightFor(
          width: 48,
          height: 48,
        ), // Smaller FAB
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 0.8, // Thinner divider
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 4, // Reduced from 8
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ), // Reduced from 16
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 15, // Reduced from 18
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: GoogleFonts.cairo(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.secondary,
        contentTextStyle: GoogleFonts.cairo(
          color: Colors.white,
          fontSize: 12,
        ), // Smaller text
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: GoogleFonts.cairo(
          fontWeight: FontWeight.bold,
          fontSize: 12, // Smaller headers
          color: AppColors.textPrimary,
        ),
        dataTextStyle: GoogleFonts.cairo(
          color: AppColors.textPrimary,
          fontSize: 12,
        ), // Smaller data
        headingRowColor: WidgetStateProperty.all(AppColors.surface),
        dataRowMinHeight: 36, // Compact rows
        dataRowMaxHeight: 44, // Compact rows
        columnSpacing: 20, // Reduced spacing
      ),
      iconTheme: const IconThemeData(size: 20), // Smaller icons globally
      listTileTheme: const ListTileThemeData(
        dense: true, // Compact list tiles
        minVerticalPadding: 4,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
      chipTheme: ChipThemeData(
        labelStyle: GoogleFonts.cairo(
          fontSize: 11,
          color: AppColors.textPrimary,
        ),
        backgroundColor: Colors.grey.shade100,
        selectedColor: AppColors.primary.withValues(alpha: 0.15),
        secondaryLabelStyle: GoogleFonts.cairo(
          fontSize: 11,
          color: AppColors.primary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        side: const BorderSide(color: AppColors.border),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        headerBackgroundColor: AppColors.primary,
        headerForegroundColor: Colors.white,
        headerHeadlineStyle: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w700),
        headerHelpStyle: GoogleFonts.cairo(fontSize: 12),
        dayStyle: GoogleFonts.cairo(fontSize: 12),
        weekdayStyle: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
        yearStyle: GoogleFonts.cairo(fontSize: 13),
        dayOverlayColor: WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.08)),
        todayBorder: const BorderSide(color: AppColors.primary),
        todayForegroundColor: WidgetStateProperty.all(AppColors.primary),
        rangePickerHeaderBackgroundColor: AppColors.primary,
        rangePickerHeaderForegroundColor: Colors.white,
        rangePickerHeaderHeadlineStyle: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700),
        rangePickerHeaderHelpStyle: GoogleFonts.cairo(fontSize: 11),
        rangeSelectionBackgroundColor: AppColors.primary.withValues(alpha: 0.12),
        rangePickerSurfaceTintColor: Colors.transparent,
        rangePickerBackgroundColor: Colors.white,
        rangePickerShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return AppColors.primary.withValues(alpha: 0.8);
          }
          if (states.contains(WidgetState.hovered)) {
            return AppColors.primary.withValues(alpha: 0.7);
          }
          return AppColors.primary.withValues(alpha: 0.4);
        }),
        trackColor: WidgetStateProperty.all(
          AppColors.border.withValues(alpha: 0.3),
        ),
        trackBorderColor: WidgetStateProperty.all(Colors.transparent),
        thickness: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return 10.0;
          }
          return 8.0;
        }),
        radius: const Radius.circular(8),
        thumbVisibility: WidgetStateProperty.all(true),
        trackVisibility: WidgetStateProperty.all(true),
        interactive: true,
      ),
    );
  }

  static ThemeData get _uralCashDarkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        primary: AppColors.primaryLight,
        secondary: AppColors.secondaryLight,
        error: AppColors.error,
        surface: AppColors.surfaceDark,
      ),
      scaffoldBackgroundColor: AppColors.secondaryDark,
      textTheme: _buildTextTheme(Brightness.dark),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.secondaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 48,
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardDark,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        margin: const EdgeInsets.all(4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: Colors.white,
          elevation: 1,
          minimumSize: const Size(64, 36),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: GoogleFonts.cairo(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.secondaryLight,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(
            color: AppColors.primaryLight,
            width: 1.5,
          ),
        ),
        hintStyle: GoogleFonts.cairo(color: AppColors.textMuted, fontSize: 12),
        labelStyle: GoogleFonts.cairo(color: AppColors.textMuted, fontSize: 12),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardDark,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderDark,
        thickness: 0.8,
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: GoogleFonts.cairo(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: Colors.white,
        ),
        dataTextStyle: GoogleFonts.cairo(color: Colors.white70, fontSize: 12),
        headingRowColor: WidgetStateProperty.all(AppColors.secondaryDark),
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        dividerThickness: 0.8,
      ),
      iconTheme: const IconThemeData(size: 20),
      listTileTheme: const ListTileThemeData(
        dense: true,
        minVerticalPadding: 4,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
      chipTheme: ChipThemeData(
        labelStyle: GoogleFonts.cairo(fontSize: 11, color: Colors.white),
        backgroundColor: AppColors.secondaryDark,
        selectedColor: AppColors.primary.withValues(alpha: 0.3),
        secondaryLabelStyle: GoogleFonts.cairo(
          fontSize: 11,
          color: AppColors.primaryLight,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        side: const BorderSide(color: AppColors.borderDark),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.cardDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        headerBackgroundColor: AppColors.secondaryDark,
        headerForegroundColor: Colors.white,
        headerHeadlineStyle: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        headerHelpStyle: GoogleFonts.cairo(fontSize: 12, color: Colors.white70),
        dayStyle: GoogleFonts.cairo(fontSize: 12, color: Colors.white),
        weekdayStyle: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
        yearStyle: GoogleFonts.cairo(fontSize: 13, color: Colors.white),
        dayOverlayColor: WidgetStateProperty.all(AppColors.primaryLight.withValues(alpha: 0.15)),
        todayBorder: const BorderSide(color: AppColors.primaryLight),
        todayForegroundColor: WidgetStateProperty.all(AppColors.primaryLight),
        rangePickerHeaderBackgroundColor: AppColors.secondaryDark,
        rangePickerHeaderForegroundColor: Colors.white,
        rangePickerHeaderHeadlineStyle: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        rangePickerHeaderHelpStyle: GoogleFonts.cairo(fontSize: 11, color: Colors.white70),
        rangeSelectionBackgroundColor: AppColors.primaryLight.withValues(alpha: 0.15),
        rangePickerSurfaceTintColor: Colors.transparent,
        rangePickerBackgroundColor: AppColors.cardDark,
        rangePickerShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return AppColors.primaryLight.withValues(alpha: 0.9);
          }
          if (states.contains(WidgetState.hovered)) {
            return AppColors.primaryLight.withValues(alpha: 0.7);
          }
          return AppColors.primaryLight.withValues(alpha: 0.45);
        }),
        trackColor: WidgetStateProperty.all(
          Colors.white.withValues(alpha: 0.08),
        ),
        trackBorderColor: WidgetStateProperty.all(Colors.transparent),
        thickness: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return 10.0;
          }
          return 8.0;
        }),
        radius: const Radius.circular(8),
        thumbVisibility: WidgetStateProperty.all(true),
        trackVisibility: WidgetStateProperty.all(true),
        interactive: true,
      ),
    );
  }

  static TextTheme _buildTextTheme(Brightness brightness) {
    final color = brightness == Brightness.light
        ? AppColors.textPrimary
        : Colors.white;
    final secondaryColor = brightness == Brightness.light
        ? AppColors.textSecondary
        : AppColors.textMuted;

    // Reduced font sizes for compact, professional UI
    return TextTheme(
      displayLarge: GoogleFonts.cairo(
        fontSize: 42, // Reduced from 57
        fontWeight: FontWeight.bold,
        color: color,
      ),
      displayMedium: GoogleFonts.cairo(
        fontSize: 34, // Reduced from 45
        fontWeight: FontWeight.bold,
        color: color,
      ),
      displaySmall: GoogleFonts.cairo(
        fontSize: 28, // Reduced from 36
        fontWeight: FontWeight.bold,
        color: color,
      ),
      headlineLarge: GoogleFonts.cairo(
        fontSize: 24, // Reduced from 32
        fontWeight: FontWeight.w600,
        color: color,
      ),
      headlineMedium: GoogleFonts.cairo(
        fontSize: 20, // Reduced from 28
        fontWeight: FontWeight.w600,
        color: color,
      ),
      headlineSmall: GoogleFonts.cairo(
        fontSize: 18, // Reduced from 24
        fontWeight: FontWeight.w600,
        color: color,
      ),
      titleLarge: GoogleFonts.cairo(
        fontSize: 16, // Reduced from 22
        fontWeight: FontWeight.w600,
        color: color,
      ),
      titleMedium: GoogleFonts.cairo(
        fontSize: 14, // Reduced from 16
        fontWeight: FontWeight.w500,
        color: color,
      ),
      titleSmall: GoogleFonts.cairo(
        fontSize: 12, // Reduced from 14
        fontWeight: FontWeight.w500,
        color: color,
      ),
      bodyLarge: GoogleFonts.cairo(
        fontSize: 14, // Reduced from 16
        color: color,
      ),
      bodyMedium: GoogleFonts.cairo(
        fontSize: 12, // Reduced from 14
        color: color,
      ),
      bodySmall: GoogleFonts.cairo(
        fontSize: 11, // Reduced from 12
        color: secondaryColor,
      ),
      labelLarge: GoogleFonts.cairo(
        fontSize: 12, // Reduced from 14
        fontWeight: FontWeight.w500,
        color: color,
      ),
      labelMedium: GoogleFonts.cairo(
        fontSize: 11, // Reduced from 12
        fontWeight: FontWeight.w500,
        color: color,
      ),
      labelSmall: GoogleFonts.cairo(
        fontSize: 10, // Reduced from 11
        fontWeight: FontWeight.w500,
        color: secondaryColor,
      ),
    );
  }
}
