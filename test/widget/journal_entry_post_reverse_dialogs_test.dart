// test/widget/journal_entry_post_reverse_dialogs_test.dart
//
// حوارا «اعتماد القيد» و«عكس القيد» — ملخّصُ التصميم لا سطرٌ فرعيّ.
//
// ═══ تصحيحُ قياسٍ في مستند التسليم ═══
//
// المستندُ يقول إنّ ثلاثةً من حوارات التصميم الأربعة «غيرُ مبنيّةٍ أصلاً»
// وإنّ الكودَ «فيه أثرٌ لـ`draft` وحدَه». **والقياسُ يعكسه**: `post`
// و`reverse` مبنيّان ويستعملان `showPicPosConfirm` بعناوين التصميم ونصوصِه
// وأزرارِه حرفاً؛ و`draft` **لا أثرَ له** في القيود (‏الـ`draft` في القوائم
// المالية `statusCode` لمستندٍ لا مسودّةُ قيد). والناقصُ حقّاً `postNew`
// وحدَه — وهو قرارُ منتَجٍ لا تنفيذ.
//
// ═══ فالفجوةُ الباقيةُ هنا واحدةٌ ومحدّدة ═══
//
// التصميمُ يعرض تحت نصِّ كلِّ حوارٍ **جدولَ ملخّصٍ** بأربعة أسطر:
// رقم القيد · البيان · التاريخ · القيمة. والكودُ كان يعرض سطرَ عنوانٍ
// فرعيٍّ بالرقم والتاريخ فقط — فلا **البيان** ولا **القيمة**.
//
// ⚠️ والقيمةُ ليست زينة: «اعتماد القيد» يجعله مؤثّراً على الأرصدة ولا
//    يمكن تعديله. فرقمُ ما سيتحرّك يجب أن يُقرأ في الحوار نفسِه، لا أن
//    يُفترَض من بطاقةٍ خلفَه.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/accounting_repository.dart';
import 'package:picpos_erp/presentation/accounting_picpos/journal_entries_picpos_screen.dart';

JournalEntryData _entry({
  required int id,
  required String number,
  required String desc,
  required bool needsApproval,
  bool isAutoPosted = false,
}) =>
    JournalEntryData(
      id: id,
      entryNumber: number,
      entryDate: DateTime(2026, 8, 12),
      description: desc,
      isPosted: true,
      isAutoPosted: isAutoPosted,
      needsApproval: needsApproval,
      exchangeRate: 1,
      isDeleted: false,
      updatedAt: DateTime(2026, 8, 12),
      rowVersion: 1,
      createdAt: DateTime(2026, 8, 12),
    );

class _FakeAccountingRepo implements IAccountingRepository {
  _FakeAccountingRepo({required this.entries, this.lines = const []});

  final List<JournalEntryData> entries;
  final List<Map<String, dynamic>> lines;

  @override
  Stream<List<JournalEntryData>> watchJournalEntries({
    DateTime? from,
    DateTime? to,
  }) =>
      Stream.value(entries);

  /// مجاميعُ الصفوف — الشريطُ والأعمدةُ الثلاثةُ يقرآنها مُجمَّعةً مرّةً
  /// واحدةً لا بنداءٍ لكلّ قيد. وتُشتقُّ هنا من نفس [lines] كي لا يختلف ما
  /// يُقرأ على الصفّ عمّا يُقرأ في حواره.
  @override
  Stream<Map<int, ({double debit, double credit})>> watchJournalEntryTotals({
    DateTime? from,
    DateTime? to,
  }) =>
      Stream.value({
        for (final e in entries)
          e.id: (
            debit: lines.fold<double>(
                0, (s, l) => s + ((l['debit'] as num?)?.toDouble() ?? 0)),
            credit: lines.fold<double>(
                0, (s, l) => s + ((l['credit'] as num?)?.toDouble() ?? 0)),
          ),
      });

  @override
  Future<List<Map<String, dynamic>>> getJournalEntryLinesWithAccounts(
    int entryId,
  ) async =>
      lines;

  @override
  Future<List<Account>> getAllAccounts() async => const [];

  @override
  Future<List<CostCenter>> getCostCenters() async => const [];

