// test/widget/opex_picpos_actions_test.dart
//
// «مصروف جديد» ونقلُ المصروف في دورته — فعلا الكتابة في شاشة المصروفات.
//
// ═══ ما يحرسه هذا الملفّ ═══
//
// 🔴 **حارسان لا واحد**: `expenses_manage` للتسجيل و`expenses_approve`
//    للاعتماد. مَن يسجّل المصروفَ ليس بالضرورة مَن يعتمده، وفصلُ الأدوار هو
//    غرضُ دورة الاعتماد كلِّها — فجمعُهما تحت كودٍ واحدٍ يُبطلها.
//
// 🔴 **والشاشةُ كانت محصورةً بالنطاق وحدَه**: `ScreenId.operationalExpenses`
//    بلا أيّ كودِ صلاحيّة. فزرُّ كتابةٍ بلا حارسٍ كان يجعل ترحيلَ القيد وخصمَ
//    الخزنة مبلوغَين لمن يملك القراءةَ وحدَها.
//
// 🔴 **وصفُّ حركةِ الخزنة لا يُنقَل**: `getExpensesForReport` يضمّ
//    `safe_transactions` بـ`status == null` و`id` يخصّ **جدولاً آخر**.
//    ونقلُه يكتب `status` على مصروفٍ بمعرِّفٍ مطابقٍ صدفةً — وهو أسوأُ من
//    فشلٍ ظاهر.
//
// ⚠️ **ويُقاس ما يصل المستودعَ** لا ما يظهر: الحوارُ يُرجع رمزَ الحساب
// المشتقَّ من الفئة، وهو ما يُرحَّل عليه القيدُ فعلاً.
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
import 'package:ural_erp/presentation/picpos_shell/picpos_report_tabs.dart';

final _thisMonth = DateTime(DateTime.now().year, DateTime.now().month, 5);

final _categories = [
  db.OpExpenseCategoryData(
    id: 7,
    name: 'صيانة وإصلاحات',
    type: 'variable',
    isProductionRelated: false,
    allocationMethod: 'fixed_monthly',
    defaultRate: 0,
    accountCode: '5204',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
    rowVersion: 0,
  ),
];

/// صفٌّ حقيقيٌّ من `op_expenses` وآخرُ من `safe_transactions`.
///
/// ⚠️ **ومعرِّفاهما متطابقان عمداً** (‏كلاهما ٣): هذا عينُ الالتباس الذي
/// يجعل نقلَ صفّ الخزنة يكتب على المصروف.
final _expenses = <Map<String, dynamic>>[
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
  {
    'id': 3,
    'amount': 900.0,
    'expense_date': _thisMonth,
    'period': null,
    'reference': null,
    'notes': 'سحب نقديّ',
    'status': null,
    'payment_method': 'cash',
    'branch_id': 1,
    'user_id': 4,
    'category_name': 'حركة خزنة',
    'category_type': 'cash_outflow',
    'branch_name': 'المعادي',
    'user_name': 'سارة منير',
    'source': 'safe_tx',
  },
  // ⚠️ **صفُّ خزنةٍ يحمل حالةً — دفاعٌ في العمق.**
  //
  // `getExpensesForReport` اليومَ يثبّت `'status': null` لصفوف
  // `safe_transactions`، فهي لا تظهر على اللوحة أصلاً. لكنّ تمريرَ الحالة
  // تغييرٌ سطرٌ واحدٌ في الاستعلام، وحينها تظهر بطاقةٌ معرِّفُها يخصّ جدولاً
  // آخر — ونقلُها يكتب `status` على مصروفٍ بمعرِّفٍ مطابقٍ صدفةً.
  //
  // 🔴 والفحصُ على هذا الصفّ يقيس **حارسَ `source`** نفسَه، لا غيابَ
  //    الحالة. وحارسٌ لا يُختبَر على الحالة التي يحرسها ليس حارساً.
  {
    'id': 3,
    'amount': 750.0,
    'expense_date': _thisMonth,
    'period': null,
    'reference': null,
    'notes': 'سحب نقديّ ثانٍ',
    'status': 'draft',
    'payment_method': 'cash',
    'branch_id': 1,
    'user_id': 4,
    'category_name': 'حركة خزنة بحالة',
    'category_type': 'cash_outflow',
    'branch_name': 'المعادي',
    'user_name': 'سارة منير',
    'source': 'safe_tx',
  },
];

