// ═══════════════════════════════════════════════════════════════════════════
// PICPOS — لغة التصميم
// ═══════════════════════════════════════════════════════════════════════════
//
// الملف ده هو شكل PicPos عبر **كل** الشاشات. مفيش ولا ملف شاشة اتعدّل عشانه:
// الشاشات الـ٣٠ (١٨٥٠٠ سطر) بتاخد شكلها من `ThemeData` الواحدة دي، فتغيير
// الهوية بيحصل هنا مرة واحدة بدل ٣٠ مرة.
//
// ── ليه ملف منفصل وليس تعديل `AppTheme`؟ ──────────────────────────────────
// الشاشات مشتركة بين المنتجين. تعديل الثيم في مكانه معناه إن شكل UralCash
// يتغيّر عند كل عميل قايم — كسر مباشر لقاعدة الفصل. `AppTheme` بيفرّع على
// `Brand.isPicPos` وهو **ثابت وقت الترجمة**، فالفرع بيتحسم في البناء: بناء
// UralCash مبيشوفش الكود ده أصلاً، وThemeData بتاعته بتفضل حرف بحرف زي ما هي.
//
// ── الاتجاه البصري — مقصود إنه عكس UralCash ───────────────────────────────
//   UralCash: مضغوط · زوايا ٦-٨ · ظلال · شريط علوي ملوّن · بنط ١٢-١٣
//   PicPos:   مسطّح بحدود شعرية · زوايا ١٢-١٦ · بلا ظلال · شريط علوي فاتح
//             بشريحة لونية سفلية · بنط ١٣-١٥ · حقول مملوءة بلا حدود
//
// الفرق مقروء من مسافة متر — وده المطلوب من منتج بعلامة مستقلة. لكنه مش
// «مختلف عشان يبقى مختلف»: كل قرار له سبب تشغيلي مكتوب جنبه.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class PicPosTheme {
  // ─── §٧ — وزنان اثنان لا أكثر ─────────────────────────────────────────────
  //
  // طلبُ المالك: «الخطُّ في النظام بالكامل يجب أن يكون غامقاً بولد ومتناسقاً
  // للوضوح».
  //
  // والعطبُ كان في المتن: `bodyLarge` و`bodyMedium` و`bodySmall` بلا
  // `fontWeight` إطلاقاً — أي `w400` الافتراضيّ — بينما العناوينُ `w700`.
  // وهي معظمُ ما يُقرأ (نصوصُ الجداول والبطاقات والقوائم)، فالتفاوتُ الذي
  // رآه المالكُ كان بين عنوانٍ ثقيلٍ ومتنٍ باهتٍ في البطاقة الواحدة.
  //
  // ⚠️ ووزنان اثنان لا ثلاثة: توحيدُ كلّ شيءٍ على `w700` يمحو التراتبَ
  // البصريَّ فيصير النصُّ كتلةً واحدة، والثلاثةُ تُعيد التفاوتَ من بابٍ آخر.
  // فالعناوينُ والتسمياتُ `w700`، والمتنُ `w600` — أغلظُ من الافتراضيّ وأخفُّ
  // من العنوان.
  //
  // ⚠️ وحدُّ هذا التغيير مقيسٌ ومكتوب: كثيرٌ من الجداول تضبط `fontWeight` في
  // موضع الرسم فتتجاهل الثيمَ تماماً. فما لا يرث الثيمَ لا يتغيّر هنا، وهو
  // يحتاج مرورَ عينٍ على شاشتَي البيع والتقارير بعد البناء.

  /// وزنُ العناوين والتسميات.
  static const FontWeight headingWeight = FontWeight.w700;

  /// وزنُ المتن — أغلظُ من `w400` الافتراضيّ وأخفُّ من العنوان.
  static const FontWeight bodyWeight = FontWeight.w600;

  PicPosTheme._();

  // ── رموز التصميم (design tokens) ────────────────────────────────────────
  //
  // القيم دي محلية للثيم عن قصد — مش في `AppColors`. `AppColors` مستخدمة في
  // ~٤٩١ سياق `const`، وأي إضافة ليها مسؤولية دايمة؛ ودي درجات سطح مشتقة
  // بتخص الشكل بس، مالهاش أي معنى للمنتج.

  /// خلفية التطبيق — رمادي مزرقّ فاتح جداً، مشتق من الأزرق الأساسي عشان
  /// السطوح البيضا فوقه تبان «طافية» من غير ظلال.
  static const Color _canvas = Color(0xFFF2F5FA);

  /// حدود شعرية. بتحل محل الظلال في كل مكان — الظل على شاشة كاشير طول اليوم
  /// بيتقرا كضوضاء، والحد بيدّي نفس الفصل بتكلفة رسم أقل.
  static const Color _hairline = Color(0xFFDCE3EE);

  /// خلفية الحقول: أزرق باهت بدل الأبيض. بتخلّي الحقل القابل للكتابة يتميّز
  /// عن الكارت الأبيض اللي جوّاه من غير ما يحتاج إطار.
  static const Color _fieldFill = Color(0xFFF4F7FC);

  /// نسخ داكنة — الوضع الليلي بيستخدم كحلي مزرقّ مش رمادي محايد، عشان
  /// العلامة تفضل حاضرة في الوضعين.
  static const Color _canvasDark = Color(0xFF0A1220);
  static const Color _cardDark = Color(0xFF121C2E);
  static const Color _hairlineDark = Color(0xFF243247);
  static const Color _fieldFillDark = Color(0xFF18243A);

  static const double _radiusCard = 14;
  static const double _radiusControl = 10;
  static const double _radiusPill = 999;

  // ── الوضع الفاتح ────────────────────────────────────────────────────────

  static ThemeData get lightTheme {
    final text = _textTheme(Brightness.light);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        secondary: AppColors.primaryDark,
        error: AppColors.error,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: _canvas,
      textTheme: text,

      // شريط علوي فاتح بنص داكن — أوضح فرق silhouette عن UralCash (اللي
      // شريطه مصمت بلون العلامة). الشريحة اللونية تحته بتدّي حضور للعلامة
      // من غير ما تاكل ٤٨ بكسل من الشاشة بلون مشبع.
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primaryDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 54,
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
        ),
        iconTheme: const IconThemeData(color: AppColors.primaryDark, size: 21),
        shape: const Border(
          bottom: BorderSide(color: AppColors.primary, width: 2.5),
        ),
      ),

      // كروت مسطّحة بحد. `elevation: 0` مقصود — الفصل بييجي من الحد واللون.
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.all(6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusCard),
          side: const BorderSide(color: _hairline),
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
            borderRadius: BorderRadius.circular(_radiusControl),
          ),
          textStyle: GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          side: const BorderSide(color: _hairline, width: 1.5),
          minimumSize: const Size(76, 42),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusControl),
          ),
          textStyle: GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(56, 38),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.cairo(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      // حقول مملوءة بلا حد ظاهر لحد التركيز. الحقل الفاضي بيبقى «مساحة»
      // مش «صندوق»، والتركيز بيرسم إطار أزرق سميك — الكاشير يشوف مكان
      // المؤشر من غير ما يدوّر.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _fieldFill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        hintStyle: GoogleFonts.cairo(color: AppColors.textMuted, fontSize: 13),
        labelStyle:
            GoogleFonts.cairo(color: AppColors.textSecondary, fontSize: 13),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
        ),
        sizeConstraints: const BoxConstraints.tightFor(width: 52, height: 52),
      ),

      dividerTheme: const DividerThemeData(color: _hairline, thickness: 1),

      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _hairline),
        ),
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
        ),
        contentTextStyle: GoogleFonts.cairo(
          fontSize: 14,
          color: AppColors.textSecondary,
          height: 1.6,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryDark,
        contentTextStyle: GoogleFonts.cairo(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
        ),
      ),

      // جداول: رأس مصمت بلون العلامة ونص أبيض. الجداول هي معظم شاشات
      // الـERP، فالرأس المصمت هو أسرع علامة بصرية إن دي شاشة PicPos.
      // والصفوف أطول من UralCash — أسهل في الاستهداف بالماوس.
      dataTableTheme: DataTableThemeData(
        headingTextStyle: GoogleFonts.cairo(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: Colors.white,
        ),
        dataTextStyle: GoogleFonts.cairo(
          color: AppColors.textPrimary,
          fontSize: 13,
        ),
        headingRowColor: WidgetStateProperty.all(AppColors.primaryDark),
        dataRowMinHeight: 44,
        dataRowMaxHeight: 54,
        columnSpacing: 24,
        dividerThickness: 1,
        headingRowHeight: 46,
      ),

      iconTheme: const IconThemeData(size: 21, color: AppColors.primaryDark),

      listTileTheme: ListTileThemeData(
        dense: false,
        minVerticalPadding: 8,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
        ),
        selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
        selectedColor: AppColors.primary,
      ),

      // شرايح كبسولية — أوضح فرق شكلي عن شرايح UralCash المستطيلة.
      chipTheme: ChipThemeData(
        labelStyle: GoogleFonts.cairo(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryDark,
        ),
        backgroundColor: _fieldFill,
        selectedColor: AppColors.primary.withValues(alpha: 0.14),
        secondaryLabelStyle:
            GoogleFonts.cairo(fontSize: 12, color: AppColors.primary),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        side: const BorderSide(color: _hairline),
        shape: const StadiumBorder(),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle:
            GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.primary, width: 3),
        ),
        dividerColor: _hairline,
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _hairline),
        ),
        headerBackgroundColor: AppColors.primaryDark,
        headerForegroundColor: Colors.white,
        headerHeadlineStyle:
            GoogleFonts.cairo(fontSize: 19, fontWeight: FontWeight.w700),
        headerHelpStyle: GoogleFonts.cairo(fontSize: 12),
        dayStyle: GoogleFonts.cairo(fontSize: 13),
        weekdayStyle: GoogleFonts.cairo(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
        yearStyle: GoogleFonts.cairo(fontSize: 14),
        dayOverlayColor:
            WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.08)),
        todayBorder: const BorderSide(color: AppColors.primary, width: 1.5),
        todayForegroundColor: WidgetStateProperty.all(AppColors.primary),
        rangePickerHeaderBackgroundColor: AppColors.primaryDark,
        rangePickerHeaderForegroundColor: Colors.white,
        rangePickerHeaderHeadlineStyle:
            GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.w700),
        rangePickerHeaderHelpStyle: GoogleFonts.cairo(fontSize: 12),
        rangeSelectionBackgroundColor:
            AppColors.primary.withValues(alpha: 0.12),
        rangePickerSurfaceTintColor: Colors.transparent,
        rangePickerBackgroundColor: Colors.white,
        rangePickerShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),

      scrollbarTheme: _scrollbar(),

      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
          side: const BorderSide(color: _hairline),
        ),
        textStyle: GoogleFonts.cairo(fontSize: 13),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.primaryDark,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: GoogleFonts.cairo(fontSize: 12, color: Colors.white),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.primary
                : const Color(0xFFC7D2E1)),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.primary
                : Colors.transparent),
        side: const BorderSide(color: Color(0xFFB6C2D4), width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearMinHeight: 3,
      ),
    );
  }

  // ── الوضع الداكن ────────────────────────────────────────────────────────

  static ThemeData get darkTheme {
    final text = _textTheme(Brightness.dark);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        primary: AppColors.primaryLight,
        secondary: AppColors.primary,
        error: AppColors.error,
        surface: _cardDark,
      ),
      scaffoldBackgroundColor: _canvasDark,
      textTheme: text,

      appBarTheme: AppBarTheme(
        backgroundColor: _cardDark,
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
        color: _cardDark,
        elevation: 0,
        margin: const EdgeInsets.all(6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusCard),
          side: const BorderSide(color: _hairlineDark),
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
            borderRadius: BorderRadius.circular(_radiusControl),
          ),
          textStyle:
              GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: _hairlineDark, width: 1.5),
          minimumSize: const Size(76, 42),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusControl),
          ),
          textStyle:
              GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          minimumSize: const Size(56, 38),
          textStyle:
              GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _fieldFillDark,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        hintStyle: GoogleFonts.cairo(color: AppColors.textMuted, fontSize: 13),
        labelStyle: GoogleFonts.cairo(color: Colors.white70, fontSize: 13),
      ),

      dividerTheme: const DividerThemeData(color: _hairlineDark, thickness: 1),

      dialogTheme: DialogThemeData(
        backgroundColor: _cardDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _hairlineDark),
        ),
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        contentTextStyle: GoogleFonts.cairo(
          fontSize: 14,
          color: Colors.white70,
          height: 1.6,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
        contentTextStyle: GoogleFonts.cairo(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
        ),
      ),

      dataTableTheme: DataTableThemeData(
        headingTextStyle: GoogleFonts.cairo(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: Colors.white,
        ),
        dataTextStyle:
            GoogleFonts.cairo(color: Colors.white, fontSize: 13),
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
          borderRadius: BorderRadius.circular(_radiusControl),
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
        backgroundColor: _fieldFillDark,
        selectedColor: AppColors.primary.withValues(alpha: 0.30),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        side: const BorderSide(color: _hairlineDark),
        shape: const StadiumBorder(),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primaryLight,
        unselectedLabelColor: Colors.white54,
        labelStyle:
            GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.primaryLight, width: 3),
        ),
        dividerColor: _hairlineDark,
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: _cardDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _hairlineDark),
        ),
        headerBackgroundColor: AppColors.primaryDark,
        headerForegroundColor: Colors.white,
        headerHeadlineStyle:
            GoogleFonts.cairo(fontSize: 19, fontWeight: FontWeight.w700),
        headerHelpStyle: GoogleFonts.cairo(fontSize: 12),
        dayStyle: GoogleFonts.cairo(fontSize: 13, color: Colors.white),
        weekdayStyle: GoogleFonts.cairo(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white70,
        ),
        yearStyle: GoogleFonts.cairo(fontSize: 14, color: Colors.white),
        dayOverlayColor:
            WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.18)),
        todayBorder:
            const BorderSide(color: AppColors.primaryLight, width: 1.5),
        todayForegroundColor: WidgetStateProperty.all(AppColors.primaryLight),
        rangePickerHeaderBackgroundColor: AppColors.primaryDark,
        rangePickerHeaderForegroundColor: Colors.white,
        rangePickerHeaderHeadlineStyle:
            GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.w700),
        rangePickerHeaderHelpStyle: GoogleFonts.cairo(fontSize: 12),
        rangeSelectionBackgroundColor:
            AppColors.primary.withValues(alpha: 0.22),
        rangePickerSurfaceTintColor: Colors.transparent,
        rangePickerBackgroundColor: _cardDark,
        rangePickerShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _hairlineDark),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? Colors.white
                : Colors.white70),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.primary
                : _fieldFillDark),
        trackOutlineColor: WidgetStateProperty.all(_hairlineDark),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.primary
                : Colors.transparent),
        side: const BorderSide(color: _hairlineDark, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),

      scrollbarTheme: _scrollbar(),

      popupMenuTheme: PopupMenuThemeData(
        color: _cardDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
          side: const BorderSide(color: _hairlineDark),
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

  // ── مشترك ───────────────────────────────────────────────────────────────

  static ScrollbarThemeData _scrollbar() => ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return AppColors.primary;
          }
          if (states.contains(WidgetState.hovered)) {
            return AppColors.primary.withValues(alpha: 0.75);
          }
          return AppColors.primary.withValues(alpha: 0.35);
        }),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        trackBorderColor: WidgetStateProperty.all(Colors.transparent),
        thickness: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.dragged)
                ? 10.0
                : 6.0),
        radius: const Radius.circular(_radiusPill),
        thumbVisibility: WidgetStateProperty.all(true),
        trackVisibility: WidgetStateProperty.all(false),
        interactive: true,
      );

  /// سلّم بنط أوسع من UralCash بدرجة واحدة تقريباً، و`height` أعلى.
  /// العربي بيحتاج تباعد أسطر أكرم من اللاتيني — التشكيل والنقط بتتقصّ
  /// بصرياً عند `height` منخفض، وده بيتراكم على شاشة مليانة جداول.
  static TextTheme _textTheme(Brightness brightness) {
    final onSurface =
        brightness == Brightness.light ? AppColors.textPrimary : Colors.white;
    final muted = brightness == Brightness.light
        ? AppColors.textSecondary
        : Colors.white70;

    return TextTheme(
      displayLarge: GoogleFonts.cairo(
          fontSize: 30, fontWeight: headingWeight, color: onSurface),
      displayMedium: GoogleFonts.cairo(
          fontSize: 25, fontWeight: headingWeight, color: onSurface),
      displaySmall: GoogleFonts.cairo(
          fontSize: 21, fontWeight: headingWeight, color: onSurface),
      headlineMedium: GoogleFonts.cairo(
          fontSize: 19, fontWeight: headingWeight, color: onSurface),
      headlineSmall: GoogleFonts.cairo(
          fontSize: 17, fontWeight: headingWeight, color: onSurface),
      titleLarge: GoogleFonts.cairo(
          fontSize: 16, fontWeight: headingWeight, color: onSurface),
      titleMedium: GoogleFonts.cairo(
          fontSize: 15, fontWeight: headingWeight, color: onSurface),
      titleSmall: GoogleFonts.cairo(
          fontSize: 14, fontWeight: headingWeight, color: onSurface),
      bodyLarge: GoogleFonts.cairo(
          fontSize: 15, height: 1.65, fontWeight: bodyWeight, color: onSurface),
      bodyMedium: GoogleFonts.cairo(
          fontSize: 14, height: 1.65, fontWeight: bodyWeight, color: onSurface),
      bodySmall: GoogleFonts.cairo(
          fontSize: 13, height: 1.6, fontWeight: bodyWeight, color: muted),
      labelLarge: GoogleFonts.cairo(
          fontSize: 14, fontWeight: headingWeight, color: onSurface),
      labelMedium: GoogleFonts.cairo(
          fontSize: 13, fontWeight: headingWeight, color: muted),
      labelSmall: GoogleFonts.cairo(
          fontSize: 12, fontWeight: headingWeight, color: muted),
    );
  }
}
