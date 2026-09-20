// مخطَّطُ القاعة — أوّلُ كاتبٍ لجدول v174 `FloorPlanItems`.
//
// ═══ 🔴 ما يُقاس هنا ولماذا ═══
//
// ‏١) **الحفظُ مستندٌ واحدٌ في معاملةٍ واحدة.** المصمّمُ القديم كان يكتب عند
//    نهاية كلّ سحبة: لا تراجعَ ممكن، ولا ذرّيّةَ لنصفِ ترتيبٍ انقطع.
//
// ‏٢) 🔴 **وما غاب عن الحمولة يُحذَف حذفاً ناعماً.** الحمولةُ **صورةُ
//    المخطَّط كلِّه** لا فرقُه، فجدارٌ مسحه المستخدمُ يجب ألّا يعود في أوّل
//    فتحٍ للشاشة.
//
// ‏٣) 🔴 **وطاولةُ قسمٍ آخرَ لا تتحرّك.** الحمولةُ تأتي من شاشةٍ أو من السلك،
//    وطاولةٌ من قسمٍ آخرَ ذُكرت فيها كانت ستُنقَل إلى إحداثيّاتِ لوحةٍ لا
//    تخصّها — فتختفي من قسمها ولم يلمسها أحد.
//
// ‏٤) **والمعرِّفُ العالميُّ يُولَد مع المعلَم** لا بعد أوّل مزامنة: المعلَمُ
//    قد يُرسَم دون اتّصالٍ ويُدفَع لاحقاً، فلا بدّ أن يحمل حينها نفسَ
//    المعرِّف.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/floor_plan_layout.dart';

