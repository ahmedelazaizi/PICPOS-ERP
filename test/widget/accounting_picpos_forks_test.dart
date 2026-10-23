// test/widget/accounting_picpos_forks_test.dart
//
// اختبارُ **تركيب** فوركات تبويبات الحسابات الخمسة بعرضَين.
//
// ⚠️ بعرضَي ١٢٨٠ و١٩٢٠ مع `takeException`: فيضاناتُ الجلسات السابقة كانت
// **تتغيّر بالعرض** (٩٢ و٢٧ في العروض · ٣٠٧ في دليل الحسابات)، فقياسُ عرضٍ
// واحدٍ يمرّ على العطب. وكلُّ شاشةٍ تُقاس بنصٍّ من **محتواها** لا بـ«لم تنهر».
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/accounting_repository.dart';
import 'package:picpos_erp/domain/repositories/branch_repository.dart';
import 'package:picpos_erp/presentation/accounting_picpos/account_mapping_picpos_screen.dart';
import 'package:picpos_erp/presentation/accounting_picpos/cost_centers_picpos_screen.dart';
import 'package:picpos_erp/presentation/accounting_picpos/general_ledger_picpos_screen.dart';
import 'package:picpos_erp/presentation/accounting_picpos/journal_templates_picpos_screen.dart';

class _FakeAccountingRepo implements IAccountingRepository {
  _FakeAccountingRepo({
    this.accounts = const [],
    this.costCenters = const [],
    this.templates = const [],
    this.mappings = const [],
    this.templateLines = const [],
    this.ledger = const [],
  });

  final List<Account> accounts;
  final List<CostCenter> costCenters;
  final List<JournalEntryTemplateData> templates;
  final List<AccountMapping> mappings;
  final List<Map<String, dynamic>> templateLines;
  final List<Map<String, dynamic>> ledger;

  @override
  Future<List<Account>> getAllAccounts() async => accounts;

  @override
  Future<List<CostCenter>> getActiveCostCenters() async => costCenters;

  @override
  Stream<List<CostCenter>> watchCostCenters() => Stream.value(costCenters);

  @override
  Stream<List<JournalEntryTemplateData>> watchAllTemplates() =>
      Stream.value(templates);

  @override
  Future<List<Map<String, dynamic>>> getTemplateLinesWithAccounts(int id) async =>
      templateLines;

  @override
  Future<List<AccountMapping>> getAllAccountMappings() async => mappings;

  @override
  Future<Map<String, double>> getCostCenterBalance(int id) async =>
      const {'debit': 500, 'credit': 200};

