// مايجريشن v132 كان بيقفل التطبيق على أي ترقية من إصدار < 132.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// `epoch_3.dart` بيعمل `ALTER TABLE activity_logs ADD COLUMN global_id TEXT
// UNIQUE`. **SQLite ما بتقبلش ده نهائياً** — مفيش صيغة `ADD COLUMN` بقيد
// تفرّد، لأن الجدول ممكن يكون فيه صفوف مكرَّرة أصلاً.
//
// والجملة متغلّفة بـ`_safeMigrate` اللي قايمة الأخطاء المسموح تخطّيها فيه
// كانت تلاتة بس (`duplicate column name` · `already exists` · `no such
// column`) — مفيهاش `cannot add a unique column`. فالنتيجة `rethrow`،
// و`_migrateEpoch3` مالوش try، و`runOnUpgrade` مالوش try → الاستثناء بيطلع
// من `onUpgrade` → drift ما بيفتحش القاعدة → `beforeOpen` عمره ما بيشتغل.
//
// والترقية جوه ترانزاكشن، فبترجع وتعيد المحاولة **كل إقلاع** — يعني التطبيق
// ميت نهائياً على التركيبة دي مش مجرد ميزة ناقصة.
//
// بيضرب بالظبط التركيبات القديمة اللي الإصدار موجّه ليها: تركيبة اتعملت
// fresh بعد ما `globalId` دخل كلاس Drift هتدي `duplicate column name`
// وتتخطّى بأمان؛ التركيبة اللي `activity_logs` بتاعتها اتعملت في v68 من غير
// العمود هي اللي بتموت.
//
// ── نفس النمط في v119 وv128 ─────────────────────────────────────────────────
// ٣٣ جدول تاني بنفس الجملة، بس مبلوعة في `try/catch` عادي فبتكمّل بصمت
// والأعمدة ما بتتعملش. دليل داخلي إن البلوكات دي ماحدش جرّبها: v114/v118 في
// نفس الملف بيستعملوا `ADD COLUMN ... TEXT NOT NULL DEFAULT ''` من غير
// UNIQUE — وde بينجح فعلاً.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late QueryExecutor db;

  setUp(() async {
    db = NativeDatabase.memory();
    await db.ensureOpen(_NoopUser());
    await db.runCustom(
        'CREATE TABLE activity_logs (id INTEGER PRIMARY KEY, action TEXT)', []);
  });

  tearDown(() => db.close());

  group('الحقيقة اللي العطل مبني عليها', () {
    test('SQLite بترفض ADD COLUMN ... UNIQUE', () async {
      await expectLater(
        db.runCustom(
            'ALTER TABLE activity_logs ADD COLUMN global_id TEXT UNIQUE', []),
        throwsA(predicate((e) =>
            e.toString().toLowerCase().contains('cannot add a unique column'))),
      );
    });

    test('الصيغة البديلة (عمود عادي + فهرس فريد جزئي) بتنجح', () async {
      await db.runCustom(
          'ALTER TABLE activity_logs ADD COLUMN global_id TEXT', []);
      await db.runCustom(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_activity_logs_global_id '
          'ON activity_logs(global_id) WHERE global_id IS NOT NULL',
          []);
      // والفهرس بيفرض التفرّد فعلاً — مش مجرد عمود.
      await db.runCustom(
          "INSERT INTO activity_logs (action, global_id) VALUES ('a', 'g1')",
          []);
      await expectLater(
        db.runCustom(
            "INSERT INTO activity_logs (action, global_id) VALUES ('b', 'g1')",
            []),
        throwsA(anything),
      );
    });

    test('الفهرس الجزئي بيسمح بأكتر من صف NULL (زي UNIQUE في SQLite)',
        () async {
      await db.runCustom(
          'ALTER TABLE activity_logs ADD COLUMN global_id TEXT', []);
      await db.runCustom(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_activity_logs_global_id '
          'ON activity_logs(global_id) WHERE global_id IS NOT NULL',
          []);
      await db.runCustom("INSERT INTO activity_logs (action) VALUES ('a')", []);
      await db.runCustom("INSERT INTO activity_logs (action) VALUES ('b')", []);
      final rows =
          await db.runSelect('SELECT COUNT(*) c FROM activity_logs', []);
      expect(rows.first['c'], 2);
    });
  });

  group('isIdempotentMigrationError — بوابة الـrethrow', () {
    test('«Cannot add a UNIQUE column» لازم تتخطّى مش تقتل الإقلاع', () {
      expect(
        isIdempotentMigrationError(
            'SqliteException(1): while executing, Cannot add a UNIQUE column, '
            'SQL logic error (code 1)'),
        isTrue,
      );
    });

    test('الأنماط التلاتة القديمة لسه بتتخطّى', () {
      expect(
          isIdempotentMigrationError(
              'SqliteException(1): duplicate column name: global_id'),
          isTrue);
      expect(
          isIdempotentMigrationError(
              'SqliteException(1): table activity_logs already exists'),
          isTrue);
      expect(
          isIdempotentMigrationError(
              'SqliteException(1): no such column: movement_date'),
          isTrue);
    });

    test('الأخطاء الحقيقية لسه بترمي — الحارس ما اتوسّعش أكتر من اللازم', () {
      expect(isIdempotentMigrationError('database is locked'), isFalse);
      expect(isIdempotentMigrationError('no such table: activity_logs'),
          isFalse);
      expect(isIdempotentMigrationError('disk I/O error'), isFalse);
      // «already exists» من غير نوع الكيان مش سبب كافي للتخطّي.
      expect(isIdempotentMigrationError('constraint already exists'), isFalse);
    });
  });
}

class _NoopUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;
  @override
  Future<void> beforeOpen(QueryExecutor e, OpeningDetails d) async {}
}
