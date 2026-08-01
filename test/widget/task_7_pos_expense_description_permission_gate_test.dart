// Task 7 — نقطة البيع: وصف حر لسند المصروف.
//
// `pos_expense_description` كان حقل الوصف في ديالوج المصروف السريع دايماً
// ظاهر من غير أي فحص، رغم إن الحقل الشقيق (نوع المصروف، `_canSelectType`)
// مربوط بصلاحيته الخاصة من زمان.
//
// ── ليه مش الديالوج كامل ──────────────────────────────────────────────────
// `PosExpenseDialog._checkPermissions()` بتنادي `IAuthRepository.
// userHasPermission` بشكل async جوه initState — تركيبها محتاج fake كامل
// لـ`IAuthRepository` أو قاعدة بيانات حقيقية. الحقل نفسه (`if (canEnter)
// TextField(...)`) اتستخرج كدالة top-level (`buildPosExpenseDescriptionField`)
// عشان نختبر التحكّم في الظهور مباشرة — نفس منطق الجلب غير المتزامن للحقل
// الشقيق `_canSelectType` أصلاً مالوش اختبار في هذا الملف لنفس السبب.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/pos/widgets/pos_expense_dialog.dart';

void main() {
  group('pos_expense_description — حقل الوصف في ديالوج المصروف', () {
    testWidgets('بدون الصلاحية: الحقل مش موجود خالص', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildPosExpenseDescriptionField(
              canEnter: false,
              controller: controller,
            ),
          ),
        ),
      );

      expect(find.text('الوصف (اختياري)'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('مع الصلاحية: الحقل ظاهر وقابل للكتابة', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildPosExpenseDescriptionField(
              canEnter: true,
              controller: controller,
            ),
          ),
        ),
      );

      expect(find.text('الوصف (اختياري)'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'صيانة مكيف');
      expect(controller.text, 'صيانة مكيف');
    });
  });
}
