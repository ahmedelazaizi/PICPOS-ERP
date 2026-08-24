import 'package:flutter/material.dart';

import '../config/brand.dart';

/// Professional color palette for the POS system.
///
/// ── لوحة كل علامة ────────────────────────────────────────────────────────
///   UralCash — تركواز:  #134657 (غامق) / #2B737F (أساسي) / #469CA5 (فاتح)
///   PicPos   — أزرق:    #012258 (غامق) / #0250D3 (أساسي) / #4A80E8 (فاتح)
///
/// لونا PicPos الغامق والأساسي **مسحوبين من ملف اللوجو نفسه** (أكثر لونين
/// تكراراً فيه)، مش مقدَّرين بالعين. الفاتح مشتق منهم.
///
/// ── ليه الاختيار بالـ `? :` وليس بمتغير وقت التشغيل؟ ──────────────────────
/// `Brand.isPicPos` قيمة `const` (مشتقة من `String.fromEnvironment`), فالتفريع
/// بيتحسم وقت الترجمة وكل لون هنا بيفضل `const`. ده شرط مش تفضيل: الألوان
/// دي مستخدمة ٤٥٣٧ مرة عبر ٣٥٥ ملف، منهم ~٤٩١ جوّه سياق `const` زي
/// `const Icon(..., color: AppColors.primary)`. أي لون يبطل `const` بيحوّل
/// كل المواضع دي لأخطاء ترجمة.
///
/// **لما تضيف علامة جديدة:** زوّد فرع هنا — متخليش أي لون يتحول لـ getter.
class AppColors {
  AppColors._();

  // Primary Colors — per-brand
  static const Color primary =
      Brand.isPicPos ? Color(0xFF0250D3) : Color(0xFF2B737F);
  static const Color primaryDark =
      Brand.isPicPos ? Color(0xFF012258) : Color(0xFF134657);
  static const Color primaryLight =
      Brand.isPicPos ? Color(0xFF4A80E8) : Color(0xFF469CA5);

  // Secondary Colors
  static const Color secondary = Color(0xFF1E293B); // Slate
  static const Color secondaryDark = Color(0xFF0F172A);
  static const Color secondaryLight = Color(0xFF334155);

  // Semantic Colors
  static const Color success = Color(0xFF22C55E); // Green
  static const Color successDark = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color warningDark = Color(0xFFD97706);
  static const Color error = Color(0xFFEF4444); // Red
  static const Color errorDark = Color(0xFFDC2626);
  // مشتق من لون العلامة الفاتح — بيتبدّل معاها.
  static const Color info =
      Brand.isPicPos ? Color(0xFF4A80E8) : Color(0xFF469CA5);
  static const Color booking = Color(
    0xFF8B5CF6,
  ); // Purple (Vibrant Purple for booking)
  static const Color bookingDark = Color(0xFF7C3AED);

  // Surface Colors
  static const Color surface = Color(0xFFF8FAFC); // Slate 50
  static const Color surfaceDark =
      Brand.isPicPos ? Color(0xFF012258) : Color(0xFF134657);
  static const Color card = Colors.white;
  /// ⚠️ **فرعُ PicPos يطابق `PicPosTheme._cardDark` عمداً.**
  ///
  /// كان `#0A2E63` وهو **لا يظهر في أيّ مكانٍ آخرَ من الشجرة**: ثيمُ PicPos
  /// يرسم بطاقاته بـ`#121C2E`. فكانت الشاشةُ الواحدةُ تحمل لونَي بطاقةٍ —
  /// ما يأخذ لونَه من الثيم، وما يأخذه من `picposCard` عبر هذا الثابت.
  /// وهو ما ظهر في صور المالك 2026-08-24.
  ///
  /// والقيمةُ الجديدةُ هي عينُ `--card` الداكنة في تصميم الإعدادات.
  /// وفرعُ UralCash لم يُمَسّ.
  static const Color cardDark =
      Brand.isPicPos ? Color(0xFF121C2E) : Color(0xFF1E4A5A);

  // Text Colors - Light Mode (All text should be BLACK for maximum readability)
  static const Color textPrimary = Color(
    0xFF000000,
  ); // Pure black for light mode
  static const Color textPrimaryDark = Color(
    0xFFFFFFFF,
  ); // Pure white for dark mode
  static const Color textSecondary = Color(0xFF374151); // Dark gray
  static const Color textMuted = Color(0xFF6B7280); // Medium gray
  static const Color textOnPrimary = Colors.white;
  static const Color textOnDark = Colors.white; // For text on dark backgrounds

  // Text Container for dark backgrounds (white frame/card)
  static const Color textContainerLight =
      Colors.white; // White background for text on dark
  static const Color textContainerBorder = Color(0xFFE5E7EB); // Light border

  // Border Colors
  static const Color border = Color(0xFFE2E8F0);
  /// ⚠️ **فرعُ PicPos يطابق `PicPosTheme._hairlineDark` عمداً.**
  ///
  /// كان `#0250D3` — وهو لونُ العلامةِ الأساسيُّ لا لونَ حدّ. وثيمُ PicPos
  /// يرسم حدودَه بـ`#243247`، فكانت الشاشةُ الواحدةُ تحمل حدَّين: رماديّاً
  /// خافتاً من الثيم، وأزرقَ ساطعاً ممّا يقرأ هذا الثابت. والحدُّ بلونِ
  /// العلامةِ يسحب العينَ إلى الإطار بدلَ المحتوى.
  ///
  /// والقيمةُ الجديدةُ هي عينُ `--hairline` الداكنة في تصميم الإعدادات.
  /// وفرعُ UralCash لم يُمَسّ.
  static const Color borderDark =
      Brand.isPicPos ? Color(0xFF243247) : Color(0xFF2B737F);

  // Gradients - UralCash Brand
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [success, successDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient errorGradient = LinearGradient(
    colors: [error, errorDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient brandGradient = LinearGradient(
    colors: [primaryDark, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // POS Specific Colors
  static const Color posBackground = Color(0xFFF1F5F9);
  static const Color posCard = Colors.white;
  static const Color posCategoryActive = primary;
  static const Color posCategoryInactive = Color(0xFFE2E8F0);
  static const Color posPrice = success;
  static const Color posPriceDark = Color(
    0xFF4ADE80,
  ); // Brighter Green for Dark Mode
  static const Color posDiscount = error;
  static const Color posDiscountDark = Color(
    0xFFF87171,
  ); // Brighter Red for Dark Mode

  /// Get theme-aware price color
  static Color getPriceColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light
        ? posPrice
        : posPriceDark;
  }
}
