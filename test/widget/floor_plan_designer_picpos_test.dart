// شاشةُ «مصمم القاعة» — التركيبُ والأدوات، قسمُ ٧.
//
// ═══ 🔴 ولا قاعدةَ حقيقيّةً داخلَ `testWidgets` ═══
//
// مقيسٌ في هذا المستودع: `AppDatabase.forTesting()` داخلَ `testWidgets` يجمّد
// **سويّةَ الودجت كلَّها** — جسمُ الاختبار في منطقةٍ وهميّةِ الزمن ومؤقّتاتُ
// drift لا يحرّكها أحدٌ فيها. فالمحقونُ هنا مستودعٌ وهميّ، والحسابُ الحقيقيُّ
// مقيسٌ في `floor_plan_dao_test` على قاعدةٍ حقيقيّةٍ خارجَ المنطقة الوهميّة.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/models/floor_plan_layout.dart';
import 'package:picpos_erp/domain/repositories/restaurant_repository.dart';
import 'package:picpos_erp/presentation/floor_plan_picpos/screens/floor_plan_designer_picpos_screen.dart';
import 'package:picpos_erp/presentation/floor_plan_picpos/widgets/floor_plan_canvas_picpos.dart';

final _now = DateTime(2026, 9, 20);

TableSection _section(int id, String name) => TableSection(
      id: id,
      name: name,
      isActive: true,
      createdAt: _now,
      sortOrder: 0,
      rowVersion: 0,
      globalId: 'sec-$id',
    );

RestaurantTable _table(
  int id, {
  int sectionId = 1,
  String name = 'طاولة',
  int capacity = 4,
  double x = 100,
  double y = 100,
  double? width,
  double? height,
  String status = 'available',
}) =>
    RestaurantTable(
      id: id,
      sectionId: sectionId,
      name: name,
      capacity: capacity,
      status: status,
      x: x,
      y: y,
      shape: 'rect',
      lastStatusAt: _now,
      isActive: true,
      createdAt: _now,
      width: width,
      height: height,
      rotation: 0,
      rowVersion: 0,
      globalId: 'tbl-$id',
    );

class _FakeRestaurantRepo implements IRestaurantRepository {
  _FakeRestaurantRepo({
    List<TableSection>? sections,
    List<RestaurantTable>? tables,
    Map<int, FloorPlanSectionLayout>? layouts,
  })  : _sections = sections ?? [_section(1, 'الصالة'), _section(2, 'التراس')],
        _tables = tables ?? [_table(1)],
        _layouts = layouts ?? {};

  final List<TableSection> _sections;
  final List<RestaurantTable> _tables;
  final Map<int, FloorPlanSectionLayout> _layouts;

  final saved = <FloorPlanSectionLayout>[];
  Object? throwOnSave;

  // ── بثٌّ حيٌّ — لمحاكاة إنشاءِ قسمٍ أو طاولةٍ **والمصمّمُ مفتوحٌ** ──
  //
  // 🔴 وهي الحالُ الواقعيّةُ لا فرضٌ نظريّ: الشاشتان تابان في
  //    `IndexedStack`، و«كلُّ تابٍ مفتوحٍ شجرةٌ حيّةٌ بمؤقّتاتها
  //    ومراقباتها» (تعليقُ `_openScreensStack`). فالمستخدمُ ينشئ القسمَ
  //    في «الطاولات» والمصمّمُ حيٌّ في تابه.
  final _sectionsCtl =
      StreamController<List<TableSection>>.broadcast();
  final _tablesCtl = StreamController<List<RestaurantTable>>.broadcast();

  @override
  Stream<List<TableSection>> watchAllSections() async* {
    yield List.of(_sections);
    yield* _sectionsCtl.stream;
  }

  @override
  Stream<List<RestaurantTable>> watchAllTables() async* {
    yield List.of(_tables);
    yield* _tablesCtl.stream;
  }

