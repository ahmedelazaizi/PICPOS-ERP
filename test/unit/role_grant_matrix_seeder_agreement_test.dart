// test/unit/role_grant_matrix_seeder_agreement_test.dart
//
// كل كود، لكل دور، في RoleGrantMatrix.defaultGrants بالكامل — مش
// `dashboard_access` بس — لازم يكون فعلاً ممنوح للدور المقابل بعد ما
// السيدر يزرع قاعدة جديدة، مش بس موجود كمفتاح في تعريف المصفوفة نفسها.
//
// ── ليه الترقية (Task 3d) ────────────────────────────────────────────────
// النسخة القديمة (كان اسمها dashboard_access_default_grant_test.dart)
// كانت بتفحص كود واحد بس (`dashboard_access`) من المصفوفة الثابتة، من
// غير ما تلمس قاعدة بيانات حقيقية. لو السيدر (database_seeder_permissions.dart)
// سقّط منح أي كود تاني لأي دور رغم إنه موجود في المصفوفة — بالظبط نفس
// عائلة اختلاف «الخريطة ضد القائمة» اللي راجعة تاسك ٣ج رفعتها — الاختبار
// القديم كان هيفضل أخضر لأنه بيتحقق من تعريف الثابت لكود واحد، مش من
// الأثر الفعلي بعد الزرع لكل الأكواد والأدوار.
//
// التغطية الحقيقية كانت موجودة بالصدفة في role_grant_preflight_service_test
// (بيزرع قاعدة فعلية بـ `AppDatabase.forTesting()` ويقارن كل كود في
// المصفوفة بمنح السيدر الفعلي عبر `scanMissingGrants()`). هنا بنستخدم
// نفس الـ harness والخدمة الحقيقية — مش بننسخ منطق الزرع أو الفحص — عشان
// الاعتماد ده يبقى صريح تحت الاسم اللي المطوّرين بيدوروا عليه لما يعدّلوا
// المصفوفة أو يضيفوا دور جديد.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/role_grant_preflight_service.dart';

void main() {
  test(
      'كل كود في RoleGrantMatrix.defaultGrants ممنوح فعلاً في قاعدة مزروعة '
      'بالسيدر', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    final report = await RoleGrantPreflightService(db).scanMissingGrants();

    expect(report.totalMissingPairs, equals(0),
        reason: 'كود في المصفوفة مش ممنوح فعلياً بعد زرع السيدر — يعني '
            'المصفوفة والسيدر مختلفين (نفس عائلة اختلاف الخريطة/القائمة، '
            'لكن هنا بين المصفوفة والسيدر):\n'
            '${report.missingByKnownRole}');
  });
}
