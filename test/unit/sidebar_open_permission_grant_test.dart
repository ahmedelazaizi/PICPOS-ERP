// ═══════════════════════════════════════════════════════════════════════════
// §٤ — صلاحيةُ فتح القائمة الجانبية تصل الأدوارَ فعلاً
// ═══════════════════════════════════════════════════════════════════════════
//
// ── لماذا اختبارُ منحٍ لا اختبارُ إنفاذ ─────────────────────────────────────
// `permission_enforcement_coverage_test` يثبت أن للكود موضعَ إنفاذٍ في `lib/`،
// وهذا نصفُ الحكاية. والنصفُ الذي يسقط صامتاً هو **المنح**: كودٌ يُزرع صفّاً
// في القاعدة ولا يملكه أحد، فيبقى مربّعُ الاختيار مطفأً لكلّ دورٍ والميزةُ
// كأنها غيرُ موجودة. وقع هذا حرفياً مع `tables_view` و`kitchen_view` — كودان
// منفَّذان بلا دورٍ واحدٍ يملكهما في المصفوفة ولا في البذرة.
//
// ── وما الذي يحرسه هذا الملفّ بالضبط ────────────────────────────────────────
// `isOriginallyManager` فحصُ **نصٍّ على اسم الدور**: كلُّ دورٍ اسمُه يحوي
// «مدير» مُعفىً اليومَ من حوار كلمة المرور بلا نظرٍ في صلاحياته. فلو زُرع
// الكودُ بلا منحٍ لهذه الأدوار لظهر المربّعُ **مطفأً وهي مُعفاةٌ فعلاً** —
// وهو أسوأُ من الثقب: ضابطٌ يكذب على من يقرأه.
//
// وفي المقابل «كاشير» يجب أن يبقى **بلا** المنحة: وجودُ المربّع فارغاً هو
// بعينه ما طلبه المالك — أن يؤشّره لمن يشاء بدل أن تكون الميزةُ حكراً على
// المسمّى الوظيفيّ.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/core/permissions/role_grant_matrix.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  group('مصفوفةُ المنح', () {
    test('الأدوارُ المُعفاةُ باسمها تملك الكودَ صراحةً', () {
      for (final role in const ['مدير فرع', 'مدير مالي', 'مدير مخزون']) {
        expect(
          RoleGrantMatrix.defaultGrants[role],
          contains(PermissionCodes.systemSidebarOpen),
          reason: '«$role» مُعفىً بـisOriginallyManager فيلزم أن يظهر مؤشَّراً',
        );
      }
    });

    test('كاشير بلا المنحة — والمربّعُ الفارغُ هو المطلوب', () {
      expect(
        RoleGrantMatrix.defaultGrants['كاشير'],
        isNot(contains(PermissionCodes.systemSidebarOpen)),
      );
    });
  });

  group('البذرة', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    test('الكودُ مزروعٌ صفّاً في قاعدةٍ جديدة', () async {
      final row = await (db.select(db.permissions)
            ..where((p) => p.code.equals(PermissionCodes.systemSidebarOpen)))
          .getSingleOrNull();

      expect(row, isNotNull, reason: 'الكودُ غيرُ مزروعٍ فلا يظهر في الشاشة');
      expect(row!.category, 'system');
    });

    test('«مدير فرع» يملكه فعلاً بعد الزرع', () async {
      final role = await (db.select(db.roles)
            ..where((r) => r.name.equals('مدير فرع')))
          .getSingleOrNull();
      expect(role, isNotNull, reason: 'الدورُ نفسُه غيرُ مزروع');

      // ⚠️ الحكمُ على المنح لا على وجود الصفّ: `seedRolesAndPermissions`
      // يستعمل `insertOrIgnore`، و`syncAllPermissions` يزرع الكودَ ولا
      // يمنحه — فالوجودُ وحدَه لا يدلّ على شيء.
      final held = await db.roleHasPermission(
        role!.id,
        PermissionCodes.systemSidebarOpen,
      );
      expect(held, isTrue);
    });

    test('«كاشير» لا يملكه بعد الزرع', () async {
      final role = await (db.select(db.roles)
            ..where((r) => r.name.equals('كاشير')))
          .getSingleOrNull();
      expect(role, isNotNull);

      final held = await db.roleHasPermission(
        role!.id,
        PermissionCodes.systemSidebarOpen,
      );
      expect(held, isFalse);
    });
  });
}
