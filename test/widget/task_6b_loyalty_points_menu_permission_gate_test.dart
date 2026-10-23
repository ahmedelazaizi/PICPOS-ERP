// Task 6b — فيكس المراجعة (Critical 1 + التزام "اختبر السلك مش الدالة
// لوحدها"): قائمة إضافة/خصم نقاط الولاء.
//
// نفس شكل فيكس `OfferCardActionsMenu` — القائمة كلها (`PopupMenuButton` +
// منطق `onSelected`) اتنقلت لودجت top-level مستقل (`LoyaltyPointsAdjustMenu`
// في `loyalty_points_tab.dart`) بياخد `onAdd`/`onSubtract` كبارامترات
// بسيطة، عشان فتح الميني واختيار عنصر يتفحصوا فعلياً من غير شاشة
// `LoyaltyScreen`/قاعدة بيانات — لو حد شال شرط `canAdjustLoyaltyPoints` من
// جوه `onSelected`، الاختبارات دي هتفشل (مش زي فحص الدالة لوحدها).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/screens/loyalty_screen.dart';

void main() {
  Future<void> pumpMenu(
    WidgetTester tester,
    List<String> perms, {
    required VoidCallback onAdd,
    required VoidCallback onSubtract,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: LoyaltyPointsAdjustMenu(onAdd: onAdd, onSubtract: onSubtract),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> openMenuAndSelect(
    WidgetTester tester,
    String itemText, {
    bool settleAfterToast = false,
  }) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(itemText));
    await tester.pumpAndSettle();
    if (settleAfterToast) {
      // مدة عرض التنبيه (2500ms) + الـreverse animation (300ms) — لتصريف
      // الـTimer بتاع `AppToast` قبل ما الاختبار يخلص.
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  group('LoyaltyPointsAdjustMenu — «إضافة نقاط»', () {
    testWidgets('بدون loyalty_manage: onAdd ما بيتنفّذش وبيظهر تنبيه رفض',
        (tester) async {
      var added = false;
      await pumpMenu(tester, const [], onAdd: () => added = true, onSubtract: () {});

      await openMenuAndSelect(tester, 'إضافة نقاط', settleAfterToast: true);

      expect(added, isFalse);
    });

    testWidgets('مع loyalty_manage: onAdd بيتنفّذ فعلاً', (tester) async {
      var added = false;
      await pumpMenu(
        tester,
        [PermissionCodes.loyaltyManage],
        onAdd: () => added = true,
        onSubtract: () {},
      );

      await openMenuAndSelect(tester, 'إضافة نقاط');

      expect(added, isTrue);
    });
  });

  group('LoyaltyPointsAdjustMenu — «خصم نقاط»', () {
    testWidgets('بدون loyalty_manage: onSubtract ما بيتنفّذش وبيظهر تنبيه رفض',
        (tester) async {
      var subtracted = false;
      await pumpMenu(
        tester,
        const [],
        onAdd: () {},
        onSubtract: () => subtracted = true,
      );

      await openMenuAndSelect(tester, 'خصم نقاط', settleAfterToast: true);

      expect(subtracted, isFalse);
    });

    testWidgets('مع loyalty_manage: onSubtract بيتنفّذ فعلاً', (tester) async {
      var subtracted = false;
      await pumpMenu(
        tester,
        [PermissionCodes.loyaltyManage],
        onAdd: () {},
        onSubtract: () => subtracted = true,
      );

      await openMenuAndSelect(tester, 'خصم نقاط');

      expect(subtracted, isTrue);
    });
  });
}
