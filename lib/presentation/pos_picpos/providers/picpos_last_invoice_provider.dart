import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/providers.dart';
import '../../pos/providers/checkout_controller.dart';

/// آخر فاتورة **للمستخدم الحالي** — بتغذّي ترويسة الفاتورة (طلب ٨) وديالوج
/// «الفاتورة السابقة» (طلب ٩) من نفس المصدر، فمستحيل يختلفوا.
///
/// ── متطلَّب صاحب المنتج بالحرف ────────────────────────────────────────────
/// «آخر فاتورة للمستخدم الحالي، يعني لو الكاشير اتطلب منه يسترجع آخر فاتورة
/// عشان يعيد طباعتها تظهرله بتاعته — مش تستدعي بتاع جهاز تاني مختلف على
/// السيرفر أو مستخدم تاني موجود على السيرفر.»
///
/// فالتحديد على مستويين:
/// 1. **`lastInvoiceId` من `checkoutControllerProvider`** لو مضبوط — ده معرّف
///    الفاتورة اللي **هذه العملية** رحّلتها، وهو الإشارة الوحيدة في النظام اللي
///    بتفرّق هذا التِل عن غيره.
/// 2. وإلا **أحدث فاتورة `userId == المستخدم الحالي`** داخل نافذة الوردية
///    المفتوحة — نفس تحديد ديالوج الفواتير السابقة.
///
/// ── حدود التصميم: نفس الحساب على تِلّين ──────────────────────────────────
/// جدول `salesInvoices` فيه `userId` و `branchId` و**مفيش عمود جهاز/طرفية**.
/// فقبل أول بيعة في الجلسة (`lastInvoiceId == null`) الترويسة بتعرض آخر فاتورة
/// للحساب ده مهما كان التِل اللي باعها؛ بعد أول بيعة محلية تبقى صح لباقي
/// الجلسة. المتابعة الموصى بها: حفظ آخر معرّف محلي في `shared_preferences`
/// فيعيش بعد إعادة التشغيل — بلا تغيير سكيما وبلا `build_runner`.
///
/// ── ليه `authProvider.user` مش `effectiveUser` ───────────────────────────
/// `processCheckout` بيبصم `userId = originalUser?.id ?? 1`، و`originalUser`
/// هو نفسه `user`. لو قرينا `effectiveUser` كانت المطابقة تنكسر أول لحظة
/// ترقية مدير، فالكاشير يشوف «لا توجد فاتورة» وهو لسه بايع منها ثانية.
final picposLastInvoiceProvider =
    StreamProvider.autoDispose<SalesInvoiceData?>((ref) async* {
  final userId = ref.watch(authProvider.select((s) => s.user?.id));
  if (userId == null) {
    yield null;
    return;
  }

  final sessionInvoiceId =
      ref.watch(checkoutControllerProvider.select((s) => s.lastInvoiceId));
  final repo = ref.watch(salesRepositoryProvider);

  DateTime? since;
  try {
    final shift = await ref
        .read(treasuryRepositoryProvider)
        .getCurrentOpenShift(userId);
    since = shift?.startTime;
  } catch (_) {
    // وردية مش مقروءة ما تصحّش تخفي الفاتورة — نكمّل بلا حد أدنى.
    since = null;
  }

  yield* repo.watchLastInvoiceForUser(userId, since: since).asyncMap(
    (newest) async {
      if (sessionInvoiceId == null || newest?.id == sessionInvoiceId) {
        return newest;
      }
      // فاتورة أحدث ظهرت من تِل تاني بنفس الحساب: الجلسة المحلية أدق.
      return await repo.getRawInvoiceById(sessionInvoiceId) ?? newest;
    },
  );
});
