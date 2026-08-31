// ═══════════════════════════════════════════════════════════════════════════
// §٦‑٣ على PostgreSQL — أعمدةُ تدقيقِ إعادة فتح الفترة
// ═══════════════════════════════════════════════════════════════════════════
//
// نظيرُ `test/unit/go_blockers_period_reopen_columns_test.dart`. والسويّتان
// تُصلَحان معاً وإلّا افترقتا: `ensureSchemaDefaults` — التي تُضيف الأعمدةَ على
// SQLite — **تعود مبكّراً على PG**، وهجرةُ v82 التي تكتبها متجاوَزةٌ كلّيّاً
// هناك (‏«PG uses fresh schema»). فمصدرُ الأعمدة على الخادم هو كتلةُ
// `_ensurePostgresSyncInfrastructure` وحدَها.
//
// وعلى PG يكون العَرَضُ `42703: column "reopen_reason" does not exist`.
//
// ⚠️ يعمل عبر `melos test:pg` وحدَه.

@Tags(['pg'])
library;

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

  test('قاعدةُ PostgreSQL جديدةٌ تحمل أعمدةَ إعادة الفتح الثلاثة', () async {
    final rows = await db
        .customSelect(
          "SELECT column_name FROM information_schema.columns "
          "WHERE table_name = 'accounting_periods'",
        )
        .get();
    final cols = rows
        .map((r) => (r.data['column_name'] as String).toLowerCase())
        .toSet();

    expect(cols, contains('is_closed'),
        reason: 'مرساة: الجدولُ موجودٌ وقُرئت أعمدتُه فعلاً');
    expect(
      cols,
      containsAll(<String>['reopen_reason', 'reopened_by', 'reopened_at']),
      reason: 'PG لا تمرُّ بهجرة v82 ولا بـ`ensureSchemaDefaults` — '
          'فمصدرُها كتلةُ التوافق وحدَها. ما وُجد: ${cols.toList()..sort()}',
    );
  });
}
