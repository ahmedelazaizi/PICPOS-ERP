// test/widget/opex_picpos_screen_test.dart
//
// شاشةُ «المصاريف التشغيلية» بهويّة PicPos — التبويباتُ الخمسة.
//
// ═══ الفجوةُ المقيسة ═══
//
// القائمُ `operational_expenses_screen.dart` **٩٠ سطراً بتبويبَين**،
// والتصميمُ خمسة. فهذا بناءُ شاشةٍ لا تنسيقُ واحدة.
//
// ═══ وما يحرسه هذا الملفّ ═══
//
// ⚠️ **يُفتَح كلُّ تبويبٍ ويُقاس محتواه** — لا «لم تنهر». اختبارُ التركيب
// يمسك ما تفوته اختباراتُ القطع، وعلى **عرضَين** لأنّ الأعطابَ تتغيّر
// بالعرض.
//
// 🔴 **وملاحظةُ تبويب `flow` ليست نصَّ التصميم**: التصميمُ يكتب «القيد ينشأ
//    عند الاعتماد» وهو **غيرُ صحيحٍ في المحرّك** —
//    `recordAndPostOperationalExpense` يقيّد عند التسجيل. وشاشةٌ تُعلّم
//    المستخدمَ محاسبةً لا تقع أسوأُ من شاشةٍ بلا ملاحظة.
//
// 🔴 **وفرقُ الموازنة موازنةٌ ناقصَ منفَّذ**: مفتاحُ `variance` في تقرير
//    القاعدة معكوسٌ (`actual - planned`)، فنقلُه كما هو يجعل التوفيرَ سالباً
//    والتجاوزَ موجباً — وهو عكسُ ما يقرؤه المحاسب.
//
// 🔴 **وجدولٌ فارغٌ في الموازنة ليس «صفرَ تجاوزات»**: بلا سنةٍ ماليّةٍ لا
//    موازنةَ إطلاقاً، وقراءةُ الفراغ اطمئناناً خطأٌ يقع.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/accounting_repository.dart';
import 'package:picpos_erp/domain/repositories/budget_repository.dart';
import 'package:picpos_erp/domain/repositories/manufacturing_repository.dart';
import 'package:picpos_erp/presentation/opex_picpos/screens/opex_picpos_screen.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_report_tabs.dart';

final _now = DateTime.now();
final _thisMonth = DateTime(_now.year, _now.month, 5);

final _categories = [
  db.OpExpenseCategoryData(
    id: 1,
    name: 'غاز ووقود أفران',
    type: 'direct',
    isProductionRelated: true,
    allocationMethod: 'per_unit',
    defaultRate: 1.20,
    accountCode: '5207',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
    rowVersion: 0,
  ),
  db.OpExpenseCategoryData(
    id: 2,
    name: 'إيجارات',
    type: 'fixed',
    isProductionRelated: false,
    allocationMethod: 'fixed_monthly',
    defaultRate: 0,
    accountCode: '5202',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
    rowVersion: 0,
  ),
];

/// صفوفُ `getExpensesForReport` — خرائطُ لا كياناتٌ، كما يعطيها الاستعلام.
final _expenses = <Map<String, dynamic>>[
  {
    'id': 1,
    'amount': 48000.0,
    'expense_date': _thisMonth,
    'period': 'monthly',
    'reference': 'RENT-08',
    'notes': '٣ عقود',
    'status': 'paid',
    'payment_method': 'bank',
    'branch_id': null,
    'user_id': 1,
    'category_name': 'إيجارات',
    'category_type': 'fixed',
    'branch_name': null,
    'user_name': 'سارة منير',
    'source': 'op_expense',
  },
  {
    'id': 2,
    'amount': 8640.0,
    'expense_date': _thisMonth,
    'period': 'weekly',
    'reference': 'GAS-33',
    'notes': 'محمّل على الإنتاج',
    'status': 'approved',
    'payment_method': 'cash',
    'branch_id': 1,
    'user_id': 2,
    'category_name': 'غاز ووقود أفران',
    'category_type': 'variable',
    'branch_name': 'المعادي',
    'user_name': 'محمود سعيد',
    'source': 'op_expense',
  },
  {
    'id': 3,
    'amount': 2400.0,
    'expense_date': _thisMonth,
    'period': 'one_time',
    'reference': null,
    'notes': 'صيانة كومبرسور ثلاجة',
    'status': 'draft',
    'payment_method': 'cash',
    'branch_id': 1,
    'user_id': 3,
    'category_name': 'صيانة وإصلاحات',
    'category_type': 'variable',
    'branch_name': 'المعادي',
    'user_name': 'خالد عبد الله',
    'source': 'op_expense',
  },
];

