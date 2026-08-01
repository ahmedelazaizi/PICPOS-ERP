import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';

/// إشعار غير مانع بوجود وردية مفتوحة عند مغادرة الجلسة — خروج أو تبديل.
///
/// ── ليه بقى إشعاراً بعد ما كان بوابة ─────────────────────────────────────
/// كان اسمه `ensureShiftClosed` وكان بيجبر الترصيد قبل المغادرة، بلا تجاوز
/// ولا لمدير النظام. المستخدم راجع القرار وطلب إن الوردية تفضل مفتوحة
/// ويكمّلها صاحبها لما يرجع، أو يقفلها اللي عنده `pos_shift_close` من شاشة
/// الورديات المفتوحة.
///
/// ── ليه ده مش بيكسر نسبة المبيعات ────────────────────────────────────────
/// `shifts.userId` عمود موجود من الأول، و`getCurrentOpenShift(userId)`
/// مفلترة بيه وبـ`status='open'`. يعني وردية كل كاشير مستقلة أصلاً: «ب»
/// بيبيع على ورديته هو مهما كانت وردية «أ» لسه مفتوحة. البوابة ما كانتش
/// بتحمي النسبة — كانت بتفرض انضباط الترصيد، وده اتنقل لشاشة الورديات
/// المتروكة.
///
/// بترجّع `void` عن قصد: مفيش قرار للمستدعي يتفرّع عليه، فمفيش قيمة ترجع.
/// أي مستدعي جديد بيكمّل غصب عنه — ما ينفعش تتحول لبوابة تاني بالغلط.
Future<void> notifyOpenShift({
  required BuildContext context,
  required WidgetRef ref,

  /// بيوضّح للمستخدم السياق ("قبل تسجيل الخروج" / "قبل تحويل المستخدم").
  required String reason,
}) async {
  final userId = ref.read(authProvider).user?.id;
  if (userId == null) return;

  ShiftData? openShift;
  try {
    openShift =
        await ref.read(treasuryRepositoryProvider).getCurrentOpenShift(userId);
  } catch (_) {
    // فشل الاستعلام مايعطّلش الخروج. قبل كده كان الفشل الآمن «امنع»، وده كان
    // صح وقت ما كان منع؛ دلوقتي التعطيل على إشعار هو الضرر الأكبر.
    return;
  }
  if (openShift == null || !context.mounted) return;

  AppToast.show(
    context,
    'ورديتك (#${openShift.id}) لسه مفتوحة $reason — تقدر تكمّلها لما ترجع.',
    type: ToastType.warning,
  );
}
