// ═══════════════════════════════════════════════════════════════════════════
// فهارسُ drift على PostgreSQL — كانت غائبةً عن آخرها
// ═══════════════════════════════════════════════════════════════════════════
//
// كلُّ `@TableIndex` في المستودع يُولَّد بلهجةِ SQLite وحدَها (خيارُ `dialects`
// في `build.yaml` لا يذكر postgres)، وdrift يؤكّد على وجود اللهجة قبل التنفيذ:
//   «Tried running SQL optimized for … SqlDialect.sqlite. However, the
//    database is running SqlDialect.postgres.»
//
// ومسارا المعالجة كلاهما كانا يعيدان نداءَ `Migrator.create` نفسِه فيفشلان
// بعينِ السبب: مسارُ الإنشاء الأوّل (`_createAllForPostgres`) ومسارُ التطابق
// كلَّ إقلاع (`_ensurePostgresSchemaParity`). فالنتيجةُ المقيسة 2026-08-31 على
// قاعدةٍ حيّة: **١٤٨ من ١٤٨** فهرساً غائبة — وPostgreSQL هي خلفيّةُ الخادم في
// تنصيبة العميل/المرآة، أي أنّ كلّ استعلامٍ يعتمدها كان يمسح جدولَه كاملاً.
//
// والعلاجُ بلا codegen: الجملُ المولَّدةُ محمولةٌ حرفيّاً
// (‏`CREATE INDEX idx_accounts_code ON accounts (code)`) فتُنفَّذ خامّاً.
//
// ⚠️ يعمل عبر `melos test:pg` وحدَه.

@Tags(['pg'])
library;

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

import '_support/pg_fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    final fx = await bootPgTestSchema();
    addTearDown(fx.tearDown);
    db = fx.db;
    await db.select(db.accounts).get(); // يُجبر الهجرةَ ومسارَ الإقلاع
  });

  test('كلُّ فهرسٍ مُعلَنٍ في drift موجودٌ فعلاً في `pg_indexes`', () async {
    final declared = db.allSchemaEntities.whereType<Index>().toList();

    // مرساة: الاستخراجُ يعمل — لو عاد فارغاً لمرَّ التوكيدُ التالي زوراً.
    expect(declared.length, greaterThan(100),
        reason: 'المستودعُ يُعلن أكثرَ من مئةِ فهرسٍ بـ@TableIndex');

    final rows = await db
        .customSelect("SELECT indexname FROM pg_indexes WHERE schemaname = 'public'")
        .get();
    final present = rows
        .map((r) => (r.data['indexname'] as String).toLowerCase())
        .toSet();

    final missing = declared
        .map((i) => i.entityName.toLowerCase())
        .where((n) => !present.contains(n))
        .toList()
      ..sort();

    expect(missing, isEmpty,
        reason: 'غابت ${missing.length} من ${declared.length} فهرساً. '
            'أوّلُ خمسةٍ: ${missing.take(5).join(", ")}');
  });

  test('جملةُ الفهرس المحمولةُ تحمل `IF NOT EXISTS` فتصلح للشفاء المتكرّر',
      () async {
    final declared = db.allSchemaEntities.whereType<Index>().toList();
    expect(declared, isNotEmpty, reason: 'مرساة');

    for (final index in declared.take(5)) {
      final sql = db.pgPortableIndexSql(index);
      expect(sql.toUpperCase(), contains('IF NOT EXISTS'),
          reason: 'بلا هذا يفشل الشفاءُ على قاعدةٍ تحمل الفهرسَ أصلاً');
      // وإعادةُ التنفيذ على قاعدةٍ ركّبته لتوّها يجب أن تمرَّ بلا استثناء.
      await db.customStatement(sql);
    }
  });
}
