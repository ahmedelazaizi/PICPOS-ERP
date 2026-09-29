import 'package:ural_erp/core/i18n/tr.dart';
// رموزُ تصميم شاشة الخزينة — **مكانٌ واحدٌ لا سبعة**.
//
// قرارُ المالك 2026-08-22 يمنع مشاركةَ تعديلات PicPos مع UralCash، فالودجتُ
// تُفرك. لكنّه **لا يأمر بالنسخ مرّتين داخلَ PicPos**: بطاقةُ العدّاد وُحّدت
// بعد أن كُتبت مرّتين، وهذه الرموزُ تخدم أربعَ ودجتاتٍ في هذه الشاشة
// (البطاقات · الحركات · شريطُ التبويبات · شرائحُ التقسيم) فتُكتب هنا مرّةً.
//
// القيمُ مأخوذةٌ من متغيّرات CSS في التصميم:
//   `--field:#F4F7FC` · `--hairline:#DCE3EE` · `--muted:#6B7280`
//   `--txt2:#374151` · `--hero:#012258`
// والثلاثةُ الأخيرةُ موجودةٌ أصلاً في [AppColors] فتُقرأ منها لا تُكرَّر.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_surface.dart';

/// رموزُ الأسطح والحدود في شاشة الخزينة بهويّة PicPos.
abstract final class TreasuryPicposTokens {
  /// `--field` — أرضيّةُ ترويسات الكروت وحقلِ البحث.
  ///
  /// ⚠️ **دالّةٌ لا ثابت.** الثابتُ كان قيمةَ الوضع الفاتحِ وحدَها، فبقيت
  /// ترويساتُ الكروت بيضاءَ في الغامق — وهو أحدُ سببَي بلاغِ المالك
  /// 2026-08-24 أنّ الخزينةَ لا تأخذ الغامق. والقيمةُ الفاتحةُ **هي هي**
  /// (`#F4F7FC`) فلا يتبدّل الفاتحُ بايتاً.
  static Color fieldOf(BuildContext context) => context.picposIsDark
      ? const Color(0xFF18243A)
      : const Color(0xFFF4F7FC);

  /// حدُّ الكروت. يُقرأ من [AppColors] كي لا تختلف الخزينةُ عن بقيّةِ كروت
  /// PicPos (`PicPosContentCard` تستعمل نفسَه) — وبنظيرِه الداكنِ في الغامق.
  static Color hairlineOf(BuildContext context) => context.picposHairline;

  // ── ألوانُ أنواع الصناديق ───────────────────────────────────────────────
  //
  // ⚠️ **قِيست من التصميم، ووُحّدت لأنها كانت متضاربة**: شرائحُ التقسيم كانت
  // ترسم كليك بـ`#A78BFA` بينما بطاقةُ الصندوق في الأصل ترسمه `#8B5CF6`
  // والتصميمُ يقول `#8B5CF6`. فلونان لنفس النوع على نفس الشاشة — والقارئُ
  // يظنُّهما نوعَين.
  static const Color cashTint = AppColors.success; // #22C55E
  static const Color bankTint = Color(0xFF4A80E8);
  static const Color clickTint = Color(0xFF8B5CF6);
  static const Color customTint = Color(0xFFEA580C);

  /// لونُ النوع. ما لا يُعرَف نوعُه يأخذ لونَ «المخصّص» — لا لونَ النقديّ،
  /// كي لا يُقرأ صندوقٌ مجهولُ النوع نقديّاً.
  ///
  /// ⚠️ ولا يُخلَط هذا بقاعدة [PicPosTreasurySplit] التي تضمُّ المجهولَ إلى
  /// **مجموع** النقديّ (‏افتراضُ العمود `withDefault('cash')`): ذاك حسابُ
  /// رصيدٍ لا يجوز أن يُسقط مالاً، وهذا لونُ أيقونةٍ يجوز أن يقول «لا أعرف».
  static Color tintFor(String safeType) => switch (safeType) {
        'cash' => cashTint,
        'bank' => bankTint,
        'click' => clickTint,
        _ => customTint,
      };

  /// أيقونةُ النوع — التصميمُ يرسم `ph-vault` لكلّ الصناديق في قائمة الخزينة.
  static IconData iconFor(String safeType) => switch (safeType) {
        'cash' => PhosphorIconsBold.money,
        'bank' => PhosphorIconsBold.bank,
        'click' => PhosphorIconsBold.cellSignalFull,
        _ => PhosphorIconsBold.vault,
      };

  /// تسميةُ النوع بالعربيّة. النوعُ المجهولُ يُعرض كما هو في العمود بدل أن
  /// يُترجَم إلى «مخصّص» فيضيع الفرقُ بين نوعَين مجهولَين.
  static String labelFor(String safeType) => switch (safeType) {
        'cash' => tr('نقدي'),
        'bank' => tr('بنك'),
        'click' => tr('تحويل كليك'),
        _ => safeType,
      };
}
