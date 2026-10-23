// هجرةُ v166 — أعمدةُ المزامنة لاثنَي عشرَ جدولاً ذاتِ أثرٍ محاسبيّ.
//
// ═══ ما يحمي هذا الملفّ ═══
//
// المرحلةُ ٢ تسدّ تفاوتاً: القيدُ يُزامَن ومستندُه لا، فدفترُ الخادم يحمل
// أثراً ماليّاً بلا مصدرٍ يفسّره. والسدُّ يقوم على خمسة أعمدةٍ ومُشغِّلٍ
// واحد، ولكلٍّ طريقةٌ في الفشل الصامت:
//
//  ‏١) **`ADD COLUMN … UNIQUE` مرفوضةٌ في SQLite** — والخطأُ في قائمة
//     `_safeMigrate` المبلوعة، فالعمودُ لا يُنشَأ والترقيةُ تُعلن النجاح.
//     وقع في v119 وv128 على ٣٣ جدولاً. فالصيغةُ عمودٌ عاديٌّ + فهرسٌ فريدٌ
//     جزئيّ، وهنا يُثبَت الأمران: أنّ الأولى ترمي، وأنّ الثانيةَ تفرض التفرّد.
//
//  ‏٢) 🔴 **`row_version` بلا مُشغِّلٍ رقمٌ ميّت.** لا شيءَ يرفعه، فيبدو كلُّ
//     صفٍّ أزليّاً ويسحب الخادمُ لا شيء. والعطبُ لا يظهر في أيّ فحصِ
//     مخطَّط: العمودُ موجودٌ وقيمتُه صفرٌ صحيحةٌ ابتداءً.
//
//  ‏٣) **وحارسُ `WHEN` يمنع الدور** — التحديثُ داخلَ المُشغِّل يوقظه ثانيةً
//     لولاه. والحارسُ يخدم غرضاً ثانياً: تحديثٌ يحمل `row_version` صريحاً
//     (‏وارداً من الخادم) يجب أن يُحترَم لا أن يُرفَع فوقه.
//
//  ‏٤) **والمخطَّطُ الجديدُ غيرُ مسار الترقية.** `forTesting()` يبني
//     بـ`createAll` ولا يمرّ بـ`onUpgrade` إطلاقاً، فالفحصان مفصولان عمداً.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

/// الاثنا عشرَ بأسمائها SQL — نفسُ قائمة `phase2Tables` في `epoch_3.dart`.
const _phase2Tables = <String>[
  'landed_cost_sheets',
  'landed_cost_items',
  'landed_cost_allocations',
  'fixed_assets',
  'asset_categories',
  'asset_depreciations',
  'op_expenses',
  'op_expense_categories',
  'bill_of_materials',
  'manufacturing_orders',
  'mfg_order_costs',
  'bom_components',
];

const _syncColumns = <String>[
  'global_id',
  'last_modified_at',
  'deleted_at',
  'origin_client_id',
  'row_version',
];

