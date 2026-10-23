// «مصمم القاعة»: زرُّ الرجوع وحارسُ التغييرات غير المحفوظة — خطة A.5.
//
// المصمّمُ تابٌ في الشِّلّ لا راوتٌ مدفوع، فـ`Navigator.canPop` خاطئةٌ فيه
// وكان الرأسُ لا يرسم سهمَ رجوع. ولا قاعدةَ حقيقيّةً داخل `testWidgets`
// (مستودعٌ وهميّ) — راجع تعليقَ `floor_plan_designer_picpos_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/providers/screen_navigation_provider.dart';
import 'package:picpos_erp/domain/models/floor_plan_layout.dart';
import 'package:picpos_erp/domain/repositories/restaurant_repository.dart';
import 'package:picpos_erp/presentation/floor_plan_picpos/screens/floor_plan_designer_picpos_screen.dart';

final _now = DateTime(2026, 10, 18);

class _Repo implements IRestaurantRepository {
  final _sections = [
    TableSection(
      id: 1,
      name: 'الصالة',
      isActive: true,
      createdAt: _now,
      sortOrder: 0,
      rowVersion: 0,
      globalId: 'sec-1',
    ),
  ];

  @override
  Stream<List<TableSection>> watchAllSections() => Stream.value(_sections);

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
  Future<List<FloorPlanSectionBox>> getFloorPlanSectionBoxes() async =>
      const <FloorPlanSectionBox>[];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<ProviderContainer> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        restaurantRepositoryProvider.overrideWithValue(repo),
        currentUserPermissionsProvider
            .overrideWith((ref) => const ['tables_manage']),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
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
  return container;
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  testWidgets('زرُّ الرجوع موجودٌ رغم أنّ الشاشةَ ليست راوتاً مدفوعاً',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('picpos_header_back')), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('نظيفٌ: الرجوعُ يفتح «الطاولات» بلا أيّ سؤال', (tester) async {
    final container = await _pump(tester);
    expect(container.read(screenNavigationProvider), isNull);

    await tester.tap(find.byKey(const Key('picpos_header_back')));
    await tester.pump();
    await tester.pump();

    expect(find.text('تغييراتٌ لم تُحفَظ'), findsNothing,
        reason: 'سؤالٌ بلا تغييرات');
    final req = container.read(screenNavigationProvider);
    expect(req?.screenIndex, ScreenId.tables.navigationIndex);
    await _teardown(tester);
  });

  testWidgets('متّسخٌ: يسأل، و«ابقَ» لا يغادر ولا يُسقط التغييرات',
      (tester) async {
    final container = await _pump(tester);
    await tester.tap(find.byKey(const Key('floor_plan_add_wall')));
    await tester.pump();
    expect(find.text('حفظ *'), findsOneWidget, reason: 'لم يتّسخ المخطَّط');

    await tester.tap(find.byKey(const Key('picpos_header_back')));
    await tester.pumpAndSettle();
    expect(find.text('تغييراتٌ لم تُحفَظ'), findsWidgets);

    await tester.tap(find.text('ابقَ'));
    await tester.pumpAndSettle();
    expect(container.read(screenNavigationProvider), isNull,
        reason: 'غادر رغم «ابقَ»');
    expect(find.text('حفظ *'), findsOneWidget,
        reason: 'ضاعت التغييراتُ رغم «ابقَ»');
    await _teardown(tester);
  });

  testWidgets('متّسخٌ: «غادِر» يفتح الطاولات ويُسقط المسوّدة', (tester) async {
    final container = await _pump(tester);
    await tester.tap(find.byKey(const Key('floor_plan_add_wall')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('picpos_header_back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('floor_plan_discard_ok')));
    await tester.pumpAndSettle();

    expect(container.read(screenNavigationProvider)?.screenIndex,
        ScreenId.tables.navigationIndex);
    // التابُ يبقى حيّاً: المسوّدةُ أُسقطت فلا يعود المستخدمُ إلى «متّسخ» وهميّ.
    expect(find.text('حفظ'), findsOneWidget);
    expect(find.text('حفظ *'), findsNothing);
    await _teardown(tester);
  });

  testWidgets('PopScope: Navigator.maybePop على مخطَّطٍ متّسخ يسأل أيضاً',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('floor_plan_add_wall')));
    await tester.pump();

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    // `home` هو الراوتُ الجذر فلا يخرج منه؛ المهمُّ أنّ الحارس يعترض.
    await nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('تغييراتٌ لم تُحفَظ'), findsWidgets,
        reason: 'PopScope لا يعترض الرجوعَ على مخطَّطٍ متّسخ');
    await tester.tap(find.text('ابقَ'));
    await tester.pumpAndSettle();
    await _teardown(tester);
  });
}