  @override
  Stream<List<JournalEntryTemplateData>> watchActiveTemplates() =>
      Stream.value(const []);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // ‏٥٠٠ مديناً و٥٠٠ دائناً. والقيمةُ المتوقَّعةُ ٥٠٠ لا ١٠٠٠: القيدُ متوازنٌ
  // بحكم تعريفه، فجمعُ الطرفَين يضاعف ما يقرأه المشغّلُ قبل الاعتماد.
  final expected = (500.0).toStringAsFixed(AppConstants.decimalPlaces);
  final doubled = (1000.0).toStringAsFixed(AppConstants.decimalPlaces);

  const lines = [
    {
      'account_code': '1111',
      'account_name': 'الصندوق',
      'debit': 500.0,
      'credit': 0.0,
    },
    {
      'account_code': '4121',
      'account_name': 'مبيعات محلية',
      'debit': 0.0,
      'credit': 500.0,
    },
  ];

  Future<void> pump(
    WidgetTester tester,
    double width, {
    required bool needsApproval,
    bool isAutoPosted = false,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountingRepositoryProvider.overrideWithValue(
            _FakeAccountingRepo(
              entries: [
                _entry(
                  id: 1,
                  number: 'JE-2026-0042',
                  desc: 'إثبات مبيعات نقدية',
                  needsApproval: needsApproval,
                  isAutoPosted: isAutoPosted,
                ),
              ],
              lines: lines,
            ),
          ),
          allBranchesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: JournalEntriesPicPosScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> openVia(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon).first);
    await tester.pump();
    // جلبُ الأسطر غيرُ متزامنٍ — إطارٌ له ثمّ إطارٌ لحركة الحوار.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    group('عرض $w', () {
      testWidgets('«اعتماد القيد» يعرض ملخّصَ التصميم بأسطره الأربعة',
          (tester) async {
        await pump(tester, width, needsApproval: true);
        await openVia(tester, PhosphorIconsBold.checkCircle);

        expect(find.text('اعتماد القيد'), findsWidgets);
        // مفاتيحُ التصميم الأربعة.
        expect(find.text('رقم القيد'), findsOneWidget);
        expect(find.text('البيان'), findsOneWidget);
        expect(find.text('التاريخ'), findsOneWidget);
        expect(find.text('القيمة'), findsOneWidget);
        // وقيمُها — لا المفاتيحُ وحدَها.
        expect(find.text('JE-2026-0042'), findsWidgets);
        expect(find.text('إثبات مبيعات نقدية'), findsWidgets);
        expect(find.textContaining(expected), findsWidgets);
        // ⚠️ المصيدةُ الحقيقيّة: جمعُ المدين والدائن معاً.
        expect(find.textContaining(doubled), findsNothing);
        expect(find.text('تأكيد الاعتماد'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('و«عكس القيد» يعرضه كذلك مع تحذيرِ القيد الآليّ',
          (tester) async {
        await pump(
          tester,
          width,
          needsApproval: false,
          isAutoPosted: true,
        );
        await openVia(tester, PhosphorIconsBold.arrowUUpLeft);

        expect(find.text('عكس القيد'), findsWidgets);
        expect(find.text('رقم القيد'), findsOneWidget);
        expect(find.text('القيمة'), findsOneWidget);
        expect(find.textContaining(expected), findsWidgets);
        expect(find.textContaining(doubled), findsNothing);
        // ⚠️ تحذيرُ MJE-2 لا يسقط بإضافة الملخّص.
        expect(
          find.textContaining('الأفضل عكسُه من المستند المصدر'),
          findsOneWidget,
        );
        expect(find.text('تأكيد العكس'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('وقيدٌ يدويٌّ لا يحمل تحذيرَ الآليّ', (tester) async {
        await pump(tester, width, needsApproval: false);
        await openVia(tester, PhosphorIconsBold.arrowUUpLeft);

        expect(find.text('عكس القيد'), findsWidgets);
        expect(
          find.textContaining('الأفضل عكسُه من المستند المصدر'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('و«إلغاء» يُغلق حوارَ الاعتماد بلا اعتماد', (tester) async {
        await pump(tester, width, needsApproval: true);
        await openVia(tester, PhosphorIconsBold.checkCircle);

        await tester.tap(find.widgetWithText(TextButton, 'إلغاء'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('تأكيد الاعتماد'), findsNothing);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });
    });
  }
}
