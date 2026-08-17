// Task 7 — البيع السريع: فتح ديالوج الميزان.
//
// `pos_weight_dialog` كان فتح ديالوج إدخال الوزن (لصنف isSoldByWeight)
// شغّال لأي مستخدم من غير أي فحص صلاحية، في الفورك ين — UralCash
// (`pos_main_operations.dart`) وPicPos (`picpos_pos_operations.dart`).
//
// ── ليه فحص صريح مش PermissionGuard ────────────────────────────────────────
// `_handleProductTap` دالة imperative (async handler) جوه mixin مربوط
// بـ`ConsumerState` حقيقي بيقرا حالة السلة وإعدادات كتير — تركيبها كاملة
// يحتاج شاشة POS كاملة وقاعدة بيانات (نفس فخ Task 6a). الفحص اتستخرج
// كدالة top-level نقيّة (`canOpenPosWeightDialog`) في كل فورك — مكرَّرة
// عمداً لأن الملفين مكتبتين مختلفتين بلا نقطة مشتركة، مطابق لمعاملة
// `einvoice_cancel`/`modify_closed_period` في Task 6a (فحص منطقي بحت،
// مش اختبار wiring كامل، لنفس قيد "مفيش حدود ودجت طبيعية للفّه").
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/presentation/pos/screens/pos_main_screen.dart'
    as uralcash;
import 'package:ural_erp/presentation/pos_picpos/screens/picpos_pos_screen.dart'
    as picpos;

void main() {
  group('canOpenPosWeightDialog — UralCash (pos_main_operations.dart)', () {
    test('مرفوض من غير الكود', () {
      expect(uralcash.canOpenPosWeightDialog(const []), isFalse);
    });

    test('مسموح مع الكود', () {
      expect(
        uralcash.canOpenPosWeightDialog([PermissionCodes.posWeightDialog]),
        isTrue,
      );
    });

    test('مسموح لمدير النظام حتى من غير الكود صراحة (مش عملية مالية حرجة)',
        () {
      expect(uralcash.canOpenPosWeightDialog(const ['system_admin']), isTrue);
      expect(uralcash.canOpenPosWeightDialog(const ['*']), isTrue);
    });
  });

  group('canOpenPosWeightDialog — PicPos (picpos_pos_operations.dart)', () {
    test('مرفوض من غير الكود', () {
      expect(picpos.canOpenPosWeightDialog(const []), isFalse);
    });

    test('مسموح مع الكود', () {
      expect(
        picpos.canOpenPosWeightDialog([PermissionCodes.posWeightDialog]),
        isTrue,
      );
    });

    test('مسموح لمدير النظام حتى من غير الكود صراحة', () {
      expect(picpos.canOpenPosWeightDialog(const ['system_admin']), isTrue);
    });
  });
}
