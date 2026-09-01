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
import 'package:ural_erp/data/database/database.dart' as db;
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/providers.dart' show excelServiceProvider;
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/data/services/excel_service.dart' show BankStatementRowsSummary;
import 'package:ural_erp/domain/repositories/accounting_repository.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/presentation/accounting_picpos/bank_reconciliation_picpos_screen.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_dialog.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_hub_kpi.dart';

// ⚠️ **`db.BankStatementLine` هنا لا في الشاشة**: الشاشةُ تقرأ عناصرَ
// القوائمِ الثلاثِ ديناميكيّاً (`avoid_dynamic_calls` مُلغًى فيها عمداً) —
// فلا تستورد `data/database/database.dart` مطلقاً؛ حارسُ
// `presentation_db_import_guard_test.dart` يمنع أيَّ ملفّ عرضٍ **جديد**
// من ذلك، وهذا الملفُّ ليس في القائمة البيضاء. أمّا اختبارُ ودجتٍ فخارجَ
// نطاق ذلك الحارس (يفحص `lib/presentation` فقط)، فاستيرادُ النوع الحقيقيّ
// هنا آمنٌ ومطابقٌ لنمط ملفّاتٍ أخرى (`fixed_assets_picpos_screen_test.dart`).

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

/// شبيهٌ لصفّ `QueryRow` — يحمل `.data` فقط، وهو كلُّ ما تقرؤه الشاشةُ من
/// `outstandingBookEntries` (نداءٌ ديناميكيّ). بناءُ `QueryRow` الحقيقيّ
/// يحتاج `DatabaseConnectionUser` داخليّاً؛ وهذا الشبيهُ يغني عنه لأنّ
/// الشاشةَ لا تستعمل من الصفّ غيرَ `.data['...']`.
class _FakeQueryRow {
  const _FakeQueryRow(this.data);
  final Map<String, dynamic> data;
}

/// تقريرٌ افتراضيٌّ واقعيٌّ — سطرُ كشفٍ غيرُ مطابَقٍ (`REF-1`)، وقيدُ دفترٍ
/// معلَّقٌ («قيد الإيداع»)، وسطرٌ مطابَقٌ سلفاً (لزرّ «نزع»). اختباراتُ
/// المهمّة ٦ (القائمتان والمطابقةُ اليدويّة) تحتاج بياناتٍ حقيقيّةً في
/// المفاتيح الثلاثة — لا قوائمَ فارغةً كسابقتها.
Map<String, dynamic> _sampleReconciliationReport() {
  // ⚠️ **مراجعةٌ — مأخذ ١**: `entry_date` بختمٍ صحيحٍ (ثوانٍ منذ الإبوك)
  // لا نصِّ ISO. النوعُ الفعليُّ القادمُ من `customSelect` هو `int`
  // (`lib/data/database/database.dart`: `dateVar` تكتب
  // `Variable<int>(dt.millisecondsSinceEpoch ~/ 1000)`، ولا تحويلَ درِفتيّ
  // على نتيجة `customSelect` الخامّة). نصٌّ حرفيٌّ هنا كان يُخفي عطباً
  // إنتاجيّاً حقيقيّاً: الشاشةُ لم تكن تعالج فرعَ `int` إطلاقاً، فكان هذا
  // المزيَّفُ يقيس شكلاً لا يُنتجه المحرّكُ أبداً.
  //
  // ⚠️ **٥/١١ لا ٥/١٠ عمداً — تفادي تصادمٍ صامت**: `REF-1` أدناه
  // بتاريخٍ `2026-05-10` أيضاً (عمودٌ منسوخٌ عن `l.transactionDate`
  // مباشرةً لا عن `_fmtEntryDate`)؛ فلو تطابق التاريخان لمرّ اختبارُ
  // «عمودُ تاريخِ الدفتر» حتى لو أخفقت `_fmtEntryDate` في فرع `int` —
  // لأنّ عمودَ الكشف كان سيُظهر «2026-05-10» بمعزلٍ عن عمود الدفتر.
  // اكتشفتُ هذا بطفرةٍ فعليّة (حذفُ فرع `int`) لم تُسقط الاختبارَ.
  final entryDateEpoch = DateTime(2026, 5, 11).millisecondsSinceEpoch ~/ 1000;
  return {
    'reconciliation': null,
    'statementBalance': 1000.0,
    'bookBalance': 1000.0,
    'difference': 0.0,
    'matchedCount': 1,
    'unmatchedCount': 1,
    'matchedLines': <dynamic>[
      db.BankStatementLine(
        id: 10,
        bankAccountId: 5,
        transactionDate: DateTime(2026, 5, 9),
        reference: 'REF-0',
        description: 'إيداعٌ مطابَقٌ سلفاً',
        debitAmount: 0,
        creditAmount: 300,
        runningBalance: 300,
        isMatched: true,
        matchedJournalLineId: 4,
        matchType: 'manual',
        createdAt: DateTime(2026, 5, 9),
      ),
    ],
    'unmatchedBankLines': <dynamic>[
      db.BankStatementLine(
        id: 3,
        bankAccountId: 5,
        transactionDate: DateTime(2026, 5, 10),
        reference: 'REF-1',
        description: 'إيداع نقدي',
        debitAmount: 0,
        creditAmount: 500,
        runningBalance: 800,
        isMatched: false,
        createdAt: DateTime(2026, 5, 10),
      ),
    ],
    'outstandingBookEntries': <dynamic>[
      _FakeQueryRow({
        'id': 7,
        'entry_id': 1,
        'account_id': 5,
        'debit': 0.0,
        'credit': 500.0,
        'entry_date': entryDateEpoch,
        'entry_desc': 'قيد الإيداع',
      }),
    ],
  };
}

