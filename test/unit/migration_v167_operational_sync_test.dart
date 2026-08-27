// هجرةُ v167 — أعمدةُ المزامنة للفئةِ التشغيليّة (تسعةَ عشرَ جدولاً).
//
// ═══ ما يحمي هذا الملفّ ═══
//
// المرحلةُ ٣ تُخرج المطاعمَ والمطبخَ والحجوزاتِ والتوزيعَ من العزلة. وهي
// أرخصُ من المرحلة ٢ (‏`tables_dao` و`kitchen_dao` فيهما صفرُ قيدٍ
// محاسبيّ)، لكنّ طرقَ الفشل الصامت هي هي:
//
//  ‏١) **`ADD COLUMN … UNIQUE` مرفوضةٌ في SQLite** والخطأُ مبلوعٌ في
//     `_safeMigrate`. الصيغةُ عمودٌ عاديٌّ + فهرسٌ فريدٌ جزئيّ.
//
//  ‏٢) 🔴 **`row_version` بلا مُشغِّلٍ رقمٌ ميّت** — لا يظهر في أيّ فحصِ
//     مخطَّط: العمودُ موجودٌ وقيمتُه صفرٌ صحيحةٌ ابتداءً.
//
//  ‏٣) 🔴 **و`employees` هي الفخُّ الخاصُّ بهذه المرحلة.** أُدرجت في ستِّ
//     قوائمِ مزامنةٍ وهي بلا `global_id`، وكلُّ فحصٍ قائمٍ مرّ أخضر:
//     `_upsertRow` يبتلع خطأَ العمود المفقود ويمضي. فلها فحصٌ باسمها
//     أدناه لا مجرَّدَ عضويّةٍ في حلقة.
//
//  ‏٤) **وثلاثةُ جداولِ حجوزاتٍ لها `deleted_at` سلفاً** — وُلدت به. الهجرةُ
//     تعتمد على الـsafe-skip، وهذا يُثبت أنّ العمودَ لم يُفقَد بسببه.
//
//  ‏٥) **والمخطَّطُ الجديدُ غيرُ مسار الترقية.** `forTesting()` يبني
//     بـ`createAll` ولا يمرّ بـ`onUpgrade` إطلاقاً، فالفحصان مفصولان عمداً.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

/// التسعةَ عشرَ بأسمائها SQL — نفسُ قائمة `phase3Tables` في `epoch_3.dart`.
const _phase3Tables = <String>[
  'employees',
  'table_sections',
  'restaurant_tables',
  'table_orders',
  'table_order_items',
  'table_reservations',
  'table_order_payments',
  'kitchen_stations',
  'category_station_mappings',
  'work_orders',
  'work_order_items',
  'booking_resources',
  'booking_services',
  'bookings',
  'booking_reminders',
  'sales_routes',
  'route_visits',
  'sales_rep_targets',
  'sales_rep_collections',
];

