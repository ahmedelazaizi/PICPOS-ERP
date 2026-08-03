// ═══════════════════════════════════════════════════════════════════════════
// `InsertMode.insertOrIgnore` على PostgreSQL — قياس السلوك الفعلي
// ═══════════════════════════════════════════════════════════════════════════
//
// الكودبيس موثّق فيه (permissions_dao) إن «drift_postgres مش بيترجم
// insertOrIgnore بثبات». الوصف ده **مضلِّل**: مش بيترجمها بثبات — بيتجاهلها
// **دايماً وبشكل حتمي**. في drift 2.32.1 (‏insert.dart) الـmode بيتحوّل لـ
// `InsertMode.insert` على ديالكت postgres، والـ`DO NOTHING` بتتكتب **بس** لما
// المنادي يبعت `onConflict` كمان — وماكانش فيه ولا موضع واحد من الـ٤٨ بيبعته.
//
// والفرق مهم: «بيشتغل أحياناً» بيغري إن الباقي يتساب.
//
// والأهم: قِسنا إن تنصيبة PG جديدة **عندها القيود فعلاً** (٥٣ UNIQUE
// و١٥٤ PRIMARY KEY)، فالنتيجة على سيرفر سليم **مش** تكرار صامت — دي
// `23505` بترمي في وش المنادي اللي كان متوقّع لا-عملية صامتة.
//
// الاختبار ده بيثبّت السلوك المقيس عشان ما يتغيّرش من تحتنا، وبيوثّق البديل
// اللي الكودبيس نفسه بيستعمله في المواضع اللي اتصلّحت.

@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

import '_support/pg_fixture.dart';

void main() {
  group('insertOrIgnore على PostgreSQL', () {
    late PgTestFixture fx;

    setUpAll(() async {
      fx = await bootPgTestSchema();
      await fx.db.customSelect('SELECT 1').get();
    });

    tearDownAll(() async => fx.tearDown());

    test('بترمي 23505 على قيد UNIQUE — مش بتتجاهل بصمت', () async {
      const code = 'probe_insert_or_ignore';

      // نضمن حالة البداية.
      await fx.db.customStatement(
        'DELETE FROM permissions WHERE code = ?',
        [code],
      );

      Future<void> insertIgnore() => fx.db.into(fx.db.permissions).insert(
            PermissionsCompanion.insert(
              code: code,
              name: 'probe',
              category: 'probe',
            ),
            mode: InsertMode.insertOrIgnore,
          );

      await insertIgnore(); // الأول بينجح

      // الشرط المسبق: القيد لازم يكون موجود فعلاً، وإلا الاختبار بيقيس
      // «تكرار صامت» بدل «استثناء» وبيبقى بيوثّق العكس.
      final hasUnique = await fx.db.customSelect(
        "SELECT 1 AS x FROM pg_constraint "
        "WHERE conrelid = 'permissions'::regclass AND contype = 'u' "
        "AND pg_get_constraintdef(oid) LIKE '%(code)%' LIMIT 1",
      ).get();
      expect(hasUnique, isNotEmpty,
          reason: 'الشرط المسبق: permissions.code لازم يكون عليه UNIQUE.');

      // التاني: على SQLite ده لا-عملية صامتة. على PG بيرمي.
      await expectLater(
        insertIgnore(),
        throwsA(predicate((e) => e.toString().contains('23505'))),
        reason: 'drift بيسقّط insertOrIgnore على postgres وبيبعت INSERT عادي، '
            'فالقيد بيرمي 23505 بدل ما الصف يتتجاهل. أي منادي متوقّع '
            'لا-عملية صامتة بياخد استثناء في وشه.',
      );

      // البديل اللي الكودبيس بيستعمله في المواضع المتصلَّحة — محايد للقيود:
      // بيشتغل صح سواء القيد موجود أو لأ، وعلى الديالكتين.
      await fx.db.customStatement(
        'INSERT INTO permissions (code, name, category) VALUES (?, ?, ?) '
        'ON CONFLICT DO NOTHING',
        [code, 'probe', 'probe'],
      );

      final rows = await fx.db.customSelect(
        'SELECT count(*) AS c FROM permissions WHERE code = ?',
        variables: [const Variable<String>(code)],
      ).getSingle();
      expect(rows.read<int>('c'), 1,
          reason: 'ON CONFLICT DO NOTHING الخام هو الشكل اللي بيدّي '
              'دلالة insertOrIgnore فعلاً على PG.');

      await fx.db.customStatement(
        'DELETE FROM permissions WHERE code = ?',
        [code],
      );
    });

    test('onConflict: DoNothing(target: []) بيدّي الدلالة الصح على PG',
        () async {
      // البديل الـdrift-native المحايد للقيود. `target: []` معناه «ما تكتبش
      // هدف صريح» فبتطلع `ON CONFLICT DO NOTHING` مجرّدة — بتطابق **أي** قيد،
      // فبتشتغل صح سواء السيرفر عنده الـUNIQUE أو فقده. من غير `target: []`
      // drift بياخد المفتاح الأساسي كهدف افتراضي، وده غلط هنا لأن التصادم
      // على `global_id` مش على `id`.
      const code = 'probe_do_nothing';
      await fx.db.customStatement(
        'DELETE FROM permissions WHERE code = ?',
        [code],
      );

      Future<void> insertDoNothing() =>
          fx.db.into(fx.db.permissions).insert(
                PermissionsCompanion.insert(
                  code: code,
                  name: 'probe',
                  category: 'probe',
                ),
                onConflict: DoNothing(target: []),
              );

      await insertDoNothing();
      // المرة التانية لازم تبقى لا-عملية صامتة — مش استثناء.
      await expectLater(insertDoNothing(), completes,
          reason: 'ON CONFLICT DO NOTHING المجرّدة لازم تبلع التصادم على PG.');

      final rows = await fx.db.customSelect(
        'SELECT count(*) AS c FROM permissions WHERE code = ?',
        variables: [const Variable<String>(code)],
      ).getSingle();
      expect(rows.read<int>('c'), 1,
          reason: 'صف واحد بالظبط — لا استثناء ولا تكرار.');

      await fx.db.customStatement(
        'DELETE FROM permissions WHERE code = ?',
        [code],
      );
    });
  });
}
