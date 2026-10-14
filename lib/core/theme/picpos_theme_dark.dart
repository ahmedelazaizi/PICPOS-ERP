part of 'picpos_theme.dart';

ThemeData _buildPicPosDarkTheme() {
  final text = PicPosTheme._textTheme(Brightness.dark);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primaryLight,
      secondary: AppColors.primary,
      error: AppColors.error,
      surface: PicPosTheme._cardDark,
    ),
    scaffoldBackgroundColor: PicPosTheme._canvasDark,
    dividerColor: PicPosTheme._hairlineDark,
    textTheme: text,

    appBarTheme: AppBarTheme(
      backgroundColor: PicPosTheme._cardDark,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 54,
      titleTextStyle: GoogleFonts.cairo(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Colors.white, size: 21),
      shape: const Border(
        bottom: BorderSide(color: AppColors.primary, width: 2.5),
      ),
    ),

    cardTheme: CardThemeData(
      color: PicPosTheme._cardDark,
      elevation: 0,
      margin: const EdgeInsets.all(6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PicPosTheme._radiusCard),
        side: const BorderSide(color: PicPosTheme._hairlineDark),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(76, 42),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PicPosTheme._radiusControl),
        ),
        textStyle: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: PicPosTheme._hairlineDark, width: 1.5),
        minimumSize: const Size(76, 42),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PicPosTheme._radiusControl),
        ),
        textStyle: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryLight,
        minimumSize: const Size(56, 38),
        textStyle: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PicPosTheme._fieldFillDark,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PicPosTheme._radiusControl),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PicPosTheme._radiusControl),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PicPosTheme._radiusControl),
        borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PicPosTheme._radiusControl),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      hintStyle: GoogleFonts.cairo(color: PicPosTheme._m, fontSize: 13),
      labelStyle: GoogleFonts.cairo(color: PicPosTheme._s, fontSize: 13),
    ),

    dividerTheme: const DividerThemeData(
      color: PicPosTheme._hairlineDark,
      thickness: 1,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: PicPosTheme._cardDark,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: PicPosTheme._hairlineDark),
      ),
      titleTextStyle: GoogleFonts.cairo(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      contentTextStyle: GoogleFonts.cairo(
        fontSize: 14,
        color: PicPosTheme._s,
        height: 1.6,
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.primary,
      contentTextStyle: GoogleFonts.cairo(color: Colors.white, fontSize: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PicPosTheme._radiusControl),
      ),
    ),

    dataTableTheme: DataTableThemeData(
      headingTextStyle: GoogleFonts.cairo(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: Colors.white,
      ),
      dataTextStyle: GoogleFonts.cairo(color: Colors.white, fontSize: 13),
      headingRowColor: WidgetStateProperty.all(AppColors.primaryDark),
      dataRowMinHeight: 44,
      dataRowMaxHeight: 54,
      columnSpacing: 24,
      headingRowHeight: 46,
    ),

    iconTheme: const IconThemeData(size: 21, color: Colors.white),

    listTileTheme: ListTileThemeData(
      dense: false,
      minVerticalPadding: 8,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PicPosTheme._radiusControl),
      ),
      selectedTileColor: AppColors.primary.withValues(alpha: 0.18),
      selectedColor: AppColors.primaryLight,
    ),

    chipTheme: ChipThemeData(
      labelStyle: GoogleFonts.cairo(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      backgroundColor: PicPosTheme._fieldFillDark,
      selectedColor: AppColors.primary.withValues(alpha: 0.30),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      side: const BorderSide(color: PicPosTheme._hairlineDark),
      shape: const StadiumBorder(),
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primaryLight,
      unselectedLabelColor: Colors.white54,
      labelStyle: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700),
      unselectedLabelStyle: GoogleFonts.cairo(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: const UnderlineTabIndicator(
        borderSide: BorderSide(color: AppColors.primaryLight, width: 3),
      ),
      dividerColor: PicPosTheme._hairlineDark,
    ),

    datePickerTheme: DatePickerThemeData(
      backgroundColor: PicPosTheme._cardDark,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: PicPosTheme._hairlineDark),
      ),
      headerBackgroundColor: AppColors.primaryDark,
      headerForegroundColor: Colors.white,
      headerHeadlineStyle: GoogleFonts.cairo(
        fontSize: 19,
        fontWeight: FontWeight.w700,
      ),
      headerHelpStyle: GoogleFonts.cairo(fontSize: 12),
      dayStyle: GoogleFonts.cairo(fontSize: 13, color: Colors.white),
      weekdayStyle: GoogleFonts.cairo(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: PicPosTheme._s,
      ),
      yearStyle: GoogleFonts.cairo(fontSize: 14, color: Colors.white),
      dayOverlayColor: WidgetStateProperty.all(
        AppColors.primary.withValues(alpha: 0.18),
      ),
      todayBorder: const BorderSide(color: AppColors.primaryLight, width: 1.5),
      todayForegroundColor: WidgetStateProperty.all(AppColors.primaryLight),
      rangePickerHeaderBackgroundColor: AppColors.primaryDark,
      rangePickerHeaderForegroundColor: Colors.white,
      rangePickerHeaderHeadlineStyle: GoogleFonts.cairo(
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      rangePickerHeaderHelpStyle: GoogleFonts.cairo(fontSize: 12),
      rangeSelectionBackgroundColor: AppColors.primary.withValues(alpha: 0.22),
      rangePickerSurfaceTintColor: Colors.transparent,
      rangePickerBackgroundColor: PicPosTheme._cardDark,
      rangePickerShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: PicPosTheme._hairlineDark),
      ),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : AppColors.textSecondaryDark,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.primary
            : PicPosTheme._fieldFillDark,
      ),
      trackOutlineColor: WidgetStateProperty.all(PicPosTheme._hairlineDark),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.primary
            : Colors.transparent,
      ),
      side: const BorderSide(color: PicPosTheme._hairlineDark, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),

    scrollbarTheme: PicPosTheme._scrollbar(),

    popupMenuTheme: PopupMenuThemeData(
      color: PicPosTheme._cardDark,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PicPosTheme._radiusControl),
        side: const BorderSide(color: PicPosTheme._hairlineDark),
      ),
      textStyle: GoogleFonts.cairo(fontSize: 13, color: Colors.white),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: GoogleFonts.cairo(fontSize: 12, color: Colors.white),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primaryLight,
      linearMinHeight: 3,
    ),
  );
}
