// test/widget/journal_entries_picpos_dialogs_test.dart
//
// اختبارُ **توصيفٍ** لحوارات قيود اليومية — يُكتَب قبل أوّلِ سطرِ تنسيق.
//
// ═══ لماذا قبل التنسيق ═══
//
// `journal_entries_picpos_screen.dart` (‏١٠٥٥ سطراً) وجزؤه
// `journal_entries_picpos_create_dialog.dart` (‏٥٢٩ سطراً) لم يكن يمسّهما
// **أيُّ** اختبارٍ يوم 2026-08-27 — مقيسٌ بـ`grep -rl` على `test/` كلِّه.
// وفيهما ثلاثةٌ من الحوارات الأربعة العارية المطلوبِ نقلُها إلى
// `PicPosDialog`. فبلا هذا الملفّ لا يُعرَف الكسرُ إلّا من المالك.
//
// وهذه اختباراتُ توصيفٍ لا مواصفاتٍ جديدة: تُثبّت **السلوكَ القائم** —
// ماذا يُفتَح، وبأيّ نصٍّ، وماذا يحدث عند الإلغاء — فتبقى خضراءَ قبل النقل
// وبعده. أيُّ احمرارٍ بعده = النقلُ غيّر سلوكاً لا شكلاً.
//
// ⚠️ وبعرضَين لا واحد: أعطابُ التخطيط في هذا المستودع **تتغيّر بالعرض**،
//    وقياسُ عرضٍ واحدٍ يمرّ عليها.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/accounting_repository.dart';
import 'package:ural_erp/presentation/accounting_picpos/journal_entries_picpos_screen.dart';

class _FakeAccountingRepo implements IAccountingRepository {
  _FakeAccountingRepo({
    this.accounts = const [],
    this.costCenters = const [],
    this.templates = const [],
  });

  final List<Account> accounts;
  final List<CostCenter> costCenters;
  final List<JournalEntryTemplateData> templates;

  @override
  Stream<List<JournalEntryData>> watchJournalEntries({
    DateTime? from,
    DateTime? to,
  }) =>
      Stream.value(const []);

  @override
  Future<List<Account>> getAllAccounts() async => accounts;

  @override
  Future<List<CostCenter>> getCostCenters() async => costCenters;

  @override
  Future<List<CostCenter>> getActiveCostCenters() async => costCenters;

  @override
  Stream<List<CostCenter>> watchCostCenters() => Stream.value(costCenters);

  @override
  Stream<List<JournalEntryTemplateData>> watchActiveTemplates() =>
      Stream.value(templates);