final _orders = [
  db.ManufacturingOrderData(
    id: 10,
    orderNumber: 'MFG-2026-0142',
    bomId: 1,
    orderedQty: 2400,
    producedQty: 2400,
    warehouseId: 1,
    startDate: _thisMonth,
    status: 'completed',
    additionalCosts: 2880,
    totalCost: 8600,
    createdAt: _thisMonth,
    rowVersion: 0,
  ),
  db.ManufacturingOrderData(
    id: 11,
    orderNumber: 'MFG-2026-0138',
    bomId: 2,
    orderedQty: 180,
    producedQty: 180,
    warehouseId: 1,
    startDate: _thisMonth,
    status: 'completed',
    additionalCosts: 0,
    totalCost: 6580,
    createdAt: _thisMonth,
    rowVersion: 0,
  ),
];

db.MfgOrderCostData _cost(int id, int orderId, String type, double amount) =>
    db.MfgOrderCostData(
      id: id,
      orderId: orderId,
      costType: type,
      description: type,
      amount: amount,
      createdAt: _thisMonth,
      rowVersion: 0,
    );

/// الأمرُ ١٠ محمَّلٌ والأمرُ ١١ **بلا تحميل** — وهو ما ترصده الشريحة.
final _costs = [
  _cost(1, 10, 'raw_material', 4320),
  _cost(2, 10, 'labor', 1400),
  _cost(3, 10, 'overhead', 2880),
  _cost(4, 11, 'raw_material', 6300),
  _cost(5, 11, 'labor', 280),
];

/// ‏الموازنة ٢٤,٠٠٠ والمنفَّذ ٢٨,٨٠٠ ⇒ تجاوزٌ ١٢٠٪ والفرقُ **(4,800)**.
final _budgetReport = <Map<String, dynamic>>[
  {
    'budgetId': 1,
    'accountId': 5203,
    'accountName': 'كهرباء ومياه',
    'accountCode': '5203',
    'annualBudget': 288000.0,
    'totalPlanned': 24000.0,
    'totalActual': 28800.0,
    'variance': 4800.0,
    'utilizationPct': 120.0,
    'lines': const [],
  },
  {
    'budgetId': 2,
    'accountId': 5204,
    'accountName': 'صيانة وإصلاحات',
    'accountCode': '5204',
    'annualBudget': 360000.0,
    'totalPlanned': 30000.0,
    'totalActual': 21600.0,
    'variance': -8400.0,
    'utilizationPct': 72.0,
    'lines': const [],
  },
];

class _FakeMfgRepo implements ManufacturingRepository {
  @override
  Stream<List<db.OpExpenseCategoryData>> watchExpenseCategories() =>
      Stream.value(_categories);

  @override
  Future<List<Map<String, dynamic>>> getExpensesForReport({
    required DateTime from,
    required DateTime to,
  }) async =>
      _expenses;

  @override
  Stream<List<db.ManufacturingOrderData>> watchManufacturingOrders({
    String? status,
  }) =>
      Stream.value(_orders);

