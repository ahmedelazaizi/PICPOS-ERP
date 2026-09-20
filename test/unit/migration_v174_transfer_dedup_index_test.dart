// v174 على **مسار الترقية** — لا على التنصيبة الجديدة.
//
// ═══ لماذا ملفٌّ ثانٍ ═══
//
// `asset_transfer_chain_posts_each_move_test` يقيس `AppDatabase.forTesting()`،
// وهي تبني الفهرسَ من `kCreateJeAutopostDedupIndexSql` مباشرةً — أي بشكله
// **الجديد** دائماً. فالنقلةُ الثانيةُ تمرّ هناك حتى لو كانت خطوةُ v174
// محذوفةً بالكامل، والقاعدةُ المُرقّاةُ من تنصيبةٍ قائمةٍ تبقى كما هي.
//
// والسببُ أنّ `CREATE UNIQUE INDEX IF NOT EXISTS` **لا يبدّل شكلَ فهرسٍ
// قائم**: يراه موجوداً بالاسم فيمضي صامتاً. وشفاءُ `ensureSchemaDefaults`
// كلَّ إقلاعٍ يُنفّذ هذه الجملةَ نفسَها — فلا يُصلح شيئاً على قاعدةٍ تحمل
// الشكلَ القديم. الطريقُ الوحيدُ هو `DROP` ثمّ `CREATE` في خطوة الترقية،
// وهذا ما يقيسه هذا الملفّ.
//
// ═══ ما يُقاس ═══
//
//  ‏١) مرساةٌ سالبة: الفهرسُ يبدأ بشكلِ ما قبلَ v174 (بلا `asset_transfer`).
//  ‏٢) ومرساةٌ موجبة: الفهرسُ القديمُ **حيٌّ فعلاً** ويرفض النقلةَ الثانية —
//     وإلّا لم يقس الفحصُ التالي شيئاً.
//  ‏٣) 🔴 الترقيةُ 173 ← 174 تُعيد بناءَه بالنوعَين الجديدَين.
//  ‏٤) 🔴 والنقلةُ الثانيةُ تُقبَل بعدها.
//  ‏٥) ⚠️ والفهرسُ ما زال يحرس: نوعٌ غيرُ معفًى ما زال يُرفَض. بلا هذا الفحص
//     يمرّ كلُّ ما سبق لو أسقطت الترقيةُ الفهرسَ ولم تُعِد إنشاءه.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:ural_erp/data/database/database.dart';

/// شكلُ الفهرس قبلَ v174 — إعفاءاتُ v168 بلا نقلِ الأصل ولا تقييمه.
const _preV174IndexSql =
    'CREATE UNIQUE INDEX idx_je_autopost_dedup '
    'ON journal_entries(reference_type, reference_id) '
    'WHERE is_auto_posted = 1 '
    "AND reference_type NOT IN "
    "('sales_return', 'purchase_return', 'commercial_paper', "
    "'partial_collection', 'asset_depreciation')";

