// ═══════════════════════════════════════════════════════════════════════════
// §٣‑٦ — قيدُ قاعدةٍ ضدّ تغطيةِ سطرَي كشفٍ بقيدٍ واحد
// ═══════════════════════════════════════════════════════════════════════════
//
// المطابقةُ الآليّةُ تُقصي سطرَ القيد المستعملَ سلفاً، واليدويّةُ صارت ترمي
// عليه — **لكنّ الاثنين كودُ تطبيق**. ونفسُ حجّةِ فهرسَي B1/B2 تسري هنا حرفاً
// («استيرادُ البصمة بقى يعمل upsert… لكن ده كود تطبيق كمان»): الأثرُ ماليّ.
//
// وسطرا كشفٍ يُغلقان على نفس سطر القيد يُعَدّان مطابَقَين اثنَين، فينخفض «غيرُ
// المطابَق» بمقدارَين وتبدو المطابقةُ تامّةً بينما حركةٌ بنكيّةٌ كاملةٌ بلا ما
// يقابلها في الدفتر — **إخفاءُ الفرق**، وهو عينُ ما تقوم المطابقةُ لكشفه.
//
// ── ⚠️ ولماذا يُقاس **وجودُ الفهرس** لا نجاحُ الجملة ──────────────────────
//
// حلقةُ الشفاء الذاتيِّ في `ensureSchemaDefaults` **تبتلع الفشلَ بصمت** — وهو
// مقصودٌ (بياناتٌ مزدوجةٌ قائمةٌ لا تُحذف تلقائيّاً). فقاعدةٌ قد تخرج بلا
// حمايةٍ ولا بلاغ، ونجاحُ الإقلاع ليس دليلاً. ولذلك يبدأ الفحصُ من
// `sqlite_master` ثمّ يقيس **الرفضَ الفعليّ**.
//
// ── ولا فهرسٌ جزئيّ ────────────────────────────────────────────────────────
// العمودُ nullable، و`UNIQUE` تعامل `NULL` قيماً **متمايزةً** في SQLite
// وPostgreSQL معاً — فآلافُ الأسطر غير المطابَقة لا تتصادم. وآخرُ اختبارٍ هنا
// يقفل ذلك صراحةً، فهو الافتراضُ الذي لو انقلب لتعطّل الاستيرادُ كلُّه.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  Future<bool> indexExists() async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' "
      "AND name = '$kBankStatementMatchDedupIndexName'",
    ).get();
    return rows.isNotEmpty;
  }

  /// إدراجٌ خامٌّ يتجاوز أيَّ منطقِ تطبيقٍ — الغرضُ اختبارُ القيد نفسِه.
  Future<Object?> insertLine({required int id, int? matchedLineId}) async {
    try {
      await db.into(db.bankStatementLines).insert(
            BankStatementLinesCompanion.insert(
              bankAccountId: 1,
              transactionDate: DateTime(2026, 5, 10),
              reference: Value('REF-$id'),
              matchedJournalLineId: Value(matchedLineId),
              isMatched: Value(matchedLineId != null),
            ),
          );
      return null;
    } catch (e) {
      return e;
    }
  }

  test('مرساة: الفهرسُ موجودٌ على تنصيبةٍ جديدةٍ بلا هجرة', () async {
    expect(await indexExists(), isTrue,
        reason: 'الشفاءُ الذاتيُّ يبتلع الفشلَ بصمت — فوجودُ الفهرس هو '
            'الدليلُ الوحيد، لا نجاحُ الإقلاع');
  });

  test('🔴 قيدٌ واحدٌ لا يغطّي سطرَي كشفٍ — القاعدةُ ترفض', () async {
    expect(await insertLine(id: 1, matchedLineId: 99), isNull,
        reason: 'الإسنادُ الأوّلُ يمرّ');

    expect(await insertLine(id: 2, matchedLineId: 99), isNotNull,
        reason: 'الإسنادُ الثاني لنفس سطر القيد يجب أن ترفضه **القاعدة** — '
            'لا حارسُ التطبيق وحدَه');

    final rows = await db.select(db.bankStatementLines).get();
    expect(rows.where((r) => r.matchedJournalLineId == 99), hasLength(1));
  });

  test('قيودٌ مختلفةٌ تمرّ — حارسٌ ضدّ تشديدٍ زائد', () async {
    expect(await insertLine(id: 1, matchedLineId: 101), isNull);
    expect(await insertLine(id: 2, matchedLineId: 102), isNull);
  });

  test('🔴 أسطرٌ غيرُ مطابَقةٍ كثيرةٌ تتعايش — `NULL` قيمٌ متمايزة', () async {
    // لو عومِلت `NULL` قيمةً واحدةً لتعطّل **استيرادُ الكشف كلُّه**: كلُّ سطرٍ
    // مستورَدٍ يبدأ غيرَ مطابَق.
    for (var i = 1; i <= 5; i++) {
      expect(await insertLine(id: i), isNull,
          reason: 'السطرُ غيرُ المطابَق رقم $i رُفض — الفهرسُ يخنق الاستيراد');
    }

    final rows = await db.select(db.bankStatementLines).get();
    expect(rows, hasLength(5));
  });

  test('ونزعُ المطابقةِ يُحرّر القيدَ لسطرٍ آخر', () async {
    await insertLine(id: 1, matchedLineId: 55);
    final first = (await db.select(db.bankStatementLines).get()).single;

    await db.unmatchStatement(first.id);

    expect(await insertLine(id: 2, matchedLineId: 55), isNull,
        reason: 'بعد النزع لا يبقى ما يزاحم');
  });
}