  /// يُنشئ قسماً كما تفعل شاشةُ الطاولات.
  void addSection(TableSection s) {
    _sections.add(s);
    _sectionsCtl.add(List.of(_sections));
  }

  /// ويُنشئ طاولةً كذلك.
  void addTable(RestaurantTable t) {
    _tables.add(t);
    _tablesCtl.add(List.of(_tables));
  }

  void disposeControllers() {
    _sectionsCtl.close();
    _tablesCtl.close();
  }

  @override
  Future<List<TableSection>> getAllSections() async => _sections;

  @override
  Future<List<RestaurantTable>> getAllTables() async => _tables;

  /// كم مرّةً طُلب مخطَّطُ قسمٍ — به يُقاس «هل أُعيد التحميل؟»، وهو
  /// المرصدُ الوحيدُ لذلك: إعادةُ تحميلٍ لنفس البيانات ترسم نفسَ الشاشة.
  final layoutReads = <int>[];

  @override
  Future<FloorPlanSectionLayout?> getFloorPlanLayout(int sectionId) async {
    layoutReads.add(sectionId);
    if (!_sections.any((s) => s.id == sectionId)) return null;
    return _layouts[sectionId] ??
        (
          sectionId: sectionId,
          sectionGlobalId: 'sec-$sectionId',
          canvasWidth: kDefaultCanvasWidth,
          canvasHeight: kDefaultCanvasHeight,
          originX: 0.0,
          originY: 0.0,
          tables: <FloorPlanTableGeometry>[
            for (final t in _tables)
              if (t.sectionId == sectionId)
                (
                  id: t.id,
                  globalId: t.globalId,
                  x: t.x,
                  y: t.y,
                  width: t.width,
                  height: t.height,
                  rotation: t.rotation,
                  shape: t.shape,
                ),
          ],
          items: const <FloorPlanItemInput>[],
        );
  }

  @override
  Future<List<FloorPlanSectionBox>> getFloorPlanSectionBoxes() async =>
      resolveSectionOrigins([
        for (final s in _sections)
          (
            sectionId: s.id,
            originX: s.originX,
            originY: s.originY,
            width: s.canvasWidth ?? kDefaultCanvasWidth,
            height: s.canvasHeight ?? kDefaultCanvasHeight,
          ),
      ]);

