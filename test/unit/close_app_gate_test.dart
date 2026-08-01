// test/unit/close_app_gate_test.dart
//
// مين يقدر يقفل البرنامج من غير كلمة سر مدير؟
//
// ── الباج ─────────────────────────────────────────────────────────────────
// الشرط كان بيسيب فرع `(role?.isSystemRole ?? false)` — و`isSystemRole` مش
// إشارة أقدمية. الأدوار المزروعة كنظام: مدير النظام، **كاشير**، مخزني،
// محاسب، مدير مالي. فالكاشير كان بيقفل البرنامج بلا كلمة سر، وهي بالظبط
// الحالة اللي البوابة موجودة عشانها.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/app_main_screen.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/database/database.dart';

// نفس مُساعِد بناء `AuthState` من test/unit/role_name_bypass_test.dart
// (Task 1) — منقول هنا بالحرف بدل اختراع واحد جديد، لأنه بيتعامل مع
// مُنشئات drift المولَّدة (Role/User/UserWithRole) وحقولها الإلزامية.
AuthState authStateForRole(String name, {required bool isSystemRole}) {
  // ملاحظة: `Role`/`User` مولّدين بـ drift (database.g.dart)، وفيهم حقول
  // إلزامية زيادة عن اللي في مسودة المهمة (rowVersion, defaultScreen,
  // discountLimitIsPercent, forcePasswordChange) — مضاف قيم افتراضية ليها
  // عشان الاختبار يبني، من غير ما تأثر على الأسيرشنز المطلوبة.
  final role = Role(
    id: 2,
    name: name,
    description: null,
    isSystemRole: isSystemRole,
    globalId: null,
    createdAt: DateTime(2026, 1, 1),
    rowVersion: 1,
  );
  final user = User(
    id: 5,
    username: 'u',
    displayName: 'u',
    passwordHash: 'h',
    passwordSalt: 's',
    roleId: 2,
    isActive: true,
    isLocked: false,
    pin: null,
    defaultScreen: 'pos',
    discountLimitIsPercent: true,
    forcePasswordChange: false,
    createdAt: DateTime(2026, 1, 1),
    rowVersion: 1,
  );
  return AuthState(userWithRole: UserWithRole(user: user, role: role));
}

void main() {
  group('canCloseAppWithoutPassword', () {
    test('كاشير — دور نظام لكنه مش مدير — لا يعدّي', () {
      expect(canCloseAppWithoutPassword(
          authStateForRole('كاشير', isSystemRole: true)), isFalse);
    });

    test('مخزني ومحاسب ومدير مالي لا يعدّوا', () {
      for (final name in ['مخزني', 'محاسب', 'مدير مالي']) {
        expect(
          canCloseAppWithoutPassword(
              authStateForRole(name, isSystemRole: true)),
          isFalse,
          reason: '$name دور نظام بس مش مدير النظام',
        );
      }
    });

    test('مدير النظام يعدّي', () {
      expect(canCloseAppWithoutPassword(
          authStateForRole('مدير النظام', isSystemRole: true)), isTrue);
    });

    test('بلا دور لا يعدّي', () {
      expect(canCloseAppWithoutPassword(const AuthState()), isFalse);
    });
  });
}
