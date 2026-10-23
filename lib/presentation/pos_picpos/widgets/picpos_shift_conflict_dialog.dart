import 'package:picpos_erp/core/i18n/tr.dart';
// «ورديتُك مفتوحةٌ على جهازٍ آخر» — حوارٌ حاجزٌ لا إشعارٌ عابر.
//
// ── طلبُ المالك (2026-08-14) ────────────────────────────────────────────────
// «النظامُ ينبّه ولا يقبل، إلا بعد إغلاق المفتوحة.» فالحوارُ
// `barrierDismissible: false` ولا يمرّ بالضغط في الفراغ: قبولٌ صامتٌ هو
// بالضبط السلوكُ الذي اشتكى منه.
//
// ── ولماذا مخرجُ المدير ────────────────────────────────────────────────────
// جهازٌ ينطفئ فجأةً يترك ورديتَه مفتوحةً إلى الأبد، فيُحبَس صاحبُها بلا
// حيلة. وقرارُ المالك بين ثلاثةٍ كان «منعٌ + تجاوزُ مدير يفتح رغماً» —
// والتجاوزُ يُسجَّل في سجلّ النشاط كي لا يصير باباً صامتاً.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';

/// ما اختاره المستخدمُ أمام وردية مفتوحةٍ على طرفٍ آخر.
enum ShiftConflictChoice {
  /// انصرف بلا فتح — شاشةُ البيع تبقى بلا وردية.
  cancel,

  /// اذهب لشاشة إغلاق الوردية لتصفيتها.
  closeExisting,

  /// افتح ورديةً جديدةً رغماً — يتطلّب إذنَ مدير عند نقطة الاستدعاء.
  overrideOpen,
}

/// يعرض المنعَ ويرجع اختيارَ المستخدم. لا يفتح شيئاً بنفسه.
Future<ShiftConflictChoice> showPicposShiftConflictDialog(
  BuildContext context, {
  required int shiftId,
  required DateTime startedAt,
  required String userName,
}) async {
  final since = DateTime.now().difference(startedAt);
  final sinceText = since.inHours >= 1
      ? tr('منذ {p0} ساعة', {'p0': since.inHours})
      : tr('منذ {p0} دقيقة', {'p0': since.inMinutes});

  final choice = await showDialog<ShiftConflictChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        icon: const Icon(PhosphorIconsBold.warningCircle,
            color: AppColors.warning, size: 40),
        title:  Text(tr('وردية مفتوحة على جهاز آخر')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('المستخدم «{userName}» له وردية مفتوحة رقم #{shiftId} بدأت {sinceText} على طرف آخر.', {'userName': userName, 'shiftId': shiftId, 'sinceText': sinceText}),
            ),
            const SizedBox(height: 12),
             Text(
              tr('لا يمكن فتح وردية ثانية لنفس المستخدم — أغلق المفتوحة أولاً.'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ShiftConflictChoice.cancel),
            child:  Text(tr('إلغاء')),
          ),
          // التجاوزُ ثانياً وبلا تمييزٍ بصريّ: هو المخرجُ لا الطريقُ الأوّل.
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, ShiftConflictChoice.overrideOpen),
            child:  Text(tr('فتح بإذن مدير')),
          ),
          ElevatedButton.icon(
            onPressed: () =>
                Navigator.pop(ctx, ShiftConflictChoice.closeExisting),
            icon: const Icon(PhosphorIconsBold.lockKey, size: 16),
            label:  Text(tr('إغلاق الوردية المفتوحة')),
          ),
        ],
      ),
    ),
  );

  // إغلاقٌ خارجَ الأزرار (زرُّ الرجوع في النظام) يُقرأ إلغاءً، لا موافقة.
  return choice ?? ShiftConflictChoice.cancel;
}