  @override
  Future<void> saveFloorPlanLayout(FloorPlanSectionLayout layout) async {
    final boom = throwOnSave;
    if (boom != null) throw boom;
    saved.add(layout);
    _layouts[layout.sectionId] = layout;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<_FakeRestaurantRepo> _pump(
  WidgetTester tester, {
  _FakeRestaurantRepo? repo,
  double width = 1920,
}) async {
  final r = repo ?? _FakeRestaurantRepo();
  // ⚠️ المقاسُ ١٩٢٠×١٠٨٠ لا الافتراضيّ: خطُّ الاختبار يرسم كلَّ محرفٍ
  //    مربّعاً كاملَ العرض فيتضخّم النصُّ العربيُّ ويولّد فيضاناتٍ وهمية.
  tester.view.physicalSize = Size(width, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        restaurantRepositoryProvider.overrideWithValue(r),
        // تجاوزٌ متزامنٌ لا `async`: `ensurePermission` تقرأ المزوّدَ بـ
        // `ref.read(...).value` ولا أحدَ يراقبه قبل النقرة، فالقراءةُ باردة.
        currentUserPermissionsProvider
            .overrideWith((ref) => const ['tables_manage']),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('ar'), Locale('en')],
        locale: Locale('ar'),
        home: FloorPlanDesignerPicposScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
  return r;
}

Future<void> _teardownTree(WidgetTester tester) async {
  // مؤقّتُ `AppToast` ٢٫٥ث — بلا هذا يسقط الاختبارُ بـ«A Timer is still
  // pending» رغم صحّة كلِّ شيءٍ قبله.
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  group('التركيب', () {
    for (final width in [1280.0, 1920.0]) {
      final w = width.toInt();
      testWidgets('الشاشةُ تُرسَم بلا فيضان عند عرض $w', (tester) async {
        await _pump(tester, width: width);
        expect(tester.takeException(), isNull);
        expect(find.text('مصمم القاعة'), findsWidgets);
        await _teardownTree(tester);
      });
    }

    testWidgets('وتفتح أوّلَ قسمٍ تلقائيّاً — لا شاشةَ فارغةٍ بمنسدلةٍ مملوءة',
        (tester) async {
      await _pump(tester);
      expect(find.byType(FloorPlanEditorCanvas), findsOneWidget);
      await _teardownTree(tester);
    });

    testWidgets('ولا أقسامَ ⇒ حالةُ فراغٍ تشرح الطريق', (tester) async {
      await _pump(tester,
          repo: _FakeRestaurantRepo(sections: [], tables: []));
      expect(find.byKey(const Key('floor_plan_no_sections')), findsOneWidget);
      expect(find.byType(FloorPlanEditorCanvas), findsNothing);
      await _teardownTree(tester);
    });

    testWidgets('وأزرارُ الأنواع الستّةِ كلُّها معروضة', (tester) async {
      await _pump(tester);
      for (final kind in kFloorPlanItemKinds) {
        expect(find.byKey(Key('floor_plan_add_$kind')), findsOneWidget,
            reason: 'زرُّ $kind غائب');
      }
      await _teardownTree(tester);
    });
  });

  group('الأدوات', () {
    testWidgets('🔴 إضافةُ جدارٍ ثمّ تراجعٌ ثمّ إعادة', (tester) async {
      await _pump(tester);

      // تراجعٌ مُعطَّلٌ قبل أيّ تعديل.
      final undo = tester.widget<IconButton>(
          find.byKey(const Key('floor_plan_undo')));
      expect(undo.onPressed, isNull);

      await tester.tap(find.byKey(const Key('floor_plan_add_wall')));
      await tester.pump();

      final canvas = tester.widget<FloorPlanEditorCanvas>(
          find.byType(FloorPlanEditorCanvas));
      expect(canvas.layout.items.length, 1);
      expect(canvas.layout.items.single.kind, 'wall');

      await tester.tap(find.byKey(const Key('floor_plan_undo')));
      await tester.pump();
      expect(
        tester
            .widget<FloorPlanEditorCanvas>(find.byType(FloorPlanEditorCanvas))
            .layout
            .items,
        isEmpty,
      );

      await tester.tap(find.byKey(const Key('floor_plan_redo')));
      await tester.pump();
      expect(
        tester
            .widget<FloorPlanEditorCanvas>(find.byType(FloorPlanEditorCanvas))
            .layout
            .items
            .length,
        1,
      );

      await _teardownTree(tester);
    });

    testWidgets('🔴 ومعلَمُ النصّ يُولَد بنصٍّ — وإلّا مُنع الحفظُ بلا سبب',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('floor_plan_add_text')));
      await tester.pump();

      final canvas = tester.widget<FloorPlanEditorCanvas>(
          find.byType(FloorPlanEditorCanvas));
      final item = canvas.layout.items.single;
      expect(item.kind, 'text');
      expect(validateFloorPlanItem(item), isNull);

      await _teardownTree(tester);
    });

    testWidgets('والمعلَمُ الجديدُ محدَّدٌ فوراً فيمكن حذفُه', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('floor_plan_add_pillar')));
      await tester.pump();

      final canvas = tester.widget<FloorPlanEditorCanvas>(
          find.byType(FloorPlanEditorCanvas));
      expect(canvas.selection.length, 1);

      await tester.tap(find.byKey(const Key('floor_plan_delete')));
      await tester.pump();
      expect(
        tester
            .widget<FloorPlanEditorCanvas>(find.byType(FloorPlanEditorCanvas))
            .layout
            .items,
        isEmpty,
      );

