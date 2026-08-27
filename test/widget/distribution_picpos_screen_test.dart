// شاشةُ «المناطق ومسارات التوزيع» — نسخةُ PicPos.
//
// تُقاس هنا نفسُ الأربعة التي أمسكت أعطاباً في شاشة الفروع: التركيبُ على
// عرضين، والشاراتُ مشتقّةٌ لا مكتوبة، والملاحظةُ تتبع التبويبة، ولوحةُ
// الحالات تعدّ الكلَّ لا المعروض.
//
// ⚠️ **ولا قاعدةَ بيانات**: المتحكّمُ نفسُه يُستبدَل بزائفٍ. فتحُ شاشةٍ على
// قاعدةٍ حيّةٍ في اختبار ودجت يعلّق — درسٌ مسجَّل لا تخمين.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/providers/distribution_controller.dart';
import 'package:ural_erp/presentation/settings_picpos/screens/distribution_picpos_screen.dart';

SalesRoute _route(int id, String name, {int? repId, String? area}) => SalesRoute(
      id: id,
      name: name,
      salesRepId: repId,
      area: area,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      rowVersion: 0, // v167
    );

RouteVisit _visit(int id, int routeId, String status,
        {double amount = 0, int? saleId}) =>
    RouteVisit(
      id: id,
      routeId: routeId,
      customerId: 100 + id,
      salesRepId: 7,
      visitDate: DateTime(2026, 8, 10),
      status: status,
      saleId: saleId,
      orderAmount: amount,
      createdAt: DateTime(2026, 8, 1),
      rowVersion: 0, // v167
    );

/// متحكّمٌ زائف — ينفّذ ما تناديه الشاشةُ وحدَه.
class _FakeController implements DistributionController {
  _FakeController({
    required this.routes,
    required this.visits,
    this.reps = const [],
    this.targets = const [],
  });

  final List<SalesRoute> routes;
  final Map<int, List<RouteVisit>> visits;
  final List<Employee> reps;
  final List<SalesRepTarget> targets;

  @override
  Stream<List<SalesRoute>> watchSalesRoutes() => Stream.value(routes);

  @override
  Future<List<Employee>> getAllEmployees() async => reps;

  @override
  Stream<List<RouteVisit>> watchRouteVisits(
          int routeId, DateTime from, DateTime to) =>
      Stream.value(visits[routeId] ?? const []);

  @override
  Stream<List<SalesRepTarget>> watchMonthlyTargets(int year, int month) =>
      Stream.value(targets);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  final routes = [
    _route(1, 'مسار شرق القاهرة', repId: 7, area: 'المعادي · المقطم'),
    _route(2, 'مسار مدينة نصر'),
  ];

  // خمسُ زياراتٍ على المسار الأوّل: ٣ مخططة · ١ منفَّذة · ١ متخطّاة.
  final visits = {
    1: [
      _visit(1, 1, 'planned'),
      _visit(2, 1, 'planned'),
      _visit(3, 1, 'planned'),
      _visit(4, 1, 'completed', amount: 6420, saleId: 55),
      _visit(5, 1, 'skipped'),
    ],
    2: <RouteVisit>[],
  };

  final reps = <Employee>[
    Employee(
      id: 7,
      name: 'يوسف طارق',
      role: 'مندوب',
      salary: 0,
      salaryType: 'monthly',
      isActive: true,
      hiredAt: DateTime(2026, 1, 1),
      rowVersion: 0, // v167
    ),
  ];