/// الثلاثةُ التي وُلدت بـ`deleted_at` — الهجرةُ تتخطّاه بالـsafe-skip.
const _bornWithDeletedAt = <String>[
  'booking_resources',
  'booking_services',
  'booking_reminders',
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
      // بلا هذه المرساةِ يمرّ كلُّ فحصٍ أدناه أخضرَ لو عادت القراءةُ فارغةً،
      // ورسالةُ الفشل تتّهم الهجرةَ بدل أن تتّهم القراءة.
      final cols = await columnsOf('parties');
      expect(cols, contains('global_id'),
          reason: 'قراءةُ PRAGMA مكسورة — كلُّ حكمٍ بعدها باطل');
    });

    for (final table in _phase3Tables) {
      test('$table يحمل أعمدةَ المزامنة الخمسة', () async {
        final cols = await columnsOf(table);
        expect(cols.length, greaterThan(3),
            reason: 'قراءةُ PRAGMA لـ$table عادت شبهَ فارغة');
        expect(cols, containsAll(_syncColumns));
      });
    }

    test('🔴 `employees` تحديداً — الجدولُ الذي فات القوائمَ الستَّ', () async {
      // فحصٌ باسمه لا عضويّةٌ في حلقة: هذا هو البلاغُ الذي وقع فعلاً في
      // هذه المرحلة — عضويّةُ ستِّ قوائمِ مزامنةٍ بلا عمودٍ واحد.
      final cols = await columnsOf('employees');
      expect(cols, containsAll(_syncColumns),
          reason: 'مزامنةُ `employees` عقدٌ لا خيار: ثلاثةُ جداولِ توزيعٍ '
              'تشير إليها بإشارةٍ غيرِ قابلةٍ للإفراغ، و`_upsertRow` يبتلع '
              'خطأَ المفتاح — فبدونها يُسقَط كلُّ صفِّ زيارةٍ صامتاً.');
      // ولا يعني ذلك فتحَ شؤون الموظّفين: بقيّةُ جداولها محلّيّةٌ بقرار.
      final leaves = await columnsOf('employee_leaves');
      expect(leaves.contains('global_id'), isFalse,
          reason: 'شؤونُ الموظّفين مؤجَّلةٌ بقرار مالك — خرجت `employees` '
              'وحدَها لسببِ مفاتيحَ لا لفتحِ الميزة.');
    });

    test('والثلاثةُ التي وُلدت بـ`deleted_at` لم تفقده', () async {
      // الهجرةُ تعتمد على الـsafe-skip لهذه: `ALTER TABLE … ADD COLUMN
      // deleted_at` يرمي «duplicate column» ويُبتلَع. والخطرُ أن يُبتلَع
      // شيءٌ آخرُ معه فيسقط العمودُ كلُّه.
      for (final t in _bornWithDeletedAt) {
        expect(await columnsOf(t), contains('deleted_at'),
            reason: 'الجدولُ $t فقد `deleted_at` — الـsafe-skip ابتلع أكثرَ '
                'ممّا ينبغي، والحذفُ الناعمُ لا يُزامَن بعدها.');
      }
    });

    test('🔴 الترقيةُ لا تكتب صفّاً في أيٍّ منها', () async {
      // الأعمدةُ تُضاف ولا تُنشئ بيانات. صفٌّ زائدٌ هنا بيانةٌ اخترعها
      // البرنامجُ عن المالك.
      //
      // ⚠️ و`kitchen_stations` تُزرَع محطّةً واحدةً في الإقلاع
      //    (`database_startup.dart:514`) — زرعٌ قائمٌ قبلَ v167 ولا شأنَ
      //    له بها. والعددُ **مضبوطٌ لا متجاوَزٌ عنه**: لو صار اثنين فذاك
      //    ازدواجُ زرعٍ حقيقيٌّ يجب أن يحمرّ.
      const seeded = <String, int>{'kitchen_stations': 1};

      for (final table in _phase3Tables) {
        final rows =
            await db.customSelect('SELECT COUNT(*) AS n FROM $table').get();
        expect(rows.single.data['n'], seeded[table] ?? 0,
            reason: '$table يحمل صفوفاً لا يفسّرها زرعُ الإقلاع');
      }
    });

    test('رقمُ المخطَّط بلغ ١٦٧ فأكثر', () async {
      // «بلغ» لا «تجمّد»: توكيدٌ مساوٍ يكسر الترقيةَ التاليةَ ويكون الفشلَ
      // الوحيدَ في بوّابةٍ كاملة. الأعمدةُ أعلاه هي الدليل، والرقمُ حدٌّ أدنى.
      expect(db.schemaVersion, greaterThanOrEqualTo(167));
    });
  });

  group('منطقُ الترقية — على SQLite خامّ', () {
    late QueryExecutor raw;

    setUp(() async {
      raw = NativeDatabase.memory();
      await raw.ensureOpen(_NoopUser());
      // جدولٌ بشكلِ ما قبلَ v167: بلا أيِّ عمودِ مزامنة.
      await raw.runCustom(
        'CREATE TABLE table_orders ('
        'id INTEGER PRIMARY KEY, order_number TEXT, status TEXT)',
        [],
      );
    });

    tearDown(() => raw.close());

    test('مرساة: SQLite ترفض ADD COLUMN … UNIQUE', () async {
      // الحقيقةُ التي بُنيت عليها الصيغة. لو قبلتها نسخةٌ مستقبليّةٌ سقط
      // مبرِّرُ الفهرس الجزئيّ وسقط معه هذا الاختبار — وذلك مقصود.
      await expectLater(
        raw.runCustom(
          'ALTER TABLE table_orders ADD COLUMN global_id TEXT UNIQUE',
          [],
        ),
        throwsA(predicate((Object? e) =>
            e.toString().toLowerCase().contains('cannot add a unique column'))),
      );
    });

    test('والصيغةُ المستعملةُ تنجح وتفرض التفرّدَ فعلاً', () async {
      await raw.runCustom(
          'ALTER TABLE table_orders ADD COLUMN global_id TEXT', []);
      await raw.runCustom(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_table_orders_global_id '
        'ON table_orders(global_id) WHERE global_id IS NOT NULL',
        [],
      );

      await raw.runCustom(
          "INSERT INTO table_orders (id, global_id) VALUES (1, 'g-1')", []);

      // الفهرسُ **جزئيّ**: يمنع تكرارَ القيمة ويسمح بتعدّد NULL.
      await expectLater(
        raw.runCustom(
            "INSERT INTO table_orders (id, global_id) VALUES (2, 'g-1')", []),
        throwsA(anything),
        reason: 'التفرّدُ غيرُ مفروض ⇒ طلبان بنفس المعرّف العالميّ يتصادمان '
            'على الخادم فيُنتجان طلبَ طاولةٍ مكرَّراً.',
      );

      await raw.runCustom(
          'INSERT INTO table_orders (id, global_id) VALUES (3, NULL)', []);
      await raw.runCustom(
          'INSERT INTO table_orders (id, global_id) VALUES (4, NULL)', []);
      final n =
          await raw.runSelect('SELECT COUNT(*) AS n FROM table_orders', []);
      expect(n.single['n'], 3, reason: 'الفهرسُ الجزئيُّ منع تعدّدَ NULL');
    });

    group('المُشغِّل', () {
      setUp(() async {
        for (final ddl in const [
          'ALTER TABLE table_orders ADD COLUMN global_id TEXT',
          'ALTER TABLE table_orders ADD COLUMN last_modified_at INTEGER',
          'ALTER TABLE table_orders ADD COLUMN deleted_at INTEGER',
          'ALTER TABLE table_orders ADD COLUMN origin_client_id TEXT',
          'ALTER TABLE table_orders '
              'ADD COLUMN row_version INTEGER NOT NULL DEFAULT 0',
        ]) {
          await raw.runCustom(ddl, []);
        }
        await raw.runCustom('''
          CREATE TRIGGER IF NOT EXISTS table_orders_bump_version
          AFTER UPDATE ON table_orders FOR EACH ROW
          WHEN NEW.row_version = OLD.row_version
          BEGIN
            UPDATE table_orders SET
              last_modified_at = strftime('%s', 'now'),
              row_version = OLD.row_version + 1
            WHERE id = NEW.id;
          END
        ''', []);
        await raw.runCustom(
          "INSERT INTO table_orders (id, order_number, status) "
          "VALUES (1, 'T-1', 'open')",
          [],
        );
      });

      Future<Map<String, Object?>> row() async => (await raw.runSelect(
            'SELECT row_version, last_modified_at FROM table_orders '
            'WHERE id = 1',
            [],
          ))
              .single;

      test('🔴 تعديلٌ يرفع النسخةَ ويختم الزمن', () async {
        final before = await row();
        expect(before['row_version'], 0);
        expect(before['last_modified_at'], isNull,
            reason: 'صفٌّ قديمٌ يبدأ بلا ختمِ زمن');

        await raw.runCustom(
            "UPDATE table_orders SET status = 'paid' WHERE id = 1", []);

        final after = await row();
        expect(after['row_version'], 1,
            reason: 'النسخةُ لم تُرفَع ⇒ الخادمُ لا يرى إغلاقَ الطلب أبداً، '
                'والعمودُ رقمٌ ميّتٌ يبدو صحيحاً في أيّ فحصِ مخطَّط.');
        expect(after['last_modified_at'], isNotNull,
            reason: 'بلا ختمِ زمنٍ لا يلتقط سحبُ الدلتا الصفَّ');
      });

      test('وتعديلان يرفعانها مرّتين — لا مرّةً واحدة', () async {
        await raw.runCustom(
            "UPDATE table_orders SET status = 'paid' WHERE id = 1", []);
        await raw.runCustom(
            "UPDATE table_orders SET status = 'void' WHERE id = 1", []);
        expect((await row())['row_version'], 2);
      });

      test('وحارسُ WHEN يحترم نسخةً واردةً صريحة', () async {
        // صفٌّ يصل من الخادم بنسخته. رفعُها فوقها يجعل الجهازَ يبدو أحدثَ
        // من المصدر، فيغلب في `lastWriteWins` بتعديلٍ لم يقع.
        await raw.runCustom(
            'UPDATE table_orders SET row_version = 9 WHERE id = 1', []);
        expect((await row())['row_version'], 9,
            reason: 'المُشغِّلُ رفع فوقَ نسخةٍ صريحةٍ ⇒ الحارسُ معطَّل، '
                'وتحديثُه الداخليُّ كان ليوقظ نفسَه دوراً.');
      });
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
