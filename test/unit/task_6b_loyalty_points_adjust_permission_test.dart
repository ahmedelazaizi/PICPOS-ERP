// Task 6b — فيكس المراجعة (Critical 1): نقاط الولاء (`loyalty_manage`).
//
// `_showAdjustPointsDialog` (إضافة/خصم نقاط على رصيد عميل) في
// `loyalty_points_tab.dart` كان بلا أي فحص صلاحية أصلاً — تبويب شقيق
// لـ`loyalty_programs_tab.dart` جوه نفس `part of 'loyalty_screen.dart'`،
// اتغطّى غلط في تعداد Task 6b الأول (اقتصر على ملف البرامج بس).
//
// هنا اختبار الدالة النقية `canAdjustLoyaltyPoints` لوحدها. اختبار السلك
// الفعلي (إن `onSelected` بينده عليها فعلاً) في
// `test/widget/task_6b_loyalty_points_menu_permission_gate_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/presentation/screens/loyalty_screen.dart';

void main() {
  group('canAdjustLoyaltyPoints — loyalty_manage', () {
    test('من غير الصلاحية ومن غير أدمن: ممنوع', () {
      expect(canAdjustLoyaltyPoints(const []), isFalse);
      expect(canAdjustLoyaltyPoints(const ['some_other_perm']), isFalse);
    });

    test('مع loyalty_manage: مسموح', () {
      expect(canAdjustLoyaltyPoints([PermissionCodes.loyaltyManage]), isTrue);
    });

    test('أدمن (system_admin أو *) بيعدّى — الكود ده مش critical financial op',
        () {
      expect(canAdjustLoyaltyPoints(const ['system_admin']), isTrue);
      expect(canAdjustLoyaltyPoints(const ['*']), isTrue);
    });
  });
}
