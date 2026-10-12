// سيناريو (م): مخازن bins وFEFO — مغطّى بالكامل في اختبارات قائمة فلا يُكرَّر هنا:
//   test/integration/mc1_bins_fefo_test.dart          (bins + FEFO عبر المسار الحي)
//   test/integration/batch_fefo_expiry_order_test.dart (ترتيب الصرف حسب الانتهاء)
//   test/integration/batch_quantity_conservation_test.dart · batch_warehouse_isolation_test.dart
// الملف يوثّق الحدّ ويحجز موضعاً لسيناريو مبيعات→دفعات شامل لاحقاً.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'بيع عبر الـorchestrator يصرف من أقرب دفعة انتهاءً ويطابق قيد التكلفة بتكلفة الدفعة',
    () {},
    skip: 'مغطّى في test/integration/mc1_bins_fefo_test.dart (وbatch_fefo_expiry_order_test.dart)؛ '
        'لم يُكرَّر. الجزء غير المغطّى: ربط تكلفة الدفعة الفعلية بقيد COGS من الـorchestrator.',
  );
}
