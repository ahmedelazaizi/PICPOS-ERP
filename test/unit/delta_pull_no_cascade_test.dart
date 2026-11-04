// R5 (docs/plans/2026-10-30-review-stability-sustainability.md): سحبُ صفٍّ
// أبٍ معدَّل عبر `_upsertRow` (INSERT OR REPLACE) كان يحذف الصفَّ ثم يعيد
// إدراجه فيُطلق ON DELETE CASCADE على التوابع (foreign_keys=ON)، والسحبُ
// تفاضليٌّ فلا تعود. الاختبار يُثبت أنّ التوابعَ تنجو بعد السحب.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    DeltaPullService.instance.initialize(db);
    await db.ensureModifierTables(); // جداول الإضافات خارج مخطط drift
  });
  tearDown(() => db.close());

  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.first as int;

  Future<void> seed() async {
    await db.customStatement(
        "INSERT INTO products (id, code, name, global_id) "
        "VALUES (41, 'P-1', 'صنف', 'prod-gid-1')");
    await db.customStatement(
        "INSERT INTO modifier_groups (id, name) VALUES (7, 'حجم')");
    await db.customStatement(
        "INSERT INTO modifier_items (id, group_id, name) VALUES (1, 7, 'كبير')");
    await db.customStatement(
        'INSERT INTO product_modifier_groups (product_id, modifier_group_id) '
        'VALUES (41, 7)');
  }

  test('foreign_keys مفعّل في قاعدة الاختبار (شرط صلاحية الدليل)', () async {
    final r = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(r.data.values.first, 1);
  });

  test('سحبُ صنفٍ معدَّل لا يمسح product_modifier_groups', () async {
    await seed();
    await DeltaPullService.instance.upsertRowForTest('products', {
      'id': 41,
      'global_id': 'prod-gid-1',
      'code': 'P-1',
      'name': 'صنف معدَّل',
      'sale_price': 12.5,
      'last_modified_at': 1700000000,
      'row_version': 2,
    });
    expect(await count("SELECT COUNT(*) FROM products WHERE name='صنف معدَّل'"),
        1,
        reason: 'الصفُّ طُبِّق فعلاً');
    expect(await count('SELECT COUNT(*) FROM product_modifier_groups'), 1,
        reason: 'REPLACE على الأب يطلق CASCADE ويمسح الربط');
  });

  test('سحبُ مجموعةِ إضافاتٍ معدَّلة لا يمسح عناصرها ولا ربطها', () async {
    await seed();
    await DeltaPullService.instance.upsertRowForTest('modifier_groups', {
      'id': 7,
      'name': 'حجم معدَّل',
      'last_modified_at': 1700000000,
      'row_version': 2,
    });
    expect(
        await count("SELECT COUNT(*) FROM modifier_groups "
            "WHERE name='حجم معدَّل'"),
        1,
        reason: 'الصفُّ طُبِّق فعلاً');
    expect(await count('SELECT COUNT(*) FROM modifier_items'), 1,
        reason: 'عناصر المجموعة مُسحت بالـCASCADE');
    expect(await count('SELECT COUNT(*) FROM product_modifier_groups'), 1,
        reason: 'ربط الصنف بالمجموعة مُسح بالـCASCADE');
  });
}