/// مزيَّفٌ يلتقط الحسابَ الذي وصله `createReconciliation`، ويعيد تقريراً
/// قابلاً للتخصيص من `getReconciliationReport` — لقياسِ أنّ بطاقاتِ
/// المؤشّرات تعرض **قيمَ الخريطة المزيَّفة** لا أرقاماً ثابتةً في الشاشة.
class _FakeAccounting implements IAccountingRepository {
  _FakeAccounting({
    Map<String, dynamic>? report,
    this.sessionId = 1,
    this.autoMatchResult = 0,
    this.manualMatchThrows,
    this.reportAfterAutoMatch,
  }) : report = report ?? _sampleReconciliationReport();

  final Map<String, dynamic> report;
  final int sessionId;
  final int autoMatchResult;

  /// إن وُضعت، تُعاد بدل [report] بعد أوّل «مطابقة آلية» — لمحاكاة سطرِ
  /// كشفٍ طوبق فاختفى من `unmatchedBankLines` (مراجعةٌ 2026-09-01، مأخذ ٨‑ج).
  final Map<String, dynamic>? reportAfterAutoMatch;

  /// إن وُضعت، يرميها `manualMatchStatement` بدل أن يسجّل — لقياس مطابقةٍ
  /// مكرّرةٍ (المحرّكُ يرمي `StateError` تسمّي السطرَ الآخر).
  ///
  /// ⚠️ **`unmatchStatement`/`completeReconciliation` بلا نظيرٍ للرمي
  /// عمداً**: لا اختبارَ في هذا الملفّ يقيس فشلَهما، وحقلٌ لا يُقرأ إلّا
  /// من مكانٍ واحدٍ لن يُستدعى منه أبداً هو كودٌ ميّت يرصده `analyze`
  /// (‏`unused_element_parameter`) — يُضاف حين يحتاجه اختبارٌ فعليّ.
  final Object? manualMatchThrows;

  int? createdBankAccountId;
  double? createdStatementBalance;
  DateTime? createdPeriodStart;
  DateTime? createdPeriodEnd;

  /// ⚠️ **مراجعةٌ 2026-09-01، مأخذ ٥**: `createReconciliation` تقبل
  /// `int? userId` والشاشةُ لم تكن تمرّره — فـ`preparedBy` فارغٌ في كلّ
  /// جلسة. و`0` ليس القيمةَ الافتراضيّة هنا عمداً: `null` هو ما كان يصل،
  /// فالتوكيدُ يفرّق بين «لم يُمرَّر» و«مُرِّر صفراً».
  int? createdUserId;
  bool createCalled = false;
  int autoMatchCalls = 0;
  int? autoMatchedBankAccountId;
  int? importedBankAccountId;
  List<Map<String, dynamic>>? importedLines;
  String? importedBatchId;

  int manualMatchCalls = 0;
  int? manualMatchStatementLineId;
  int? manualMatchJournalLineId;

  int unmatchCalls = 0;
  int? unmatchedStatementLineId;

  int completeCalls = 0;
  int? completedReconciliationId;

  /// عددُ استدعاءات `getReconciliationReport` — يثبت أنّ `ref.invalidate`
  /// أعاد الاستعلامَ فعلاً بعد مطابقةٍ/نزعٍ/إقفال، لا مجرّد أنّ الشاشةَ لم
  /// تنهر (مراجعةٌ — مأخذ ٤).
  int getReportCalls = 0;

  /// معرّفاتُ الجلسات التي طُلب تقريرُها — تفرّق «فُتح تقريرُ الجلسة القائمة»
  /// عن «فُتح تقريرُ جلسةٍ أُنشئت للتوّ»، وهو عينُ ما يقيسه اختبارُ الاستئناف.
  final List<int> reportedSessionIds = [];

  /// جلساتٌ قائمةٌ يعيدها `getReconciliationSessions` — فارغةٌ افتراضاً كي
  /// تبقى كلُّ الاختبارات القديمةِ على سلوكها (‏«جلسة جديدة»).
  List<db.BankReconciliationData> openSessions = const [];

  @override
  Future<List<db.BankReconciliationData>> getReconciliationSessions() async =>
      openSessions;

  @override
  Future<int> createReconciliation({
    required int bankAccountId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double statementBalance,
    int? userId,
  }) async {
    createCalled = true;
    createdBankAccountId = bankAccountId;
    createdStatementBalance = statementBalance;
    createdPeriodStart = periodStart;
    createdPeriodEnd = periodEnd;
    createdUserId = userId;
    return sessionId;
  }

  @override
  Future<Map<String, dynamic>> getReconciliationReport(
      int reconciliationId) async {
    getReportCalls++;
    reportedSessionIds.add(reconciliationId);
    final after = reportAfterAutoMatch;
    if (after != null && autoMatchCalls > 0) return after;
    return report;
  }

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
  Future<void> manualMatchStatement({
    required int statementLineId,
    required int journalLineId,
  }) async {
    manualMatchCalls++;
    manualMatchStatementLineId = statementLineId;
    manualMatchJournalLineId = journalLineId;
    final throws = manualMatchThrows;
    if (throws != null) throw throws;
  }

  @override
  Future<void> unmatchStatement(int statementLineId) async {
    unmatchCalls++;
    unmatchedStatementLineId = statementLineId;
  }

