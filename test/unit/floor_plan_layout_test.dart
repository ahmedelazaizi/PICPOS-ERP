// حسابُ مخطَّط القاعة — قسمُ ٧.
//
// كلُّ ما هنا خالصٌ بلا قاعدةٍ ولا ودجت، فيُقاس بلا فتح شاشةٍ ولا
// `ProviderContainer`.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/floor_plan_layout.dart';

FloorPlanItemInput _item({
  String kind = 'wall',
  double x = 0,
  double y = 0,
  double width = 100,
  double height = 20,
  double rotation = 0,
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
      rotation: rotation,
      label: label,
    );

FloorPlanSectionLayout _layout({
  double canvasWidth = kDefaultCanvasWidth,
  double canvasHeight = kDefaultCanvasHeight,
  double originX = 0,
  double originY = 0,
  List<FloorPlanTableGeometry> tables = const [],
  List<FloorPlanItemInput> items = const [],
  String? sectionGlobalId = 'sec-gid',
}) =>
    (
      sectionId: 1,
      sectionGlobalId: sectionGlobalId,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      originX: originX,
      originY: originY,
      tables: tables,
      items: items,
    );

FloorPlanTableGeometry _table({
  int id = 1,
  String? globalId = 't-gid',
  double x = 0,
  double y = 0,
  double? width,
  double? height,
  double rotation = 0,
  String shape = 'rect',
}) =>
    (
      id: id,
      globalId: globalId,
      x: x,
      y: y,
      width: width,
      height: height,
      rotation: rotation,
      shape: shape,
    );

void main() {
  group('مقاسُ الطاولة', () {
    test('المحفوظُ يسبق المشتقَّ من السعة', () {
      final s = resolveTableSize(width: 300, height: 60, capacity: 4);
      expect(s.width, 300);
      expect(s.height, 60);
    });

    test('والغائبُ وحدَه يعود إلى الاشتقاق', () {
      final s = resolveTableSize(width: 300, height: null, capacity: 4);
      expect(s.width, 300);
      expect(s.height, legacyTableSide(4));
    });

    test('ومقاسٌ صفرٌ ليس مقاساً — يعود إلى الاشتقاق', () {
      // صفرٌ في القاعدة يعني طاولةً بلا أبعادٍ على الشاشة: لا تُرى ولا
      // تُلتقَط بالماوس، فلا تُصلَح.
      final s = resolveTableSize(width: 0, height: 0, capacity: 6);
      expect(s.width, legacyTableSide(6));
      expect(s.height, legacyTableSide(6));
    });

    test('🔴 والانطباقُ عند الطرفَين لا عند ٢ و٣', () {
      // ⚠️ وهذا **يصحّح تشخيصَ الخطّة**: كتبت «فطاولتا ٢ و٣
      //    متطابقتان»، والقياسُ يقول غيرَ ذلك: ٣ تُعطي ٨٤ فتمرّ.
      expect(legacyTableSide(2), isNot(legacyTableSide(3)));
      expect(legacyTableSide(3), 84);
    });

    test('🔴 فالسعتان ١ و٢ تُقصّان إلى مقاسٍ واحد', () {
      expect(legacyTableSide(1), legacyTableSide(2));
      expect(legacyTableSide(1), 80);
    });

    test('وكلُّ سعةٍ فوق العاشرة متطابقةٌ كذلك', () {
      expect(legacyTableSide(10), 140);
      expect(legacyTableSide(20), 140);
      expect(legacyTableSide(99), 140);
    });

    test('والاشتقاقُ يتحرّك بين الحدَّين', () {
      expect(legacyTableSide(4), 92);
      expect(legacyTableSide(8), 124);
    });
  });

  group('الالتقاطُ بالشبكة', () {
    test('يقرّب إلى أقرب خطوة', () {
      expect(snapToStep(97, 40), 80);
      expect(snapToStep(101, 40), 120);
    });

    test('🔴 وخطوةُ صفرٍ تُعيد القيمةَ كما هي لا تقسم عليها', () {
      expect(snapToStep(97, 0), 97);
      expect(snapToStep(97, -40), 97);
    });

    test('وخطوةُ NaN كذلك — وإلّا صار الموضعُ NaN ورمى الرسمُ', () {
      expect(snapToStep(97, double.nan), 97);
      expect(snapToStep(97, double.infinity), 97);
    });

    test('وقيمةٌ غيرُ منتهيةٍ تمرّ كما هي', () {
      expect(snapToStep(double.nan, 40).isNaN, isTrue);
    });

    test('والخطواتُ المتاحةُ كلُّها موجبة', () {
      for (final step in kFloorPlanGridSteps) {
        expect(step, greaterThan(0));
      }
    });
  });

  group('تحقّقُ المعلَم', () {
    test('نوعٌ خارجَ المجموعة يُرفَض', () {
      expect(validateFloorPlanItem(_item(kind: 'window')), isNotNull);
    });

    test('والأنواعُ الستّةُ كلُّها تمرّ', () {
      for (final kind in kFloorPlanItemKinds) {
        final e = validateFloorPlanItem(
          _item(kind: kind, label: kind == 'text' ? 'كاشير' : null),
        );
        expect(e, isNull, reason: 'النوعُ $kind رُفض');
      }
    });

    test('ومعلَمُ النصّ بلا نصّ يُرفَض', () {
      expect(validateFloorPlanItem(_item(kind: 'text')), isNotNull);
      expect(validateFloorPlanItem(_item(kind: 'text', label: '   ')), isNotNull);
      expect(validateFloorPlanItem(_item(kind: 'text', label: 'كاشير')), isNull);
    });

    test('ومقاسٌ أصغرُ من الحدّ يُرفَض — نقطةٌ لا تُلتقَط لا تُحذَف', () {
      expect(validateFloorPlanItem(_item(width: 2)), isNotNull);
      expect(validateFloorPlanItem(_item(height: 2)), isNotNull);
      expect(
        validateFloorPlanItem(_item(width: kMinItemSide, height: kMinItemSide)),
        isNull,
      );
    });

    test('ونصٌّ أطولُ من حدِّ العمود يُرفَض قبل أن تقطعَه القاعدة', () {
      final long = 'ج' * (kFloorPlanLabelMax + 1);
      expect(validateFloorPlanItem(_item(label: long)), isNotNull);
      expect(
        validateFloorPlanItem(_item(label: 'ج' * kFloorPlanLabelMax)),
        isNull,
      );
    });

    test('وإحداثيّةٌ غيرُ منتهيةٍ تُرفَض', () {
      expect(validateFloorPlanItem(_item(x: double.nan)), isNotNull);
      expect(validateFloorPlanItem(_item(rotation: double.infinity)), isNotNull);
    });
  });

  group('تحقّقُ اللوحة', () {
    test('أصغرُ من الحدّ يُرفَض', () {
      expect(
        validateCanvasSize(width: kMinCanvasSide - 1, height: 800),
        isNotNull,
      );
    });

    test('وأكبرُ من الحدّ يُرفَض', () {
      expect(
        validateCanvasSize(width: kMaxCanvasSide + 1, height: 800),
        isNotNull,
      );
    });

    test('وما بينهما يمرّ', () {
      expect(validateCanvasSize(width: 1200, height: 900), isNull);
    });

    test('والمخطَّطُ يُردّ بأوّل معلَمٍ فاسد', () {
      final bad = validateFloorPlanLayout(
        _layout(items: [_item(), _item(kind: 'window')]),
      );
      expect(bad, isNotNull);
    });

    test('وموضعُ القسم غيرُ المنتهي يُرفَض', () {
      expect(validateFloorPlanLayout(_layout(originX: double.nan)), isNotNull);
    });
  });

  group('الحصرُ داخلَ اللوحة', () {
    test('🔴 طاولةٌ وراء الحافّة تعود داخلَها بعد تصغير الصالة', () {
      final out = clampLayoutToCanvas(
        _layout(
          canvasWidth: 500,
          canvasHeight: 500,
          tables: [_table(x: 900, y: 900, width: 100, height: 100)],
        ),
        capacityOf: (_) => 4,
      );
      expect(out.tables.single.x, 400);
      expect(out.tables.single.y, 400);
    });

    test('ومعلَمٌ أعرضُ من اللوحة يُقصّ إلى عرضها', () {
      final out = clampLayoutToCanvas(
        _layout(
          canvasWidth: 500,
          canvasHeight: 500,
          items: [_item(width: 900, height: 900, globalId: 'g')],
        ),
        capacityOf: (_) => 4,
      );
      expect(out.items.single.width, 500);
      expect(out.items.single.height, 500);
      expect(out.items.single.x, 0);
    });

    test('وما هو داخلَ اللوحة أصلاً لا يتحرّك', () {
      final out = clampLayoutToCanvas(
        _layout(tables: [_table(x: 120, y: 240)]),
        capacityOf: (_) => 4,
      );
      expect(out.tables.single.x, 120);
      expect(out.tables.single.y, 240);
    });

    test('والحصرُ يقرأ المقاسَ المحفوظَ لا المشتقّ', () {
      // طاولةٌ عرضُها ٤٠٠ لا تُحصَر كأنّها ٩٢: نصفُها كان سيبقى خارجاً.
      final out = clampLayoutToCanvas(
        _layout(
          canvasWidth: 500,
          canvasHeight: 500,
          tables: [_table(x: 490, width: 400, height: 100)],
        ),
        capacityOf: (_) => 4,
      );
      expect(out.tables.single.x, 100);
    });
  });

  group('نظرةُ المحلّ', () {
    test('🔴 الأقسامُ بلا موضعٍ تُرصَف صفّاً لا تنطبق عند الصفر', () {
      final boxes = resolveSectionOrigins([
        (sectionId: 1, originX: null, originY: null, width: 400, height: 300),
        (sectionId: 2, originX: null, originY: null, width: 500, height: 300),
        (sectionId: 3, originX: null, originY: null, width: 200, height: 300),
      ]);
      expect(boxes[0].originX, 0);
      expect(boxes[1].originX, 400 + kSectionGap);
      expect(boxes[2].originX, 400 + kSectionGap + 500 + kSectionGap);
      expect(boxes.map((b) => b.originX).toSet().length, 3);
    });

    test('والموضعُ المحفوظُ يُحترَم ولا يُزحزَح الرصفُ به', () {
      final boxes = resolveSectionOrigins([
        (sectionId: 1, originX: 900, originY: 40, width: 400, height: 300),
        (sectionId: 2, originX: null, originY: null, width: 500, height: 300),
      ]);
      expect(boxes[0].originX, 900);
      expect(boxes[0].originY, 40);
      // القسمُ المحفوظُ لا يدفع المؤشِّر، فالثاني يبدأ من الصفر.
      expect(boxes[1].originX, 0);
    });

    test('وموضعٌ غيرُ منتهٍ يُعامَل كأنّه غائب', () {
      final boxes = resolveSectionOrigins([
        (
          sectionId: 1,
          originX: double.nan,
          originY: 0,
          width: 400,
          height: 300
        ),
      ]);
      expect(boxes.single.originX, 0);
    });

    test('والامتدادُ يشمل أبعدَ قسمٍ لا أوّلَه', () {
      final ext = shopExtent([
        (sectionId: 1, originX: 0, originY: 0, width: 400, height: 300),
        (sectionId: 2, originX: 900, originY: 500, width: 200, height: 100),
      ]);
      expect(ext.width, 1100);
      expect(ext.height, 600);
    });

    test('ولا أقسامَ ⇒ لوحةٌ افتراضيّةٌ لا صفر', () {
      final ext = shopExtent(const []);
      expect(ext.width, kDefaultCanvasWidth);
      expect(ext.height, kDefaultCanvasHeight);
    });
  });

  group('ملاءمةُ الشاشة', () {
    test('تصغّر ما لا يتّسع', () {
      final s = fitScale(
        contentWidth: 2000,
        contentHeight: 1000,
        viewWidth: 1000,
        viewHeight: 1000,
      );
      expect(s, 0.5);
    });

    test('🔴 ولا تكبّر ما يتّسع — «الملاءمة» أن يُرى الكلُّ لا أن يُملأ الفراغ',
        () {
      final s = fitScale(
        contentWidth: 200,
        contentHeight: 100,
        viewWidth: 1000,
        viewHeight: 1000,
      );
      expect(s, 1.0);
    });

    test('وتأخذ الضلعَ الأضيق', () {
      final s = fitScale(
        contentWidth: 1000,
        contentHeight: 4000,
        viewWidth: 1000,
        viewHeight: 1000,
      );
      expect(s, 0.25);
    });

    test('ومقاسٌ صفرٌ لا يُنتج قسمةً على صفر', () {
      expect(fitScale(contentWidth: 0, contentHeight: 0, viewWidth: 100, viewHeight: 100), 1.0);
      expect(fitScale(contentWidth: 100, contentHeight: 100, viewWidth: 0, viewHeight: 0), 1.0);
    });
  });

  group('المحاذاةُ والتوزيع', () {
    List<FloorPlanBox> boxes(List<List<double>> xy) =>
        [for (var i = 0; i < xy.length; i++) (key: 'k$i', x: xy[i][0], y: xy[i][1])];

    test('المحاذاةُ الأفقيّةُ تُسوّي الصادات على متوسّطها', () {
      final out = alignBoxes(
        boxes([[0, 100], [50, 200], [100, 300]]),
        horizontal: true,
      );
      expect(out.map((b) => b.y), [200, 200, 200]);
      expect(out.map((b) => b.x), [0, 50, 100], reason: 'السينات لا تُمَسّ');
    });

    test('والرأسيّةُ تُسوّي السينات', () {
      final out = alignBoxes(
        boxes([[0, 100], [50, 200], [100, 300]]),
        horizontal: false,
      );
      expect(out.map((b) => b.x), [50, 50, 50]);
      expect(out.map((b) => b.y), [100, 200, 300]);
    });

    test('🔴 وصندوقٌ واحدٌ لا يتحرّك — «محاذاةٌ» بلا ما يُحاذى إليه', () {
      final src = boxes([[13, 17]]);
      expect(alignBoxes(src, horizontal: true), src);
      expect(alignBoxes(src, horizontal: false), src);
    });

    test('والتوزيعُ يجعل الخطوات متساوية', () {
      final out = distributeBoxes(
        boxes([[0, 0], [10, 0], [100, 0]]),
        horizontal: true,
      );
      expect(out.map((b) => b.x), [0, 50, 100]);
    });

    test('🔴 والطرفان يبقيان مكانَهما — وإلّا انزلق الصفُّ عن جداره', () {
      final out = distributeBoxes(
        boxes([[20, 0], [30, 0], [40, 0], [120, 0]]),
        horizontal: true,
      );
      expect(out.first.x, 20);
      expect(out.last.x, 120);
    });

    test('ويرتّب قبل التوزيع فلا يعتمد على ترتيب الاختيار', () {
      final out = distributeBoxes(
        boxes([[100, 0], [0, 0], [10, 0]]),
        horizontal: true,
      );
      expect(out.map((b) => b.x), [0, 50, 100]);
    });

    test('وأقلُّ من ثلاثةٍ لا يُوزَّع — لا شيءَ بينهما', () {
      final src = boxes([[0, 0], [100, 0]]);
      expect(distributeBoxes(src, horizontal: true), src);
    });
  });

  group('مكدّسُ التراجع', () {
    test('يبدأ بلا تراجعٍ ولا إعادة', () {
      final s = FloorPlanUndoStack<int>(0);
      expect(s.canUndo, isFalse);
      expect(s.canRedo, isFalse);
      expect(s.current, 0);
    });

    test('ويتراجع ويعيد', () {
      final s = FloorPlanUndoStack<int>(0)
        ..push(1)
        ..push(2);
      expect(s.current, 2);
      expect(s.undo(), 1);
      expect(s.undo(), 0);
      expect(s.canUndo, isFalse);
      expect(s.redo(), 1);
      expect(s.redo(), 2);
    });

    test('🔴 وخطوةٌ جديدةٌ تمحو ما بعدها — لا قفزَ إلى فرعٍ مهجور', () {
      final s = FloorPlanUndoStack<int>(0)
        ..push(1)
        ..push(2);
      s.undo();
      expect(s.canRedo, isTrue);
      s.push(99);
      expect(s.canRedo, isFalse);
      expect(s.current, 99);
    });

    test('والتراجعُ على مكدّسٍ فارغٍ لا يرمي', () {
      final s = FloorPlanUndoStack<int>(7);
      expect(s.undo(), 7);
      expect(s.redo(), 7);
    });

    test('والسقفُ يُسقط الأقدمَ لا الأحدث', () {
      final s = FloorPlanUndoStack<int>(0, limit: 3);
      for (var i = 1; i <= 10; i++) {
        s.push(i);
      }
      expect(s.depth, 3);
      expect(s.current, 10);
      expect(s.undo(), 9);
    });
  });

  group('توسيمُ المعرّفات', () {
    test('🔴 المعلَمُ بلا معرِّفٍ ينال واحداً — وإلّا حمل صفّا العميل والخادم '
        'هويّتَين لمعلَمٍ واحد', () {
      var n = 0;
      final out = stampMissingGlobalIds(
        _layout(items: [_item(), _item(globalId: 'keep')]),
        () => 'new-${++n}',
      );
      expect(out.items[0].globalId, 'new-1');
      expect(out.items[1].globalId, 'keep');
      expect(n, 1);
    });

    test('ومعرِّفٌ فارغٌ يُعامَل كغائب', () {
      final out = stampMissingGlobalIds(
        _layout(items: [_item(globalId: '')]),
        () => 'fresh',
      );
      expect(out.items.single.globalId, 'fresh');
    });
  });

  group('هويّةُ السلك', () {
    test('قسمٌ بلا معرِّفٍ عالميٍّ لا يُرسَل', () {
      expect(
        validateFloorPlanWireIdentity(_layout(sectionGlobalId: null)),
        isNotNull,
      );
    });

    test('وطاولةٌ بلا معرِّفٍ عالميٍّ توقف الإرسالَ كذلك', () {
      expect(
        validateFloorPlanWireIdentity(
          _layout(tables: [_table(globalId: null)]),
        ),
        isNotNull,
      );
    });

    test('ومخطَّطٌ كاملُ الهويّة يمرّ', () {
      expect(
        validateFloorPlanWireIdentity(_layout(tables: [_table()])),
        isNull,
      );
    });
  });

  group('السلك', () {
    test('🔴 الحمولةُ لا تحمل رقمَ صفٍّ محلّيّاً لطاولةٍ ولا لمعلَم', () {
      final json = floorPlanLayoutToJson(
        _layout(
          tables: [_table(id: 77)],
          items: [_item(id: 55, globalId: 'g')],
        ),
      );
      expect(json.toString(), isNot(contains('"id"')));
      final t = (json['tables'] as List).single as Map<String, dynamic>;
      final i = (json['items'] as List).single as Map<String, dynamic>;
      expect(t.containsKey('id'), isFalse);
      expect(i.containsKey('id'), isFalse);
      expect(t['globalId'], 't-gid');
      expect(i['globalId'], 'g');
    });

    test('والذهابُ والإيابُ يحفظان الهندسة', () {
      final src = _layout(
        canvasWidth: 1400,
        canvasHeight: 700,
        originX: 200,
        originY: 300,
        tables: [_table(x: 40, y: 80, width: 200, height: 60, rotation: 90)],
        items: [_item(globalId: 'g', x: 10, y: 20, kind: 'bar')],
      );
      final back = floorPlanLayoutFromJson(
        floorPlanLayoutToJson(src),
        sectionId: 9,
        resolveTableId: (_) => 5,
      );
      expect(back.sectionId, 9);
      expect(back.canvasWidth, 1400);
      expect(back.originY, 300);
      expect(back.tables.single.id, 5);
      expect(back.tables.single.width, 200);
      expect(back.tables.single.rotation, 90);
      expect(back.items.single.kind, 'bar');
      expect(back.items.single.globalId, 'g');
    });

    test('🔴 وطاولةٌ لم يُحلَّ معرِّفُها تُسقَط لا تُكتَب على رقمٍ مخمَّن', () {
      final back = floorPlanLayoutFromJson(
        floorPlanLayoutToJson(_layout(tables: [_table()])),
        sectionId: 9,
        resolveTableId: (_) => null,
      );
      expect(back.tables, isEmpty);
    });

    test('وحمولةٌ بلا قوائمَ لا ترمي', () {
      final back = floorPlanLayoutFromJson(
        <String, dynamic>{'sectionGlobalId': 'g'},
        sectionId: 3,
        resolveTableId: (_) => 1,
      );
      expect(back.tables, isEmpty);
      expect(back.items, isEmpty);
      expect(back.canvasWidth, kDefaultCanvasWidth);
      expect(back.canvasHeight, kDefaultCanvasHeight);
    });

    test('وقيمةٌ نصّيّةٌ تُقرأ رقماً، والفاسدةُ تعود إلى الافتراض', () {
      final back = floorPlanLayoutFromJson(
        <String, dynamic>{'canvasWidth': '1500', 'originX': 'س'},
        sectionId: 3,
        resolveTableId: (_) => 1,
      );
      expect(back.canvasWidth, 1500);
      expect(back.originX, 0);
    });
  });
}
