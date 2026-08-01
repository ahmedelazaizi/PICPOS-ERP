// test/unit/payment_permission_test.dart
//
// فحص صلاحية طريقة الدفع في لوحة الدفع.
//
// ── عيبين كانوا هنا ───────────────────────────────────────────────────────
// ١. `if (auth.isAdmin || auth.isManager) return true;` — والاتنين دول
//    بيتحددوا بمطابقة اسم الدور، فأي دور اسمه فيه «مدير» كان بيعدّي بلا
//    صلاحية دفع. الأدوار المزروعة «مدير فرع» و«مدير مالي» و«مدير مخزون».
// ٢. `|| permissions.isEmpty` — مستخدم بصفر صلاحيات كان بيعدّي كل الفحوص.
//    يعني سحب كل صلاحيات الدفع من كاشير كان بيديله كلها.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/pos/widgets/payment_sheet.dart';

void main() {
  group('hasPaymentPermission', () {
    test('«مدير فرع» بلا صلاحية دفع لا يعدّي', () {
      expect(
        hasPaymentPermission(
          isSystemAdmin: false,
          permissions: const ['pos_access'],
          permCode: 'pos_payment_cash',
        ),
        isFalse,
      );
    });

    test('قائمة صلاحيات فاضية لا تعدّي — الفشل مقفول', () {
      // كان `|| permissions.isEmpty` بيرجّع true هنا.
      expect(
        hasPaymentPermission(
          isSystemAdmin: false,
          permissions: const [],
          permCode: 'pos_payment_cash',
        ),
        isFalse,
      );
    });

    test('مدير النظام يعدّي', () {
      expect(
        hasPaymentPermission(
          isSystemAdmin: true,
          permissions: const [],
          permCode: 'pos_payment_cash',
        ),
        isTrue,
      );
    });

    test('كاشير عنده الصلاحية يعدّي', () {
      expect(
        hasPaymentPermission(
          isSystemAdmin: false,
          permissions: const ['pos_payment_cash'],
          permCode: 'pos_payment_cash',
        ),
        isTrue,
      );
    });
  });
}
