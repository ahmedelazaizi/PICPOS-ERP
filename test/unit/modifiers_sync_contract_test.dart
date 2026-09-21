// عقدُ مزامنة الإضافات والخيارات — قرارُ المالك 2026-09-21.
//
// ═══ ما بُلِّغ وما قِيس ═══
//
// الإضافاتُ والخيارات ميزةٌ مشحونةٌ يستعملها ثمانيةُ ملفّاتٍ في نقطة البيع:
// الإضافةُ ملاحظةٌ يستلمها المطبخ (زيادةُ جبنٍ أو كاتشب)، والخيارُ **مُسعَّرٌ
// يزيد قيمةَ الصنف في الفاتورة**. وجداولُها الثلاثةُ كانت خارجَ قوائم
// المزامنة الثماني **كلِّها** — فمجموعةٌ يعرّفها المديرُ لا تصل الكاشيرَ
// أبداً، وسعرُ الخيار يختلف من جهازٍ لآخرَ في فاتورتَين.
//
// وقرارُ المالك: **بياناتٌ رئيسةٌ عامّةٌ** كالأصناف والفئات — تعريفٌ واحدٌ
// يصل كلَّ الأجهزة في كلّ الفروع.
//
// ═══ 🔴 وثلاثةُ عقودٍ يقيسها هذا الملفّ ═══
//
// ‏١) **كلُّ صفٍّ يُولَد بمعرّفٍ عالميّ.** صفٌّ بلا `global_id` لا يحلّه
//    `_upsertRow` على الطرف الآخر، فيُدرَج ثانيةً بمعرّفٍ محلّيٍّ مختلف —
//    مجموعةُ «إضافات البرجر» مرّتين في منتقي الكاشير.
//
// ‏٢) 🔴 **والحذفُ ناعمٌ لا قاطع.** حذفٌ قاطعٌ محلّيّاً يترك الصفَّ على
//    الخادم، **فيعود بأوّل سحبٍ تفاضليّ**. والمستخدمُ يحذف الخيارَ فيعود
//    بعد دقائقَ بلا سبب.
//
// ‏٣) **والمحذوفُ لا يُقرأ.** الحذفُ الناعمُ بلا ترشيحٍ في القراءة يُبقي
//    الخيارَ معروضاً — «حذفٌ» لا يحذف.

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.ensureModifierTables();
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> rowOf(String table, int id) async {
    final r = await db
        .customSelect('SELECT * FROM $table WHERE id = ?', variables: [
      Variable(id),
    ]).getSingle();
    return r.data;
  }

  Future<int> seedProduct({int id = 501}) async {
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            code: 'BRG-1',
            name: 'برجر',
            salePrice: const Value(50),
            id: Value(id),
          ),
        );
    return id;
  }

  group('١ · كلُّ صفٍّ يُولَد بمعرّفٍ عالميّ', () {
    test('مرساةٌ — الأعمدةُ الخمسةُ موجودةٌ على الجداول الثلاثة', () async {
      for (final t in const [
        'modifier_groups',
        'modifier_items',
        'product_modifier_groups',
      ]) {
        final cols = await db
            .customSelect('SELECT * FROM $t WHERE 1 = 0')
            .get()
            .then((_) => true)
            .catchError((_) => false);
        expect(cols, isTrue, reason: 'الجدولُ $t غيرُ موجود');
      }
      // وعمودُ المعرّف يُقبَل في الإدراج — وإلّا سقط ما تحته بـ«no such column».
      final gid = await db.createModifierGroup(name: 'إضافات البرجر');
      expect((await rowOf('modifier_groups', gid))['global_id'], isNotNull);
    });

    test('🔴 مجموعةٌ تُنشأ بمعرّفٍ عالميّ', () async {
      final id = await db.createModifierGroup(name: 'الصوصات');
      final gid = (await rowOf('modifier_groups', id))['global_id'];
      expect(gid, isA<String>(),
          reason: '🔴 بلا معرّفٍ عالميٍّ يُدرَج الصفُّ ثانيةً على الجهاز '
              'الآخرِ بمعرّفٍ محلّيٍّ مختلف — مجموعةٌ مكرّرةٌ في المنتقي');
      expect((gid as String).length, greaterThan(20));
    });

    test('🔴 وعنصرٌ كذلك — وهو حاملُ السعر', () async {
      final g = await db.createModifierGroup(name: 'الصوصات');
      final i = await db.createModifierItem(
          groupId: g, name: 'جبنة', extraPrice: 5);
      expect((await rowOf('modifier_items', i))['global_id'], isA<String>(),
          reason: '🔴 العنصرُ يحمل `extra_price` الذي يزيد قيمةَ الفاتورة — '
              'وتكرارُه يعني سعرَين لخيارٍ واحد');
    });

    test('🔴 وربطُ المنتج بالمجموعة كذلك', () async {
      final p = await seedProduct();
      final g = await db.createModifierGroup(name: 'الصوصات');
      await db.linkModifierToProduct(productId: p, modifierGroupId: g);
      final r = await db
          .customSelect('SELECT * FROM product_modifier_groups')
          .getSingle();
      expect(r.data['global_id'], isA<String>(),
          reason: '🔴 الربطُ بلا معرّف ⇒ الصنفُ يصل الجهازَ الآخرَ بلا '
              'إضافاته، أو بربطٍ مكرَّر');
    });

    test('والختمُ الزمنيُّ يُكتَب — وإلّا لم يلتقطه السحبُ التفاضليّ', () async {
      final id = await db.createModifierGroup(name: 'الصوصات');
      expect((await rowOf('modifier_groups', id))['last_modified_at'],
          isNotNull,
          reason: 'السحبُ التفاضليُّ يطلب ما تغيّر بعد ختمٍ — وصفٌّ بلا ختمٍ '
              'لا يُسلَّم أبداً');
    });

    test('وتعديلٌ يُحرّك الختم', () async {
      final id = await db.createModifierGroup(name: 'الصوصات');
      final before =
          (await rowOf('modifier_groups', id))['last_modified_at'] as int;
      await db.updateModifierGroup(
        id: id,
        name: 'الصوصات الحارّة',
        type: 'addon',
        minSelect: 0,
        maxSelect: 1,
        isRequired: false,
        isActive: true,
      );
      final after =
          (await rowOf('modifier_groups', id))['last_modified_at'] as int;
      expect(after, greaterThanOrEqualTo(before));
      expect((await rowOf('modifier_groups', id))['name'], 'الصوصات الحارّة');
    });
  });

  group('٢ · الحذفُ ناعمٌ ولا يُقرأ', () {
    test('🔴 حذفُ مجموعةٍ يَسِمها ولا يمحوها', () async {
      final id = await db.createModifierGroup(name: 'الصوصات');
      await db.deleteModifierGroup(id);

      final rows = await db
          .customSelect('SELECT * FROM modifier_groups WHERE id = ?',
              variables: [Variable(id)])
          .get();
      expect(rows, hasLength(1),
          reason: '🔴 حذفٌ قاطعٌ محلّيّاً يترك الصفَّ على الخادم فيعود بأوّل '
              'سحبٍ — يحذف المستخدمُ الخيارَ فيعود بعد دقائقَ بلا سبب');
      expect(rows.single.data['deleted_at'], isNotNull,
          reason: '🔴 الصفُّ باقٍ بلا وسمِ حذفٍ ⇒ لم يُحذَف إطلاقاً');
    });

    test('🔴 والمحذوفُ لا يُعرَض', () async {
      final keep = await db.createModifierGroup(name: 'الصوصات');
      final drop = await db.createModifierGroup(name: 'ملغاة');
      await db.deleteModifierGroup(drop);

      final all = await db.getAllModifierGroups();
      expect(all.map((g) => g.id), contains(keep));
      expect(all.map((g) => g.id), isNot(contains(drop)),
          reason: '🔴 المحذوفُ ما زال في المنتقي — «حذفٌ» لا يحذف');
    });

    test('🔴 وعنصرٌ محذوفٌ لا يُعرَض في مجموعته', () async {
      final g = await db.createModifierGroup(name: 'الصوصات');
      final keep =
          await db.createModifierItem(groupId: g, name: 'جبنة', extraPrice: 5);
      final drop = await db.createModifierItem(
          groupId: g, name: 'ملغى', extraPrice: 3);
      await db.deleteModifierItem(drop);

      final items = await db.getModifierItems(g);
      expect(items.map((i) => i.id), contains(keep));
      expect(items.map((i) => i.id), isNot(contains(drop)),
          reason: '🔴 خيارٌ محذوفٌ ما زال يُعرَض ويُسعَّر');
    });

    test('🔴 وفكُّ ربطٍ ناعمٌ كذلك', () async {
      final p = await seedProduct();
      final g = await db.createModifierGroup(name: 'الصوصات');
      await db.linkModifierToProduct(productId: p, modifierGroupId: g);
      await db.unlinkModifierFromProduct(productId: p, modifierGroupId: g);

      final rows =
          await db.customSelect('SELECT * FROM product_modifier_groups').get();
      expect(rows, hasLength(1),
          reason: '🔴 فكٌّ قاطعٌ يعود بأوّل سحب');
      expect(rows.single.data['deleted_at'], isNotNull);

      final groups = await db.getProductModifierGroupIds(p);
      expect(groups, isEmpty,
          reason: '🔴 الصنفُ ما زال يعرض إضافاتٍ فُكَّ ربطُها');
    });

    test('🔴 وإعادةُ الربط بعد الفكِّ تعمل — الصفُّ يُحيا لا يُهمَل',
        (() async {
      // 🔴 **مصيدةٌ يولّدها الحذفُ الناعم نفسُه**: الصفُّ الموسومُ ما زال
      //    يشغل `UNIQUE(product_id, modifier_group_id)`، فإدراجٌ بـ
      //    `ON CONFLICT DO NOTHING` يُهمَل بصمتٍ ويبقى الربطُ محذوفاً.
      //    أي أنّ إعادةَ ربطِ إضافةٍ بصنفٍ **لا تعمل أبداً** بعد فكٍّ واحد،
      //    والمستخدمُ يضغط ولا يحدث شيء.
      final p = await seedProduct(id: 502);
      final g = await db.createModifierGroup(name: 'الصوصات');
      await db.linkModifierToProduct(productId: p, modifierGroupId: g);
      await db.unlinkModifierFromProduct(productId: p, modifierGroupId: g);
      await db.linkModifierToProduct(productId: p, modifierGroupId: g);

      expect(await db.getProductModifierGroupIds(p), contains(g),
          reason: '🔴 أُعيد الربطُ ولم يعد — الصفُّ الموسومُ يحجز القيدَ '
              'والإدراجُ يُهمَل بصمت');
      final rows =
          await db.customSelect('SELECT * FROM product_modifier_groups').get();
      expect(rows, hasLength(1), reason: 'صفٌّ مكرَّرٌ لنفس الربط');
      expect(rows.single.data['deleted_at'], isNull);
    }));
  });
}
