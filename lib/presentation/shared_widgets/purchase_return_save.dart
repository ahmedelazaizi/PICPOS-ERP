import 'package:ural_erp/core/i18n/tr.dart';
// ═══════════════════════════════════════════════════════════════════════════
// حفظُ مرتجع المشتريات — **ولا إخفاقَ صامت**
// ═══════════════════════════════════════════════════════════════════════════
//
// 🔴 بلاغُ المالك: «تأكيد المرتجع» يُغلق الحوارَ وتبقى الشاشةُ كما هي، ولا
// رسالة، والمردودُ لا يظهر في السجلّ. والسببُ سلسلةٌ من حلقتين:
//
//   ١. مرتجعُ فاتورةٍ **مسدَّدة** يُردّ كلُّه نقداً، والنقدُ الداخلُ إلى الدرج
//      يستلزم ورديّةً مفتوحة (ح‑١) ⇒ المستودعُ يرمي `ShiftRequiredException`
//      (أو غيرَه: خزنةٌ غيرُ مضبوطة، فترةٌ مقفلة، حسابٌ غيرُ مربوط…).
//   ٢. المزوّدُ يبتلع الرميةَ في `state.error` ويُرجع `false`، والشاشتان
//      **لا تقرآن `error` أصلاً** ولا تفعلان شيئاً عند `false`.
//
// فهذا المساعدُ هو المسارُ الواحدُ للشاشتين التوأمين (‏`purchase_returns_picpos`
// و`screens/purchase_returns`) — نسخُه بينهما هو «مصيدةُ النسخ §٥.٥»:
//   • «لا ورديّة» ⇒ عرضُ فتحِها ثمّ إعادةُ المحاولة (`runWithOpenShiftPrompt`)؛
//   • أيُّ إخفاقٍ آخر ⇒ حوارٌ عربيٌّ بالسبب، لا شيءَ يمرّ بلا كلمة.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../providers/purchase_return_provider.dart';
import 'open_shift_prompt.dart';

/// ينفّذ `processReturn` ويُرجع `true` إن حُفظ المرتجع.
///
/// كلُّ مسارٍ غيرُ النجاح يُعرَض للمستخدم قبل أن يعود بـ`false`.
Future<bool> savePurchaseReturnWithFeedback({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final notifier = ref.read(purchaseReturnProvider.notifier);
  var success = false;
  final outcome = await runWithOpenShiftPrompt(
    context: context,
    ref: ref,
    attempt: () async => success = await notifier.processReturn(),
  );
  if (!context.mounted) return success;

  if (outcome != ShiftPromptOutcome.completed) {
    AppToast.show(
      context,
      outcome == ShiftPromptOutcome.cancelledByUser
          ? tr('أُلغي المرتجع — لم تُفتَح وردية')
          : tr('تعذّر فتح الوردية، فلم يُنفَّذ المرتجع'),
      type: ToastType.warning,
    );
    return false;
  }
  if (success) return true;

  final message = ref.read(purchaseReturnProvider).error ?? tr('خطأ غير معروف');
  notifier.clearError();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('purchase_return_save_error'),
      title: Row(
        children: [
          const Icon(PhosphorIconsBold.warningCircle, color: AppColors.error),
          const SizedBox(width: 8),
          Flexible(child: Text(tr('تعذّر حفظ مرتجع المشتريات'))),
        ],
      ),
      content: SelectableText(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr('حسناً')),
        ),
      ],
    ),
  );
  return false;
}