void main() {
  late AppDatabase db;
  late int sectionA;
  late int sectionB;

  setUp(() async {
    db = AppDatabase.forTesting();
    sectionA = await db.createSection('الصالة');
    sectionB = await db.createSection('التراس');
  });

  tearDown(() => db.close());

  Future<int> seedTable(String name, int sectionId, {int capacity = 4}) =>
      db.createTable(name: name, sectionId: sectionId, capacity: capacity);

  FloorPlanItemInput item({
    String kind = 'wall',
    double x = 40,
    double y = 40,
    double width = 200,
    double height = 20,
    String? label,
    String? globalId,
    int? id,
  }) =>
      (
        id: id,
        globalId: globalId,
        kind: kind,
        x: x,
        y: y,
        width: width,
        height: height,
        rotation: 0,
        label: label,
      );

  FloorPlanSectionLayout layout(
    int sectionId, {
    double canvasWidth = 1200,
    double canvasHeight = 900,
    double originX = 0,
    double originY = 0,
    List<FloorPlanTableGeometry> tables = const [],
    List<FloorPlanItemInput> items = const [],
  }) =>
      (
        sectionId: sectionId,
        sectionGlobalId: null,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
        originX: originX,
        originY: originY,
        tables: tables,
        items: items,
      );

  FloorPlanTableGeometry geom(
    int id, {
    double x = 100,
    double y = 100,
    double? width,
    double? height,
    double rotation = 0,
    String shape = 'rect',
  }) =>
      (
        id: id,
        globalId: null,
        x: x,
        y: y,
        width: width,
        height: height,
        rotation: rotation,
        shape: shape,
      );

  group('القراءة', () {
    test('قسمٌ بلا مخطَّطٍ يعود بلوحةٍ افتراضيّةٍ لا بـnull', () async {
      final l = await db.getFloorPlanSectionLayout(sectionA);
      expect(l, isNotNull);
      expect(l!.canvasWidth, kDefaultCanvasWidth);
      expect(l.canvasHeight, kDefaultCanvasHeight);
      expect(l.items, isEmpty);
    });

    test('وقسمٌ غيرُ موجودٍ يعود null', () async {
      expect(await db.getFloorPlanSectionLayout(9999), isNull);
    });

    test('ويحمل طاولاتِ قسمه وحدَها', () async {
      await seedTable('١', sectionA);
      await seedTable('٢', sectionB);
      final l = await db.getFloorPlanSectionLayout(sectionA);
      expect(l!.tables.length, 1);
    });
  });

  group('الحفظ', () {
    test('يكتب هندسةَ القسم ومعالمَه وطاولاته معاً', () async {
      final t = await seedTable('١', sectionA);
      await db.saveFloorPlanLayout(layout(
        sectionA,
        canvasWidth: 1400,
        canvasHeight: 700,
        originX: 200,
        originY: 300,
        tables: [geom(t, x: 320, y: 240, width: 200, height: 80, rotation: 90)],
        items: [item(kind: 'bar', label: 'البار')],
      ));

      final l = (await db.getFloorPlanSectionLayout(sectionA))!;
      expect(l.canvasWidth, 1400);
      expect(l.canvasHeight, 700);
      expect(l.originX, 200);
      expect(l.originY, 300);
      expect(l.tables.single.x, 320);
      expect(l.tables.single.width, 200);
      expect(l.tables.single.rotation, 90);
      expect(l.items.single.kind, 'bar');
      expect(l.items.single.label, 'البار');
    });

    test('🔴 والمعلَمُ يُولَد بمعرِّفٍ عالميٍّ قبل أيّ مزامنة', () async {
      await db.saveFloorPlanLayout(layout(sectionA, items: [item()]));
      final l = (await db.getFloorPlanSectionLayout(sectionA))!;
      expect(l.items.single.globalId, isNotNull);
      expect(l.items.single.globalId, isNotEmpty);
    });

    test('ومعرِّفٌ جاء مع الحمولة يُحترَم لا يُستبدَل', () async {
      await db.saveFloorPlanLayout(
          layout(sectionA, items: [item(globalId: 'from-client')]));
      final l = (await db.getFloorPlanSectionLayout(sectionA))!;
      expect(l.items.single.globalId, 'from-client');
    });

    test('وحفظٌ ثانٍ يُحدِّث المعلَمَ نفسَه لا يضاعفه', () async {
      await db.saveFloorPlanLayout(
          layout(sectionA, items: [item(globalId: 'g1', x: 40)]));
      await db.saveFloorPlanLayout(
          layout(sectionA, items: [item(globalId: 'g1', x: 400)]));

      final l = (await db.getFloorPlanSectionLayout(sectionA))!;
      expect(l.items.length, 1);
      expect(l.items.single.x, 400);
    });

    test('🔴 وما غاب عن الحمولة يُحذَف — وإلّا عاد الجدارُ المحذوفُ غداً',
        () async {
      await db.saveFloorPlanLayout(layout(sectionA, items: [
        item(globalId: 'a'),
        item(globalId: 'b', y: 300),
      ]));
      expect((await db.getFloorPlanItems(sectionA)).length, 2);

      await db
          .saveFloorPlanLayout(layout(sectionA, items: [item(globalId: 'a')]));

      final left = await db.getFloorPlanItems(sectionA);
      expect(left.length, 1);
      expect(left.single.globalId, 'a');
    });

    test('والحذفُ ناعمٌ — الصفُّ يبقى بوسمِ حذفه لتصل المزامنةُ به', () async {
      await db.saveFloorPlanLayout(layout(sectionA, items: [item(globalId: 'a')]));
      await db.saveFloorPlanLayout(layout(sectionA));

      final raw = await db.select(db.floorPlanItems).get();
      expect(raw.length, 1);
      expect(raw.single.deletedAt, isNotNull);
      expect(raw.single.isActive, isFalse);
    });

    test('وحفظُ قسمٍ لا يمسّ معالمَ قسمٍ آخر', () async {
      await db.saveFloorPlanLayout(layout(sectionB, items: [item(globalId: 'b')]));
      await db.saveFloorPlanLayout(layout(sectionA, items: [item(globalId: 'a')]));
      await db.saveFloorPlanLayout(layout(sectionA));

      expect((await db.getFloorPlanItems(sectionA)), isEmpty);
      expect((await db.getFloorPlanItems(sectionB)).length, 1);
    });

    test('🔴 وطاولةُ قسمٍ آخرَ ذُكرت في الحمولة لا تتحرّك', () async {
      final foreign = await seedTable('غريبة', sectionB);
      await db.saveFloorPlanLayout(
          layout(sectionA, tables: [geom(foreign, x: 777, y: 777)]));

      final row = await (db.select(db.restaurantTables)
            ..where((t) => t.id.equals(foreign)))
          .getSingle();
      expect(row.x, 0);
      expect(row.y, 0);
      expect(row.sectionId, sectionB);
    });

    test('ولا يكتب حالةَ الطاولة — المصمّمُ يحفظ مواضعَ لا حالات', () async {
      final t = await seedTable('١', sectionA);
      await db.updateTableStatus(t, 'occupied');
      await db.saveFloorPlanLayout(layout(sectionA, tables: [geom(t)]));

      final row = await (db.select(db.restaurantTables)
            ..where((x) => x.id.equals(t)))
          .getSingle();
      expect(row.status, 'occupied');
    });

    test('ويبصم `lastModifiedAt` على القسم والطاولة والمعلَم', () async {
      final t = await seedTable('١', sectionA);
      await db.saveFloorPlanLayout(
          layout(sectionA, tables: [geom(t)], items: [item(globalId: 'g')]));

      final section = await (db.select(db.tableSections)
            ..where((s) => s.id.equals(sectionA)))
          .getSingle();
      final table = await (db.select(db.restaurantTables)
            ..where((x) => x.id.equals(t)))
          .getSingle();
      final it = (await db.getFloorPlanItems(sectionA)).single;

      expect(section.lastModifiedAt, isNotNull);
      expect(table.lastModifiedAt, isNotNull);
      expect(it.lastModifiedAt, isNotNull);
    });
  });

  group('الرفض', () {
    test('🔴 نوعُ معلَمٍ غيرُ معروفٍ يُرفَض — لا يُرسَم فيسقط صامتاً', () async {
      await expectLater(
        db.saveFloorPlanLayout(layout(sectionA, items: [item(kind: 'window')])),
        throwsA(isA<ArgumentError>()),
      );
      expect(await db.getFloorPlanItems(sectionA), isEmpty);
    });

    test('ولوحةٌ خارجَ الحدود تُرفَض', () async {
      await expectLater(
        db.saveFloorPlanLayout(layout(sectionA, canvasWidth: 10)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('ومعلَمُ نصٍّ بلا نصٍّ يُرفَض', () async {
      await expectLater(
        db.saveFloorPlanLayout(layout(sectionA, items: [item(kind: 'text')])),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('🔴 والرفضُ يسبق المعاملةَ فلا يبقى نصفُ حفظ', () async {
      // حفظٌ سليمٌ أوّلاً، ثمّ حفظٌ فيه معلَمٌ فاسدٌ ومقاسُ لوحةٍ جديد:
      // المقاسُ يجب ألّا يُكتَب.
      await db.saveFloorPlanLayout(layout(sectionA, canvasWidth: 1400));
      await expectLater(
        db.saveFloorPlanLayout(layout(
          sectionA,
          canvasWidth: 2000,
          items: [item(kind: 'window')],
        )),
        throwsA(isA<ArgumentError>()),
      );

      final l = (await db.getFloorPlanSectionLayout(sectionA))!;
      expect(l.canvasWidth, 1400);
    });
  });

  group('صناديقُ المحلّ', () {
    test('تُرصَف الأقسامُ بلا موضعٍ صفّاً لا تنطبق', () async {
      final boxes = await db.getFloorPlanSectionBoxes();
      expect(boxes.length, 2);
      expect(boxes[0].originX, isNot(boxes[1].originX));
    });

    test('والموضعُ المحفوظُ يُقرأ كما كُتب', () async {
      await db.saveFloorPlanLayout(
          layout(sectionA, originX: 900, originY: 120));
      final boxes = await db.getFloorPlanSectionBoxes();
      final a = boxes.firstWhere((b) => b.sectionId == sectionA);
      expect(a.originX, 900);
      expect(a.originY, 120);
    });

    test('ومقاسُ اللوحة المحفوظُ يدخل الصندوق', () async {
      await db.saveFloorPlanLayout(
          layout(sectionA, canvasWidth: 2000, canvasHeight: 400));
      final boxes = await db.getFloorPlanSectionBoxes();
      final a = boxes.firstWhere((b) => b.sectionId == sectionA);
      expect(a.width, 2000);
      expect(a.height, 400);
    });

    test('والقسمُ المعطَّلُ يغيب عن الأرضيّة', () async {
      await db.deleteSection(sectionB);
      final boxes = await db.getFloorPlanSectionBoxes();
      expect(boxes.map((b) => b.sectionId), [sectionA]);
    });
  });
}
