// `storeFkMapping` كان بيرمي بدل ما يحدّث — فماب الـFK بيتجمّد على أول قيمة.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// `insertOnConflictUpdate` من غير `target` بيستعمل **الـPK** كهدف التعارض،
// والـPK هنا `id` autoincrement — عمره ما بيتعارض لأنه مش بيتبعت أصلاً.
// والتفرّد الحقيقي في `idx_remote_id_local (table_name, local_id)`، وهو مش
// مغطّى بالـtarget فبيضرب كـUNIQUE constraint مكشوف.
//
// والتعليق فوق الدالة بيوعد بالعكس بالحرف: «If the (tableName, localId) pair
// already exists, the remoteId and globalId are updated in place.»
//
// ── ليه ده مهم ──────────────────────────────────────────────────────────────
// `delta_pull_service.dart:360` بيسجّل الماب بعد أول مطابقة globalId، والنداء
// جوه `try` بيطبع «will fall back» ويكمّل — فالماب **عمره ما بيتحدّث تاني**.
// ولو الـremoteId اتغيّر (سيرفر اتعمله rebuild) الماب بيفضل قديم غلط،
// والطابور بيحلّ الـFK على id سيرفر مش موجود.
// وفي `offline_sync_worker.dart:412` النداء `unawaited` فالاستثناء بيروح
// لـzone handler من غير ما حد يشوفه.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<List<Map<String, dynamic>>> mappings() async {
    final rows = await db.customSelect(
      'SELECT table_name, local_id, remote_id, global_id FROM remote_id_mappings '
      'ORDER BY id',
    ).get();
    return rows.map((r) => r.data).toList();
  }

  test('نفس (الجدول، الـid المحلي) بيتحدّث في مكانه مش بيرمي', () async {
    await db.storeFkMapping(
        tableName: 'parties', localId: 5, remoteId: 100, globalId: 'g1');
    await db.storeFkMapping(
        tableName: 'parties', localId: 5, remoteId: 200, globalId: 'g2');

    final rows = await mappings();
    expect(rows, hasLength(1), reason: 'تحديث مش صف جديد');
    expect(rows.single['remote_id'], 200);
    expect(rows.single['global_id'], 'g2');
  });

  test('الكتابة المتكررة بنفس القيم بالظبط ما بتفشلش', () async {
    // مسار DeltaPull بيعيد تسجيل نفس الماب في كل سحبة — ده الشكل الغالب
    // فعلياً، وكان بيرمي في كل مرة بعد الأولى.
    for (var i = 0; i < 3; i++) {
      await db.storeFkMapping(
          tableName: 'products', localId: 9, remoteId: 42, globalId: 'gid-x');
    }
    final rows = await mappings();
    expect(rows, hasLength(1));
    expect(rows.single['remote_id'], 42);
  });

  test('نفس الـid المحلي في جدولين مختلفين صفّين مستقلّين', () async {
    await db.storeFkMapping(tableName: 'parties', localId: 5, remoteId: 100);
    await db.storeFkMapping(tableName: 'products', localId: 5, remoteId: 700);

    final rows = await mappings();
    expect(rows, hasLength(2));
    expect(rows.map((r) => r['remote_id']).toSet(), {100, 700});
  });

  test('ids محلية مختلفة في نفس الجدول صفّين مستقلّين', () async {
    await db.storeFkMapping(tableName: 'parties', localId: 5, remoteId: 100);
    await db.storeFkMapping(tableName: 'parties', localId: 6, remoteId: 101);

    expect(await mappings(), hasLength(2));
  });

  test('globalId فاضي ما بيمسحش القيمة المسجّلة قبله', () async {
    // مسارات بتنده الدالة من غير globalId (بتعرفه من الـid بس) — ما ينفعش
    // تمسح هوية اتسجّلت من مسار تاني.
    await db.storeFkMapping(
        tableName: 'parties', localId: 5, remoteId: 100, globalId: 'g1');
    await db.storeFkMapping(tableName: 'parties', localId: 5, remoteId: 150);

    final rows = await mappings();
    expect(rows.single['remote_id'], 150);
    expect(rows.single['global_id'], 'g1');
  });
}
