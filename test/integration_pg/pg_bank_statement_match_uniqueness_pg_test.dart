// ═══════════════════════════════════════════════════════════════════════════
// §٣‑٦ على PostgreSQL — نظيرُ `test/unit/bank_statement_match_uniqueness`
// ═══════════════════════════════════════════════════════════════════════════
//
// السويّتان تُصلَحان معاً وإلّا افترقتا: `ensureSchemaDefaults` — التي تُركّب
// الفهرسَ على SQLite — **تعود مبكّراً على PG** (`if (_isPostgres) return`).
// فبلا الكتلةِ المضافةِ في `_ensureDatabaseIntegrity` تبقى **كلُّ** قاعدةِ
// PostgreSQL بلا قيدِ التفرّد.
//
// وPG هي خلفيّةُ الخادم في تنصيبةِ العميل/المرآة — أي الموضعُ الذي تتعدّد فيه
// الأجهزةُ أصلاً، وهو بالضبط ما يجعل تغطيةَ سطرَي كشفٍ بقيدٍ واحدٍ أقربَ
// للوقوع. فالسويّةُ هنا ليست تكراراً بل هي الأولى بالحراسة.
//
// ⚠️ **و`NULL` متمايزةٌ في PostgreSQL كما في SQLite** — وهذا الافتراضُ هو
// الذي لو انقلب لخنق استيرادَ الكشف كلَّه (كلُّ سطرٍ مستورَدٍ يبدأ غيرَ
// مطابَق). فيُقاس صراحةً هنا لا يُفترَض.
//
// ⚠️ يعمل عبر `melos test:pg` وحدَه (يحتاج حاوية PostgreSQL). `flutter test`
// المعتادة تتخطّاه.

@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

import '_support/pg_fixture.dart';

void main() {
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
          "WHERE tablename = 'bank_statement_lines' "
          "  AND indexname = '$kBankStatementMatchDedupIndexName'",
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<Object?> insertLine({required int id, int? matchedLineId}) async {
    try {
      await db.into(db.bankStatementLines).insert(
            BankStatementLinesCompanion.insert(
              bankAccountId: 1,
              transactionDate: DateTime(2026, 5, 10),
              reference: Value('REF-PG-$id'),
              matchedJournalLineId: Value(matchedLineId),
              isMatched: Value(matchedLineId != null),
            ),
          );
      return null;
    } catch (e) {
      return e;
    }
  }

  test('قاعدةُ PostgreSQL جديدةٌ تحمل القيدَ وترفض تغطيةَ سطرَين بقيدٍ واحد',
      () async {
    expect(await indexExists(), isTrue,
        reason: 'PG لا تمرُّ بـ`ensureSchemaDefaults` — فالقيدُ يأتي من '
            '`_ensureDatabaseIntegrity` وحدَه');

    expect(await insertLine(id: 1, matchedLineId: 77), isNull,
        reason: 'الإسنادُ الأوّلُ يمرّ');
    expect(await insertLine(id: 2, matchedLineId: 77), isNotNull,
        reason: 'الإسنادُ الثاني لنفس سطر القيد يجب أن ترفضه القاعدة');

    final rows = await db.select(db.bankStatementLines).get();
    expect(rows.where((r) => r.matchedJournalLineId == 77), hasLength(1));
  });

  test('🔴 أسطرٌ غيرُ مطابَقةٍ كثيرةٌ تتعايش على PG — `NULL` متمايزة', () async {
    for (var i = 1; i <= 5; i++) {
      expect(await insertLine(id: i), isNull,
          reason: 'السطرُ غيرُ المطابَق رقم $i رُفض — الفهرسُ يخنق الاستيراد');
    }

    final rows = await db.select(db.bankStatementLines).get();
    expect(rows, hasLength(5));
  });
}
