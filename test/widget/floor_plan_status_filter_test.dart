// ═══════════════════════════════════════════════════════════════════════════
// مرشِّحُ الحالة يسري على الخريطة كما يسري على الشبكة
// ═══════════════════════════════════════════════════════════════════════════
//
// `TablesUIState.isVisualView` افتراضُها `true`، فالمستخدمُ يهبط على الخريطة.
// وكان الترشيحُ في فرعِ الشبكة وحدَه — فالنقرُ على «متاحة» في عمود الحالات لا
// يغيّر شيئاً في شاشة الهبوط.
//
// والمعامِلُ اختياريٌّ عمداً: `TablesScreen` القديمة لا تمرّره، وسلوكُها
// الافتراضيُّ محفوظٌ — وهذا ما يقيسه التوكيدُ الأوّل.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/table_status_palette.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/repository_providers.dart';
import 'package:picpos_erp/domain/models/table_status.dart';
import 'package:picpos_erp/domain/repositories/restaurant_repository.dart';
import 'package:picpos_erp/presentation/screens/tables/floor_plan_designer.dart';

RestaurantTable _table(int id, String name, String status) => RestaurantTable(
      id: id,
      sectionId: 1,
      name: name,
      capacity: 4,
      status: status,
      x: 40.0 * id,
      y: 40.0 * id,
      shape: 'square',
      lastStatusAt: DateTime(2026, 1, 1),
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      rowVersion: 0, // v167
      rotation: 0, // v174
    );

final _tables = [
  _table(1, 'T1', TableStatus.available),
  _table(2, 'T2', TableStatus.occupied),
  _table(3, 'T3', TableStatus.available),
];

class _StubRestaurantRepo implements IRestaurantRepository {
  @override
  Stream<List<RestaurantTable>> watchTablesInSection(int sectionId) =>
      Stream.value(_tables);
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

Future<void> _pump(
  WidgetTester tester, {
  String? statusFilter,
  bool isEditMode = false,
}) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        restaurantRepositoryProvider.overrideWithValue(_StubRestaurantRepo()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: FloorPlanDesigner(
            sectionId: 1,
            isEditMode: isEditMode,
            statusFilter: statusFilter,
            onTap: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('بلا مرشِّحٍ تُرسَم الطاولاتُ كلُّها — سلوكُ الشاشة القديمة',
      (tester) async {
    await _pump(tester);
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('T2'), findsOneWidget);
    expect(find.text('T3'), findsOneWidget);
  });

  // خطة الطاولات A.7: الاختيارُ يُميِّز ولا يُخفي — كانت هذه الحالةُ تؤكّد
  // الإخفاء (`T2` غائبة) فصارت تؤكّد أنّ كلَّ الطاولات مرسومةٌ وغيرَ المطابقة
  // معتَّمة.
  testWidgets('المرشِّحُ يُعتِّم غيرَ المطابقة ولا يُخفيها', (tester) async {
    await _pump(tester, statusFilter: TableStatus.available);
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('T3'), findsOneWidget);
    expect(find.text('T2'), findsOneWidget,
        reason: 'المشغولةُ يجب أن تبقى مرسومةً — التمييزُ لا يُخفي');

    double opacityOf(String name) => tester
        .widget<Opacity>(find
            .ancestor(of: find.text(name), matching: find.byType(Opacity))
            .first)
        .opacity;
    expect(opacityOf('T2'), TableStatusPalette.dimmedOpacity);
    expect(
      find.ancestor(
        of: find.text('T1'),
        matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1),
      ),
      findsNothing,
      reason: 'المطابقةُ لا تُعتَّم',
    );
  });

  testWidgets('وضعُ التصميم يتجاهل المرشِّح — لا تُرتَّب خريطةٌ ناقصة',
      (tester) async {
    await _pump(
      tester,
      statusFilter: TableStatus.available,
      isEditMode: true,
    );
    expect(find.text('T2'), findsOneWidget,
        reason: 'إخفاءُ طاولةٍ أثناء الترتيب يخدع العين وأدواتُ المحاذاة '
            'تعمل على القائمة كاملةً');
  });
}