      await _teardownTree(tester);
    });

    testWidgets('والتدويرُ يزيد ٩٠ درجة', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('floor_plan_add_bar')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('floor_plan_rotate')));
      await tester.pump();

      final canvas = tester.widget<FloorPlanEditorCanvas>(
          find.byType(FloorPlanEditorCanvas));
      expect(canvas.layout.items.single.rotation, 90);

      await _teardownTree(tester);
    });

    testWidgets('والمعلَمُ يُولَد في وسط الصالة لا في زاويتها', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('floor_plan_add_kitchen')));
      await tester.pump();

      final canvas = tester.widget<FloorPlanEditorCanvas>(
          find.byType(FloorPlanEditorCanvas));
      final it = canvas.layout.items.single;
      expect(it.x, greaterThan(0));
      expect(it.y, greaterThan(0));
      expect(it.x + it.width, lessThanOrEqualTo(canvas.layout.canvasWidth));

      await _teardownTree(tester);
    });

    testWidgets('وتبديلُ الشبكة يُطفئ الرسمَ ولا يمسّ المخطَّط',
        (tester) async {
      await _pump(tester);
      expect(
        tester
            .widget<FloorPlanEditorCanvas>(find.byType(FloorPlanEditorCanvas))
            .showGrid,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('floor_plan_grid_toggle')));
      await tester.pump();
      expect(
        tester
            .widget<FloorPlanEditorCanvas>(find.byType(FloorPlanEditorCanvas))
            .showGrid,
        isFalse,
      );
      await _teardownTree(tester);
    });
  });

  group('المحاذاةُ والتوزيعُ والملاءمة', () {
    testWidgets('🔴 المحاذاةُ مُعطَّلةٌ بمحدَّدٍ واحد — لا شيءَ يُحاذى إليه',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('floor_plan_add_wall')));
      await tester.pump();

      for (final k in ['floor_plan_align_h', 'floor_plan_align_v']) {
        expect(tester.widget<IconButton>(find.byKey(Key(k))).onPressed, isNull,
            reason: '$k يعمل بمحدَّدٍ واحد');
      }
      await _teardownTree(tester);
    });

    testWidgets('والتوزيعُ يحتاج ثلاثةً لا اثنين', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('floor_plan_add_wall')));
      await tester.pump();
      await tester.longPress(find.byKey(const Key('floor_plan_table_1')));
      await tester.pump();

      // اثنان: المحاذاةُ تعمل والتوزيعُ لا.
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('floor_plan_align_h')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<IconButton>(
                find.byKey(const Key('floor_plan_distribute_h')))
            .onPressed,
        isNull,
      );
      await _teardownTree(tester);
    });

    testWidgets('🔴 والمحاذاةُ تمسّ المحدَّدَ وحدَه لا القاعةَ كلَّها',
        (tester) async {
      await _pump(
        tester,
        repo: _FakeRestaurantRepo(
          tables: [
            _table(1, x: 0, y: 100),
            _table(2, x: 300, y: 500),
            _table(3, x: 600, y: 800),
          ],
        ),
      );

      // طاولتان فقط في التحديد.
      await tester.tap(find.byKey(const Key('floor_plan_table_1')));
      await tester.pump();
      await tester.longPress(find.byKey(const Key('floor_plan_table_2')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('floor_plan_align_h')));
      await tester.pump();

      final layout = tester
          .widget<FloorPlanEditorCanvas>(find.byType(FloorPlanEditorCanvas))
          .layout;
      final byId = {for (final t in layout.tables) t.id: t};
      expect(byId[1]!.y, 300, reason: 'متوسّطُ 100 و500');
      expect(byId[2]!.y, 300);
      expect(byId[3]!.y, 800, reason: 'غيرُ المحدَّد لا يتحرّك');

      await _teardownTree(tester);
    });

    testWidgets('وملاءمةُ الشاشة لا تُسقط المخطَّط', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('floor_plan_fit')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(FloorPlanEditorCanvas), findsOneWidget);
      await _teardownTree(tester);
    });
  });

  group('الحفظ', () {
    testWidgets('🔴 يُسلّم المخطَّطَ كاملاً للمستودع', (tester) async {
      final repo = await _pump(tester);
      await tester.tap(find.byKey(const Key('floor_plan_add_wall')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('floor_plan_save')));
      await tester.pump();
      await tester.pump();

      expect(repo.saved.length, 1);
      expect(repo.saved.single.items.single.kind, 'wall');
      expect(repo.saved.single.tables.length, 1,
          reason: 'هندسةُ الطاولات تسافر مع المخطَّط لا بعده');

      await _teardownTree(tester);
    });

    testWidgets('ولا حفظَ قبل أيّ تعديل ⇒ الزرُّ يعمل ولا يُعلَّم بنجمة',
        (tester) async {
      await _pump(tester);
      expect(find.text('حفظ'), findsOneWidget);
      expect(find.text('حفظ *'), findsNothing);
      await _teardownTree(tester);
    });

    testWidgets('وبعد تعديلٍ يُعلَّم الزرُّ بنجمة', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('floor_plan_add_door')));
      await tester.pump();
      expect(find.text('حفظ *'), findsOneWidget);
      await _teardownTree(tester);
    });

    testWidgets('وفشلُ الحفظ يُبلَّغ ولا يُبتلَع', (tester) async {
      final repo = _FakeRestaurantRepo()..throwOnSave = StateError('انقطاع');
      await _pump(tester, repo: repo);
      await tester.tap(find.byKey(const Key('floor_plan_add_wall')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('floor_plan_save')));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('فشل الحفظ'), findsOneWidget);
      await _teardownTree(tester);
    });
  });

  group('اللوحة', () {
    testWidgets('🔴 الطاولةُ تُرسَم بمقاسها المحفوظ لا بالمشتقّ من السعة',
        (tester) async {
      await _pump(
        tester,
        repo: _FakeRestaurantRepo(
          tables: [_table(1, width: 320, height: 60, capacity: 2)],
        ),
      );

      final box = tester.getSize(find.byKey(const Key('floor_plan_table_1')));
      expect(box.width, 320);
      expect(box.height, 60);
      expect(box.width, isNot(legacyTableSide(2)));

      await _teardownTree(tester);
    });

    testWidgets('وبلا مقاسٍ محفوظٍ تعود إلى الاشتقاق', (tester) async {
      await _pump(
        tester,
        repo: _FakeRestaurantRepo(tables: [_table(1, capacity: 6)]),
      );
      final box = tester.getSize(find.byKey(const Key('floor_plan_table_1')));
      expect(box.width, legacyTableSide(6));
      await _teardownTree(tester);
    });

    testWidgets('واسمُ الطاولة وسعتُها معروضان على الخريطة', (tester) async {
      await _pump(
        tester,
        repo: _FakeRestaurantRepo(
          tables: [_table(1, name: 'ط-٧', capacity: 8)],
        ),
      );
      expect(find.text('ط-٧'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      await _teardownTree(tester);
    });
  });

  group('نظرةُ المحلّ', () {
    testWidgets('تعرض كلَّ الأقسام لا قسماً واحداً', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('المحلّ كلّه'));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('floor_plan_shop_section_1')), findsOneWidget);
      expect(find.byKey(const Key('floor_plan_shop_section_2')), findsOneWidget);
      expect(find.byType(FloorPlanEditorCanvas), findsNothing);

      await _teardownTree(tester);
    });

    testWidgets('🔴 والأقسامُ بلا موضعٍ لا تنطبق الواحدةُ فوق الأخرى',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.text('المحلّ كلّه'));
      await tester.pump();
      await tester.pump();

      final a =
          tester.getTopLeft(find.byKey(const Key('floor_plan_shop_section_1')));
      final b =
          tester.getTopLeft(find.byKey(const Key('floor_plan_shop_section_2')));
      expect(a, isNot(b));

      await _teardownTree(tester);
    });

    testWidgets('🔴 وتُرسَم طاولاتُ كلّ قسمٍ داخلَ صندوقِه', (tester) async {
      // مستطيلاتٌ مسمّاةٌ وحدَها ليست مخطَّطَ محلّ: المديرُ يضع التراسَ
      // خلفَ الصالة ليرى **أين تقع الطاولاتُ بعضُها من بعض**.
      await _pump(tester);
      await tester.tap(find.text('المحلّ كلّه'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('floor_plan_shop_table_1')), findsOneWidget);

      await _teardownTree(tester);
    });

    testWidgets('وحفظُ المواضع مُعطَّلٌ حتّى تُسحَب واحدة', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('المحلّ كلّه'));
      await tester.pump();
      await tester.pump();

      final btn = tester.widget<FilledButton>(
          find.byKey(const Key('floor_plan_shop_save')));
      expect(btn.onPressed, isNull);

      await _teardownTree(tester);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  group('🔴 القسمُ المُنشأُ يصل المصمّمَ — بلاغٌ ميدانيّ 2026-09-21', () {
    // ═══ ما بُلِّغ ═══
    //
    // أُنشئ قسمٌ («التراس») وطاولةٌ في «إدارة الطاولات» وظهرا فيها،
    // و«مصمم القاعة» يقول «لا أقسامَ بعد».
    //
    // ═══ والسببُ المقيس ═══
    //
    // الشاشتان تقرآن **نفسَ** الجدول بنفس الشرط (`is_active = 1`) —
    // `tables_dao.getAllSections` و`watchAllSections` متطابقتان حرفاً.
    // الفرقُ أنّ شاشةَ الطاولات تقرأ **بثّاً** والمصمّمَ يقرأ **لقطةً**:
    //
    //     /// أقسامُ الطاولات — لقطةٌ لا بثّ.
    //     final floorPlanSectionsProvider = FutureProvider.autoDispose…
    //
    // و`autoDispose` لا ينقذ: الشاشتان تابان في `IndexedStack` و«كلُّ
    // تابٍ مفتوحٍ شجرةٌ حيّةٌ بمؤقّتاتها ومراقباتها» — فالمراقبُ قائمٌ
    // والمزوّدُ لا يتخلّص ولا يُعيد القراءةَ أبداً.
    //
    // ⇒ فالمقيسُ هنا **التتبُّعُ** لا القراءةُ الأولى: يُفتَح المصمّمُ
    //   فارغاً ثمّ يُنشأ القسمُ، ويجب أن يصل.

    testWidgets('مرساةٌ — المصمّمُ يقول «لا أقسام» حين لا أقسامَ فعلاً',
        (tester) async {
      final repo = _FakeRestaurantRepo(sections: [], tables: []);
      addTearDown(repo.disposeControllers);
      await _pump(tester, repo: repo);
      expect(find.byKey(const Key('floor_plan_no_sections')), findsOneWidget,
          reason: 'بلا هذه لا يعني اختفاءُ الرسالة تحتَها شيئاً');
    });

    testWidgets('🔴 وقسمٌ يُنشأ والمصمّمُ مفتوحٌ يظهر فيه', (tester) async {
      final repo = _FakeRestaurantRepo(sections: [], tables: []);
      addTearDown(repo.disposeControllers);
      await _pump(tester, repo: repo);
      expect(find.byKey(const Key('floor_plan_no_sections')), findsOneWidget);

      // ← وهذا ما فعله المالكُ في «إدارة الطاولات».
      repo.addSection(_section(7, 'التراس'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('floor_plan_no_sections')), findsNothing,
          reason: '🔴 القسمُ أُنشئ والمصمّمُ ما زال يقول «لا أقسامَ بعد» — '
              'فالمستخدمُ لا يملك سبيلاً لرسم صالته إلّا بإغلاق البرنامج');
    });

    testWidgets('🔴 وطاولةُ قسمٍ آخرَ لا تُعيد تحميلَ هذا القسم',
        (tester) async {
      // 🔴 نجت طفرةٌ تُسقط شرطَ القسم (‏F4): كلُّ طاولةٍ في المطعم كانت
      //    تُعيد تحميلَ المخطَّط المفتوح. والأثرُ ليس أداءً وحدَه — إعادةُ
      //    التحميل تبني `FloorPlanUndoStack` جديدةً فيضيع تاريخُ التراجع.
      final repo = _FakeRestaurantRepo(
        sections: [_section(7, 'التراس'), _section(8, 'الصالة')],
        tables: [],
      );
      addTearDown(repo.disposeControllers);
      await _pump(tester, repo: repo);
      final before = repo.layoutReads.length;
      expect(before, greaterThan(0), reason: 'لم يُحمَّل قسمٌ أصلاً');

      // طاولةٌ في القسم **الآخر**.
      repo.addTable(_table(21, sectionId: 8, name: 'ص-1'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(repo.layoutReads.length, before,
          reason: '🔴 أُعيد تحميلُ القسم المفتوح لطاولةٍ ليست فيه');
    });

    testWidgets('🔴 ومسوّدةٌ لم تُحفَظ لا تُسقَط بطاولةٍ جديدة',
        (tester) async {
      // 🔴 نجت طفرةٌ تحذف شرطَ `_dirty` (‏F5): إعادةُ التحميل تبني مكدّسَ
      //    تراجعٍ جديداً، فكلُّ سحبةٍ ورسمةٍ لم تُحفَظ تضيع **بلا سؤال**
      //    لأنّ زميلاً أضاف طاولةً في شاشةٍ أخرى. وضياعُ عملِ المستخدم
      //    أسوأُ من طاولةٍ تتأخّر حتى الحفظ.
      final repo = _FakeRestaurantRepo(
        sections: [_section(7, 'التراس')],
        tables: [],
      );
      addTearDown(repo.disposeControllers);
      await _pump(tester, repo: repo);

      // تعديلٌ لم يُحفَظ — جدارٌ يُضاف.
      await tester.tap(find.byKey(const Key('floor_plan_add_wall')));
      await tester.pump();
      await tester.pump();
      expect(find.text('تغييراتٌ لم تُحفَظ'), findsOneWidget,
          reason: 'لم تتّسخ المسوّدةُ ⇒ الفحصُ تحتَها لا يقيس شيئاً');

      final before = repo.layoutReads.length;
      repo.addTable(_table(31, sectionId: 7, name: 'ت-9'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(repo.layoutReads.length, before,
          reason: '🔴 أُعيد التحميلُ فوق مسوّدةٍ متّسخة — وضاع عملُ '
              'المستخدم بلا سؤال');
      expect(find.text('تغييراتٌ لم تُحفَظ'), findsOneWidget,
          reason: '🔴 التعديلُ غير المحفوظ اختفى');
    });

    testWidgets('🔴 وطاولةٌ تُنشأ تصل المصمّمَ كذلك', (tester) async {
      // الطاولاتُ تُقرأ بنفس الشكل (`getAllTables` لقطةً)، والمالكُ أنشأ
      // طاولةً مع القسم. فلو أُصلح القسمُ وحدَه لَرأى صالةً فارغةً.
      final repo = _FakeRestaurantRepo(
        sections: [_section(7, 'التراس')],
        tables: [],
      );
      addTearDown(repo.disposeControllers);
      await _pump(tester, repo: repo);

      repo.addTable(_table(11, sectionId: 7, name: 'ت-1'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('ت-1'), findsWidgets,
          reason: '🔴 الطاولةُ أُنشئت ولم تصل المصمّمَ — فيرى المستخدمُ '
              'صالةً فارغةً وطاولتُه في الشاشة المجاورة');
    });
  });
}