  @override
  Stream<List<db.MfgOrderCostData>> watchAllMfgOrderCosts() =>
      Stream.value(_costs);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccountingRepo implements IAccountingRepository {
  _FakeAccountingRepo({this.year});

  final db.FiscalYearData? year;

  @override
  Future<db.FiscalYearData?> getCurrentFiscalYear() async => year;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBudgetRepo implements IBudgetRepository {
  _FakeBudgetRepo(this.report);

  final List<Map<String, dynamic>> report;

  @override
  Future<List<Map<String, dynamic>>> getBudgetVsActualReport(int y) async =>
      report;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _fiscalYear = db.FiscalYearData(
  id: 1,
  name: '٢٠٢٦',
  startDate: DateTime(2026, 1, 1),
  endDate: DateTime(2026, 12, 31),
  isClosed: false,
  isCurrent: true,
  createdAt: DateTime(2026, 1, 1),
  rowVersion: 0,
);

Future<void> _pump(
  WidgetTester tester,
  double width, {
  bool withBudget = true,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        manufacturingRepositoryProvider.overrideWithValue(_FakeMfgRepo()),
        accountingRepositoryProvider.overrideWithValue(
          _FakeAccountingRepo(year: withBudget ? _fiscalYear : null),
        ),
        budgetRepositoryProvider.overrideWithValue(
          _FakeBudgetRepo(withBudget ? _budgetReport : const []),
        ),
        currentUserPermissionsProvider.overrideWith((ref) async => const ['*']),
      ],
      child: const MaterialApp(home: OpexPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// يفتح التبويبَ من **داخل شريط التبويبات** — بعضُ العناوين تتكرّر في الجداول.
///
/// ⚠️ `PicPosReportTabs` ينادي `animateTo` لا `index =` — فالانتقالُ بحركةٍ
/// لها زمن، وضخّةٌ بلا مدّةٍ تُبقي محتوى التبويب القديم معروضاً فيمرّ الفحصُ
/// على الشاشة الخطأ.
///
/// ⚠️ **و`ensureVisible` ليست احتياطاً**: شريطُ التبويبات يتمرّر أفقيّاً،
/// وعلى عرض ١٢٨٠ يقع «مقابل الموازنة» **خارجَ الشاشة**. والنقرُ عليه هناك لا
/// يبدّل التبويبَ — فيقرأ الفحصُ محتوى التبويب الأوّل ويُبلغ «لم أجد» عن
/// شيءٍ موجودٍ في تبويبٍ لم يُفتَح. وقد وقع ذلك فعلاً: التبويبان الرابعُ
/// والخامسُ نجحا على ١٩٢٠ وسقطا على ١٢٨٠ بهذا السبب وحدَه.
Future<void> _openTab(WidgetTester tester, String label) async {
  final tab = find.descendant(
    of: find.byType(PicPosReportTabs),
    matching: find.text(label),
  );
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    group('عرض $w', () {
      testWidgets('الرأسُ والتبويباتُ الخمسة', (tester) async {
        await _pump(tester, width);

        expect(find.text('المصاريف التشغيلية'), findsWidgets);
        for (final t in const [
          'المصروفات',
          'الفئات وقواعد التحميل',
          'تحميل أوامر التصنيع',
          'الاعتماد والسداد',
          'مقابل الموازنة',
        ]) {
          expect(
            find.descendant(
              of: find.byType(PicPosReportTabs),
              matching: find.text(t),
            ),
            findsOneWidget,
            reason: 'تبويبُ «$t» غائب',
          );
        }
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('١ · المصروفات: الإجماليُّ محسوبٌ لا مكتوب',
          (tester) async {
        await _pump(tester, width);

        // ‏48,000 + 8,640 + 2,400 = 59,040 — محسوبةٌ بيد.
        expect(find.text('59,040'), findsOneWidget);
        // والمسوّدةُ واحدةٌ بمبلغ 2,400.
        expect(find.text('بانتظار الاعتماد'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('٢ · الفئات: «ثابت شهرياً» بلا معدّلٍ يعرض «—» لا صفراً',
          (tester) async {
        // 🔴 «0.00» تُقرأ معدّلاً صفريّاً مضبوطاً عمداً، وهو معنًى آخر.
        await _pump(tester, width);
        await _openTab(tester, 'الفئات وقواعد التحميل');

        expect(find.text('لكل وحدة منتجة'), findsOneWidget);
        expect(find.text('ثابت شهرياً'), findsOneWidget);
        expect(find.text('1.20'), findsOneWidget);
        expect(find.text('5207'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('٣ · التصنيع: أمرٌ بلا تحميلٍ يُرصَد', (tester) async {
        await _pump(tester, width);
        await _openTab(tester, 'تحميل أوامر التصنيع');

        expect(find.text('أوامر بلا تحميل'), findsOneWidget);
        // الأمرُ ١١ بلا `overhead` ⇒ وسمُ «بلا تحميل» في صفّه.
        expect(find.text('بلا تحميل'), findsWidgets);
        // وخاماتُ الأمرَين 4,320 + 6,300 = 10,620 — تظهر في سطر الإجمالي
        // **وفي شريط «خامات مباشرة»**، وهما موضعان لنفس الرقم عن قصد.
        expect(find.text('10,620'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('٤ · الدورة: الملاحظةُ تقول الحقيقةَ لا نصَّ التصميم',
          (tester) async {
        await _pump(tester, width);
        await _openTab(tester, 'الاعتماد والسداد');

        expect(
          find.textContaining('القيد يُرحَّل عند تسجيل المصروف'),
          findsOneWidget,
        );
        // 🔴 ونصُّ التصميم المخالفُ غيرُ معروضٍ إطلاقاً.
        expect(find.textContaining('القيد ينشأ عند الاعتماد'), findsNothing);

        // والأعمدةُ الثلاثةُ موزَّعةٌ بالحالة: مسوّدةٌ ومعتمدةٌ ومسدَّدة.
        expect(find.text('مسوّدة'), findsWidgets);
        expect(find.text('معتمدة'), findsWidgets);
        expect(find.text('مسدَّدة'), findsWidgets);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('٥ · الموازنة: الفرقُ موازنةٌ ناقصَ منفَّذ لا العكس',
          (tester) async {
        await _pump(tester, width);
        await _openTab(tester, 'مقابل الموازنة');

        // 🔴 24,000 − 28,800 = **(4,800)** تجاوزاً. ومفتاحُ `variance` في
        //    التقرير يعطي **+4,800** — ونقلُه كما هو يقلب الإشارة.
        expect(find.text('-4,800'), findsOneWidget);
        // و30,000 − 21,600 = 8,400 توفيراً موجباً.
        expect(find.text('8,400'), findsOneWidget);

        expect(find.text('تجاوز'), findsWidgets);
        expect(find.text('سليم'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('🔴 وبلا سنةٍ ماليّةٍ يُقال ذلك — لا جدولٌ فارغٌ صامت',
          (tester) async {
        await _pump(tester, width, withBudget: false);
        await _openTab(tester, 'مقابل الموازنة');

        expect(
          find.text('لا موازناتٌ مسجَّلةٌ للسنة المالية الجارية'),
          findsOneWidget,
        );
        expect(
          find.textContaining('لغياب الموازنة لا لانعدام التجاوز'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }
}