void main() {
  late AppDatabase db;

  /// نصُّ الفهرس كما تحمله القاعدةُ فعلاً — لا كما يقول الثابتُ في الشيفرة.
  Future<String> indexSqlInDb() async {
    final rows = await db
        .customSelect("SELECT sql FROM sqlite_master WHERE type = 'index' "
            "AND name = '$kJeAutopostDedupIndexName'")
        .get();
    return rows.isEmpty ? '' : (rows.single.data['sql'] as String? ?? '');
  }

  /// يُدرج قيداً تلقائيّاً خاماً — يمرّ بالفهرس وحدَه، لا بحارس
  /// `createJournalEntry` البرمجيّ. فما يُقاس هنا هو القاعدةُ لا الشيفرة.
  Future<void> insertAutoJe({
    required String entryNumber,
    required String referenceType,
    required int referenceId,
  }) =>
      db.customStatement(
        'INSERT INTO journal_entries '
        '(entry_number, entry_date, reference_type, reference_id, '
        ' is_posted, is_auto_posted) '
        "VALUES ('$entryNumber', 1000, '$referenceType', $referenceId, 1, 1)",
      );

  setUp(() async {
    db = AppDatabase.forTesting();
    // أعِد الفهرسَ إلى شكلِ ما قبلَ v174.
    await db.customStatement('DROP INDEX IF EXISTS $kJeAutopostDedupIndexName');
    await db.customStatement(_preV174IndexSql);
  });

  // لا `db.close()`: مؤقّتُ drift ينتظر في المنطقة الوهميّة فيعلّق الاختبار.
  tearDown(() async {});

  test('⚓ مرساة سالبة: الفهرسُ يبدأ بلا إعفاءِ النقل', () async {
    final sql = await indexSqlInDb();
    expect(sql, isNotEmpty, reason: 'مرساةٌ موجبة: الفهرسُ رُكّب فعلاً');
    expect(sql.contains('asset_depreciation'), isTrue,
        reason: 'وهو شكلُ v168 لا شكلٌ مخترَع');
    expect(sql.contains('asset_transfer'), isFalse,
        reason: 'لو بدأ الفهرسُ معفيّاً لم تقس الترقيةُ شيئاً');
  });

  test('⚓ ومرساةٌ موجبة: الفهرسُ القديمُ يرفض النقلةَ الثانيةَ فعلاً', () async {
    // بلا هذا الفحص قد يمرّ ما بعده لأنّ الفهرسَ لم يكن يحرس أصلاً.
    await insertAutoJe(
        entryNumber: 'JE-1', referenceType: 'asset_transfer', referenceId: 1);

    await expectLater(
      insertAutoJe(
          entryNumber: 'JE-2', referenceType: 'asset_transfer', referenceId: 1),
      throwsA(anything),
      reason: 'الفهرسُ القديمُ يجب أن يرفض — وهذا هو العطبُ الذي تُصلحه v174',
    );
  });

  test('🔴 الترقيةُ 173 ← 174 تُعيد بناءَ الفهرس بالنوعَين الجديدَين', () async {
    await db.runOnUpgrade(Migrator(db), 173, 174);

    final sql = await indexSqlInDb();
    expect(sql, isNotEmpty,
        reason: 'الترقيةُ أسقطت الفهرسَ ولم تُعِد إنشاءه ⇒ لا حمايةَ إطلاقاً');
    expect(sql.contains('asset_transfer'), isTrue,
        reason: '`CREATE ... IF NOT EXISTS` وحدَه لا يبدّل شكلَ فهرسٍ قائم، '
            'فبلا `DROP` تبقى القاعدةُ المُرقّاةُ على الشكل القديم وتُختَم '
            '١٧٤ — والنقلةُ الثانيةُ تظلّ مبتلَعةً إلى الأبد.');
    expect(sql.contains('asset_revaluation'), isTrue);
  });

  test('🔴 والنقلةُ الثانيةُ تُقبَل بعد الترقية', () async {
    await db.runOnUpgrade(Migrator(db), 173, 174);

    await insertAutoJe(
        entryNumber: 'JE-1', referenceType: 'asset_transfer', referenceId: 1);
    await insertAutoJe(
        entryNumber: 'JE-2', referenceType: 'asset_transfer', referenceId: 1);

    final rows = await db
        .customSelect("SELECT COUNT(*) AS n FROM journal_entries "
            "WHERE reference_type = 'asset_transfer' AND reference_id = 1")
        .get();
    expect(rows.single.data['n'], 2);
  });

  test('⚠️ والفهرسُ ما زال يحرس: نوعٌ غيرُ معفًى يُرفَض', () async {
    // لو كانت الترقيةُ قد أسقطت الفهرسَ ونسيت إعادةَ إنشائه لمرّ كلُّ ما
    // سبق أخضرَ — وهذا هو الفحصُ الذي يمنع «إصلاحاً» يرفع الحمايةَ كلَّها.
    await db.runOnUpgrade(Migrator(db), 173, 174);

    await insertAutoJe(
        entryNumber: 'JE-1', referenceType: 'asset_disposal', referenceId: 7);

    await expectLater(
      insertAutoJe(
          entryNumber: 'JE-2', referenceType: 'asset_disposal', referenceId: 7),
      throwsA(anything),
      reason: '`asset_disposal` ليس معفًى — قبولُه يعني أنّ الفهرسَ سقط.',
    );
  });
}
