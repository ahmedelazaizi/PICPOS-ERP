// ═══════════════════════════════════════════════════════════════════════════
// المرحلة ٤ على PostgreSQL — الأعمدةُ تصل، والمُشغِّلُ **يختم الإدراج**
// ═══════════════════════════════════════════════════════════════════════════
//
// اختبارُ SQLite (`migration_v173_regulatory_sync_test`) يقيس الأعمدةَ، وهذا
// يقيس ما لا يمسّه SQLite أصلاً: أنّ `fn_bump_row_version` مركَّبٌ على
// الجداول الجديدة فيختم `last_modified_at` عند **الإدراج** — وهو الشرطُ
// الذي يرشّح به مسارُ السحب (`last_modified_at IS NOT NULL AND > since`).
//
// 🔴 **والمرحلتان ٢ و٣ تُقاسان هنا أيضاً**: كانتا في القوائم الستِّ كلِّها
// وغائبتَين عن `_syncHardenedTables` — فصفٌّ يُدرَج في `table_sections` على
// خادم PostgreSQL كان يُولَد بختمٍ فارغٍ ولا يصل عميلاً بعد أوّل سحب. لم يمسكه
// اختبارٌ واحدٌ قبل 2026-09-02. فـ`table_sections` هنا باسمها: لو أُخرجت
// من القائمة المصلَّبة عاد العطبُ لها وحدَها ومرّ حارسُ العضويّة لو أُخرجت
// من `pullTables` معها.
//
// ⚠️ يعمل عبر `dart run scripts/run_pg_tests.dart` وحدَه.

@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

import '_support/pg_fixture.dart';

const _syncColumns = <String>[
  'global_id',
  'last_modified_at',
  'deleted_at',
  'origin_client_id',
  'row_version',
];

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
    return rows
        .map((r) => (r.data['column_name'] as String).toLowerCase())
        .toSet();
  }

  test('الجداولُ الرقابيّةُ والتشغيليّةُ تصل PG بأعمدة المزامنة', () async {
    for (final t in const [
      'bank_reconciliations',
      'bank_statement_lines',
      'e_invoice_submissions',
      'field_audit_logs',
      'approval_requests',
      'cycle_count_items',
      'loyalty_transactions',
    ]) {
      final cols = await columnsOf(t);
      expect(cols, isNotEmpty, reason: 'مرساة: $t أُنشئ على PG');
      expect(cols, containsAll(_syncColumns), reason: t);
    }
  });

  test('🔴 `e_invoice_status_log` يصل PG كياناً بأعمدة المزامنة', () async {
    // كان يُبنى بكتلةِ SQL خامّةٍ في `_ensurePostgresSyncInfrastructure`
    // (٦‑١) بلا أعمدةِ مزامنة. الآن كيانٌ يبنيه `_createAllForPostgres`،
    // والكتلةُ الخامّةُ `IF NOT EXISTS` عديمةُ الأثر بعده.
    final cols = await columnsOf('e_invoice_status_log');
    expect(cols, contains('submission_id'), reason: 'مرساة: الجدولُ موجود');
    expect(cols, containsAll(_syncColumns));
  });

  test('و`e_invoice_configs` بلا `global_id` — الاستثناءُ الأمنيّ', () async {
    final cols = await columnsOf('e_invoice_configs');
    expect(cols, contains('client_secret'), reason: 'مرساة');
    expect(cols.contains('global_id'), isFalse);
  });

  test('🔴 المُشغِّلُ يختم الإدراجَ على جدولٍ من المرحلة ٤', () async {
    final id = await db.into(db.loyaltyPrograms).insert(
          const LoyaltyProgramsCompanion(
            name: Value('برنامج المرحلة ٤'),
            pointsPerUnit: Value(1),
            redemptionRate: Value(0.1),
          ),
        );
    final row = (await db
            .customSelect(
              'SELECT last_modified_at, row_version FROM loyalty_programs '
              'WHERE id = $id',
            )
            .get())
        .single
        .data;

    expect(row['last_modified_at'], isNotNull,
        reason: 'الإدراجُ بلا ختمٍ ⇒ مسارُ السحب يرشّحه فلا يصل أيَّ عميل '
            'بعد أوّل سحب. المُشغِّلُ غيرُ مركَّبٍ على الجدول — راجع '
            '`_syncHardenedTables`.');
    expect(row['row_version'], 0);

    await db.customStatement(
      "UPDATE loyalty_programs SET name = 'معدَّل' WHERE id = $id",
    );
    final after = (await db
            .customSelect(
              'SELECT row_version FROM loyalty_programs WHERE id = $id',
            )
            .get())
        .single
        .data;
    expect(after['row_version'], 1,
        reason: 'التعديلُ لم يرفع النسخةَ ⇒ تعديلُ الخادم لا يغلب على العميل');
  });

  test('🔴 وعلى جدولٍ من المرحلة ٣ — الذي كان بلا مُشغِّلٍ قبل v173',
      () async {
    final id = await db.into(db.tableSections).insert(
          const TableSectionsCompanion(name: Value('صالة المرحلة ٣')),
        );
    final row = (await db
            .customSelect(
              'SELECT last_modified_at FROM table_sections WHERE id = $id',
            )
            .get())
        .single
        .data;

    expect(row['last_modified_at'], isNotNull,
        reason: 'هذا هو العطبُ الذي مرّ صامتاً في المرحلتين ٢ و٣: القوائمُ '
            'الستُّ فيها الجدولُ والسابعةُ (‏مُشغِّلاتُ PostgreSQL) لا. '
            'قسمُ الصالة الجديدُ لا يصل الكاشير أبداً.');
  });

  test('ومرساةٌ سالبة: جدولٌ خارجَ القائمة لا يُختم', () async {
    // يثبت أنّ الفحصَين أعلاه يقيسان المُشغِّلَ لا افتراضاً على العمود:
    // `employee_leaves` تحمل `last_modified_at`? لا — فنختار جدولاً له
    // العمودُ وبلا مُشغِّل. لا يوجد اليوم بالتصميم، فالمرساةُ هي عدُّ
    // المُشغِّلات: يساوي طولَ القائمة المصلَّبة بالضبط.
    final rows = await db
        .customSelect(
          "SELECT COUNT(*)::integer AS c FROM pg_trigger "
          "WHERE tgname LIKE '%_bump_version' AND NOT tgisinternal",
        )
        .get();
    final count = (rows.single.data['c'] as num).toInt();
    expect(count, AppDatabase.syncHardenedTablesForTest.length,
        reason: 'عددُ المُشغِّلات ≠ طولَ القائمة ⇒ إمّا جدولٌ في القائمة '
            'فشل تركيبُه (‏وابتُلع في catch) وإمّا مُشغِّلٌ بائتٌ على جدولٍ '
            'خارجَها.');
  });
}
