// test/unit/dashboard_access_default_grant_test.dart
//
// كل دور تشغيلي لازم ياخد `dashboard_access` افتراضياً.
//
// ── ليه ───────────────────────────────────────────────────────────────────
// قبل ما الشاشة تتبوّب بالكود ده، لوحة التحكم كانت بتتحقن في المسموح قسراً
// فالكل بيشوفها. لما بقت متبوّبة فعلاً، الأدوار اللي مالهاش الكود فقدت
// الشاشة — وده أثر جانبي مش قرار. الهدف إن المدير يقدر يسحبها، مش إنها
// تتسحب لوحدها عند الترقية.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/role_grant_matrix.dart';

void main() {
  test('كل دور في المصفوفة عنده dashboard_access', () {
    final missing = <String>[];
    RoleGrantMatrix.defaultGrants.forEach((role, codes) {
      if (!codes.contains('dashboard_access')) missing.add(role);
    });
    expect(missing, isEmpty,
        reason: 'الأدوار دي هتفقد شاشة الرئيسية عند الترقية: $missing');
  });
}
