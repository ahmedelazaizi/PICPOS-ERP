import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/picpos_theme.dart';

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
  Color get picposCard => picposIsDark ? AppColors.cardDark : AppColors.card;

  /// الخلفيّةُ الخافتةُ داخلَ البطاقة (الحقول والصفوف) — `--field`.
  ///
  /// القيمةُ الفاتحةُ هي تعبئةُ حقول الثيم نفسُها (`PicPosTheme.lightFieldFill`)
  /// لا `AppColors.surface` — كي لا تحمل الشاشةُ تعبئتَين متقاربتين.
  Color get picposField =>
      picposIsDark ? const Color(0xFF18243A) : PicPosTheme.lightFieldFill;

  /// خطُّ الفصل — `--hairline`. والفاتحُ هو حدُّ الثيم (`dividerColor`).
  Color get picposHairline =>
      picposIsDark ? AppColors.borderDark : PicPosTheme.lightHairline;

  /// النصُّ الأساسيّ.
  Color get picposText =>
      picposIsDark ? AppColors.textPrimaryDark : AppColors.textPrimary;

  /// النصُّ الخافت — نفسُ قيمةِ `picposDialogMuted`.
  Color get picposMuted =>
      picposIsDark ? AppColors.textMutedDark : AppColors.textMuted;

  Color get picposSecondary =>
      picposIsDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

  /// حبرُ العلامة — `--brand-ink` في التصميم.
  ///
  /// ⚠️ **ليس `AppColors.primary`.** لونُ العلامة `#0250D3` أزرقُ داكن، ويُقرأ
  /// على أرضيّةٍ فاتحةٍ ولا يُقرأ على أرضيّةٍ داكنة. ولذلك يعرّف التصميمُ
  /// رمزاً ثانياً يفتحُ في الوضع الغامق (`#7DA6F5`) ويستعمله في **كلّ نصٍّ
  /// وأيقونةٍ** بلون العلامة — لا في الأرضيّات.
  ///
  /// ⚠️ **وتعميمُه على ما بُني بندٌ مفتوح**: ودجتاتُ PicPos القائمةُ تكتب
  /// `AppColors.primary` في المقدّمة، وتحويلُها يمسّ عشراتِ المواضع فيُقاس
  /// على حدة. المستعمَلُ هنا هو شريطُ التقارير وحدَه.
  Color get picposBrandInk =>
      picposIsDark ? const Color(0xFF7DA6F5) : AppColors.primary;
}
