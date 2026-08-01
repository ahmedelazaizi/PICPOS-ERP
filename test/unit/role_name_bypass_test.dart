// test/unit/role_name_bypass_test.dart
//
// دور اسمه فيه «مدير» ما يتجاوزش الصلاحيات.
//
// `isManager` بتتحدد بمطابقة نص اسم الدور، وأربعة أدوار مزروعة اسمها فيه
// «مدير» (مدير النظام/مالي/فرع/مخزون). ٨ مواضع كانت بتستعمل
// `isAdmin || isManager` كتجاوز كامل — فسحب صلاحية من «مدير فرع» ما كانش
// بيعمل حاجة. ده اللي البلاغ كان عنه.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/database/database.dart';

AuthState _stateWithRole(String name, {required bool isSystemRole}) {
  // ملاحظة: `Role`/`User` مولّدين بـ drift (database.g.dart)، وفيهم حقول
  // إلزامية زيادة عن اللي في مسودة المهمة (rowVersion, defaultScreen,
  // discountLimitIsPercent, forcePasswordChange) — مضاف قيم افتراضية ليها
  // عشان الاختبار يبني، من غير ما تأثر على الأسيرشنز الخمسة المطلوبة.
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
  group('hasSystemAdminBypass', () {
    test('«مدير فرع» لا يتجاوز — ده جوهر البلاغ', () {
      final s = _stateWithRole('مدير فرع', isSystemRole: true);
      expect(s.isManager, isTrue, reason: 'isManager التجميلية زي ما هي');
      expect(s.hasSystemAdminBypass, isFalse,
          reason: 'التجاوز لازم يبقى على مدير النظام وبس');
    });

    test('«مدير مالي» و«مدير مخزون» لا يتجاوزوا', () {
      expect(_stateWithRole('مدير مالي', isSystemRole: true)
          .hasSystemAdminBypass, isFalse);
      expect(_stateWithRole('مدير مخزون', isSystemRole: true)
          .hasSystemAdminBypass, isFalse);
    });

    test('«مدير النظام» يتجاوز', () {
      expect(_stateWithRole('مدير النظام', isSystemRole: true)
          .hasSystemAdminBypass, isTrue);
    });

    test('دور مخصص اسمه «مدير النظام» لكنه مش دور نظام لا يتجاوز', () {
      // من غير الشرط ده، أي مشغّل يقدر يخترع دور بالاسم ده ويتجاوز كل حاجة.
      expect(_stateWithRole('مدير النظام', isSystemRole: false)
          .hasSystemAdminBypass, isFalse);
    });

    test('بلا دور لا يتجاوز', () {
      expect(const AuthState().hasSystemAdminBypass, isFalse);
    });
  });
}
