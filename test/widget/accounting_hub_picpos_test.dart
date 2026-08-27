// test/widget/accounting_hub_picpos_test.dart
//
// اختبارُ **تركيب** حاويةِ الحسابات بعرضَين.
//
// ⚠️ بعرضَين مع `takeException`: شريطُ سبعِ شرائحَ مرشَّحٌ للفيضان، وفيضاناتُ
// الجلسة الماضية **تغيّرت بالعرض** (٩٢ و٢٧ في العروض · ٣٠٧ في دليل الحسابات)
// فقياسُ عرضٍ واحدٍ يمرّ على العطب.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/accounting_repository.dart';
import 'package:ural_erp/presentation/accounting_picpos/accounting_hub_picpos_screen.dart';

class _FakeAccountingRepo implements IAccountingRepository {
  _FakeAccountingRepo(this._accounts);
  final List<Account> _accounts;

  @override
  Stream<List<Account>> watchAllAccounts() => Stream.value(_accounts);

  @override
  Future<List<Account>> getAllAccounts() async => _accounts;

  // يطلبها تبويبُ «ربط الحسابات» عند فتحه — تُجاب فارغةً كي يبقى مخرَجُ
  // الاختبار نظيفاً بدل رميةِ `noSuchMethod` تبتلعها الشاشةُ وتطبعها.
  @override
  Future<List<CostCenter>> getActiveCostCenters() async => const [];

  @override
  Future<List<AccountMapping>> getAllAccountMappings() async => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Account _acc({
  required int id,
  required String code,
  required String name,
  required String type,
  int? parentId,
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
      balance: 0,
      isSystem: false,
      isActive: true,
      isHiddenFromEntries: false,
      rowVersion: 1,
    );

void main() {
  final accounts = [
    _acc(id: 1, code: '1000', name: 'الأصول', type: 'asset'),
    _acc(id: 2, code: '1100', name: 'النقدية', type: 'asset', parentId: 1),
  ];

  Future<void> pump(
    WidgetTester tester,
    double width, {
    List<String> perms = const ['settings_view', 'reports_view'],
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountingRepositoryProvider
              .overrideWithValue(_FakeAccountingRepo(accounts)),
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
        ],
        child: const MaterialApp(
          // نبدأ على «دليل الحسابات» — التبويبُ الوحيدُ المفروكُ الذي
          // يكتفي بمستودعٍ وهميّ. والبقيّةُ تُقاس في اختباراتِها.
          home: AccountingHubPicPosScreen(initialTab: AccountingTab.coa),
        ),
      ),
    );
    // دفعتان: الأولى تُنهي `currentUserPermissionsProvider` فيُبنى التبويب،
    // والثانية تُسلّم بثَّ حساباتِه. دفعةٌ واحدةٌ تترك الحاويةَ على المؤشِّر.
    await tester.pump();
    await tester.pump();
  }

  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    testWidgets('تُبنى بلا استثناءِ تخطيطٍ عند عرض $w', (tester) async {
      await pump(tester, width);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ويظهر الشريطُ بتبويباتِه الثمانية عند عرض $w', (tester) async {
      await pump(tester, width);

      // اسمُ الحاوية على الشريط.
      expect(find.text('الحسابات'), findsOneWidget);
      for (final tab in AccountingTab.values) {
        expect(find.text(tab.label), findsWidgets,
            reason: 'تبويبُ ${tab.label} غائبٌ عن الشريط عند عرض $w');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('ومحتوى التبويب المفتوح يُرسم فعلاً عند عرض $w',
        (tester) async {
      await pump(tester, width);

      // نصٌّ من **داخل** المحتوى لا من الشريط — «لم تنهر» وحدَها لا تكفي.
      // (‏الشجرةُ تُفتَح مطويّةً، فنقيس جذراً لا ابناً.)
      expect(find.text('إجمالي الحسابات'), findsOneWidget);
      expect(find.textContaining('الأصول'), findsWidgets);
    });
  }

  testWidgets('التبديلُ بين التبويبات يبدّل المحتوى', (tester) async {
    await pump(tester, 1920);
    expect(find.text('إجمالي الحسابات'), findsOneWidget);

    await tester.tap(find.text('ربط الحسابات'));
    await tester.pump();

    // غادرنا دليلَ الحسابات — والشريطُ باقٍ.
    expect(find.text('إجمالي الحسابات'), findsNothing);
    expect(find.text('الحسابات'), findsOneWidget);
  });

  testWidgets('صلاحيةٌ ناقصةٌ تُخفي تبويباتِها وحدَها', (tester) async {
    // بلا `reports_view` يسقط «ميزانُ المراجعة» و«القوائمُ المالية» معاً —
    // وهما التبويبان الوحيدان اللذان يحرسهما هذا الكود — وتبقى الستّةُ.
    await pump(tester, 1920, perms: const ['settings_view']);

    expect(find.text('ميزان المراجعة'), findsNothing,
        reason: 'الحاويةُ لا توسّع دائرةَ مَن يرى القوائمَ المالية');
    expect(find.text('القوائم المالية'), findsNothing,
        reason: 'الشريحةُ الثامنةُ تحمل نفسَ الصلاحية — فتسقط معها');
    expect(find.text('دليل الحسابات'), findsWidgets);
    expect(find.text('ربط الحسابات'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('وبلا صلاحيةٍ أصلاً تظهر حالةُ فراغٍ لا شاشةٌ بيضاء',
      (tester) async {
    await pump(tester, 1280, perms: const []);

    expect(find.text('لا تبويباتِ حساباتٍ متاحة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