  @override
  Future<List<Map<String, dynamic>>> getTemplateLinesWithAccounts(int id) async =>
      const [];

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

CostCenter _cc(int id, String code, String name) => CostCenter(
      id: id,
      code: code,
      name: name,
      parentId: null,
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
  final centers = [_cc(1, 'CC1', 'الفرع الرئيسي')];

  Future<void> pump(
    WidgetTester tester,
    double width, {
    _FakeAccountingRepo? repo,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountingRepositoryProvider.overrideWithValue(
            repo ??
                _FakeAccountingRepo(accounts: accounts, costCenters: centers),
          ),
          // ⚠️ الشريطُ يقرأ الفروعَ من القاعدة مباشرةً — بلا هذا يُطلَب
          //    `databaseProvider` فينهار الاختبارُ قبل أن يُقاس حوار.
          allBranchesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: JournalEntriesPicPosScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// تفكيكُ الشجرةِ ثمّ دفعُ إطارٍ — بلا هذا تعلّق الاختباراتُ على مؤقّتات.
  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  Future<void> openCreateDialog(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'قيد يدوي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    group('عرض $w', () {
      testWidgets('الشاشةُ تُبنى وتحمل زرَّي الحوارَين', (tester) async {
        await pump(tester, width);

        expect(find.text('قيود اليومية'), findsWidgets);
        expect(find.widgetWithText(FilledButton, 'قيد يدوي'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'من قالب'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('«قيد يدوي» يفتح حوارَ الإنشاء ببنديه وشريطِ التوازن',
          (tester) async {
        await pump(tester, width);
        await openCreateDialog(tester);

        expect(find.text('إنشاء قيد يدوي'), findsOneWidget);
        expect(find.text('بنود القيد'), findsOneWidget);
        // بندان افتراضيّان — لا واحدٌ ولا صفر.
        expect(find.text('بند 1'), findsOneWidget);
        expect(find.text('بند 2'), findsOneWidget);
        expect(find.text('بند 3'), findsNothing);
        // القيدُ الفارغُ **غيرُ** متوازنٍ — والزرُّ معطَّلٌ تبعاً لذلك.
        expect(find.text('غير متوازن!'), findsOneWidget);
        // ⚠️ كان «حفظ القيد». وقرارُ مالك 2026-08-27 ألغى الترحيلَ الفوريَّ
        //    من هذا الحوار، فصار مسارُ الحفظ واحداً يُنتج مسودّة.
        expect(find.text('حفظ كمسودة'), findsOneWidget);
        expect(find.text('حفظ القيد'), findsNothing);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('«من قالب» يفتح حوارَ القوالب ويعرض القوالبَ النشطة',
          (tester) async {
        await pump(
          tester,
          width,
          repo: _FakeAccountingRepo(
            accounts: accounts,
            costCenters: centers,
            templates: [
              _tpl(1, 'قيد الرواتب الشهري', 'يُرحّل رواتبَ الشهر'),
              _tpl(2, 'قيد الإيجار', null),
            ],
          ),
        );

        await tester.tap(find.widgetWithText(OutlinedButton, 'من قالب'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('اختيار قالب قيد'), findsOneWidget);
        expect(find.text('قيد الرواتب الشهري'), findsOneWidget);
        expect(find.text('قيد الإيجار'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('وحوارُ القوالبِ الفارغُ يقول ذلك بدل شاشةٍ بيضاء',
          (tester) async {
        await pump(tester, width);

        await tester.tap(find.widgetWithText(OutlinedButton, 'من قالب'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('اختيار قالب قيد'), findsOneWidget);
        expect(find.text('لا توجد قوالب نشطة مسجلة.'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('الإلغاءُ بلا بياناتٍ يغلق الحوارَ بلا تحذير',
          (tester) async {
        await pump(tester, width);
        await openCreateDialog(tester);

        await tester.tap(find.widgetWithText(TextButton, 'إلغاء'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('تنبيه'), findsNothing);
        expect(find.text('إنشاء قيد يدوي'), findsNothing);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('والإلغاءُ بعد كتابةِ وصفٍ يُحذّر — و«لا، البقاء» يُبقيه',
          (tester) async {
        await pump(tester, width);
        await openCreateDialog(tester);

        await tester.enterText(
          find.widgetWithText(TextField, 'وصف القيد'),
          'قيد تسوية شهر أغسطس',
        );
        await tester.pump();

        await tester.tap(find.widgetWithText(TextButton, 'إلغاء'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // ⚠️ حارسُ U-03: بياناتٌ غيرُ محفوظةٍ ⇒ تأكيدٌ قبل الإغلاق.
        expect(find.text('تنبيه'), findsOneWidget);
        expect(
          find.text('يوجد بيانات غير محفوظة في القيد. هل أنت متأكد من الإلغاء؟'),
          findsOneWidget,
        );
        expect(find.text('لا، البقاء'), findsOneWidget);
        expect(find.text('نعم، إلغاء'), findsOneWidget);

        await tester.tap(find.text('لا، البقاء'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // الرفضُ يُبقي حوارَ الإنشاءِ مفتوحاً — لا يبتلع القيد.
        expect(find.text('تنبيه'), findsNothing);
        expect(find.text('إنشاء قيد يدوي'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('و«نعم، إلغاء» يُغلق الحوارَين معاً', (tester) async {
        await pump(tester, width);
        await openCreateDialog(tester);

        await tester.enterText(
          find.widgetWithText(TextField, 'وصف القيد'),
          'قيد تسوية شهر أغسطس',
        );
        await tester.pump();

        await tester.tap(find.widgetWithText(TextButton, 'إلغاء'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        await tester.tap(find.text('نعم، إلغاء'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('تنبيه'), findsNothing);
        expect(find.text('إنشاء قيد يدوي'), findsNothing);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });
    });
  }
}
