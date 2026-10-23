// ═══════════════════════════════════════════════════════════════════════════
// ٦‑٣ — تفرّدُ `account_mappings` على (‏الغرض، مركزُ التكلفة)
// ═══════════════════════════════════════════════════════════════════════════
//
// `getAccountByPurpose` يختار الربطَ بـ`limit(1)` بلا `orderBy`
// (`accounting_dao_reads.dart:815` و`:832`) — فصفّان لنفس الغرض يجعلان
// **اختيارَ الحساب غيرَ حتميّ**: نفسُ الفاتورةِ قد تُرحَّل على حسابٍ اليومَ
// وعلى آخرَ غداً.
//
// والازدواجُ مؤكَّدٌ ميدانيّاً — `accounting_dao_writes.dart:1060` يوثّقه:
// «mirror sync replays can leave more than one account_mappings row per
// purpose key on the mirror device». والعلاجُ هناك `.limit(1)` أي مسكّنٌ
// للعَرَض؛ والجذرُ ثلاثةٌ:
//
//   1. لا قيدَ تفرّدٍ على تنصيبةٍ جديدة. الفهرسُ التعبيريُّ الصحيح مكتوبٌ في
//      ثلاثِ خطواتِ هجرة (`epoch_3.dart:784` · `:841` · `:922`)، لكنّ
//      `onCreate` يبني من كيانات drift و`onUpgrade` لا يعمل على قاعدةٍ
//      جديدةٍ ومتجاوَزٌ كلّيّاً على PG. والمُعلَنُ في صنف الجدول
//      `@TableIndex(idx_account_mappings_purpose)` — **غيرُ فريدٍ وعلى
//      الغرض وحدَه**.
//   2. و`UNIQUE` وحدَه لا يكفي: الربطُ العامُّ `cost_center_id IS NULL`، و
//      `NULL` لا يتساوى مع `NULL` في قيدِ تفرّد — فهو **بالضبط** الصفُّ
//      الذي يزدوج. ولذلك الفهرسُ تعبيريٌّ على `coalesce(cost_center_id, 0)`.
//   3. والمزامنةُ تُدرج بـ`insertOnConflictUpdate` **مُفتاحاً بـ`id`**
//      (`account_mapping_sync_strategy.dart`)، فصفٌّ محلّيٌّ صُنع أيّامَ كان
//      الجهازُ منفرداً وصفٌّ خادميٌّ بمعرّفٍ آخرَ ونفسِ المفتاح الطبيعيّ
//      يتعايشان. وقيدُ التفرّد وحدَه كان سيقلب ذلك إلى **انهيارِ مزامنة**،
//      فالمزامنةُ تُسوّي على المفتاح الطبيعيِّ أوّلاً.
//
// وقرارُ المالك 2026-08-31 في التسوية: **يبقى الأحدثُ بـ`updated_at`**،
// والتعادلُ يُحسَم بأكبر `id`.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/strategies/account_mapping_sync_strategy.dart';