  @override
  Future<List<Map<String, dynamic>>> getCostCenterLedger(
          int id, DateTime from, DateTime to) async =>
      ledger;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBranchRepo implements IBranchRepository {
  @override
  Future<List<Branche>> getBranches() async => const [];

  @override
  Future<List<Warehouse>> getWarehouses() async => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Account _acc(int id, String code, String name) => Account(
      id: id,
      code: code,
      name: name,
      accountType: 'asset',
      accountNature: 'debit',
      normalBalance: 'debit',
      level: 1,
      balance: 0,
      isSystem: false,
      isActive: true,
      isHiddenFromEntries: false,
      rowVersion: 1,
    );

CostCenter _cc(int id, String code, String name, {int? parentId}) => CostCenter(
      id: id,
      code: code,
      name: name,
      parentId: parentId,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      rowVersion: 1,
    );

JournalEntryTemplateData _tpl(int id, String name, String? desc) =>
    JournalEntryTemplateData(
      id: id,
      name: name,
      description: desc,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  final accounts = [
    _acc(1, '1111', 'الصندوق الرئيسي'),
    _acc(2, '4121', 'مبيعات محلية'),
  ];
  final centers = [
    _cc(1, 'CC1', 'الفرع الرئيسي'),
    _cc(2, 'CC2', 'قسم التوصيل', parentId: 1),
  ];

  Future<void> pump(
    WidgetTester tester,
    double width,
    Widget screen, {
    _FakeAccountingRepo? repo,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountingRepositoryProvider.overrideWithValue(
              repo ?? _FakeAccountingRepo(accounts: accounts)),
          branchRepositoryProvider.overrideWithValue(_FakeBranchRepo()),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    // دفعتان: الأولى تُنهي المستقبلات، والثانية تُسلّم البثّ.
    await tester.pump();
    await tester.pump();
  }

  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    group('عرض $w', () {
      testWidgets('قوالبُ القيود — تركيبٌ ومحتوى', (tester) async {
        await pump(
          tester,
          width,
          const JournalTemplatesPicPosScreen(),
          repo: _FakeAccountingRepo(
            accounts: accounts,
            templates: [
              _tpl(1, 'قيد الرواتب الشهري', 'يُرحّل رواتبَ الشهر'),
              _tpl(2, 'قيد الإيجار', null),
            ],
            templateLines: const [
              {
                'account_code': '1111',
                'account_name': 'الصندوق',
                'debit': 100.0,
                'credit': 0.0,
              },
            ],
          ),
        );

        expect(find.text('قوالب القيود'), findsWidgets);
        expect(find.text('قيد الرواتب الشهري'), findsOneWidget);
        // العدّادُ مقيسٌ من الصفوف — قالبان.
        expect(find.text('2'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('قوالبُ القيود — حالةُ الفراغ لا شاشةٌ بيضاء',
          (tester) async {
        await pump(tester, width, const JournalTemplatesPicPosScreen());
        expect(find.text('لا توجد قوالب قيود'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('دفترُ الأستاذ — يفتح على طلبِ اختيارِ حساب',
          (tester) async {
        await pump(tester, width, const GeneralLedgerPicPosScreen());

        expect(find.text('دفتر الأستاذ العام'), findsWidgets);
        expect(find.text('اختر الحساب'), findsWidgets);
        expect(find.text('اختر حساباً لعرض حركاته'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('مراكزُ التكلفة — الشجرةُ واللوحةُ معاً', (tester) async {
        await pump(
          tester,
          width,
          const CostCentersPicPosScreen(),
          repo: _FakeAccountingRepo(accounts: accounts, costCenters: centers),
        );

        expect(find.text('مراكز التكلفة'), findsWidgets);
        expect(find.text('الهيكل الشجري'), findsOneWidget);
        // صفٌّ حقيقيٌّ من الشجرة، والابنُ يظهر تحت أبيه.
        expect(find.text('الفرع الرئيسي'), findsOneWidget);
        expect(find.text('قسم التوصيل'), findsOneWidget);
        expect(find.text('اختر مركز تكلفة لعرض التفاصيل'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('ربطُ الحسابات — المجموعاتُ والتحذير', (tester) async {
        await pump(
          tester,
          width,
          const AccountMappingPicPosScreen(),
          repo: _FakeAccountingRepo(accounts: accounts, costCenters: centers),
        );

        expect(find.text('ربط الحسابات بالعمليات'), findsWidgets);
        // المجموعةُ الأولى من التعريفات المنقولة.
        expect(find.text('النقدية والذمم المدينة'), findsWidgets);
        // بلا أيّ ربطٍ مخزَّن، كلُّ الأغراض غيرُ مربوطة فيظهر التحذير.
        expect(find.textContaining('تحتاج ضبط الربط'), findsOneWidget);
        expect(find.text('الصندوق الرئيسي'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('مراكزُ التكلفة — اختيارُ مركزٍ يفتح تفاصيله وحركاته',
      (tester) async {
    await pump(
      tester,
      1920,
      const CostCentersPicPosScreen(),
      repo: _FakeAccountingRepo(
        accounts: accounts,
        costCenters: centers,
        ledger: [
          {
            'entry_date': DateTime(2026, 8, 1),
            'entry_number': '',
            'entry_desc': 'رصيد أول المدة',
            'debit': 0.0,
            'credit': 0.0,
            'balance': 100.0,
            'is_opening': true,
          },
          {
            'entry_date': DateTime(2026, 8, 12),
            'entry_number': 'JE-77',
            'line_desc': 'مصروف وقود',
            'account_name': 'مصروفات',
            'debit': 250.0,
            'credit': 0.0,
            'balance': 350.0,
            'is_opening': false,
          },
        ],
      ),
    );

    await tester.tap(find.text('الفرع الرئيسي'));
    await tester.pump();
    await tester.pump();

    expect(find.text('اختر مركز تكلفة لعرض التفاصيل'), findsNothing);
    expect(find.text('حركات المركز'), findsOneWidget);
    // الرصيدُ صافي (مدين − دائن) = 500 − 200، لا مجموعُهما.
    expect(find.textContaining('300'), findsWidgets);
    // صفٌّ حقيقيٌّ من الدفتر، والافتتاحيُّ معه.
    expect(find.text('JE-77'), findsOneWidget);
    expect(find.text('مصروف وقود'), findsOneWidget);
    expect(find.text('رصيد أول المدة'), findsOneWidget);
    // عدّادُ الحركات يستثني الصفَّ الافتتاحيّ.
    expect(find.textContaining('1 حركة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ربطُ الحسابات — غرضٌ مربوطٌ يظهر بحسابه وبلا تحذير',
      (tester) async {
    await pump(
      tester,
      1920,
      const AccountMappingPicPosScreen(),
      repo: _FakeAccountingRepo(
        accounts: accounts,
        costCenters: centers,
        mappings: [
          AccountMapping(
            id: 1,
            purpose: 'cash',
            accountId: 1,
            updatedAt: DateTime(2026, 8, 1),
          ),
        ],
      ),
    );

    // «الصندوق الرئيسي» صار مربوطاً بـ1111 فتظهر شارتُه وحسابُه.
    expect(find.text('مربوط'), findsWidgets);
    expect(find.textContaining('1111'), findsWidgets);
    // والتحذيرُ يعدّ الباقيَ لا الكلَّ — ٤٥ غرضاً ناقصَ المربوطِ الواحد.
    expect(find.textContaining('44 عملية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ربطُ الحسابات — تبديلُ المجموعة يبدّل الأغراض',
      (tester) async {
    await pump(
      tester,
      1920,
      const AccountMappingPicPosScreen(),
      repo: _FakeAccountingRepo(accounts: accounts, costCenters: centers),
    );

    expect(find.text('الصندوق الرئيسي'), findsWidgets);
    await tester.tap(find.text('الإيرادات').first);
    await tester.pump();

    expect(find.text('الصندوق الرئيسي'), findsNothing);
    expect(find.text('مبيعات محلية'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
