// أزرارُ الخزينة الأربعة في شبكة ٢×٢ — يسارَ البطاقة الداكنة كما في التصميم.
//
// كانت في `headerActions` (شريطُ الهيدر العلويّ) أزراراً نصّيّةً صغيرة؛
// والتصميمُ يضعها بطاقاتٍ بعناوينَ فرعيّةٍ في العمود الثاني من الصفّ العلويّ
// (`grid-template-columns: 1fr 620px`).
//
// ═══ 🔴 الحرّاسُ انتقلوا مع الأزرار — وبطريقةٍ لا تخمّن ═══
//
// `PermissionGuard` مع `allowManagerOverride` يلفُّ الابنَ في `AbsorbPointer`
// ثمّ **يخمّن** فعلَه بـ`extractChildAction` — وهي تعرف
// `ElevatedButton`/`OutlinedButton`/`TextButton`/`IconButton`/`ListTile`/
// `InkWell`/`GestureDetector` **وترجع `null` لغيرها**.
//
// وبطاقاتُ التصميم هذه ليست أيّاً منها من الخارج (‏`Container` يلفُّ
// `InkWell`) — فلو اكتُفي بالنقل لكان الحارسُ يعرض حوارَ المدير، ويوافق
// المديرُ، **ثمّ لا يحدث شيء**. وهو بالضبط «الحارسُ الذي لا تراه يسقط».
//
// فيُمرَّر `onGranted` صراحةً — وهو ما يوصي به توثيقُ الحارس نفسُه.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../widgets/permission_guard.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'treasury_picpos_tokens.dart';

class TreasuryActionsGridPicpos extends StatelessWidget {
  const TreasuryActionsGridPicpos({
    super.key,
    required this.onReceipt,
    required this.onPayment,
    required this.onSafes,
    required this.onReconcile,
  });

  final VoidCallback onReceipt;
  final VoidCallback onPayment;
  final VoidCallback onSafes;
  final VoidCallback onReconcile;

  @override
  Widget build(BuildContext context) {
    // ترتيبُ التصميم في شبكةٍ بعمودَين: قبض · صرف / إدارة الصناديق · مراجعة.
    final cells = <Widget>[
      PermissionGuard(
        permission: PermissionCodes.treasuryReceiptsCreate,
        allowManagerOverride: true,
        actionName: 'إنشاء سند قبض',
        onGranted: onReceipt,
        child: TreasuryActionCardPicpos(
          title: 'سند قبض',
          subtitle: 'تحصيل من عميل أو جهة',
          icon: PhosphorIconsBold.arrowCircleDown,
          tint: AppColors.success,
          borderTinted: true,
          onTap: onReceipt,
        ),
      ),
      PermissionGuard(
        permission: PermissionCodes.treasuryPaymentsCreate,
        allowManagerOverride: true,
        actionName: 'إنشاء سند صرف',
        onGranted: onPayment,
        child: TreasuryActionCardPicpos(
          title: 'سند صرف',
          subtitle: 'سداد مورد أو مصروف',
          icon: PhosphorIconsBold.arrowCircleUp,
          tint: AppColors.error,
          borderTinted: true,
          onTap: onPayment,
        ),
      ),
      TreasuryActionCardPicpos(
        title: 'إدارة الصناديق',
        subtitle: 'إنشاء وربط طرق التحصيل',
        icon: PhosphorIconsBold.vault,
        tint: AppColors.primary,
        onTap: onSafes,
      ),
      TreasuryActionCardPicpos(
        title: 'مراجعة الأرصدة',
        subtitle: 'مطابقة مع دفتر الأستاذ',
        icon: PhosphorIconsBold.scales,
        tint: AppColors.info,
        onTap: onReconcile,
      ),
    ];

    // ═══ 🔴 `IntrinsicHeight` ليست تجميلاً — بدونها الشاشةُ بيضاء ═══
    //
    // `CrossAxisAlignment.stretch` في `Row` تُلزم الأبناءَ بملء المحور
    // العرضيّ (الارتفاع). وهذا الصفُّ يعيش داخل `Column(mainAxisSize: min)`
    // التي تمنح أبناءَها ارتفاعاً **غيرَ محدود** — فتُطلَب أبناءٌ بارتفاعٍ
    // لا نهائيّ وتُرمى `BoxConstraints forces an infinite height` في طور
    // التخطيط.
    //
    // وفي بناء الإصدار **لا تظهر الشاشةُ الحمراء**: يُرسم بياض. وهو ما رآه
    // المالكُ على البناء المنشور — ترويسةٌ وبحثٌ وجسمٌ فارغ.
    //
    // و`IntrinsicHeight` تقيس أطولَ بطاقةٍ في الصفّ وتُثبّت الارتفاعَ عليه،
    // فتصير `stretch` مطلباً محدوداً — وتؤدّي غرضَها الأصليّ: بطاقتان
    // متساويتا الارتفاع مهما طال عنوانٌ فرعيّ.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cells[0]),
              const SizedBox(width: 10),
              Expanded(child: cells[1]),
            ],
          ),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cells[2]),
              const SizedBox(width: 10),
              Expanded(child: cells[3]),
            ],
          ),
        ),
      ],
    );
  }
}

/// بطاقةُ فعلٍ واحدة — أيقونةٌ ملوّنة + عنوانٌ + عنوانٌ فرعيّ.
@visibleForTesting
class TreasuryActionCardPicpos extends StatelessWidget {
  const TreasuryActionCardPicpos({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.onTap,
    this.borderTinted = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  /// سندا القبض والصرف لهما حدٌّ بلون الفعل في التصميم؛ والزرّان الآخران
  /// بالحدّ الشعريّ.
  final bool borderTinted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.picposCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderTinted
                  ? tint.withValues(alpha: .35)
                  : TreasuryPicposTokens.hairlineOf(context),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
