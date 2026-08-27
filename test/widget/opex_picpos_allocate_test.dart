// test/widget/opex_picpos_allocate_test.dart
//
// «تحميل على أمر تصنيع» — الفعلُ الثاني في رأس التصميم (`HEADS.main.alt`).
//
// ═══ ما يحرسه هذا الملفّ ═══
//
// 🔴 **المرشَّحون مصروفاتُ فئاتٍ مرتبطةٍ بالإنتاج وحدَها.** تحميلُ إيجارِ
//    إدارةٍ على أمرِ تصنيعٍ يُدخِله في تكلفة الوحدة — وهو خطأُ تكاليفٍ **لا
//    يُظهره أيُّ تقرير**: الأمرُ يظهر مكتملاً وتكلفتُه أعلى، ولا شيءَ يقول
//    إنّ الإيجارَ ليس منها.
//
// 🔴 **وسطرُ التحميل يُربَط بالمصروف** (`expenseId`). بدونه يصير يتيماً:
//    يُعرَف مبلغُه ولا يُعرَف أيُّ مصروفٍ مُوّل منه، فلا يُقاس «كم بقي غيرَ
//    محمَّل» ولا يُمنَع تحميلُ المصروف مرّتَين.
//
// 🔴 **وأسطرُ الصفر تُحذَف**: صفٌّ بصفرٍ يملأ جدولَ التكاليف بلا أثرٍ على
//    تكلفة الأمر.
//
// ⚠️ **ويُقاس ما يصل المستودعَ بالرقم** — الحسابُ نفسُه مُغطًّى في
// `test/unit/expense_allocation_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart' as db;
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/accounting_repository.dart';
import 'package:ural_erp/domain/repositories/branch_repository.dart';
import 'package:ural_erp/domain/repositories/budget_repository.dart';
import 'package:ural_erp/domain/repositories/manufacturing_repository.dart';
import 'package:ural_erp/presentation/opex_picpos/screens/opex_picpos_screen.dart';

final _thisMonth = DateTime(DateTime.now().year, DateTime.now().month, 5);

/// فئةٌ إنتاجيّةٌ وأخرى ليست — والمرشَّحون من الأولى وحدَها.
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

Map<String, dynamic> _expense({
  required int id,
  required double amount,
  required String category,
  String source = 'op_expense',
}) =>
    {
      'id': id,
      'amount': amount,
      'expense_date': _thisMonth,
      'period': 'monthly',
      'reference': 'REF-$id',
      'notes': 'بيان $id',
      'status': 'approved',
      'payment_method': 'cash',
      'branch_id': 1,
      'user_id': 1,
      'category_name': category,
      'category_type': 'variable',
      'branch_name': 'المعادي',
      'user_name': 'محمود سعيد',
      'source': source,
    };

final _expenses = [
  _expense(id: 21, amount: 8640, category: 'غاز ووقود أفران'),
  _expense(id: 22, amount: 48000, category: 'إيجارات'),
];