/// مستخدمٌ مسجَّلٌ — بدونه يرتدّ الحفظُ عمداً.
///
/// ⚠️ **الشاشةُ ترفض الحفظَ بلا مستخدم** ولا تسنده إلى الرقم ١: المصروفُ
/// يُنسَب لمن سجّله في سجلّ التدقيق، ونسبةُ فعلٍ ماليٍّ إلى شخصٍ لم يفعله
/// أسوأُ من رفضٍ ظاهر. فبلا هذا الوهميّ يقيس الاختبارُ تسجيلَ الدخول لا
/// مسارَ الحفظ.
class _SignedInAuth extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        userWithRole: UserWithRole(
          user: User(
            id: 9,
            username: 'tester',
            passwordHash: '',
            passwordSalt: '',
            displayName: 'مُسجِّل المصروفات',
            defaultScreen: '0',
            isLocked: false,
            isActive: true,
            discountLimitIsPercent: true,
            forcePasswordChange: false,
            createdAt: DateTime(2026, 1, 1),
            rowVersion: 1,
          ),
        ),
      );
}

class _FakeMfgRepo implements ManufacturingRepository {
  /// ما وصل المستودعَ من نقلِ حالة — `(id, status)`.
  final List<(int, String)> moves = [];

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
      Stream.value(const []);

  @override
  Stream<List<db.MfgOrderCostData>> watchAllMfgOrderCosts() =>
      Stream.value(const []);

