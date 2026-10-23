// ═══════════════════════════════════════════════════════════════════════════
// ٦‑٣ على PostgreSQL — نظيرُ `test/unit/go_blockers_account_mapping_uniqueness`
// ═══════════════════════════════════════════════════════════════════════════
//
// السويّتان تُصلَحان معاً وإلّا افترقتا: `ensureSchemaDefaults` — التي تُركّب
// الفهرسَ على SQLite — **تعود مبكّراً على PG** (`if (_isPostgres) return`)،
// وهجراتُ SQLite التي تكتب الفهرسَ في `epoch_3.dart` متجاوَزةٌ كلّيّاً على PG
// (‏«PG uses fresh schema»). فبلا الكتلةِ المضافةِ في `_ensureDatabaseIntegrity`
// تبقى **كلُّ** قاعدةِ PostgreSQL بلا قيدِ التفرّد.
//
// وPG هي خلفيّةُ الخادم في تنصيبةِ العميل/المرآة — أي الموضعُ الذي وقع فيه
// الازدواجُ ميدانيّاً أصلاً («mirror sync replays…» في
// `accounting_dao_writes.dart`). فالسويّةُ هنا ليست تكراراً بل هي الأصل.
//
// ⚠️ يعمل عبر `melos test:pg` وحدَه (يحتاج حاوية PostgreSQL). `flutter test`
// المعتادة تتخطّاه.

@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

import '_support/pg_fixture.dart';

void main() {
  const purpose = 'go_blockers_pg_probe_purpose';

  late AppDatabase db;

  setUp(() async {
    final fx = await bootPgTestSchema();
    addTearDown(fx.tearDown);
    db = fx.db;
    // تُجبر drift على تشغيل الهجرة ومسارِ الإقلاع قبل أوّل توكيد.
    await db.select(db.accounts).get();
  });

  Future<bool> indexExists() async {
    final rows = await db
        .customSelect(
          "SELECT 1 AS x FROM pg_indexes "
          "WHERE tablename = 'account_mappings' "
          "  AND indexname = '$kAccountMappingsPurposeCcIndexName'",
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<Object?> tryInsert(int accountId, {int? costCenterId}) async {
    try {
      await db.into(db.accountMappings).insert(
            AccountMappingsCompanion.insert(
              purpose: purpose,
              accountId: accountId,
              costCenterId: Value(costCenterId),
            ),
          );
      return null;
    } catch (e) {
      return e;
    }
  }

  test('قاعدةُ PostgreSQL جديدةٌ تحمل قيدَ التفرّد وترفض الربطَ العامَّ المكرَّر',
      () async {
    expect(await indexExists(), isTrue,
        reason: 'PG لا تمرُّ بـ`ensureSchemaDefaults` ولا بهجرات SQLite — '
            'فالقيدُ يأتي من `_ensureDatabaseIntegrity` وحدَه');

    final accounts = await db.select(db.accounts).get();
    expect(accounts.length, greaterThanOrEqualTo(2),
        reason: 'مرساة: شجرةُ الحسابات مزروعة');

    expect(await tryInsert(accounts[0].id), isNull);
    expect(await tryInsert(accounts[1].id), isNotNull,
        reason: 'الربطُ العامُّ الثاني (‏cost_center_id NULL) يجب أن يُرفض — '
            'وهو ما يفلت من `UNIQUE` العاديّ لأنّ NULL لا تساوي NULL');

    final rows = await (db.select(db.accountMappings)
          ..where((m) => m.purpose.equals(purpose)))
        .get();
    expect(rows.length, 1);
    expect(rows.single.accountId, accounts[0].id);
  });
}
