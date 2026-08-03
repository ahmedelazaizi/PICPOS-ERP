// ═══════════════════════════════════════════════════════════════════════════
// أسماء الأدوار المكرّرة بتقتل منح صلاحيات المدير — بصمت
// ═══════════════════════════════════════════════════════════════════════════
//
// `Roles` مالهاش أي قيد وحدانية على `name` (متحقَّق منه على PostgreSQL حيّة:
// القيود الموجودة هي PK(id) و UNIQUE(global_id) وبس). يعني صفّين بنفس الاسم
// حالة مسموح بيها على الديالكتين.
//
// و`syncAllPermissions()` بتدوّر على دور المدير كده:
//
//     (select(roles)..where((r) => r.name.equals('مدير النظام')))
//         .getSingleOrNull()
//
// من غير `limit(1)`. و`getSingleOrNull` في drift بترمي `StateError` لو رجع
// أكتر من صف واحد (`list.single`) — مش بترجّع الأول. النتيجة: أول ما يبقى
// فيه دورين بنفس الاسم، بلوك المنح التلقائي بيرمي، والكودات الجديدة **عمرها
// ما تتمنح لمدير النظام**. والعطل صامت لأن المنادي بيبلع الاستثناء.
//
// الاختبار ده بيثبّت إن التكرار ما يعطّلش المنح. قبل الإصلاح بيفشل
// بـ`StateError: Too many elements`.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    // نتأكد إن التركيبة اتعملت وإن البذرة الافتراضية خلصت.
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async => db.close());

  /// عدد الصلاحيات الممنوحة لدور بالاسم ده (بأول صف مطابق).
  Future<int> grantedCountForAdminRole() async {
    final row = await db.customSelect(
      "SELECT COUNT(*) AS c FROM role_permissions rp "
      "WHERE rp.role_id = (SELECT id FROM roles WHERE name = 'مدير النظام' "
      "ORDER BY id LIMIT 1)",
    ).getSingle();
    return row.read<int>('c');
  }

  test('صفّان بنفس اسم دور المدير ما يمنعوش syncAllPermissions من المنح',
      () async {
    // نتأكد الأول إن الدور موجود أصلاً — لو مش موجود الاختبار مش بيقيس حاجة.
    final before = await db.customSelect(
      "SELECT COUNT(*) AS c FROM roles WHERE name = 'مدير النظام'",
    ).getSingle();
    expect(before.read<int>('c'), greaterThanOrEqualTo(1),
        reason: 'الشرط المسبق: دور «مدير النظام» لازم يكون مبذور. '
            'من غيره الاختبار بيعدّي وهو مش بيقيس التكرار.');

    // نحاكي إعادة تشغيل البذرة: صف تاني بنفس الاسم بـglobal_id مختلف.
    // ده بالظبط اللي seedRolesAndPermissions بتعمله لأنها بتولّد UUID جديد
    // كل نداء، فـinsertOrIgnore مالهاش أي قيد تتعارض معاه.
    await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'مدير النظام',
            globalId: const Value('duplicate-role-for-test'),
          ),
        );

    final dupCount = await db.customSelect(
      "SELECT COUNT(*) AS c FROM roles WHERE name = 'مدير النظام'",
    ).getSingle();
    expect(dupCount.read<int>('c'), 2,
        reason: 'الشرط المسبق: لازم يبقى فيه صفّين فعلاً عشان الاختبار '
            'يقيس المسار المكسور.');

    // المفروض تعدّي من غير ما ترمي.
    await expectLater(
      db.syncAllPermissions(),
      completes,
      reason: 'syncAllPermissions بتستعمل getSingleOrNull بلا limit(1)، '
          'فبترمي StateError على التكرار وبلوك المنح بيموت.',
    );

    // ومش بس ما ترميش — لازم تكون فعلاً منحت.
    expect(await grantedCountForAdminRole(), greaterThan(0),
        reason: 'بعد ما تعدّي، دور المدير لازم يكون خد صلاحياته — '
            'العدّاد بصفر معناه إن البلوك اتخطّى بدل ما اشتغل.');
  });
}
