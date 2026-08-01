// Task 7 — نقطة البيع: طباعة أوامر الشغل (تذاكر المطبخ).
//
// `pos_work_order` كان زرار (إعادة) طباعة أمر شغل شغّال لأي مستخدم من غير
// أي فحص صلاحية في مسارين: إعادة طباعة فاتورة سابقة
// (`pos_main_operations.dart`) وطباعة أمر شغل طاولة
// (`table_order_dialogs.dart`).
//
// ── ليه فحص صريح مش PermissionGuard ────────────────────────────────────────
// نفس سبب `pos_weight_dialog` فوق — الدالتين imperative handlers جوه mixins
// مربوطة بشاشات حقيقية، فالفحص المنطقي اتستخرج كدالة top-level نقيّة
// (`canPrintPosWorkOrder`) مكرَّرة في الملفين (مكتبتين مختلفتين).
//
// ── مسار تلاتت مش مغطّى هنا ────────────────────────────────────────────────
// زرار الطباعة في `held_orders_dialog.dart` اتلفّ بـ`PermissionGuard` widget
// عادي (نفس شكل زرارَي استرجاع/حذف جنبه) — مغطّى بملف widget منفصل
// (`task_7_held_orders_work_order_permission_gate_test.dart`) لأنه شكل
// مختلف (widget-level guard، مش inline check).
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/presentation/pos/screens/pos_main_screen.dart'
    as uralcash;
import 'package:ural_erp/presentation/screens/tables_screen.dart' as tables;

void main() {
  group('canPrintPosWorkOrder — إعادة طباعة من فاتورة سابقة (pos_main_operations.dart)',
      () {
    test('مرفوض من غير الكود', () {
      expect(uralcash.canPrintPosWorkOrder(const []), isFalse);
    });

    test('مسموح مع الكود', () {
      expect(
        uralcash.canPrintPosWorkOrder([PermissionCodes.posWorkOrder]),
        isTrue,
      );
    });

    test('مسموح لمدير النظام حتى من غير الكود صراحة', () {
      expect(uralcash.canPrintPosWorkOrder(const ['system_admin']), isTrue);
    });
  });

  group('canPrintPosWorkOrder — طباعة أمر شغل طاولة (table_order_dialogs.dart)',
      () {
    test('مرفوض من غير الكود', () {
      expect(tables.canPrintPosWorkOrder(const []), isFalse);
    });

    test('مسموح مع الكود', () {
      expect(
        tables.canPrintPosWorkOrder([PermissionCodes.posWorkOrder]),
        isTrue,
      );
    });

    test('مسموح لمدير النظام حتى من غير الكود صراحة', () {
      expect(tables.canPrintPosWorkOrder(const ['*']), isTrue);
    });
  });
}
