// إعادة الإرسال من طابور الأوفلاين كانت بتسقط الـglobalId → تنفيذ مضاعف.
//
// ── إزاي الـdedup مفروض يشتغل ────────────────────────────────────────────────
// العميل بيولّد `globalId` (UUIDv7) قبل ما يبعت، والسيرفر بيفحصه قبل التنفيذ
// ويرجّع `{'success': true, 'dedup': true}` لو شافه قبل كده. يعني إعادة
// الإرسال بعد timeout آمنة — **بشرط إن الـglobalId يوصل**.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// `offline_sync_worker._replayOperation` بيعيد بناء الطلب من الـpayload
// المخزّن. سبع cases بتمرّر `payload['globalId']` صح؛ `stock_transfers`
// كانت بتمرّر `idempotencyKey` بس — والـ`globalId` **موجود في الـpayload**
// (`cwi_trading.dart:673`) ومتاح، بس مش بيتقري.
//
// والمفتاح الممرّر بلا أثر: `/api/inventory/transfer` مش ضمن الـ٣ endpoints
// اللي بتقرا هيدر `x-idempotency-key`، والسيرفر بيعمل dedup بالـ`globalId`
// **حصرياً** (`api_data_handler.dart:2702`).
//
// السيناريو: تحويل ٥٠ كرتونة من مخزن أ لمخزن ب → الطلب وصل ونفّذ → الرد ضاع
// (انقطاع لحظي) → الصف يروح للطابور → الـdrain يعيد الإرسال بلا globalId →
// السيرفر يشوفه طلب جديد → **يخصم ٥٠ تانية**.
//
// ── ليه اختبار على استخراج الحقول مش على الـworker ──────────────────────────
// `_replayOperation` بياخد `ServerProxy` حقيقي وبيلمس قاعدة البيانات والشبكة.
// اللي انكسر هو **قراءة الحقل من الـpayload** — فده اللي اتفصل واتغطّى.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/offline_sync_worker.dart';

void main() {
  group('replayGlobalIdFrom — قراءة الـglobalId من payload مخزّن', () {
    test('بيقرا الصيغة camelCase اللي المعترض بيكتبها', () {
      expect(
        replayGlobalIdFrom(const {'fromWarehouseId': 1, 'globalId': 'g-7'}),
        'g-7',
      );
    });

    test('بيقرا الصيغة snake_case كمان — الطابور فيه الشكلين', () {
      expect(replayGlobalIdFrom(const {'global_id': 'g-9'}), 'g-9');
    });

    test('camelCase بتغلب لو الاتنين موجودين', () {
      expect(
        replayGlobalIdFrom(const {'globalId': 'new', 'global_id': 'old'}),
        'new',
      );
    });

    test('صفوف قديمة بلا globalId بترجّع null مش نص فاضي', () {
      // صفوف اتحطت في الطابور قبل ما الـglobalId يتضاف للـpayload — لازم
      // تعدّي زي الأول بدل ما تبعت '' فيتعامل معاه السيرفر كقيمة.
      expect(replayGlobalIdFrom(const {'fromWarehouseId': 1}), isNull);
      expect(replayGlobalIdFrom(const {'globalId': ''}), isNull);
      expect(replayGlobalIdFrom(const {'globalId': null}), isNull);
    });

    test('قيمة مش نص ما بتتحوّلش بالغلط', () {
      expect(replayGlobalIdFrom(const {'globalId': 12345}), isNull);
    });
  });
}