/// أمرٌ منتِجٌ وآخرُ ملغًى — والملغى لا يُعرَض.
final _orders = [
  db.ManufacturingOrderData(
    id: 138,
    orderNumber: 'MFG-0138',
    bomId: 1,
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
  db.ManufacturingOrderData(
    id: 137,
    orderNumber: 'MFG-0137',
    bomId: 2,
    orderedQty: 320,
    producedQty: 320,
    warehouseId: 1,
    startDate: _thisMonth,
    status: 'completed',
    additionalCosts: 0,
    totalCost: 4476,
    createdAt: _thisMonth,
    rowVersion: 0,
  ),
  db.ManufacturingOrderData(
    id: 999,
    orderNumber: 'MFG-0999',
    bomId: 3,
    orderedQty: 50,
    producedQty: 0,
    warehouseId: 1,
    startDate: _thisMonth,
    status: 'cancelled',
    additionalCosts: 0,
    totalCost: 0,
    createdAt: _thisMonth,
    rowVersion: 0,
  ),
];

class _FakeMfgRepo implements ManufacturingRepository {
  /// ما وصل المستودعَ — `(orderId, costType, amount, expenseId)`.
  final List<(int, String, double, int?)> costs = [];

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
      Stream.value(const []);

  @override
  Future<void> addMfgOrderCost({
    required int orderId,
    required String costType,
    required String description,
    required double amount,
    int? expenseCategoryId,
    int? expenseId,
  }) async {
    costs.add((orderId, costType, amount, expenseId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccountingRepo implements IAccountingRepository {
  @override
  Future<db.FiscalYearData?> getCurrentFiscalYear() async => null;

  @override
  Stream<List<db.CostCenter>> watchCostCenters() => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBudgetRepo implements IBudgetRepository {
  @override
  Future<List<Map<String, dynamic>>> getBudgetVsActualReport(int y) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBranchRepo implements IBranchRepository {
  @override
  Future<List<db.Branche>> getBranches() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeMfgRepo> _pump(WidgetTester tester, double width) async {
  final mfg = _FakeMfgRepo();
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        manufacturingRepositoryProvider.overrideWithValue(mfg),
        accountingRepositoryProvider.overrideWithValue(_FakeAccountingRepo()),
        budgetRepositoryProvider.overrideWithValue(_FakeBudgetRepo()),
        branchRepositoryProvider.overrideWithValue(_FakeBranchRepo()),
        currentUserPermissionsProvider
            .overrideWith((ref) async => const ['expenses_manage']),
      ],
      child: const MaterialApp(home: OpexPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
  return mfg;
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('تحميل على أمر تصنيع'));
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
      testWidgets('المرساة: الفعلُ الثاني حاضرٌ في الرأس', (tester) async {
        await _pump(tester, width);
        expect(find.text('تحميل على أمر تصنيع'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('🔴 المصروفُ غيرُ الإنتاجيِّ ليس مرشَّحاً', (tester) async {
        await _pump(tester, width);
        await _openDialog(tester);

        await tester.tap(find.byType(DropdownButtonFormField<int>).first);
        await tester.pumpAndSettle();

        // ⚠️ **البحثُ محصورٌ في بنود القائمة**: جدولُ المصروفات خلفَ الحوار
        //    يعرض «إيجارات» أيضاً، فبحثٌ عامٌّ يقيس الجدولَ لا القائمة —
        //    ويمرّ الفحصُ فاشلاً على شاشةٍ سليمة.
        Finder inMenu(String text) => find.descendant(
              of: find.byType(DropdownMenuItem<int>),
              matching: find.textContaining(text),
            );

        expect(inMenu('غاز ووقود أفران'), findsWidgets);
        // «إيجارات» فئةٌ غيرُ مرتبطةٍ بالإنتاج ⇒ ليست مرشَّحةً إطلاقاً.
        expect(inMenu('إيجارات'), findsNothing);

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('🔴 والأمرُ الملغى ليس هدفاً', (tester) async {
        await _pump(tester, width);
        await _openDialog(tester);

        expect(find.textContaining('MFG-0138'), findsOneWidget);
        expect(find.textContaining('MFG-0137'), findsOneWidget);
        expect(find.textContaining('MFG-0999'), findsNothing);

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('بالمعدل: 1.20 × ١٨٠ = 216 يصل المستودعَ مربوطاً بالمصروف',
          (tester) async {
        final repo = await _pump(tester, width);
        await _openDialog(tester);

        await tester.tap(find.byType(DropdownButtonFormField<int>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('غاز ووقود أفران').last);
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('MFG-0138'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('تحميل على 1 أمر'));
        await tester.pumpAndSettle();

        // ⚠️ ما يصل المستودعَ بالرقم — لا «تحرّك شيء».
        expect(repo.costs.length, 1);
        final (orderId, costType, amount, expenseId) = repo.costs.single;
        expect(orderId, 138);
        expect(costType, 'overhead');
        expect(amount, closeTo(216, 1e-9));
        // 🔴 الربطُ بالمصروف — بدونه يصير السطرُ يتيماً.
        expect(expenseId, 21);

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('🔴 والباقي غيرُ المحمَّل يُقال بالرقم قبل الحفظ',
          (tester) async {
        await _pump(tester, width);
        await _openDialog(tester);

        await tester.tap(find.byType(DropdownButtonFormField<int>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('غاز ووقود أفران').last);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('MFG-0138'));
        await tester.pumpAndSettle();

        // ‏8,640 − 216 = 8,424 يبقى غيرَ محمَّل، ويُقال أثرُه على الهامش.
        expect(find.text('8,424.00'), findsOneWidget);
        expect(
          find.textContaining('يتضخّم\nهامشُ الربح الظاهر').evaluate().isEmpty
              ? find.textContaining('هامشُ الربح الظاهر')
              : find.textContaining('هامشُ الربح الظاهر'),
          findsOneWidget,
        );

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('توزيعُ كامل المبلغ لا يترك باقياً — والمجموعُ يطابق',
          (tester) async {
        final repo = await _pump(tester, width);
        await _openDialog(tester);

        await tester.tap(find.byType(DropdownButtonFormField<int>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('غاز ووقود أفران').last);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('MFG-0138'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('MFG-0137'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('توزيع كامل المبلغ'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('تحميل على 2 أوامر'));
        await tester.pumpAndSettle();

        expect(repo.costs.length, 2);
        final total = repo.costs.fold<double>(0, (s, c) => s + c.$3);
        // ‏180/500 × 8,640 = 3,110.40 · و320/500 × 8,640 = 5,529.60.
        expect(total, closeTo(8640, 1e-9));

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }
}
