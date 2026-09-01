// test/widget/bank_reconciliation_picpos_screen_test.dart
//
// تركيبُ شاشة «المطابقة البنكية» بهويّة PicPos — بعرضَين.
//
// ⚠️ **العرضان ليسا احتياطاً**: القائمتان المتجاورتان أوّلُ ما ينهار ضيقاً،
// وشاشاتٌ كاملةٌ انهارت من تركيبٍ لم يُقَس عند عرضَين.
//
// ⚠️ **وخزنةٌ بلا حسابٍ مرتبطٍ تُقصى بسطرٍ يشرح** — بلا حسابٍ لا دفترَ
// يُطابَق عليه، والصمتُ يجعلها تبدو مفقودة.
//
// ⚠️ **ولا اختيارَ تلقائيّاً لأيّ خزنة** (مراجعةٌ 2026-09-01، مأخذ ٢):
// الشاشةُ تبدأ بلا خزنةٍ مختارة، فاختبارُ الإقصاء يفتح المنتقيَ فعلاً
// (مأخذ ٧) بدل الاتّكال على اختيارٍ تلقائيٍّ يُظهر اسمَ خزنةٍ بلا تفاعل.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart' show excelServiceProvider;
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/data/services/excel_service.dart' show BankStatementRowsSummary;
import 'package:ural_erp/domain/repositories/accounting_repository.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/presentation/accounting_picpos/bank_reconciliation_picpos_screen.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_hub_kpi.dart';

// نمطُ المزيَّفات من `test/widget/analytics_picpos_screen_test.dart`:
// صنفٌ `implements` الواجهةَ، الدوالُّ المستعمَلةُ صريحةً بـ`@override`
// تعيد بياناتٍ ثابتة، و`noSuchMethod` احتياطاً للباقي — لأنّ الافتراضيَّ
// **يرمي** فيتعلّق المنتظِر.

/// خزنةٌ بنكيّة — `linked` هو `linkedAccountId`.
SafeData _bankSafe(int id, {required int? linked, String? name}) {
  return SafeData(
    id: id,
    name: name ?? 'خزنة بنكية $id',
    safeType: 'bank',
    balance: 0,
    isDefault: false,
    isActive: true,
    linkedAccountId: linked,
  );
}

class _FakeTreasury implements ITreasuryRepository {
  _FakeTreasury(this._safes);
  final List<SafeData> _safes;

  @override
  Future<List<SafeData>> getSafesList() async => _safes;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// مزيَّفٌ يلتقط الحسابَ الذي وصله `createReconciliation`، ويعيد تقريراً
/// قابلاً للتخصيص من `getReconciliationReport` — لقياسِ أنّ بطاقاتِ
/// المؤشّرات تعرض **قيمَ الخريطة المزيَّفة** لا أرقاماً ثابتةً في الشاشة.
class _FakeAccounting implements IAccountingRepository {
  _FakeAccounting({
    Map<String, dynamic>? report,
    this.sessionId = 1,
    this.autoMatchResult = 0,
  }) : report = report ??
            const {
              'reconciliation': null,
              'statementBalance': 1000.0,
              'bookBalance': 1000.0,
              'difference': 0.0,
              'matchedCount': 0,
              'unmatchedCount': 0,
              'matchedLines': <dynamic>[],
              'unmatchedBankLines': <dynamic>[],
              'outstandingBookEntries': <dynamic>[],
            };

  final Map<String, dynamic> report;
  final int sessionId;
  final int autoMatchResult;

  int? createdBankAccountId;
  double? createdStatementBalance;
  int autoMatchCalls = 0;
  int? autoMatchedBankAccountId;
  int? importedBankAccountId;
  List<Map<String, dynamic>>? importedLines;
  String? importedBatchId;

  @override
  Future<int> createReconciliation({
    required int bankAccountId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double statementBalance,
    int? userId,
  }) async {
    createdBankAccountId = bankAccountId;
    createdStatementBalance = statementBalance;
    return sessionId;
  }

