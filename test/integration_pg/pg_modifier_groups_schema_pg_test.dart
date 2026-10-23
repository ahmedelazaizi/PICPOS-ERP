// ═══════════════════════════════════════════════════════════════════════════
// ٦‑٢ — `modifier_groups` على PostgreSQL: تعريفان لجدولٍ واحد
// ═══════════════════════════════════════════════════════════════════════════
//
// الجدولُ **بلا صنفِ drift** (‏SQL خامٌّ من هجرة v70)، فـ`_createAllForPostgres`
// لا يُنشئه لأنّها تمرُّ على `allSchemaEntities` وحدَها. ومَن يُنشئه على PG هو
// خطوةُ 4.5 في `_ensurePostgresSyncInfrastructure` — وكانت تحمل شكلاً **مخالفاً**
// للشكل الذي يكتبه `ensureModifierTables()`:
//
//   الخطوةُ 4.5:      (id, name, min_selection, max_selection, is_active)
//   الشكلُ الصحيح:    (id, name, type, min_select, max_select, is_required,
//                      is_active, sort_order)
//
// و`CREATE TABLE IF NOT EXISTS` تجعل **الأسبقَ يفوز**، والأسبقُ على PG هو
// الإقلاعُ لا الشاشة — فـ`ensureTables()` التي تناديها شاشةُ الإعدادات تصير
// بلا أثر. والنتيجةُ أنّ `createModifierGroup` — وهي تكتب
// `(name, type, min_select, max_select, is_required, sort_order)` — تنهار على
// **كلِّ** قاعدةِ PostgreSQL، فالميزةُ معطَّلةٌ بالكامل لا «تقرأ خطأً».
//
// وأسوأ: النداءُ في `modifier_management_widget.dart` بلا `try`، فالحوارُ
// يُغلَق ولا يُضاف صفٌّ ولا تظهر رسالة.
//
// ⚠️ يعمل عبر `melos test:pg` وحدَه.

@Tags(['pg'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

import '_support/pg_fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    final fx = await bootPgTestSchema();
    addTearDown(fx.tearDown);
    db = fx.db;
    await db.select(db.accounts).get(); // يُجبر الهجرةَ ومسارَ الإقلاع
  });

  Future<Set<String>> columnsOf(String table) async {
    final rows = await db
        .customSelect(
          "SELECT column_name FROM information_schema.columns "
          "WHERE table_name = '$table'",
        )
        .get();
    return rows.map((r) => r.data['column_name'] as String).toSet();
  }

  test('قاعدةُ PostgreSQL جديدةٌ تحمل شكلَ `modifier_groups` الصحيح', () async {
    final cols = await columnsOf('modifier_groups');
    expect(cols, isNotEmpty, reason: 'مرساة: الجدولُ أُنشئ فعلاً');
    expect(
      cols,
      containsAll(<String>[
        'type',
        'min_select',
        'max_select',
        'is_required',
        'sort_order',
      ]),
      reason: 'هذه الخمسةُ هي ما يكتبه `createModifierGroup`؛ '
          'شكلُ الخطوة 4.5 القديم كان يفقدها كلَّها',
    );
  });

  test('إنشاءُ مجموعةِ إضافاتٍ يمرُّ ويعود بكلِّ حقولها', () async {
    final id = await db.createModifierGroup(
      name: 'إضافاتُ الساندويتش',
      type: 'option',
      minSelect: 1,
      maxSelect: 3,
      isRequired: true,
      sortOrder: 2,
    );
    expect(id, greaterThan(0));

    final groups = await db.getAllModifierGroups();
    final saved = groups.firstWhere((g) => g.id == id);

    expect(saved.name, 'إضافاتُ الساندويتش');
    expect(saved.type, 'option');
    expect(saved.minSelect, 1);
    expect(saved.maxSelect, 3);
    expect(saved.isRequired, isTrue);
    expect(saved.sortOrder, 2);
    expect(saved.isActive, isTrue);
  });

  test('و`ensureTables()` من الشاشة لا تُفسد شكلاً قائماً', () async {
    // الشاشةُ تناديها عند الفتح؛ وهي `CREATE TABLE IF NOT EXISTS` فلا أثرَ لها
    // على جدولٍ موجود — الحارسُ هنا أنّ الشكلَ يبقى صحيحاً بعدها.
    await db.ensureModifierTables();
    final cols = await columnsOf('modifier_groups');
    expect(
      cols,
      containsAll(<String>[
        'type',
        'min_select',
        'max_select',
        'is_required',
        'sort_order',
      ]),
    );
    final id = await db.createModifierGroup(name: 'بعد ensureTables');
    expect(id, greaterThan(0));
  });
}
