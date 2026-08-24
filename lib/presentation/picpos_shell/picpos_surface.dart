import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// ألوانُ أسطح PicPos تابعةً للوضع (فاتح/غامق).
///
/// ⚠️ **لماذا دوالٌّ لا ثوابت.** `AppColors.card` و`.surface` و`.border`
/// ثوابتُ **الوضع الفاتح وحدَه**. ولها نظائرُ داكنةٌ (`cardDark` …) يربطها
/// `AppTheme` بـ`ThemeData`، لكنّ أيّ ودجتٍ تكتب `AppColors.card` مباشرةً
/// تبقى بيضاءَ في الوضع الداكن — وهذا سببُ أنّ الغامقَ «لا يتعمّم»: الشريطُ
/// الجانبيُّ يتبع الثيمَ والمحتوى لا يتبعه.
///
/// ولا يجوز تحويلُ تلك الثوابت إلى دوالّ: `AppColors` مستعملةٌ آلافَ المرّات
/// ومئاتُها داخلَ سياقات `const` تنكسر فوراً. فالحلُّ إضافةُ مُلحقٍ يقرأ
/// الوضعَ — على نفس نمط `picposDialogMuted` في `picpos_dialog.dart`.
extension PicPosSurface on BuildContext {
  bool get picposIsDark => Theme.of(this).brightness == Brightness.dark;

  /// خلفيّةُ البطاقة — `--card`.
  Color get picposCard =>
      picposIsDark ? AppColors.cardDark : AppColors.card;

  /// الخلفيّةُ الخافتةُ داخلَ البطاقة (الحقول والصفوف) — `--field`.
  Color get picposField =>
      picposIsDark ? const Color(0xFF18243A) : AppColors.surface;

  /// خطُّ الفصل — `--hairline`.
  Color get picposHairline =>
      picposIsDark ? AppColors.borderDark : AppColors.border;

  /// النصُّ الأساسيّ.
  Color get picposText =>
      picposIsDark ? AppColors.textPrimaryDark : AppColors.textPrimary;

  /// النصُّ الخافت — نفسُ قيمةِ `picposDialogMuted`.
  Color get picposMuted =>
      picposIsDark ? const Color(0xFF94A3B8) : AppColors.textMuted;
}
