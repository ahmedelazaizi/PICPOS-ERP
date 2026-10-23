// E-1/E-2: مصمّمُ القاعة يسجّل نفسَه «متّسخاً» فيسأل إغلاقُ التاب/النافذة، وتحريكُ
// قسمٍ في نظرة المحلّ يُعدّ تغييراً لم يُحفَظ، وتأكيدُ PopScope لا يُسقط
// راوتَ الشِّلّ.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/navigation/dirty_screens_registry.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/data/providers/screen_navigation_provider.dart';
import 'package:ural_erp/domain/models/floor_plan_layout.dart';
import 'package:ural_erp/domain/repositories/restaurant_repository.dart';
import 'package:ural_erp/presentation/floor_plan_picpos/screens/floor_plan_designer_picpos_screen.dart';

final _now = DateTime(2026, 10, 18);

class _Repo implements IRestaurantRepository {
  @override
  Stream<List<TableSection>> watchAllSections() => Stream.value([
        TableSection(
          id: 1,
          name: 'الصالة',
          isActive: true,
          createdAt: _now,
          sortOrder: 0,
          rowVersion: 0,
          globalId: 'sec-1',
        ),
      ]);

  @override
  Stream<List<RestaurantTable>> watchAllTables() =>
      Stream.value(const <RestaurantTable>[]);

  @override
  Future<FloorPlanSectionLayout?> getFloorPlanLayout(int sectionId) async => (
        sectionId: sectionId,
        sectionGlobalId: 'sec-$sectionId',
        canvasWidth: kDefaultCanvasWidth,
        canvasHeight: kDefaultCanvasHeight,
        originX: 0.0,
        originY: 0.0,
        tables: const <FloorPlanTableGeometry>[],
        items: const <FloorPlanItemInput>[],
      );

  @override
  Future<List<FloorPlanSectionBox>> getFloorPlanSectionBoxes() async => [
        (
          sectionId: 1,
          originX: 0.0,
          originY: 0.0,
          width: 800.0,
          height: 600.0,
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

late ProviderContainer _container;

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        restaurantRepositoryProvider.overrideWithValue(_Repo()),
        currentUserPermissionsProvider
            .overrideWith((ref) => const ['tables_manage']),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          _container = ProviderScope.containerOf(context);
          return const MaterialApp(
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('ar'), Locale('en')],
            locale: Locale('ar'),
            home: FloorPlanDesignerPicposScreen(),
          );
        },
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

DirtyScreensRegistry get _registry =>
    _container.read(dirtyScreensRegistryProvider);

void main() {
  final idx = ScreenId.floorPlanDesigner.navigationIndex;

  group('DirtyScreensRegistry', () {
    test('نظيفٌ: يمرّ بلا سؤال، ومتّسخٌ: يسأل والرفضُ يمنع', () async {
      final r = DirtyScreensRegistry();
      var dirty = false;
      var asked = 0;
      var answer = false;
      final owner = Object();
      r.register(owner,
          screenIndex: 7,
          isDirty: () => dirty,
          confirmDiscard: () async {
            asked++;
            return answer;
          });

      expect(await r.confirmCloseScreen(7), isTrue);
      expect(await r.confirmCloseAll(), isTrue);
      expect(asked, 0);

      dirty = true;
      expect(r.hasDirty(), isTrue);
      expect(r.hasDirty(screenIndex: 8), isFalse);
      expect(await r.confirmCloseScreen(8), isTrue, reason: 'تابٌ آخر');
      expect(await r.confirmCloseScreen(7), isFalse);
      expect(await r.confirmCloseAll(), isFalse);
      answer = true;
      expect(await r.confirmCloseAll(), isTrue);

      r.unregister(owner);
      expect(r.hasDirty(), isFalse);
    });
  });

  testWidgets('مسوّدةٌ متّسخة: إغلاقُ التاب/النافذة يسأل و«ابقَ» يمنع',
      (tester) async {
    await _pump(tester);
    final reg = _registry;
    expect(_registry.hasDirty(screenIndex: idx), isFalse);

    await tester.tap(find.byKey(const Key('floor_plan_add_wall')));
    await tester.pump();
    expect(_registry.hasDirty(screenIndex: idx), isTrue);

    // إغلاقُ التاب
    var closed = false;
    _registry.confirmCloseScreen(idx).then((v) => closed = v);
    await tester.pumpAndSettle();
    expect(find.text('تغييراتٌ لم تُحفَظ'), findsWidgets);
    await tester.tap(find.text('ابقَ'));
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    expect(find.text('حفظ *'), findsOneWidget, reason: 'ضاعت المسوّدة');

    // إغلاقُ النافذة
    var windowOk = false;
    _registry.confirmCloseAll().then((v) => windowOk = v);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('floor_plan_discard_ok')));
    await tester.pumpAndSettle();
    expect(windowOk, isTrue);
    await _teardown(tester);
    expect(reg.hasDirty(), isFalse, reason: 'لم يُلغَ التسجيلُ عند التخلّص');
  });

  testWidgets('تحريكُ قسمٍ في نظرة المحلّ يُعدّ تغييراً لم يُحفَظ',
      (tester) async {
    await _pump(tester);
    expect(_registry.hasDirty(), isFalse);

    await tester.tap(find.text('المحلّ كلّه'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const Key('floor_plan_shop_section_1')), const Offset(60, 40));
    await tester.pump();

    expect(_registry.hasDirty(screenIndex: idx), isTrue,
        reason: 'مواضعُ الأقسام المنقولة لم تُعدّ متّسخة');
    await _teardown(tester);
  });

  testWidgets('PopScope: تأكيدُ المغادرة لا يُسقط راوتَ الشِّلّ (يفتح الطاولات)',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('floor_plan_add_wall')));
    await tester.pump();

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    await nav.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('floor_plan_discard_ok')));
    await tester.pumpAndSettle();

    expect(find.byType(FloorPlanDesignerPicposScreen), findsOneWidget,
        reason: 'الراوتُ الجذر سقط — شاشةٌ سوداء');
    expect(_container.read(screenNavigationProvider)?.screenIndex,
        ScreenId.tables.navigationIndex);
    await _teardown(tester);
  });
}