  @override
  Future<bool> updateExpenseStatus(int expenseId, String status) async {
    moves.add((expenseId, status));
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingAccountingRepo implements IAccountingRepository {
  final List<Map<String, Object?>> posted = [];

  @override
  Future<db.FiscalYearData?> getCurrentFiscalYear() async => null;

  @override
  Stream<List<db.CostCenter>> watchCostCenters() => Stream.value(const []);

  @override
  Future<int> recordAndPostOperationalExpense({
    required int categoryId,
    required double amount,
    required DateTime expenseDate,
    required String description,
    required String expenseAccountCode,
    String period = 'monthly',
    int? manufacturingOrderId,
    String? reference,
    String? notes,
    required int userId,
    int? branchId,
    int? costCenterId,
    String? paymentMethod,
    int? safeId,
  }) async {
    posted.add({
      'categoryId': categoryId,
      'amount': amount,
      'description': description,
      'expenseAccountCode': expenseAccountCode,
      'period': period,
      'userId': userId,
      'paymentMethod': paymentMethod,
    });
    return posted.length;
  }

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

typedef _Repos = ({_FakeMfgRepo mfg, _RecordingAccountingRepo acc});

Future<_Repos> _pump(
  WidgetTester tester,
  double width, {
  List<String> perms = const ['expenses_manage', 'expenses_approve'],
}) async {
  final mfg = _FakeMfgRepo();
  final acc = _RecordingAccountingRepo();
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        manufacturingRepositoryProvider.overrideWithValue(mfg),
        accountingRepositoryProvider.overrideWithValue(acc),
        budgetRepositoryProvider.overrideWithValue(_FakeBudgetRepo()),
        branchRepositoryProvider.overrideWithValue(_FakeBranchRepo()),
        authProvider.overrideWith(_SignedInAuth.new),
        currentUserPermissionsProvider.overrideWith((ref) async => perms),
        // اللوحةُ تقرأ `hasPermissionProvider` — مسارُ تجاوزِ مدير النظام.
        hasPermissionProvider('expenses_approve')
            .overrideWith((ref) async => perms.contains('expenses_approve')),
      ],
      child: const MaterialApp(home: OpexPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
  return (mfg: mfg, acc: acc);
}

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
      testWidgets('المرساة: «مصروف جديد» يظهر مع expenses_manage',
          (tester) async {
        await _pump(tester, width);
        expect(
          find.text('مصروف جديد'),
          findsOneWidget,
          reason: 'الزرُّ غائبٌ حتّى مع الصلاحيّة — فنفيُ الفحص التالي '
              'سيقيس نمطَ البحث لا الحارس.',
        );
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('🔴 وبلا expenses_manage لا يظهر', (tester) async {
        await _pump(tester, width, perms: const ['expenses_approve']);
        expect(find.text('مصروف جديد'), findsNothing);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('الحسابُ مشتقٌّ من الفئة ويصل المستودعَ كما هو',
          (tester) async {
        final repos = await _pump(tester, width);
        await tester.tap(find.text('مصروف جديد'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButtonFormField<int>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('صيانة وإصلاحات').last);
        await tester.pumpAndSettle();

        // رمزُ الحساب يُعرَض مشتقّاً — لا يُكتَب بيد.
        expect(find.text('5204 · صيانة وإصلاحات'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'المبلغ *'),
          '2400',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'البيان *'),
          'صيانة كومبرسور ثلاجة',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('حفظ وترحيل'));
        await tester.pumpAndSettle();

        // ⚠️ ما يصل المستودعَ لا ما يظهر.
        expect(repos.acc.posted.length, 1);
        final row = repos.acc.posted.single;
        expect(row['categoryId'], 7);
        expect(row['amount'], 2400.0);
        expect(row['expenseAccountCode'], '5204');
        expect(row['description'], 'صيانة كومبرسور ثلاجة');
        expect(row['paymentMethod'], 'cash');

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('🔴 والزرُّ يقول «حفظ وترحيل» لا «حفظ كمسوّدة»',
          (tester) async {
        // نصُّ التصميم `save:'حفظ كمسوّدة'` يَعِد بما لا يقع: الحفظُ يرحّل
        // القيدَ ويخصم من الخزنة فوراً.
        await _pump(tester, width);
        await tester.tap(find.text('مصروف جديد'));
        await tester.pumpAndSettle();

        expect(find.text('حفظ وترحيل'), findsOneWidget);
        expect(find.text('حفظ كمسوّدة'), findsNothing);
        expect(
          find.textContaining('الحفظ يرحّل القيدَ'),
          findsOneWidget,
        );

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('نقلُ مسوّدةٍ يكتب «معتمد» بمعرِّفها', (tester) async {
        final repos = await _pump(tester, width);
        await _openTab(tester, 'الاعتماد والسداد');

        await tester.tap(find.text('صيانة وإصلاحات').first);
        await tester.pumpAndSettle();

        expect(repos.mfg.moves, [(3, 'approved')]);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('🔴 وصفُّ حركةِ الخزنة لا يُنقَل ولو طابق معرِّفُه',
          (tester) async {
        final repos = await _pump(tester, width);
        await _openTab(tester, 'الاعتماد والسداد');

        // صفٌّ بلا حالةٍ لا يقع في أيّ عمود — الحمايةُ الأولى.
        expect(find.text('حركة خزنة'), findsNothing);

        // والمرساة: صفُّ الخزنة **ذو الحالة** حاضرٌ فعلاً، وإلّا قاس النفيُ
        // التالي غيابَ بطاقةٍ لا حارسَ `source`.
        final card = find.text('حركة خزنة بحالة');
        expect(
          card,
          findsWidgets,
          reason: 'البطاقةُ غائبةٌ فالفحصُ لا يقيس الحارس',
        );

        await tester.tap(card.first);
        await tester.pumpAndSettle();

        // 🔴 معرِّفُها ٣ كمعرِّف المصروف — ونقرُها يجب ألّا يكتب شيئاً.
        expect(repos.mfg.moves, isEmpty);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('🔴 وبلا expenses_approve لا تُنقَل بطاقةٌ إطلاقاً',
          (tester) async {
        final repos = await _pump(
          tester,
          width,
          perms: const ['expenses_manage'],
        );
        await _openTab(tester, 'الاعتماد والسداد');

        await tester.tap(find.text('صيانة وإصلاحات').first);
        await tester.pumpAndSettle();

        expect(repos.mfg.moves, isEmpty);
        // ولا يُعرَض التلميحُ الذي يَعِد بالنقل.
        expect(find.textContaining('اضغط بطاقةً لنقلها'), findsNothing);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }
}
