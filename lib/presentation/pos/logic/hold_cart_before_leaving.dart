import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../providers/cart_controller.dart';

/// نتيجةُ محاولة تعليق سلّة البيع قبل مغادرتها.
enum CartHoldOutcome {
  /// السلّةُ فارغة — لا شيء يُعلَّق.
  empty,

  /// عُلّقت الفاتورةُ (و`CartController.holdOrder` فرّغ السلّةَ بعد الحفظ).
  held,

  /// فشل التعليق — السلّةُ **لم تُمسّ** (`holdOrder` يفرّغ عند النجاح فقط).
  failed,
}

/// يعلّق فاتورة البيع الحالية بآلية التعليق الوحيدة (`CartController.holdOrder`
/// ⇒ `HoldOrderUseCase`) ولا يُفقد السلّةَ بصمت: كلُّ فشلٍ (استثناءٌ أو
/// `null` من الحفظ) يُسجَّل ويُرجَع [CartHoldOutcome.failed] والسلّةُ كما هي.
///
/// معزولةٌ عن `WidgetRef` لتُختبر بلا قاعدة بيانات: [itemCount] و[hold]
/// يُحقنان، وللاختبار [onError] بدل المسجِّل.
Future<CartHoldOutcome> holdCartOrKeep({
  required int itemCount,
  required Future<String?> Function() hold,
  String reason = '',
  void Function(String message, Object? error, StackTrace? stack)? onError,
}) async {
  if (itemCount <= 0) return CartHoldOutcome.empty;
  void report(String m, [Object? e, StackTrace? s]) => onError != null
      ? onError(m, e, s)
      : AppLogger.instance.error(m, e, s, 'CART');
  try {
    final holdNum = await hold();
    if (holdNum != null) return CartHoldOutcome.held;
    report('تعليق السلة قبل المغادرة فشل ($reason) — السلة باقية', null);
  } catch (e, s) {
    report('تعليق السلة قبل المغادرة أخفق ($reason) — السلة باقية', e, s);
  }
  return CartHoldOutcome.failed;
}

/// نسخةُ الواجهة: تقرأ سلّةَ البيع الحيّة وتعلّقها عبر `cartControllerProvider`.
Future<CartHoldOutcome> holdSaleCartBeforeLeaving(
  WidgetRef ref, {
  required String reason,
}) =>
    holdCartOrKeep(
      itemCount: ref.read(cartControllerProvider).items.length,
      hold: () => ref.read(cartControllerProvider.notifier).holdOrder(),
      reason: reason,
    );
