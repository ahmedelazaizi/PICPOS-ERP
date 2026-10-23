// test/widget/chart_of_accounts_picpos_test.dart
//
// اختبارُ **تركيب** دليل الحسابات بهويّة PicPos.
//
// ⚠️ يقيس بعرضَين مع `takeException` — الخزينةُ شُحنت بيضاءَ واختباراتُ
// ودجتاتها خضراء، والعطبُ كان في التركيب لا في القطع. وفي بناء الإصدار
// يُرسم بياضٌ لا شاشةٌ حمراء.
//
// ⚠️ ويقيس أنّ **كلّ فعلٍ نُقل** من الشريط المتدرّج المحذوف: توسيع · طباعة ·
// تصدير · استيراد · إضافة · ومرشِّحُ حسابات الضريبة. وهذا الأخيرُ كاد يسقط
// فعلاً — واللِّنتُ وحدَه كشفه (`_showTaxAccountsOnly` بلا مُسنِد).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/accounting_repository.dart';
import 'package:picpos_erp/presentation/accounting_picpos/chart_of_accounts_picpos_screen.dart';

class _FakeAccountingRepo implements IAccountingRepository {
  _FakeAccountingRepo(this._accounts);
  final List<Account> _accounts;

  @override
  Stream<List<Account>> watchAllAccounts() => Stream.value(_accounts);

  @override
  Future<List<Account>> getAllAccounts() async => _accounts;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Account _acc({
  required int id,
  required String code,
  required String name,
  required String type,
  int? parentId,
  double balance = 0,
}) =>
    Account(
      id: id,
      code: code,
      name: name,
      accountType: type,
      accountNature: 'debit',
      normalBalance: 'debit',
      level: parentId == null ? 1 : 2,
      parentId: parentId,
      balance: balance,
      isSystem: false,
      isActive: true,
      isHiddenFromEntries: false,
      rowVersion: 1,
    );

void main() {
  final accounts = [
    _acc(id: 1, code: '1000', name: 'الأصول', type: 'asset', balance: 5000),
    _acc(id: 2, code: '1100', name: 'النقدية', type: 'asset', parentId: 1),
    _acc(id: 3, code: '2000', name: 'الخصوم', type: 'liability'),
    _acc(id: 4, code: '4100', name: 'ضريبة القيمة المضافة', type: 'liability'),
  ];

  Future<void> pump(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountingRepositoryProvider
              .overrideWithValue(_FakeAccountingRepo(accounts)),
        ],
        child: const MaterialApp(home: ChartOfAccountsPicPosScreen()),
      ),
    );
    await tester.pump();
  }

  for (final width in [1280.0, 1920.0]) {
    testWidgets('تُبنى بلا استثناءِ تخطيطٍ عند عرض ${width.toInt()}',
        (tester) async {
      await pump(tester, width);
      expect(tester.takeException(), isNull);
    });

    testWidgets('وتعرض محتواها فعلاً عند عرض ${width.toInt()}',
        (tester) async {
      await pump(tester, width);

      expect(find.text('دليل الحسابات'), findsWidgets);
      expect(find.text('إجمالي الحسابات'), findsOneWidget);
      // صفٌّ حقيقيٌّ من الشجرة — لا «لم تنهر» وحدَها.
      expect(find.textContaining('الأصول'), findsWidgets);
    });
  }

  testWidgets('كلُّ أفعالِ الترويسة نُقلت — لا فعلَ سقط في إعادة التنسيق',
      (tester) async {
    await pump(tester, 1920);

    expect(find.text('توسيع الكل'), findsOneWidget);
    expect(find.text('طباعة/PDF'), findsOneWidget);
    expect(find.text('إضافة حساب رئيسي'), findsOneWidget);
    expect(find.byTooltip('تصدير الدليل (Excel)'), findsOneWidget);
    expect(find.byTooltip('استيراد الدليل (Excel)'), findsOneWidget);
    // ⚠️ هذا هو الذي كاد يسقط.
    expect(find.text('حسابات الضريبة'), findsOneWidget);
  });

  testWidgets('العدّاداتُ تُقاس من القائمة غيرِ المرشَّحة', (tester) async {
    await pump(tester, 1280);

    // أربعةُ حساباتٍ: ثلاثةٌ جذورٌ (١ · ٣ · ٤) وواحدٌ ابن.
    expect(find.text('4'), findsWidgets, reason: 'الإجمالي');
    expect(find.text('3'), findsWidgets, reason: 'الرئيسية');
  });
}