void main() {
  group('المخطَّطُ الجديد — تركيبةٌ من الصفر', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting());
    tearDown(() async => db.close());

    Future<Set<String>> columnsOf(String table) async {
      final info = await db.customSelect('PRAGMA table_info($table)').get();
      return info.map((r) => r.data['name'] as String).toSet();
    }

    test('مرساة: قراءةُ PRAGMA تعمل أصلاً', () async {
      // بلا هذه المرساةِ يمرّ كلُّ فحصٍ أدناه أخضرَ لو عادت القراءةُ فارغةً
      // — `containsAll` على مجموعةٍ فارغةٍ يفشل، لكنّ رسالةَ الفشل تتّهم
      // الهجرةَ بدل أن تتّهم القراءة.
      final cols = await columnsOf('parties');
      expect(cols, contains('global_id'),
          reason: 'قراءةُ PRAGMA مكسورة — كلُّ حكمٍ بعدها باطل');
    });

    for (final table in _phase2Tables) {
      test('$table يحمل أعمدةَ المزامنة الخمسة', () async {
        final cols = await columnsOf(table);
        expect(cols.length, greaterThan(3),
            reason: 'قراءةُ PRAGMA لـ$table عادت شبهَ فارغة');
        expect(cols, containsAll(_syncColumns));
      });
    }

    test('🔴 الترقيةُ لا تكتب صفّاً في أيٍّ منها', () async {
      // الأعمدةُ تُضاف ولا تُنشئ بيانات. صفٌّ يظهر هنا بيانةٌ اخترعها
      // البرنامجُ عن المالك.
      for (final table in _phase2Tables) {
        final rows =
            await db.customSelect('SELECT COUNT(*) AS n FROM $table').get();
        expect(rows.single.data['n'], 0, reason: '$table ليس فارغاً');
      }
    });

    test('رقمُ المخطَّط بلغ ١٦٦ فأكثر', () async {
      // «بلغ» لا «تجمّد»: توكيدٌ مساوٍ يكسر الترقيةَ التاليةَ ويكون الفشلَ
      // الوحيدَ في بوّابةٍ كاملة. الأعمدةُ أعلاه هي الدليل، والرقمُ حدٌّ أدنى.
      expect(db.schemaVersion, greaterThanOrEqualTo(166));
    });
  });

  group('منطقُ الترقية — على SQLite خامّ', () {
    late QueryExecutor raw;

    setUp(() async {
      raw = NativeDatabase.memory();
      await raw.ensureOpen(_NoopUser());
      // جدولٌ بشكلِ ما قبلَ v166: بلا أيِّ عمودِ مزامنة.
      await raw.runCustom(
        'CREATE TABLE landed_cost_sheets ('
        'id INTEGER PRIMARY KEY, sheet_number TEXT, status TEXT)',
        [],
      );
    });

    tearDown(() => raw.close());

    test('مرساة: SQLite ترفض ADD COLUMN … UNIQUE', () async {
      // الحقيقةُ التي بُنيت عليها الصيغة. لو قبلتها نسخةٌ مستقبليّةٌ سقط
      // مبرِّرُ الفهرس الجزئيّ وسقط معه هذا الاختبار — وذلك مقصود.
      await expectLater(
        raw.runCustom(
          'ALTER TABLE landed_cost_sheets ADD COLUMN global_id TEXT UNIQUE',
          [],
        ),
        throwsA(predicate((Object? e) =>
            e.toString().toLowerCase().contains('cannot add a unique column'))),
      );
    });

    test('الصيغةُ المستعملةُ تنجح وتفرض التفرّدَ فعلاً', () async {
      await raw.runCustom(
          'ALTER TABLE landed_cost_sheets ADD COLUMN global_id TEXT', []);
      await raw.runCustom(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_landed_cost_sheets_global_id '
        'ON landed_cost_sheets(global_id) WHERE global_id IS NOT NULL',
        [],
      );

      await raw.runCustom(
          "INSERT INTO landed_cost_sheets (id, global_id) VALUES (1, 'g-1')",
          []);

      // الفهرسُ **جزئيّ**: يمنع تكرارَ القيمة ويسمح بتعدّد NULL — وهو ما
      // تحتاجه صفوفٌ قديمةٌ لم تُعبَّأ بعد.
      await expectLater(
        raw.runCustom(
            "INSERT INTO landed_cost_sheets (id, global_id) VALUES (2, 'g-1')",
            []),
        throwsA(anything),
        reason: 'التفرّدُ غيرُ مفروض ⇒ صفّان بنفس المعرّف العالميّ يتصادمان '
            'على الخادم ويُنتجان مستنداً مكرَّراً.',
      );

      await raw.runCustom(
          'INSERT INTO landed_cost_sheets (id, global_id) VALUES (3, NULL)', []);
      await raw.runCustom(
          'INSERT INTO landed_cost_sheets (id, global_id) VALUES (4, NULL)', []);
      final n = await raw.runSelect(
          'SELECT COUNT(*) AS n FROM landed_cost_sheets', []);
      expect(n.single['n'], 3, reason: 'الفهرسُ الجزئيُّ منع تعدّدَ NULL');
    });

    group('المُشغِّل', () {
      setUp(() async {
        for (final ddl in const [
          'ALTER TABLE landed_cost_sheets ADD COLUMN global_id TEXT',
          'ALTER TABLE landed_cost_sheets ADD COLUMN last_modified_at INTEGER',
          'ALTER TABLE landed_cost_sheets ADD COLUMN deleted_at INTEGER',
          'ALTER TABLE landed_cost_sheets ADD COLUMN origin_client_id TEXT',
          'ALTER TABLE landed_cost_sheets '
              'ADD COLUMN row_version INTEGER NOT NULL DEFAULT 0',
        ]) {
          await raw.runCustom(ddl, []);
        }
        await raw.runCustom('''
          CREATE TRIGGER IF NOT EXISTS landed_cost_sheets_bump_version
          AFTER UPDATE ON landed_cost_sheets FOR EACH ROW
          WHEN NEW.row_version = OLD.row_version
          BEGIN
            UPDATE landed_cost_sheets SET
              last_modified_at = strftime('%s', 'now'),
              row_version = OLD.row_version + 1
            WHERE id = NEW.id;
          END
        ''', []);
        await raw.runCustom(
          "INSERT INTO landed_cost_sheets (id, sheet_number, status) "
          "VALUES (1, 'LC-1', 'draft')",
          [],
        );
      });

      Future<Map<String, Object?>> row() async => (await raw.runSelect(
            'SELECT row_version, last_modified_at FROM landed_cost_sheets '
            'WHERE id = 1',
            [],
          )).single;

      test('🔴 تعديلٌ يرفع النسخةَ ويختم الزمن', () async {
        final before = await row();
        expect(before['row_version'], 0);
        expect(before['last_modified_at'], isNull,
            reason: 'صفٌّ قديمٌ يبدأ بلا ختمِ زمن');

        await raw.runCustom(
            "UPDATE landed_cost_sheets SET status = 'applied' WHERE id = 1",
            []);

        final after = await row();
        expect(after['row_version'], 1,
            reason: 'النسخةُ لم تُرفَع ⇒ الخادمُ لا يرى التعديلَ أبداً، '
                'والعمودُ رقمٌ ميّتٌ يبدو صحيحاً في أيّ فحصِ مخطَّط.');
        expect(after['last_modified_at'], isNotNull,
            reason: 'بلا ختمِ زمنٍ لا يلتقط سحبُ الدلتا الصفَّ');
      });

      test('وتعديلان يرفعانها مرّتين — لا مرّةً واحدة', () async {
        await raw.runCustom(
            "UPDATE landed_cost_sheets SET status = 'applied' WHERE id = 1", []);
        await raw.runCustom(
            "UPDATE landed_cost_sheets SET status = 'cancelled' WHERE id = 1",
            []);
        expect((await row())['row_version'], 2);
      });

      test('وحارسُ WHEN يحترم نسخةً واردةً صريحة', () async {
        // صفٌّ يصل من الخادم بنسخته. رفعُها فوقها يجعل الجهازَ يبدو أحدثَ
        // من المصدر، فيغلب في `lastWriteWins` بتعديلٍ لم يقع.
        await raw.runCustom(
          'UPDATE landed_cost_sheets SET row_version = 9 WHERE id = 1',
          [],
        );
        expect((await row())['row_version'], 9,
            reason: 'المُشغِّلُ رفع فوقَ نسخةٍ صريحةٍ ⇒ الحارسُ معطَّل، '
                'وتحديثُه الداخليُّ كان ليوقظ نفسَه دوراً.');
      });
    });

    test('التعبئةُ تملأ الفارغَ وحدَه ولا تلمس الموجود', () async {
      await raw.runCustom(
          'ALTER TABLE landed_cost_sheets ADD COLUMN global_id TEXT', []);
      await raw.runCustom(
          "INSERT INTO landed_cost_sheets (id, global_id) VALUES (1, 'keep-me')",
          []);
      await raw.runCustom(
          'INSERT INTO landed_cost_sheets (id, global_id) VALUES (2, NULL)', []);
      await raw.runCustom(
          "INSERT INTO landed_cost_sheets (id, global_id) VALUES (3, '')", []);

      final targets = await raw.runSelect(
        "SELECT id FROM landed_cost_sheets "
        "WHERE global_id IS NULL OR global_id = ''",
        [],
      );
      expect(targets.map((r) => r['id']).toList(), [2, 3],
          reason: 'شرطُ التعبئة يلتقط NULL والنصَّ الفارغَ معاً — والفارغُ '
              'وحدَه سببُ أنّ v114 تركت صفوفاً بلا معرّف.');
    });
  });
}

class _NoopUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
          QueryExecutor executor, OpeningDetails details) async =>
      Future<void>.value();
}
