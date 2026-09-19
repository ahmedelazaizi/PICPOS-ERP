// test/widget/journal_entry_draft_dialog_test.dart
//
// حوارُ `draft` من التصميم — «حفظ كمسودة» بعنوانه ونصِّه وملخّصِه.
//
// ⚠️ ويقيس **ما يُمرَّر إلى المستودع** لا ظهورَ الزرّ وحدَه: زرٌّ يُفتَح
//    ويُغلَق ثمّ يحفظ قيداً **مرحَّلاً** هو أسوأُ من غيابه — يعِد بفصلٍ
//    ولا يعطيه، والرصيدُ يتحرّك والمستخدمُ يظنّه لم يتحرّك.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/accounting_repository.dart';
import 'package:ural_erp/domain/repositories/auth_repository.dart';
import 'package:ural_erp/presentation/accounting_picpos/journal_entries_picpos_screen.dart';

/// ⚠️ **حارسُ MJE-3 يقف بين الزرّ والمستودع.** `saveManualEntry` يستدعي
/// `_requireAccountingJournalPermission` قبل الكتابة، وهو يرتدّ حين لا
/// مستخدمَ مسجَّلاً. فبلا هذين الوهميَّين لا يصل شيءٌ إلى `createJournalEntry`
/// — ويبدو الاختبارُ كأنّه يكشف عطباً في المسودّة وهو يقيس تسجيلَ الدخول.
class _SignedInAuth extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        userWithRole: UserWithRole(
          user: User(
            id: 1,
            username: 'tester',
            passwordHash: '',
            passwordSalt: '',
            displayName: 'مُدخِل القيود',
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

class _PermissiveAuthRepo implements IAuthRepository {
  @override
  Future<bool> userHasPermission(int userId, String permissionCode) async =>
      true;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingRepo implements IAccountingRepository {
  _RecordingRepo({
    this.accounts = const [],
    this.templates = const [],
    this.templateLines = const [],
  });

  final List<Account> accounts;
  final List<JournalEntryTemplateData> templates;
  final List<Map<String, dynamic>> templateLines;

  /// ما وصل فعلاً إلى طبقة البيانات.
  final List<({bool asDraft, String description, int lineCount, int? createdBy})>
      created = [];

  @override
  Stream<List<JournalEntryData>> watchJournalEntries({
    DateTime? from,
    DateTime? to,
  }) =>
      Stream.value(const []);

  @override
  Stream<Map<int, ({double debit, double credit})>> watchJournalEntryTotals({
    DateTime? from,
    DateTime? to,
  }) =>
      Stream.value(const {});

  @override
  Future<List<Account>> getAllAccounts() async => accounts;

  @override
  Future<List<CostCenter>> getCostCenters() async => const [];

  @override
  Stream<List<JournalEntryTemplateData>> watchActiveTemplates() =>
      Stream.value(templates);

  @override
  Future<List<Map<String, dynamic>>> getTemplateLinesWithAccounts(int id) async =>
      templateLines;

  @override
  Future<int> createJournalEntry({
    required String description,
    required DateTime date,
    required List<JournalLine> lines,
    String? referenceType,
    int? referenceId,
    bool isAutoPosted = false,
    int? costCenterId,
    int? branchId,
    bool asDraft = false,
    int? createdBy,
    // v174: «المرجع» صار يُكتَب من سند القيد — راجع الواجهة.
    String? reference,
  }) async {
    created.add((
      asDraft: asDraft,
      description: description,
      lineCount: lines.length,
      createdBy: createdBy,
    ));
    return 1;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Account _acc(int id, String code, String name) => Account(
      id: id,
      code: code,
      name: name,
      accountType: 'asset',
      accountNature: 'detail',
      normalBalance: 'debit',
      level: 1,
      balance: 0,
      isSystem: false,
      isActive: true,
      isHiddenFromEntries: false,
      rowVersion: 1,
    );

void main() {
  final accounts = [
    _acc(1, '1111', 'الصندوق الرئيسي'),
    _acc(2, '4121', 'مبيعات محلية'),
  ];

  /// ⚠️ قيدٌ متوازنٌ **بحساباتٍ مختارة**. و«متوازن» وحدَه لا يكفي: زرّا
  ///    الحفظ يُفعَّلان على التوازن، لكنّ `saveManualEntry` يرتدّ برسالةٍ
  ///    إن خلا بندٌ من حساب — فقياسُ الحفظ ببندَين بلا حسابٍ يقيس الارتداد.
  ///    والقالبُ أرخصُ مسارٍ يملأ الحسابات، وهو مسارُ مستخدمٍ حقيقيّ.
  const templateLines = [
    {
      'account_id': 1,
      'account_code': '1111',
      'account_name': 'الصندوق الرئيسي',
      'description': 'نقدية',
      'debit': 500.0,
      'credit': 0.0,
    },
    {
      'account_id': 2,
      'account_code': '4121',
      'account_name': 'مبيعات محلية',
      'description': 'إيراد',
      'debit': 0.0,
      'credit': 500.0,
    },
  ];

  final template = JournalEntryTemplateData(
    id: 1,
    name: 'قالب الاختبار',
    description: null,
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
  );

  /// الوصفُ الذي يملؤه المعالجُ تلقائيّاً من اسم القالب.
  const expectedDesc = 'قيد بناءً على قالب: قالب الاختبار';

  late _RecordingRepo repo;

  Future<void> pumpScreen(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    repo = _RecordingRepo(
      accounts: accounts,
      templates: [template],
      templateLines: templateLines,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountingRepositoryProvider.overrideWithValue(repo),
          allBranchesProvider.overrideWith((ref) => Stream.value(const [])),
          authProvider.overrideWith(_SignedInAuth.new),
          authRepositoryProvider.overrideWithValue(_PermissiveAuthRepo()),
        ],
        child: const MaterialApp(home: JournalEntriesPicPosScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// حوارُ إنشاءٍ **فارغٌ** — بندان بلا حسابٍ ولا مبالغ.
  Future<void> pump(WidgetTester tester, double width) async {
    await pumpScreen(tester, width);
    await tester.tap(find.widgetWithText(FilledButton, 'قيد يدوي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// حوارُ إنشاءٍ **متوازنٌ بحساباتٍ** — عبر «من قالب».
  Future<void> pumpFromTemplate(WidgetTester tester, double width) async {
    await pumpScreen(tester, width);
    await tester.tap(find.widgetWithText(OutlinedButton, 'من قالب'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('قالب الاختبار'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// ⚠️ الحفظُ الناجحُ يُظهر `AppToast`، ومؤقّتُه ٢٥٠٠ms ثمّ ٣٠٠ms للخروج.
  ///    وتفكيكُ الشجرةِ قبل انقضائه يُسقط الاختبارَ بـ«A Timer is still
  ///    pending» — وهو مؤقّتُ رسالةٍ لا عطبٌ في المسودّة. فيُدفَع الزمنُ
  ///    الوهميُّ حتّى ينقضي **قبل** التفكيك.
  Future<void> teardown(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    group('عرض $w', () {
      testWidgets('«حفظ كمسودة» هو مسارُ الحفظ **الوحيد**', (tester) async {
        await pump(tester, width);

        expect(find.text('حفظ كمسودة'), findsOneWidget);
        // ⚠️ قرارُ مالك 2026-08-27: لا زرَّ ترحيلٍ فوريّ. زرّان أحدُهما
        //    يرحّل والآخرُ يؤجّل يجعلان الضابطَ اختياريّاً.
        expect(find.text('حفظ القيد'), findsNothing);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('وقيدٌ غيرُ متوازنٍ لا يُحفَظ مسودّةً أيضاً', (tester) async {
        await pump(tester, width);

        // ⚠️ التصميمُ يترك `saveDraft` بلا شرط، والـDAO هنا **يرفض** غيرَ
        //    المتوازن برميةٍ صريحة. فالزرُّ معطَّلٌ بدل رميةٍ تصل المستخدم.
        final btn = tester.widget<InkWell>(
          find
              .ancestor(
                of: find.text('حفظ كمسودة'),
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(btn.onTap, isNull,
            reason: 'قيدٌ فارغٌ غيرُ متوازنٍ — فلا مسودّةَ منه');
        expect(repo.created, isEmpty);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('والضغطُ يفتح حوارَ التصميم بنصِّه وملخّصِه الثلاثيّ',
          (tester) async {
        await pumpFromTemplate(tester, width);

        await tester.tap(find.text('حفظ كمسودة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // العنوانُ يظهر مرّتين: على الزرّ وفي رأس الحوار.
        expect(find.text('حفظ كمسودة'), findsWidgets);
        expect(
          find.text('المسودة لا تؤثر على الأرصدة، ويمكن استكمالها '
              'واعتمادها لاحقاً من قائمة القيود.'),
          findsOneWidget,
        );
        expect(find.text('حفظ المسودة'), findsOneWidget);
        // ملخّصُ التصميم — ثلاثةُ مفاتيحَ لا أربعة.
        //
        // ⚠️ «البيان» **ليس** فريداً: حقلُ وصفِ كلِّ بندٍ يحمل نفسَ النصّ
        //    تلميحاً. فيُقاس بـ`findsWidgets`، والفرادةُ تُقاس على
        //    المفتاحَين الآخرَين وعلى قيمِها.
        expect(find.text('البيان'), findsWidgets);
        expect(find.text('عدد السطور'), findsOneWidget);
        expect(find.text('إجمالي القيد'), findsOneWidget);
        expect(find.text('2 سطر'), findsOneWidget);
        expect(
          find.textContaining((500.0).toStringAsFixed(AppConstants.decimalPlaces)),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('والإلغاءُ لا يحفظ شيئاً', (tester) async {
        await pumpFromTemplate(tester, width);

        await tester.tap(find.text('حفظ كمسودة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        await tester.tap(find.widgetWithText(TextButton, 'إلغاء').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(repo.created, isEmpty, reason: 'رفضُ التأكيد يعني لا كتابة');
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('والتأكيدُ يمرّر `asDraft: true` إلى المستودع',
          (tester) async {
        await pumpFromTemplate(tester, width);

        await tester.tap(find.text('حفظ كمسودة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        await tester.tap(find.text('حفظ المسودة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // ⚠️ هذا هو التوكيدُ الذي يفصل الميزةَ عن مظهرِها.
        expect(repo.created, hasLength(1));
        expect(repo.created.single.asDraft, isTrue,
            reason: 'زرٌّ يَعِد بمسودّةٍ ويحفظ قيداً مرحَّلاً أسوأُ من غيابه');
        expect(repo.created.single.description, expectedDesc);
        expect(repo.created.single.lineCount, 2);
        // ⚠️ ومَن أنشأ يصل أيضاً — بلا هذا لا يعرف الاعتمادُ أن يمنع نفسَه.
        expect(repo.created.single.createdBy, 1,
            reason: 'مُعرِّفُ المنشئ هو ما يبني عليه ضابطُ «لا يعتمده منشئُه»');
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('ولا مسارَ ترحيلٍ فوريٍّ في الشاشة إطلاقاً', (tester) async {
        // ⚠️ لا يكفي أن يختفي زرُّ «حفظ القيد»: المقصودُ ألّا يبقى **أيُّ**
        //    مسارٍ في هذا الحوار يكتب قيداً مرحَّلاً. فيُقاس على ما وصل
        //    المستودعَ لا على النصوص المعروضة.
        await pumpFromTemplate(tester, width);

        await tester.tap(find.text('حفظ كمسودة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('حفظ المسودة'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(repo.created, isNotEmpty);
        expect(repo.created.every((c) => c.asDraft), isTrue,
            reason: 'قيدٌ يدويٌّ يصل المستودعَ بـ`asDraft: false` = ترحيلٌ '
                'بلا اعتماد، وهو عينُ ما ألغاه قرارُ المالك');
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });
    });
  }
}