  @override
  Future<Map<String, dynamic>> getReconciliationReport(
          int reconciliationId) async =>
      report;

  @override
  Future<int> importBankStatementLines({
    required int bankAccountId,
    required List<Map<String, dynamic>> lines,
    required String batchId,
  }) async {
    importedBankAccountId = bankAccountId;
    importedLines = lines;
    importedBatchId = batchId;
    return lines.length;
  }

  @override
  Future<int> autoMatchStatementLines(int bankAccountId) async {
    autoMatchCalls++;
    autoMatchedBankAccountId = bankAccountId;
    return autoMatchResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// مزيَّفُ `ExcelService` — بلا `implements`: `excelServiceProvider` من نوع
/// `Provider<dynamic>` فيقبل أيَّ كائن (مأخوذٌ من
/// `financial_statements_picpos_screen.dart`)، والدالّتان المستعمَلتان من
/// هذه الشاشة فقط هما `exportBankStatementTemplate` و
/// `pickAndParseBankStatement` — لا حاجةَ لتزييف الصنف الحقيقيّ كاملاً.
class _FakeExcelService {
  _FakeExcelService({this.parseResult});

  final BankStatementRowsSummary? parseResult;

  Future<String?> exportBankStatementTemplate() async =>
      'C:/tmp/template.xlsx';

  Future<BankStatementRowsSummary?> pickAndParseBankStatement() async =>
      parseResult;
}

Future<void> pump(WidgetTester tester, double width, {
  required List<SafeData> safes,
  IAccountingRepository? accounting,
  Object? excelService,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        treasuryRepositoryProvider.overrideWithValue(_FakeTreasury(safes)),
        accountingRepositoryProvider
            .overrideWithValue(accounting ?? _FakeAccounting()),
        excelServiceProvider
            .overrideWithValue(excelService ?? _FakeExcelService()),
      ],
      child: const MaterialApp(home: BankReconciliationPicposScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // مراجعةٌ 2026-09-01 (مأخذ أ) — الفاصلةُ تُقبَل في مواضع الآلاف فقط.
  //
  // ⚠️ `1500,50` فاصلةٌ عشريّةٌ أوروبيّة، لا فاصلةَ آلاف — وكانت
  // `replaceAll(',', '')` تجرّدها بلا فحص موضعٍ فتُنتج `150050` (مئةَ
  // ضعف) بلا خطأٍ ولا تنبيه. القياسُ هنا على الدالّة النقيّة مباشرةً —
  // أسرعُ وأدقّ من دورة واجهةٍ كاملةٍ لكلّ حالة.
  // ═══════════════════════════════════════════════════════════════════════
  group('parseStatementBalance — الفاصلةُ في مواضع الآلاف فقط', () {
    test('1,000.00 — فاصلةُ آلافٍ في موضعها ⇒ 1000.0', () {
      expect(parseStatementBalance('1,000.00'), 1000.0);
    });

    test('15,300.50 — مجموعتا آلافٍ صحيحتان ⇒ 15300.5', () {
      expect(parseStatementBalance('15,300.50'), 15300.5);
    });

    test('🔴 1500,50 — فاصلةٌ عشريّةٌ أوروبيّة ⇒ null، لا 150050', () {
      final result = parseStatementBalance('1500,50');
      expect(result, isNull,
          reason: 'لو جرّدنا الفاصلةَ بلا فحص موضعٍ لخرج 150050 — مئةَ '
              'ضعفٍ عن القيمة الحقيقيّة، وهو عينُ العطب المُبلَّغ عنه');
    });

    test('🔴 1.000,50 — تدوينٌ أوروبيّ (نقطةُ آلافٍ وفاصلةٌ عشريّة) ⇒ null',
        () {
      expect(parseStatementBalance('1.000,50'), isNull);
    });

    test('0 — رصيدٌ بنكيٌّ صفريٌّ يبقى مقبولاً', () {
      expect(parseStatementBalance('0'), 0.0);
    });

    test('نصٌّ فارغٌ ⇒ null', () {
      expect(parseStatementBalance(''), isNull);
      expect(parseStatementBalance('   '), isNull);
    });
  });

  for (final width in [1280.0, 1920.0]) {
    testWidgets('الشاشةُ تُرسَم بلا فيضان عند ${width.toInt()}', (tester) async {
      await pump(tester, width, safes: [_bankSafe(1, linked: 5)]);

      expect(tester.takeException(), isNull);
      expect(find.text('المطابقة البنكية'), findsWidgets);
    });
  }

  testWidgets('🔴 خزنةٌ بلا حسابٍ مرتبطٍ تُقصى بسطرٍ يشرح', (tester) async {
    await pump(tester, 1920, safes: [
      _bankSafe(1, linked: 5, name: 'البنك الأهلي'),
      _bankSafe(2, linked: null, name: 'بنك بلا ربط'),
    ]);

    // سطرُ الشرح بنصّه الكامل — لا مطابقةً جزئيّةً على كلمة «حساب» يُرضيها
    // أيُّ نصٍّ مستقبليٍّ (مأخذ ٨: `find.textContaining` توكيدٌ ضعيف).
    expect(
      find.text('خزنةٌ بنكيّةٌ أو أكثرُ بلا حسابٍ مرتبطٍ — لا يمكن مطابقتُها'),
      findsOneWidget,
      reason: 'والإقصاءُ يُشرَح لا يُصمَت عليه',
    );

    // المرساةُ الحقيقيّة: بلا اختيارٍ تلقائيّ (مأخذ ٢)، لا اسمَ خزنةٍ يُرسَم
    // على الشاشة إطلاقاً قبل فتح المنتقي — فالاختبارُ يفتحه فعلاً وينظر
    // داخله (مأخذ ٧)، لا أن يتّكل على اختيارٍ تلقائيٍّ يُظهر اسماً بلا تفاعل.
    await tester.tap(find.text('اختر خزنة بنكية'));
    await tester.pumpAndSettle();

    expect(find.text('البنك الأهلي'), findsWidgets,
        reason: 'مرساة: المربوطةُ تظهر كخيارٍ داخل المنتقي');
    expect(find.text('بنك بلا ربط'), findsNothing,
        reason: 'بلا حسابٍ لا دفترَ يُطابَق عليه — فلا تظهر كخيار');
  });

  testWidgets('إنشاءُ جلسةٍ يعرض مؤشّراتِ التقرير الأربعة بقيمها الحقيقيّة',
      (tester) async {
    final accounting = _FakeAccounting(
      sessionId: 7,
      report: const {
        'reconciliation': null,
        'statementBalance': 15300.50,
        'bookBalance': 15250.75,
        'difference': 49.75,
        'matchedCount': 12,
        'unmatchedCount': 3,
        'matchedLines': <dynamic>[],
        'unmatchedBankLines': <dynamic>[],
        'outstandingBookEntries': <dynamic>[],
      },
    );

    await pump(
      tester,
      1920,
      safes: [_bankSafe(9, linked: 42, name: 'خزنة الاختبار')],
      accounting: accounting,
    );

    // اختيارُ الخزنة من المنتقي الحقيقيّ — لا حقن حالةٍ مباشرة.
    await tester.tap(find.text('اختر خزنة بنكية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خزنة الاختبار'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();

    // رصيدُ كشفٍ صالح — بصيغة الفاصلة العشرالفيّة التي تعرضها الشاشةُ
    // نفسُها (مأخذ ٣: يجب أن تُقبَل لا أن تُرفَض بصفرٍ صامت).
    await tester.enterText(find.byType(TextField), '15,300.50');
    await tester.pumpAndSettle();

    await tester.tap(find.text('جلسة جديدة'));
    await tester.pumpAndSettle();

    expect(accounting.createdBankAccountId, 42,
        reason: 'الجلسةُ يجب أن تُفتَح على حساب الخزنة المختارة لا خزنةٍ '
            'أخرى');
    expect(accounting.createdStatementBalance, 15300.50,
        reason: 'رصيدُ الكشف المُدخَل بفاصلةٍ يجب أن يُحلَّل صحيحاً — لا '
            'يسقط إلى صفرٍ صامت');

    // ⚠️ **مأخذ ب (مراجعة 2026-09-01): محصورةٌ داخل `PicPosHubKpiRow`.**
    // حقلُ رصيد الكشف يحمل نصَّ الإدخال نفسَه `'15,300.50'` (الذي كتبناه
    // أعلاه)، فتوكيدٌ بلا حصرٍ يمرّ حتى لو غابت بطاقةُ «رصيد الكشف»
    // تماماً — لأنّ `EditableText` الحقلِ يطابقه وحدَه. الحصرُ يجعل
    // التوكيدَ قادراً على السقوط فعلاً.
    final kpiRow = find.byType(PicPosHubKpiRow);
    expect(kpiRow, findsOneWidget,
        reason: 'صفُّ المؤشّرات نفسُه يجب أن يظهر بعد إنشاء الجلسة');

    expect(
      find.descendant(of: kpiRow, matching: find.text('15,250.75')),
      findsWidgets,
      reason: 'رصيدُ الدفتر يجب أن يأتي من `getReconciliationReport` '
          'المزيَّف',
    );
    expect(
      find.descendant(of: kpiRow, matching: find.text('15,300.50')),
      findsWidgets,
      reason: 'رصيدُ الكشف يجب أن يأتي من التقرير المزيَّف — لا من حقل '
          'الإدخال',
    );
    expect(
      find.descendant(of: kpiRow, matching: find.text('49.75')),
      findsWidgets,
      reason: 'الفرقُ يجب أن يأتي من التقرير المزيَّف',
    );
    expect(
      find.descendant(of: kpiRow, matching: find.text('12 / 3')),
      findsWidgets,
      reason: 'مطابَق/غيرُ مطابَق يجب أن يأتيا من التقرير المزيَّف',
    );
  });

  testWidgets(
      '🔴 رصيدٌ بفاصلةٍ عشريّةٍ أوروبيّة يُظهر خطأ الإدخال ويُعطِّل الزرّ',
      (tester) async {
    await pump(tester, 1920,
        safes: [_bankSafe(3, linked: 11, name: 'خزنة الفاصلة الأوروبية')]);

    await tester.tap(find.text('اختر خزنة بنكية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خزنة الفاصلة الأوروبية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();

    // فاصلةٌ عشريّةٌ أوروبيّة — نفسُ حالة المأخذ أ، لكن مقيسةً عبر الواجهة
    // كاملةً كما طلب المنسّق: خطأُ الإدخال يُعرَض والزرُّ يُعطَّل فعلاً.
    await tester.enterText(find.byType(TextField), '1500,50');
    await tester.pumpAndSettle();

    expect(find.text('قيمةٌ غيرُ صالحة'), findsOneWidget,
        reason: 'خطأُ الإدخال يجب أن يُقال — لا صمتَ ولا سقوطٌ إلى صفر');

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'جلسة جديدة'),
    );
    expect(button.onPressed, isNull,
        reason: 'زرُّ «جلسة جديدة» يجب أن يبقى معطَّلاً على قيمةٍ غيرِ '
            'صالحة — لا أن يُنشئ جلسةً برصيدٍ مئةَ ضعفٍ');
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المهمّةُ ٥ — الشريطُ الثلاثيّ: تنزيلُ القالب · استيرادُ كشفٍ ·
  // مطابقةٌ آليّة.
  //
  // ⚠️ **`ImportResult` غيرُ مستعمَلةٍ هنا عمداً**: الموجزُ الأصليُّ افترض
  // `excelService.importBankStatement` تعيد `ImportResult` — وهذا نصٌّ بائد.
  // الحقيقةُ المشحونة (المهمّةُ ٣، الكوميت 31d5aa3c): `ExcelService` يأخذ
  // مستوداتٍ لا قاعدة، و`pickAndParseBankStatement` **تحلّل ولا تكتب** —
  // الكتابةُ على الشاشة بالمستودع الذي بيدها (`importBankStatementLines`).
  // ═══════════════════════════════════════════════════════════════════════

  testWidgets('🔴 «مطابقة آلية» تُنادي المحرّكَ وتقول العدد', (tester) async {
    final accounting = _FakeAccounting(autoMatchResult: 3);
    await pump(tester, 1920,
        safes: [_bankSafe(1, linked: 5, name: 'خزنة المطابقة')],
        accounting: accounting);

    // اختيارُ الخزنة أوّلاً — الأزرارُ الثلاثةُ معطَّلةٌ بلا حسابٍ مختار.
    await tester.tap(find.text('اختر خزنة بنكية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خزنة المطابقة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('مطابقة آلية'));
    await tester.pumpAndSettle();

    expect(accounting.autoMatchCalls, 1,
        reason: 'الزرُّ كان يُظهر إشعاراً فقط — الآن يجب أن ينادي المحرّك');
    expect(accounting.autoMatchedBankAccountId, 5,
        reason: 'المطابقةُ تقع على حساب الخزنة المختارة');
    // العددُ بالأرقام العربيّة — «تمّت» بلا رقمٍ لا تُخبر المحاسبَ بشيء.
    expect(find.text('طوبق ٣ سطراً'), findsOneWidget,
        reason: 'والعددُ يُقال — لا صمتَ عمّا طابقَه المحرّك');

    // ⚠️ مؤقّتُ `AppToast` ٢٥٠٠ms ثمّ ٣٠٠ms خروجاً — تفكيكُ الشجرة قبل
    // انقضائه يُسقط الاختبارَ بـ«A Timer is still pending» (نمطٌ مأخوذٌ من
    // `journal_entry_draft_dialog_test.dart`).
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('🔴 إخفاقُ الاستيراد يُقال بسببه — لا يُبتلَع في «تعذّرت العمليّة»',
      (tester) async {
    final excelService = _FakeExcelService(
      parseResult: const BankStatementRowsSummary(
        <Map<String, dynamic>>[],
        <String>['الصفُّ ٢: تاريخٌ غيرُ صالح'],
      ),
    );
    await pump(tester, 1920,
        safes: [_bankSafe(4, linked: 8, name: 'خزنة الاستيراد')],
        excelService: excelService);

    await tester.tap(find.text('اختر خزنة بنكية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خزنة الاستيراد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('استيراد كشف'));
    await tester.pumpAndSettle();

    // سببُ الرفضِ نفسُه — لا مطابقةً جزئيّةً على «تعذّرت» قد يُرضيها نصٌّ
    // عامٌّ مستقبليّ.
    expect(find.text('لا صفَّ صالحاً في الملف: الصفُّ ٢: تاريخٌ غيرُ صالح'),
        findsOneWidget,
        reason: 'سببُ الرفض من التحليل يصل الشاشةَ كما هو');
    // ⚠️ مراجعة 2026-09-01 (مأخذ ١): «تعذّرت العمليّة» نصٌّ لا وجودَ له في
    // `lib` إطلاقاً — الرسالةُ العامّةُ الفعليّةُ عند استثناءٍ حقيقيٍّ هي
    // 'تعذّر استيرادُ الكشف: $e' (‏`screen.dart`، فرعُ `catch`). وهذا
    // الاختبارُ يسلك فرعَ «لا صفَّ صالحاً» فلا يبلغ ذلك الفرعَ أصلاً — لكنّ
    // التوكيدَ يجب أن ينفي الرسالةَ **الحقيقيّة** لا نصّاً وهميّاً لا يظهر
    // أبداً مهما كتب الكودُ.
    expect(find.textContaining('تعذّر استيرادُ الكشف'), findsNothing,
        reason: 'لا يُختصَر السببُ إلى رسالةٍ عامّةٍ تُخفي ما حدث فعلاً');

    // ⚠️ نفسُ مؤقّتِ `AppToast` أعلاه.
    await tester.pump(const Duration(seconds: 4));
  });

  // ═══════════════════════════════════════════════════════════════════════
  // مراجعةٌ 2026-09-01 (مأخذ ٢) — متطلَّبُ المهمّة المركزيّ (الكتابةُ
  // بالمستودع) كان يُشحَن بلا مرساةٍ تثبت أنّ الاستخراجَ يعمل: الاختبارُ
  // الوحيدُ للاستيراد كان يسلك فرعَ `lines.isEmpty` الذي لا يبلغ
  // `importBankStatementLines` أصلاً. هذا اختبارُ النجاح الجزئيّ — أصعبُ
  // الحالات (سطرٌ مُدرَجٌ وآخرُ مرفوضٌ معاً) — يقيس المستودعَ نفسَه.
  // ═══════════════════════════════════════════════════════════════════════

  testWidgets(
      '🔴 استيرادٌ ناجحٌ جزئيّاً يكتب بالمستودع على حساب الخزنة، بدفعةٍ '
      'فريدة، ويقولها كاملة', (tester) async {
    final accounting = _FakeAccounting();
    final excelService = _FakeExcelService(
      parseResult: const BankStatementRowsSummary(
        <Map<String, dynamic>>[
          {
            'date': '2026-05-10',
            'reference': 'REF-1',
            'description': 'إيداع نقدي',
            'debit': 0.0,
            'credit': 500.0,
          },
          {
            'date': '2026-05-11',
            'reference': 'REF-2',
            'description': 'سحب',
            'debit': 200.0,
            'credit': 0.0,
          },
        ],
        <String>['الصفُّ ٤: تاريخٌ غيرُ صالح'],
      ),
    );
    await pump(tester, 1920,
        safes: [_bankSafe(6, linked: 77, name: 'خزنة الاستيراد الجزئي')],
        accounting: accounting,
        excelService: excelService);

    await tester.tap(find.text('اختر خزنة بنكية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خزنة الاستيراد الجزئي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('استيراد كشف'));
    await tester.pumpAndSettle();

    // مرساةٌ تفرّق معرّفَ الحساب عن معرّف الخزنة: الخزنةُ ٦، والحسابُ
    // المرتبطُ ٧٧ — فالاختبارُ يسقط فعلاً لو نودِيَ المستودعُ بمعرّف
    // الخزنة سهواً بدل حسابها.
    expect(accounting.importedBankAccountId, 77,
        reason: 'الكتابةُ تقع على حساب الخزنة المرتبط — لا معرّف الخزنة '
            'نفسِها');
    expect(accounting.importedLines?.length, 2,
        reason: 'السطران الصالحان فقط يصلان المستودع — لا الرفوضُ معهما');
    expect(accounting.importedBatchId, isNotEmpty,
        reason: 'batchId فريدٌ لكلّ دفعة — لا فارغٌ ولا مُهمَل');

    // النصُّ الكاملُ المركَّب كما يراه المستخدم — المُدرَجُ والمرفوضُ
    // وسببُه معاً، لا جزءٌ منه.
    expect(
      find.text('استُورد ٢ سطراً، ورُفض ١: الصفُّ ٤: تاريخٌ غيرُ صالح'),
      findsOneWidget,
      reason: 'الرسالةُ تبنيها الشاشةُ من عددَي الإدراج والرفض وسببِه — لا '
          'رسالةٍ ثابتة',
    );

    await tester.pump(const Duration(seconds: 4));
  });
}