  final targets = <SalesRepTarget>[
    SalesRepTarget(
      id: 1,
      salesRepId: 7,
      year: DateTime.now().year,
      month: DateTime.now().month,
      targetAmount: 40000,
      achievedAmount: 30000,
      targetVisits: 20,
      achievedVisits: 15,
      createdAt: DateTime(2026, 8, 1),
      rowVersion: 0, // v167
    ),
  ];

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          distributionControllerProvider.overrideWithValue(
            _FakeController(
              routes: routes,
              visits: visits,
              reps: reps,
              targets: targets,
            ),
          ),
          allDeliveryCompaniesProvider
              .overrideWith((ref) => Stream.value(const <DeliveryCompany>[])),
        ],
        child: const MaterialApp(home: DistributionPicposScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('التركيبُ على عرضين', () {
    for (final e in const [
      ('عرضٌ يتّسع', Size(1500, 900)),
      ('عرضٌ ضيّق', Size(820, 760)),
    ]) {
      testWidgets('${e.$1} — بلا فيضٍ ولا انهيار', (tester) async {
        await open(tester, e.$2);
        expect(tester.takeException(), isNull,
            reason: 'انهيارُ تخطيطٍ عند العرض ${e.$2.width}');
        expect(find.text('المناطق ومسارات التوزيع'), findsOneWidget);
        expect(find.text('مسار شرق القاهرة'), findsWidgets);
        await teardownTree(tester);
      });
    }
  });

  testWidgets('شارةُ المسارات مشتقّةٌ من المزوِّد', (tester) async {
    await open(tester, const Size(1500, 900));
    expect(find.text('${routes.length}'), findsWidgets);
    expect(find.text('المسارات النشطة'), findsOneWidget);
    expect(find.text('من ${routes.length} مسجّل'), findsOneWidget);
    await teardownTree(tester);
  });

  testWidgets('مسارٌ بلا مندوبٍ يُسمّى بذلك لا يُترَك فارغاً', (tester) async {
    // فراغٌ في خانةِ المندوب يُقرأ عطباً في التحميل لا واقعاً.
    await open(tester, const Size(1500, 900));
    expect(find.text('بلا مندوب ثابت'), findsOneWidget);
    await teardownTree(tester);
  });

  testWidgets('لوحةُ الزيارات تعدّ الكلَّ وتُظهر الحالاتِ الأربع',
      (tester) async {
    await open(tester, const Size(1500, 900));
    await tester.tap(find.text('الزيارات').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('الزيارة قد تنتج فاتورة بيع أو تُتخطّى بسبب'),
        findsOneWidget);

    // الحالاتُ الأربعُ كلُّها أعمدةٌ — وإسقاطُ واحدةٍ يُخفي زياراتِها بلا أثر.
    expect(find.text('مخططة'), findsOneWidget);
    expect(find.text('منفَّذة'), findsWidgets);
    expect(find.text('متخطّاة'), findsWidgets);
    expect(find.text('ملغاة'), findsOneWidget);

    // والزيارةُ المنفَّذةُ التي أنتجت فاتورةً تقول ذلك.
    expect(find.text('أنتجت فاتورة'), findsOneWidget);
    await teardownTree(tester);
  });

  testWidgets('جدولُ الأهداف يحسب النسبةَ ولا يكتبها', (tester) async {
    await open(tester, const Size(1500, 900));
    await tester.tap(find.text('الأهداف والتحصيل').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('يوسف طارق'), findsOneWidget);
    // ‏٣٠٠٠٠ من ٤٠٠٠٠ = ٧٥٪ — مشتقّةٌ من الحقلين لا مكتوبة.
    expect(find.text('75٪'), findsOneWidget,
        reason: 'نسبةُ الإنجاز لا تطابق حاصلَ القسمة.');
    expect(find.text('15/20'), findsOneWidget);
    // والمؤشّرُ العلويُّ يقول النسبةَ نفسَها من المجاميع.
    expect(find.text('75٪ من الهدف'), findsOneWidget);
    await teardownTree(tester);
  });

  testWidgets('واسمُ المندوب يُحلّ من الموظفين لا يُعرَض رقماً', (tester) async {
    await open(tester, const Size(1500, 900));
    expect(find.text('يوسف طارق'), findsWidgets);
    expect(find.textContaining('مندوب #'), findsNothing,
        reason: 'عُرض معرِّفٌ خامٌ بدل الاسم — والمشغّلُ لا يعرف الأرقام.');
    await teardownTree(tester);
  });

  testWidgets('⚠️ وسطرُ «المزيد» يُشتقّ من الفرق لا يُكتَب', (tester) async {
    // عمودٌ فيه ٣ مخططةٍ وسقفُ العرض ٤ ⇒ لا سطرَ «المزيد» إطلاقاً. ولو كان
    // مكتوباً لظهر رقمٌ لا مقابلَ له.
    await open(tester, const Size(1500, 900));
    await tester.tap(find.text('الزيارات').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('+'), findsNothing,
        reason: 'ظهر سطرُ «المزيد» ولا زياراتٍ مخفيّة.');
    await teardownTree(tester);
  });
}