  @override
  Future<void> completeReconciliation(int reconciliationId) async {
    completeCalls++;
    completedReconciliationId = reconciliationId;
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

/// مستخدمٌ مسجَّلٌ رقمُه [_signedInUserId] — نمطُ
/// `journal_entry_draft_dialog_test.dart`.
///
/// ⚠️ **يُحقَن في كلّ استدعاءٍ لا في اختبارِ `preparedBy` وحدَه** (مراجعةٌ
/// 2026-09-01، مأخذ ٥): الشاشةُ صارت تقرأ `authProvider` عند إنشاء الجلسة،
/// و`AuthNotifier` الحقيقيُّ يشتبك بـ`WebSocketSyncClient` في `build`. فحقنُ
/// وهميٍّ في كلّ اختبارٍ يُبقي السويّةَ بلا شبكةٍ ولا قاعدة — وهو نفسُ تعليل
/// «لا `databaseProvider` هنا» في رأس الشاشة.
const int _signedInUserId = 41;

class _SignedInAuth extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        userWithRole: db.UserWithRole(
          user: db.User(
            id: _signedInUserId,
            username: 'tester',
            passwordHash: '',
            passwordSalt: '',
            displayName: 'مُعِدُّ المطابقة',
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
        authProvider.overrideWith(_SignedInAuth.new),
      ],
      child: const MaterialApp(home: BankReconciliationPicposScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// يفتح جلسةَ مطابقةٍ فعليّةً عبر الواجهة نفسِها: يختار الخزنةَ من
/// المنتقي، يكتب رصيدَ كشفٍ صالحاً، وينقر «جلسة جديدة». تُستعمَل فقط في
/// اختبارات المهمّة ٦ الجديدة (القائمتان والمطابقةُ اليدويّة) — بقيّةُ
/// اختبارات هذا الملفّ أقدمُ من هذه الدالّة وتكرّر خطواتِها صراحةً، فلا
/// داعيَ لإعادة كتابتها.
Future<void> openSession(
  WidgetTester tester,
  String safeLabel, {
  String balance = '1000',
}) async {
  await tester.tap(find.text('اختر خزنة بنكية'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(safeLabel));
  await tester.pumpAndSettle();
  await tester.tap(find.text('تطبيق'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), balance);
  await tester.pumpAndSettle();
  await tester.tap(find.text('جلسة جديدة'));
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

  // ═══════════════════════════════════════════════════════════════════════
  //  استئنافُ جلسةٍ مفتوحة — البند المفتوح ١، أُغلق 2026-09-02
  // ═══════════════════════════════════════════════════════════════════════
  //
  // 🔴 الشاشةُ لم تكن تعرض إلّا «جلسة جديدة»، و`createReconciliation` إدراجٌ
  // بلا فحصِ تكرار — فكلُّ فتحٍ للتبويبة على نفس الخزنة والفترة كان يُنشئ
  // صفّاً آخرَ في `bank_reconciliations`. و`getReconciliationSessions` كانت
  // مُعلَنةً ومُنفَّذةً وبلا مُنادٍ واحدٍ في `lib`.

  testWidgets('🔴 جلسةٌ مفتوحةٌ تُستأنَف ولا يُنشَأ صفٌّ ثانٍ', (tester) async {
    // نفسُ حسابِ `_lastMonthRange()` في الشاشة — الفترةُ الافتراضيّةُ نسبيّةٌ
    // بالزمن، فتثبيتُ تاريخٍ حرفيٍّ هنا كان يجعل الاختبارَ يمرّ في شهرٍ
    // ويسقط في آخر.
    final now = DateTime.now();
    final lastMonthEnd = DateTime(now.year, now.month, 1)
        .subtract(const Duration(days: 1));
    final periodStart = DateTime(lastMonthEnd.year, lastMonthEnd.month, 1);

    final accounting = _FakeAccounting(sessionId: 99)
      ..openSessions = [
        db.BankReconciliationData(
          id: 55,
          bankAccountId: 42,
          periodStart: periodStart,
          // ⚠️ بفارقِ ثوانٍ عن `periodEnd` الذي تحسبه الشاشةُ — والمطابقةُ
          //    يجب أن تنجح رغم ذلك، وإلّا أُنشئت نسخةٌ ثانيةٌ لكلّ فتح.
          periodEnd: DateTime(
              lastMonthEnd.year, lastMonthEnd.month, lastMonthEnd.day, 22, 13),
          statementBalance: 500,
          bookBalance: 500,
          difference: 0,
          totalMatched: 0,
          totalUnmatched: 0,
          status: 'draft',
          createdAt: periodStart,
        ),
      ];

    await pump(
      tester,
      1920,
      safes: [_bankSafe(9, linked: 42, name: 'خزنة الاختبار')],
      accounting: accounting,
    );

    await tester.tap(find.text('اختر خزنة بنكية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خزنة الاختبار'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();

    // الزرُّ انقلب — ولا يُعرَض «جلسة جديدة» فوق جلسةٍ مفتوحة.
    expect(find.text('متابعة الجلسة المفتوحة'), findsOneWidget,
        reason: 'جلسةٌ مفتوحةٌ للحساب والفترة ⇒ متابعةٌ لا إنشاء');
    expect(find.text('جلسة جديدة'), findsNothing,
        reason: 'عرضُهما معاً هو بابُ تراكمِ الصفوف');

    await tester.tap(find.text('متابعة الجلسة المفتوحة'));
    await tester.pumpAndSettle();

    expect(accounting.createCalled, isFalse,
        reason: 'الاستئنافُ لا يُنشئ صفّاً — وهذا هو العطبُ كلُّه');
    expect(accounting.reportedSessionIds, contains(55),
        reason: 'والتقريرُ يُقرأ للجلسة القائمة رقم ٥٥ لا لجلسةٍ جديدة');
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

  // ═══════════════════════════════════════════════════════════════════════
  // المهمّةُ ٦ — القائمتان المتجاورتان والمطابقةُ اليدويّةُ والنزع.
  // ═══════════════════════════════════════════════════════════════════════

  // ⚠️ **مراجعةٌ — مأخذ ١**: `entry_date` في `outstandingBookEntries` يصل
  // `int` (ثوانٍ منذ الإبوك) لا نصّاً — والشاشةُ كانت تسقط إلى عرض الرقم
  // الخامّ (تسعُ خاناتٍ أو أكثر) بدل تاريخٍ مقروء. هذا الاختبارُ يقيس
  // **شكلَ العرض** لا وجودَ رقمٍ فحسب: لو رجعت `_fmtEntryDate` تسقط إلى
  // `'$raw'` على `int`، لن يظهر النصُّ `2026-05-11` إطلاقاً ويسقط التوكيد.
  //
  // ⚠️ **التاريخُ `05-11` لا `05-10` عمداً**: `REF-1` يحمل `05-10` أيضاً
  // (عمودٌ آخرُ في الجدول المجاور، منسوخٌ عن `DateTime` حقيقيّةٍ لا عن
  // `_fmtEntryDate`) — تطابقُهما كان يمرِّر هذا التوكيدَ حتى لو أخفقت
  // `_fmtEntryDate` في فرع `int` تماماً (طفرةٌ فعليّةٌ كشفت ذلك — راجع
  // تقريرَ الإصلاح).
  testWidgets('🔴 عمودُ تاريخِ الدفتر يعرض تاريخاً مقروءاً لا ختماً خامّاً',
      (tester) async {
    await pump(tester, 1920,
        safes: [_bankSafe(1, linked: 5, name: 'خزنة تاريخ الدفتر')]);
    await openSession(tester, 'خزنة تاريخ الدفتر');

    expect(find.text('2026-05-11'), findsWidgets,
        reason: '`entry_date` يصل `int` من `customSelect` — والختمُ الخامُّ '
            'ليس تاريخاً يقرؤه محاسب');
  });

  testWidgets('🔴 «طابق» تُعطَّل حتى يُختار سطرٌ من كلّ جانب', (tester) async {
    await pump(tester, 1920,
        safes: [_bankSafe(1, linked: 5, name: 'خزنة المطابقة اليدوية')]);
    await openSession(tester, 'خزنة المطابقة اليدوية');

    final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'طابق'));
    expect(btn.onPressed, isNull, reason: 'بلا اختيارٍ لا مطابقة');

    await tester.tap(find.text('REF-1'));
    await tester.pump();
    final half = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'طابق'));
    expect(half.onPressed, isNull, reason: 'جانبٌ واحدٌ لا يكفي');

    await tester.tap(find.text('قيد الإيداع'));
    await tester.pump();
    final both = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'طابق'));
    expect(both.onPressed, isNotNull);
  });

  testWidgets('🔴 مطابقةٌ مكرّرةٌ تُعرَض رسالتُها لا تُبتلَع', (tester) async {
    final accounting = _FakeAccounting(
        manualMatchThrows: StateError(
            'سطرُ القيد رقم 7 مطابَقٌ سلفاً لسطر الكشف رقم 3.'));
    await pump(tester, 1920,
        safes: [_bankSafe(1, linked: 5, name: 'خزنة التكرار')],
        accounting: accounting);
    await openSession(tester, 'خزنة التكرار');

    await tester.tap(find.text('REF-1'));
    await tester.tap(find.text('قيد الإيداع'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'طابق'));
    await tester.pumpAndSettle();

    // ⚠️ **مراجعةٌ — مأخذ ٢**: `'مطابَقٌ سلفاً'` وحدَها **متقاطعةٌ** مع وصف
    // السطر المطابَق الافتراضيّ في `_sampleReconciliationReport`
    // (‏`'إيداعٌ مطابَقٌ سلفاً'` — يُرسَم دائماً في جدول «الأسطرُ المطابَقة»
    // أسفلَ الشاشة، بصرفِ النظر عن نجاح المطابقة أو فشلها). فالتوكيدُ كان
    // يمرّ حتى لو استُبدلت `catch` برسالةٍ عامّةٍ («تعذّرت العمليّة») —
    // أُثبت ذلك بطفرةٍ فعليّة (راجع تقريرَ الإصلاح). والنصُّ هنا **لا يوجد
    // إلّا** في رسالة المحرّك نفسِها.
    expect(find.textContaining('لسطر الكشف رقم 3'), findsWidgets,
        reason: 'نصُّ المحرّك يسمّي السطرَ الآخر — وهو ما يحتاجه المحاسب. '
            'ولا تقاطعَ مع وصف سطرٍ آخر في التقرير المزيَّف.');

    // ⚠️ مؤقّتُ `AppToast` ٢٥٠٠ms ثمّ ٣٠٠ms خروجاً — نفسُ نمط بقيّة
    // اختبارات هذا الملفّ.
    await tester.pump(const Duration(seconds: 4));
  });

  // ⚠️ **مراجعةٌ — مأخذ ٤**: مسارُ المطابقة **الناجح** كان بلا توكيدٍ
  // واحد. الاختبارُ الوحيدُ الذي يضغط «طابق» كان اختبارَ الرمي (أعلاه) —
  // فالمزيَّفُ يرمي قبل أن يُقاس شيء، ولو عُكس الوسيطان
  // (‏`statementLineId`/`journalLineId`) في `_manualMatch` كانت السويّةُ
  // كلُّها ستمرّ خضراء بينما الشاشةُ تربط سطرَ كشفٍ بقيدٍ خاطئ. `REF-1`
  // معرّفُه `3` و«قيد الإيداع» معرّفُه `7` — مختلفان عمداً كي يُمسك
  // انعكاسُهما.
  testWidgets(
      '🔴 مطابقةٌ ناجحةٌ تربط السطرَ الصحيحَ بالقيد الصحيح، وتُفرِغ '
      'الاختيارَ، وتُنعش التقرير', (tester) async {
    final accounting = _FakeAccounting();
    await pump(tester, 1920,
        safes: [_bankSafe(1, linked: 5, name: 'خزنة المطابقة الناجحة')],
        accounting: accounting);
    await openSession(tester, 'خزنة المطابقة الناجحة');

    final reportCallsBeforeMatch = accounting.getReportCalls;

    await tester.tap(find.text('REF-1'));
    await tester.tap(find.text('قيد الإيداع'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'طابق'));
    await tester.pumpAndSettle();

    expect(accounting.manualMatchCalls, 1);
    expect(accounting.manualMatchStatementLineId, 3,
        reason: 'REF-1 هو سطرُ الكشف رقم 3 في التقرير الافتراضي');
    expect(accounting.manualMatchJournalLineId, 7,
        reason: '«قيد الإيداع» هو قيدُ الدفتر رقم 7 — لو عُكس الوسيطان في '
            '_manualMatch لمرّ هذا التوكيدُ بقيمةٍ مقلوبةٍ لأنّهما مختلفان '
            'عمداً (٣ ≠ ٧)');

    final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'طابق'));
    expect(btn.onPressed, isNull,
        reason: 'نجاحُ المطابقة يُفرغ الاختيارَ — والمُوجزُ يذكر '
            '`_clearPicks` صراحةً كخطوةٍ بعد النجاح، فبلا اختيارٍ يعود '
            'الزرُّ معطَّلاً');

    expect(accounting.getReportCalls, greaterThan(reportCallsBeforeMatch),
        reason: 'التقريرُ يُنعش بعد المطابقة (`ref.invalidate`) — لا يبقى '
            'على القيم القديمة');
  });

  testWidgets('🔴 و«نزع» يُنادي المحرّك', (tester) async {
    final accounting = _FakeAccounting();
    await pump(tester, 1920,
        safes: [_bankSafe(1, linked: 5, name: 'خزنة النزع')],
        accounting: accounting);
    await openSession(tester, 'خزنة النزع');

    await tester.tap(find.text('نزع').first);
    await tester.pumpAndSettle();

    expect(accounting.unmatchCalls, 1);
    // ⚠️ **مراجعةٌ — مأخذ ٥**: العدّ وحدَه لا يمسك نزعَ السطر الخطأ —
    // السطرُ المطابَقُ الوحيدُ في التقرير الافتراضيّ معرّفُه ١٠.
    expect(accounting.unmatchedStatementLineId, 10,
        reason: 'يجب أن يُنزَع سطرُ الكشف الصحيحُ لا أيُّ معرّف');
  });

  // ⚠️ **القياسُ عند عرضَين إلزاميٌّ هنا تحديداً**: القائمتان المتجاورتان
  // أوّلُ ما ينهار ضيقاً، وخمسةُ أعطابِ تخطيطٍ أُمسكت في هذا المستودع
  // بقياس عرضَين. «لم تنهر» ليس قياساً وحدَه — فالتوكيدُ هنا هندسيٌّ:
  // يقارن ارتفاعَ صفّ REF-1 (يمين) بارتفاع صفّ «قيد الإيداع» (يسار).
  // متقاربان ⇒ صفّان في نفس السطر (`Row`)؛ متباعدان ⇒ عمودٌ (`Column`).
  for (final width in [1280.0, 1920.0]) {
    testWidgets(
        '🔴 القائمتان جنباً إلى جنبٍ فوق ١١٠٠ عرضاً (${width.toInt()})',
        (tester) async {
      await pump(tester, width,
          safes: [_bankSafe(1, linked: 5, name: 'خزنة القوائم المتجاورة')]);
      await openSession(tester, 'خزنة القوائم المتجاورة');

      expect(tester.takeException(), isNull);

      final stmtY = tester.getTopLeft(find.text('REF-1')).dy;
      final bookY = tester.getTopLeft(find.text('قيد الإيداع')).dy;
      expect((stmtY - bookY).abs(), lessThan(20),
          reason: 'عند ${width.toInt()} عرضاً يجب أن تكون القائمتان جنباً '
              'إلى جنبٍ — صفّاهما الأوّلان على ارتفاعٍ متقارب، لا واحدةً '
              'فوق الأخرى');
    });
  }

  testWidgets('🔴 القائمتان تنقلبان عموداً تحت ١١٠٠ عرضاً', (tester) async {
    await pump(tester, 900,
        safes: [_bankSafe(1, linked: 5, name: 'خزنة القوائم الضيقة')]);
    await openSession(tester, 'خزنة القوائم الضيقة');

    expect(tester.takeException(), isNull);

    final stmtY = tester.getTopLeft(find.text('REF-1')).dy;
    final bookY = tester.getTopLeft(find.text('قيد الإيداع')).dy;
    expect(bookY - stmtY, greaterThan(60),
        reason: 'تحت ١١٠٠ عرضاً يجب أن ينقلب التخطيطُ عموداً — قائمةُ '
            'الدفتر تحت قائمة الكشف لا بجانبها');
  });

  testWidgets('🔴 «إقفال الجلسة» يعرض الفرقَ في حوار التأكيد وينادي المحرّك',
      (tester) async {
    final accounting = _FakeAccounting(
      report: const {
        'reconciliation': null,
        'statementBalance': 1049.75,
        'bookBalance': 1000.0,
        'difference': 49.75,
        'matchedCount': 0,
        'unmatchedCount': 0,
        'matchedLines': <dynamic>[],
        'unmatchedBankLines': <dynamic>[],
        'outstandingBookEntries': <dynamic>[],
      },
    );
    await pump(tester, 1920,
        safes: [_bankSafe(1, linked: 5, name: 'خزنة الإقفال')],
        accounting: accounting);
    await openSession(tester, 'خزنة الإقفال');

    await tester.tap(find.widgetWithText(ElevatedButton, 'إقفال الجلسة'));
    await tester.pumpAndSettle();

    // ⚠️ **مراجعةٌ — مأخذ ٣**: بلا حصرٍ داخل الحوار، بطاقةُ «الفرق»
    // (‏`49.75`) وبطاقةُ «رصيد الكشف» (‏`1,049.75`) في صفّ المؤشّرات
    // تبقيان في الشجرة خلف الحوار غيرِ المُعتِم — فالتوكيدُ كان يمرّ حتى
    // لو حُذف الفرقُ من نصّ الحوار كلّيّاً. الحصرُ هنا داخل الحوار
    // نفسِه (نفسُ نمط `find.descendant` عند اختبار المؤشّرات أعلاه).
    //
    // ⚠️ **`PicPosDialog` لا `AlertDialog`** (مراجعةٌ 2026-09-01، مأخذ ٣):
    // الحوارُ صار يمرّ بـ`showPicPosConfirm` — والحارسُ البنيويُّ
    // `accounting_picpos_uses_picpos_dialog_test` كان يسمّي السطرَ القديمَ
    // بالضبط. والحصرُ باقٍ كما هو، فهو ما جعل التوكيدَ قادراً على السقوط.
    final dialog = find.byType(PicPosDialog);
    expect(dialog, findsOneWidget, reason: 'حوارُ التأكيد يجب أن يظهر');
    expect(
      find.descendant(of: dialog, matching: find.textContaining('49.75')),
      findsWidgets,
      reason: 'حوارُ التأكيد نفسُه يعرض الفرقَ صراحةً — لا بطاقةَ مؤشّرٍ '
          'خلفه',
    );

    await tester.tap(find.text('إقفال'));
    await tester.pumpAndSettle();

    expect(accounting.completeCalls, 1);
    expect(accounting.completedReconciliationId, accounting.sessionId);
    expect(find.textContaining('أُقفلت'), findsOneWidget,
        reason: 'نجاحُ الإقفال يُقال — لا صمتَ');

    await tester.pump(const Duration(seconds: 4));
  });

  // ═══════════════════════════════════════════════════════════════════════
  // موجةُ إصلاحِ المراجعة الشاملة 2026-09-01.
  // ═══════════════════════════════════════════════════════════════════════

  // ⚠️ **مأخذ ٢ — نهايةُ الفترة الافتراضيّة كانت منتصفَ الليل.**
  //
  // `createReconciliation` تحسب رصيدَ الدفتر بـ`e.entry_date <= ?` وقيودُ
  // اليوميّة تحمل وقتاً، فكلُّ قيدٍ في **اليوم الأخير من الفترة** كان يسقط
  // من رصيد الدفتر بينما أسطرُ الكشف لذلك اليوم تدخل ⇒ فرقٌ مُختلَقٌ في
  // المسار **الافتراضيّ** ما لم يلمس المستخدمُ شريطَ المدى.
  //
  // ⚠️ **والقياسُ على ما وصل المستودعَ لا على الدالّة الخاصّة**: `_period`
  // يمرّ بالشاشة كاملةً ثمّ يصل `createReconciliation` — ولو كسر أحدٌ
  // التمريرَ بينهما لسقط هذا التوكيدُ أيضاً، وهو ما لا تمسكه قراءةُ
  // `_lastMonthRange` وحدَها.
  testWidgets(
      '🔴 الفترةُ الافتراضيّةُ تصل المحرّكَ بنهاية اليوم لا بمنتصف ليله',
      (tester) async {
    final accounting = _FakeAccounting();
    await pump(tester, 1920,
        safes: [_bankSafe(1, linked: 5, name: 'خزنة الفترة')],
        accounting: accounting);
    await openSession(tester, 'خزنة الفترة');

    expect(accounting.createCalled, isTrue, reason: 'مرساة: الجلسةُ فُتحت');
    final end = accounting.createdPeriodEnd!;
    expect(end.hour, 23,
        reason: 'نهايةٌ عند 00:00 تُسقط قيودَ اليوم الأخير كلَّها من رصيد '
            'الدفتر — والكشفُ يحملها، فيُختلَق فرقٌ ويُصدَّق');
    expect(end.minute, 59);

    // والبدايةُ تبقى منتصفَ الليل — لا تُدفَع هي الأخرى بلا داعٍ.
    final start = accounting.createdPeriodStart!;
    expect(start.hour, 0, reason: 'اليومُ الأوّلُ يدخل كاملاً من أوّله');

    // ومرساةٌ تُثبت أنّ المدى شهرٌ ماضٍ فعليٌّ لا يومٌ واحد.
    expect(end.isAfter(start), isTrue);
  });

  // ⚠️ **مأخذ ٥ — `preparedBy` كان فارغاً في كلّ جلسة.**
  testWidgets('🔴 مُعِدُّ الجلسة يصل المحرّكَ — لا `preparedBy` فارغاً',
      (tester) async {
    final accounting = _FakeAccounting();
    await pump(tester, 1920,
        safes: [_bankSafe(1, linked: 5, name: 'خزنة المُعِدّ')],
        accounting: accounting);
    await openSession(tester, 'خزنة المُعِدّ');

    expect(accounting.createdUserId, _signedInUserId,
        reason: 'الشاشةُ لم تكن تمرّر `userId` إطلاقاً، فعمودُ `preparedBy` '
            'في `bank_reconciliations` لا يُملأ أبداً — مطابقةٌ مقفلةٌ بلا '
            'اسمِ من أعدَّها. والرقمُ ٤١ لا ١ كي يسقط التوكيدُ لو مُرِّر '
            'ثابتٌ بدل قراءةِ الجلسة');
  });

  // ⚠️ **مأخذ ٦ — الإقفالُ لا يُقفل شيئاً.**
  //
  // بعد `completeReconciliation` كان `_sessionId` يبقى والتقريرُ معروضاً
  // وأزرارُ «طابق» و«نزع» و«استيراد كشف» و«مطابقة آلية» فعّالةً كلَّها على
  // جلسةٍ `status = 'completed'`. والشاشةُ لم تكن تقرأ `report['reconciliation']`
  // ولا `status` في أيّ موضع.
  testWidgets('🔴 جلسةٌ مقفلةٌ تُعطِّل أزرارَ التعديل وتقول إنّها مقفلة',
      (tester) async {
    // ⚠️ صفُّ drift **حقيقيٌّ** لا خريطة: الشاشةُ تقرأ `.status` نداءً
    // ديناميكيّاً (‏لا تستورد `database.dart`)، وخريطةٌ هنا كانت ستقيس
    // مساراً لا يُنتجه `getReconciliationReport` أبداً.
    final base = _sampleReconciliationReport();
    final accounting = _FakeAccounting(
      report: {
        ...base,
        'reconciliation': db.BankReconciliationData(
          id: 1,
          bankAccountId: 5,
          periodStart: DateTime(2026, 5, 1),
          periodEnd: DateTime(2026, 5, 31, 23, 59, 59),
          statementBalance: 1000,
          bookBalance: 1000,
          difference: 0,
          totalMatched: 1,
          totalUnmatched: 1,
          status: 'completed',
          createdAt: DateTime(2026, 6, 1),
        ),
      },
    );
    await pump(tester, 1920,
        safes: [_bankSafe(1, linked: 5, name: 'خزنة المقفلة')],
        accounting: accounting);
    await openSession(tester, 'خزنة المقفلة');

    expect(
      find.text('الجلسةُ مقفلة — لا استيرادَ ولا مطابقةَ ولا نزعَ بعد الإقفال'),
      findsOneWidget,
      reason: 'الحالةُ تُقال — زرٌّ رماديٌّ بلا سببٍ يُقرأ «مكسور»',
    );

    // ⚠️ **الاختيارُ يُنقَر فعلاً قبل القياس**: بلا اختيارٍ يكون «طابق»
    // معطَّلاً بأيّ حال، فالتوكيدُ كان سيمرّ ولو أُلغي الإقفالُ كلُّه.
    await tester.tap(find.text('REF-1'));
    await tester.tap(find.text('قيد الإيداع'));
    await tester.pump();

    final match = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'طابق'));
    expect(match.onPressed, isNull,
        reason: 'مطابقةٌ يدويّةٌ على جلسةٍ مقفلةٍ تكتب في دفترٍ أُغلق');

    final complete = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'إقفال الجلسة'));
    expect(complete.onPressed, isNull, reason: 'ولا يُقفَل المقفول');

    // ⚠️ **بأنواعها الملموسة**: `find.byType` يطابق `runtimeType` تطابقاً
    // تامّاً، فـ`ButtonStyleButton` المجرَّدةُ لا تُطابِق شيئاً — وقد سقط
    // هذا التوكيدُ بـ«No element» قبل التصويب.
    const writeButtons = <String, Type>{
      'استيراد كشف': OutlinedButton,
      'مطابقة آلية': FilledButton,
    };
    for (final entry in writeButtons.entries) {
      final button = tester.widget<ButtonStyleButton>(
          find.widgetWithText(entry.value, entry.key));
      expect(button.onPressed, isNull,
          reason: '«${entry.key}» تكتب أسطراً في حسابٍ طُوبق وأُقفل');
    }

    // ⚠️ **ومرساةٌ تُثبت أنّ القفلَ مُنتقىً لا شاملاً**: «تنزيل القالب» لا
    // يمسّ شيئاً ويبقى فعّالاً — ولولا هذا التوكيدُ لمرَّ «عطِّل الشريطَ
    // كلَّه» بوصفه إصلاحاً.
    final template = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'تنزيل القالب'));
    expect(template.onPressed, isNotNull,
        reason: 'تنزيلُ القالب قراءةٌ لا كتابة — لا يُمنَع بالإقفال');

    // ⚠️ `PicPosButtonCell` تُرسَم `InkWell` لا `IconButton` — قِيس لا خُمِّن
    // (‏`picpos_data_table.dart`، فرعُ `case PicPosButtonCell()`).
    final unmatch = tester.widget<InkWell>(
      find
          .ancestor(of: find.text('نزع'), matching: find.byType(InkWell))
          .first,
    );
    expect(unmatch.onTap, isNull, reason: 'و«نزع» تفكّ مطابقةً مختومة');
  });

  // ⚠️ **مأخذ ٧ — «0/0» بلونِ النجاح على فترةٍ لا تلتقي مع الكشف.**
  testWidgets(
      '🔴 كشفٌ كلُّ أسطره خارجَ الفترة يُقال صراحةً لا يُعَدُّ نجاحاً',
      (tester) async {
    // ⚠️ **تواريخُ `DateTime` لا نصوصٌ**: هذا ما يُخرجه
    // `parseBankStatementRow` فعلاً، والفحصُ في الشاشة يشترط `DateTime`
    // عمداً كي لا يصيح إنذاراً على شكلٍ لا يعرفه.
    //
    // و2020 خارجَ «الشهر الماضي» مهما كان تاريخُ تشغيل الاختبار — لا
    // اتّكالَ على `DateTime.now()` في التوكيد.
    final excelService = _FakeExcelService(
      parseResult: BankStatementRowsSummary(
        <Map<String, dynamic>>[
          {
            'date': DateTime(2020, 1, 5),
            'reference': 'OLD-1',
            'description': 'إيداعٌ قديم',
            'debit': 0.0,
            'credit': 500.0,
          },
        ],
        const <String>[],
      ),
    );
    await pump(tester, 1920,
        safes: [_bankSafe(1, linked: 5, name: 'خزنة خارج الفترة')],
        excelService: excelService);

    await tester.tap(find.text('اختر خزنة بنكية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خزنة خارج الفترة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('استيراد كشف'));
    await tester.pumpAndSettle();

    expect(
      find.text('استُورد ١ سطراً — ولا سطرَ منها يقع في الفترة المختارة، '
          'فلن تظهر في المطابقة'),
      findsOneWidget,
      reason: 'الأسطرُ أُدرجت فعلاً لكنّ قوائمَ التقرير كلَّها ترشِّح '
          'بالفترة — فبطاقةُ «مطابَق / غير مطابَق» تعرض صفراً على صفرٍ '
          'بلون النجاح، وهو رقمٌ صحيحٌ يُقرأ خطأً',
    );

    await tester.pump(const Duration(seconds: 4));
  });

  // ⚠️ **مأخذ ٨‑ب — رصيدُ كشفِ خزنةٍ يبقى معروضاً لأخرى.**
  testWidgets('🔴 تبديلُ الخزنة يمسح رصيدَ الكشف — لا يُورَّث', (tester) async {
    await pump(tester, 1920, safes: [
      _bankSafe(1, linked: 5, name: 'خزنة أولى'),
      _bankSafe(2, linked: 6, name: 'خزنة ثانية'),
    ]);

    await tester.tap(find.text('اختر خزنة بنكية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خزنة أولى'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '9999.99');
    await tester.pumpAndSettle();

    // مرساة: الرقمُ مكتوبٌ فعلاً قبل التبديل.
    expect(find.text('9999.99'), findsOneWidget);

    await tester.tap(find.text('خزنة أولى'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خزنة ثانية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();

    expect(find.text('9999.99'), findsNothing,
        reason: 'رصيدُ كشفِ الخزنة الأولى يدخل `difference` مباشرةً بلا أيّ '
            'تحقّقٍ خلفه — فإبقاؤه لخزنةٍ أخرى تصديقُ رقمٍ ليس لها');

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'جلسة جديدة'),
    );
    expect(button.onPressed, isNull,
        reason: 'وبلا رقمٍ يعود الزرُّ معطَّلاً حتّى يُكتَب رقمُ هذه الخزنة');
  });

  // ⚠️ **مأخذ ٨‑ج — الاختيارُ لا يُصالَح بعد الإنعاش.**
  //
  // اختَر سطراً ثمّ اضغط «مطابقة آلية»: المحرّكُ يطابقه فيختفي من
  // `unmatchedBankLines`، وكان `_pickedStmtId` يبقى عليه و«طابق» يبقى
  // فعّالاً — نقرةٌ عليه تُنادي المحرّكَ على سطرٍ مطابَقٍ سلفاً.
  testWidgets(
      '🔴 سطرٌ اختير ثمّ طوبق آليّاً يسقط من الاختيار ويُعطَّل «طابق»',
      (tester) async {
    final base = _sampleReconciliationReport();
    final accounting = _FakeAccounting(
      autoMatchResult: 1,
      // ⚠️ **قائمةُ الدفتر تبقى كما هي عمداً**: لو أُفرغت القائمتان معاً
      // لمرَّ التوكيدُ بلا إصلاحٍ أيضاً (‏الزرُّ يُعطَّل لغياب أيّ صفٍّ
      // يُنقَر). فالمقيسُ هنا أنّ `_pickedJeLineId` يبقى صالحاً بينما
      // `_pickedStmtId` وحدَه يسقط — وهو عينُ الحالة المُبلَّغ عنها.
      reportAfterAutoMatch: {
        ...base,
        'unmatchedBankLines': const <dynamic>[],
        'unmatchedCount': 0,
        'matchedCount': 2,
      },
    );
    await pump(tester, 1920,
        safes: [_bankSafe(1, linked: 5, name: 'خزنة الاختيار')],
        accounting: accounting);
    await openSession(tester, 'خزنة الاختيار');

    await tester.tap(find.text('REF-1'));
    await tester.tap(find.text('قيد الإيداع'));
    await tester.pump();

    // مرساة: الاختيارُ اكتمل والزرُّ فعّالٌ **قبل** المطابقة الآليّة.
    final before = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'طابق'));
    expect(before.onPressed, isNotNull);

    await tester.tap(find.text('مطابقة آلية'));
    await tester.pumpAndSettle();

    expect(find.text('REF-1'), findsNothing,
        reason: 'مرساة: السطرُ اختفى فعلاً من قائمة غيرِ المطابَق');
    expect(find.text('قيد الإيداع'), findsWidgets,
        reason: 'مرساة: وقيدُ الدفتر باقٍ — فالاختيارُ الثاني ما زال صالحاً');

    final after = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'طابق'));
    expect(after.onPressed, isNull,
        reason: 'السطرُ المختارُ لم يعد في القائمة — و«طابق» عليه نداءٌ '
            'على سطرٍ مطابَقٍ سلفاً');

    await tester.pump(const Duration(seconds: 4));
  });
}