void main() {
  late AppDatabase db;
  late int accountA;
  late int accountB;

  const purpose = 'go_blockers_probe_purpose';
  const indexName = 'idx_account_mappings_purpose_cc';

  setUp(() async {
    db = AppDatabase.forTesting();
    final accounts = await db.select(db.accounts).get();
    accountA = accounts[0].id;
    accountB = accounts[1].id;
  });

  tearDown(() async => db.close());

  Future<List<AccountMapping>> mappingsFor(String p) =>
      (db.select(db.accountMappings)..where((m) => m.purpose.equals(p))).get();

  Future<bool> indexExists() async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'index' AND name = '$indexName'",
        )
        .get();
    return rows.isNotEmpty;
  }

  /// إدراجٌ خامٌّ يتجاوز أيَّ منطقِ تطبيقٍ — الغرضُ اختبارُ القيد نفسِه.
  Future<Object?> tryInsert({
    required int accountId,
    int? costCenterId,
    DateTime? updatedAt,
  }) async {
    try {
      await db.into(db.accountMappings).insert(
            AccountMappingsCompanion.insert(
              purpose: purpose,
              accountId: accountId,
              costCenterId: Value(costCenterId),
              updatedAt:
                  updatedAt == null ? const Value.absent() : Value(updatedAt),
            ),
          );
      return null;
    } catch (e) {
      return e;
    }
  }

  test('تنصيبةٌ جديدةٌ ترفض ربطَين عامَّين لنفس الغرض', () async {
    expect(await indexExists(), isTrue,
        reason: 'الفهرسُ الفريدُ يجب أن يوجد على قاعدةٍ جديدةٍ بلا هجرة');

    expect(await tryInsert(accountId: accountA), isNull,
        reason: 'الربطُ الأوّلُ يمرّ');

    final err = await tryInsert(accountId: accountB);
    expect(err, isNotNull,
        reason: 'الربطُ العامُّ الثاني لنفس الغرض يجب أن يُرفض — '
            'و`cost_center_id IS NULL` هو الحالةُ التي لا يمسكها UNIQUE');

    final rows = await mappingsFor(purpose);
    expect(rows.length, 1);
    expect(rows.single.accountId, accountA);
  });

  test('تجاوزُ مركزِ التكلفة يبقى مسموحاً — حارسٌ ضدّ تشديدٍ زائد', () async {
    final centers = await db.select(db.costCenters).get();
    final ccId = centers.isNotEmpty
        ? centers.first.id
        : await db.into(db.costCenters).insert(
              CostCentersCompanion.insert(code: 'GB-CC', name: 'مركز اختبار'),
            );

    expect(await tryInsert(accountId: accountA), isNull,
        reason: 'الربطُ العامّ');
    expect(await tryInsert(accountId: accountB, costCenterId: ccId), isNull,
        reason: 'تجاوزٌ لمركزِ تكلفةٍ — مفتاحٌ طبيعيٌّ مختلف، فيُقبل');

    expect(await tryInsert(accountId: accountA, costCenterId: ccId), isNotNull,
        reason: 'تجاوزان لنفس المركز يُرفضان');

    expect((await mappingsFor(purpose)).length, 2);
  });

  test('الشفاءُ الذاتيُّ يسوّي المزدوجَ ويُبقي الأحدثَ بـ`updated_at`',
      () async {
    // القيدُ يُرفَع كي تُزرَع الحالةُ التي كانت تصل من المرآة قبل الإصلاح.
    await db.customStatement('DROP INDEX IF EXISTS $indexName');
    expect(await indexExists(), isFalse);

    final old = DateTime(2026, 1, 1);
    final newest = DateTime(2026, 6, 1);
    expect(await tryInsert(accountId: accountA, updatedAt: old), isNull);
    expect(await tryInsert(accountId: accountB, updatedAt: newest), isNull);
    expect((await mappingsFor(purpose)).length, 2,
        reason: 'مرساة: الازدواجُ زُرع فعلاً');

    await db.ensureSchemaDefaults();

    final rows = await mappingsFor(purpose);
    expect(rows.length, 1, reason: 'التسويةُ تُبقي صفّاً واحداً');
    expect(rows.single.accountId, accountB,
        reason: 'قرارُ المالك: يبقى الأحدثُ بـ`updated_at` — الحسابُ B');
    expect(await indexExists(), isTrue,
        reason: 'وبعد التسويةِ يُركَّب القيد؛ لو فشلت التسويةُ صامتةً '
            'لبقي الفهرسُ غائباً');
  });

  test('إعادةُ تشغيل المزامنة لا تُنتج ازدواجاً ولا تنهار', () async {
    // الحالةُ الميدانيّة: صفٌّ محلّيٌّ صُنع والجهازُ منفرد، ثمّ صار مرآةً
    // فأرسل الخادمُ نفسَ الغرضِ بمعرّفٍ آخر.
    expect(await tryInsert(accountId: accountA), isNull);
    final localId = (await mappingsFor(purpose)).single.id;
    final serverId = localId + 1000;

    final strategy = AccountMappingSyncStrategy(db);
    await strategy.syncFromJson({
      'account_mappings': [
        {
          'id': serverId,
          'purpose': purpose,
          'accountId': accountB,
          'costCenterId': null,
          'description': 'من الخادم',
          'updatedAt': DateTime(2026, 7, 1).toIso8601String(),
        },
      ],
    });

    final rows = await mappingsFor(purpose);
    expect(rows.length, 1,
        reason: 'الخادمُ هو السلطةُ — صفٌّ واحدٌ لا صفّان');
    expect(rows.single.id, serverId);
    expect(rows.single.accountId, accountB);
  });
}
