// Task 6a — طبقة الإدارة: `modify_closed_period` (إعادة فتح فترة مقفلة).
//
// زرار «إعادة فتح الفترة» في fiscal_year_screen.dart كان بينفّذ من غير أي
// فحص. الفحص المضاف فحص صريح (مش PermissionGuard) عشان `modify_closed_period`
// كود فصل سلطات (segregation of duties) — لازم يتمنح صراحة للمستخدم نفسه،
// من غير أي مسار «موافقة مدير» بديل، حتى مدير النظام نفسه.
//
// القرار مستخرج في دالة top-level (`canReopenClosedPeriod`) واستخدمناها هنا
// مباشرة — نفس النمط اللي Task 2 (`hasPaymentPermission`) وTask 2b
// (`canCloseAppWithoutPassword`) استخدموه: فحص الدالة الحقيقية بدل تركيب
// شاشة `FiscalYearScreen` كاملة بقاعدة بيانات وسنة مالية وفترة مقفلة.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/presentation/screens/fiscal_year_screen.dart';

void main() {
  group('canReopenClosedPeriod — modify_closed_period', () {
    test('من غير الصلاحية: ممنوع', () {
      expect(canReopenClosedPeriod(const []), isFalse);
      expect(canReopenClosedPeriod(const ['some_other_perm']), isFalse);
    });

    test('مع modify_closed_period صراحة: مسموح', () {
      expect(
        canReopenClosedPeriod([PermissionCodes.modifyClosedPeriod]),
        isTrue,
      );
    });

    test('حتى مع system_admin أو *: ممنوع — كود فصل سلطات بلا أي استثناء',
        () {
      expect(canReopenClosedPeriod(const ['system_admin']), isFalse);
      expect(canReopenClosedPeriod(const ['*']), isFalse);
    });
  });
}
