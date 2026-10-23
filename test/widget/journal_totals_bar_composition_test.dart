// شريطُ إجماليّات اليومية العامة — **ولماذا «الفرق = 0» قد يكذب**.
//
// ═══ قرارُ المالك 2026-09-18 ═══
//
// تصميمُ اليومية العامة يرسم تحت القائمة شريطاً بأربع بطاقات: **عدد القيود ·
// إجمالي المدين · إجمالي الدائن · الفرق**، ويرسم على كلّ صفّ عمودَي
// «إجمالي المدين/الدائن» و«الفرق».
//
// ═══ 🔴 والعطبُ الذي يُبنى الشريطُ لكشفه ═══
//
// قيدان: أحدُهما مدينُه زائدٌ مئةً، والآخرُ دائنُه زائدٌ مئةً. **مجموعُهما
// فرقُه صفر**. فشريطٌ يقرأ فرقَ المجموع يعرض «٠» أخضرَ وفي الصفحة قيدان
// مكسوران — وهو بالضبط ما جاء الشريطُ ليقوله.
//
// فالرقمُ المعروضُ فرقُ المجموع (وإلّا لم يطابق طرحَ العمودَين بجانبه)،
// **والحكمُ من [JournalBalance.worstOf]** — أسوأِ قيدٍ منفرد.
//
// ⚠️ **والقياسُ على النصِّ الظاهر لا على اللون**: لونٌ يتغيّر لا يُقرأ في
// لقطةٍ نصّيّة، ومستخدمٌ لا يميّز الأحمرَ لا يرى شيئاً. فالحالةُ تُقال
// كلمةً.
//
// ⚠️ **وثلاثةُ عروض**: ثلاثةُ أعمدةٍ رقميّةٍ أُضيفت إلى صفٍّ مكتظٍّ أصلاً،
// و`RenderFlex overflowed` **لا يرمي في الإصدار** — يرسم شريطاً أصفرَ ويمضي.
// فيُلتقَط `FlutterError.onError` صراحةً.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/accounting_repository.dart';
import 'package:picpos_erp/presentation/accounting_picpos/journal_entries_picpos_screen.dart';

JournalEntryData _entry({
  required int id,
  required String number,
  required String desc,
  bool isPosted = true,
  bool needsApproval = false,
  bool isAutoPosted = false,
}) =>
    JournalEntryData(
      id: id,
      entryNumber: number,
      entryDate: DateTime(2026, 9, 8),
      description: desc,
      isPosted: isPosted,
      isAutoPosted: isAutoPosted,
      needsApproval: needsApproval,
      exchangeRate: 1,
      isDeleted: false,
      updatedAt: DateTime(2026, 9, 8),
      rowVersion: 1,
      createdAt: DateTime(2026, 9, 8),
    );

class _FakeAccountingRepo implements IAccountingRepository {
  _FakeAccountingRepo({required this.entries, required this.totals});

  final List<JournalEntryData> entries;
  final Map<int, ({double debit, double credit})> totals;

  @override
  Stream<List<JournalEntryData>> watchJournalEntries({
    DateTime? from,
    DateTime? to,
  }) =>
      Stream.value(entries);

  @override
  Stream<Map<int, ({double debit, double credit})>> watchJournalEntryTotals({
    DateTime? from,
    DateTime? to,
  }) =>
      Stream.value(totals);

  @override
  Future<List<Map<String, dynamic>>> getJournalEntryLinesWithAccounts(
          int entryId) async =>
      const [];

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

/// نفسُ المنسّق الذي تقرؤه الشاشة — كي لا يسقط الفحصُ على لغةِ الأرقام.
String _m(double v) => journalMoney.format(v);

void main() {
  /// يبني الشاشةَ ويُرجع ما سجّله `FlutterError.onError` من أعطاب تخطيط.
  Future<List<String>> pump(
    WidgetTester tester,
    double width, {
    required List<JournalEntryData> entries,
    required Map<int, ({double debit, double credit})> totals,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString());
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountingRepositoryProvider.overrideWithValue(
              _FakeAccountingRepo(entries: entries, totals: totals),
            ),
            allBranchesProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: const MaterialApp(home: JournalEntriesPicPosScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    } finally {
      FlutterError.onError = previous;
    }
    return errors;
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  final balancedPair = [
    _entry(id: 1, number: 'JV-0031', desc: 'إثبات مصروف إيجار'),
    _entry(id: 2, number: 'JV-0032', desc: 'إثبات مبيعات نقدية'),
  ];
  const balancedTotals = {
    1: (debit: 1000.0, credit: 1000.0),
    2: (debit: 500.0, credit: 500.0),
  };

  // 🔴 مكسوران بمقدارَين متعاكسَين — مجموعُهما متّزنٌ تماماً.
  const cancellingTotals = {
    1: (debit: 1100.0, credit: 1000.0),
    2: (debit: 500.0, credit: 600.0),
  };

  for (final width in [900.0, 1280.0, 1920.0]) {
    final w = width.toInt();

    group('عرض $w', () {
      testWidgets('الشريطُ يحمل بطاقاتِ التصميم الأربعةَ بأرقامها',
          (tester) async {
        final errors = await pump(tester, width,
            entries: balancedPair, totals: balancedTotals);

        expect(find.text('عدد القيود'), findsOneWidget);
        expect(find.text('إجمالي المدين'), findsOneWidget);
        expect(find.text('إجمالي الدائن'), findsOneWidget);
        expect(find.text('الفرق'), findsOneWidget);

        expect(find.text('2'), findsWidgets, reason: 'عددُ القيود لا يُعرَض');
        // ‏١٥٠٠ مجموعُ الطرفَين — ولا يُخلَط بمجاميع الصفوف المفردة.
        expect(find.text(_m(1500)), findsWidgets);
        expect(errors, isEmpty, reason: 'عطبُ تخطيطٍ عند $w: $errors');
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('وأعمدةُ الصفّ الثلاثةُ تُعرَض لكلّ قيد', (tester) async {
        final errors = await pump(tester, width,
            entries: balancedPair, totals: balancedTotals);

        expect(find.text(_m(1000)), findsWidgets,
            reason: 'مجموعُ القيد الأوّل غائبٌ عن صفّه');
        expect(find.text(_m(500)), findsWidgets,
            reason: 'مجموعُ القيد الثاني غائبٌ عن صفّه');
        expect(errors, isEmpty, reason: 'عطبُ تخطيطٍ عند $w: $errors');

        await teardown(tester);
      });

      testWidgets('🔴 ومجموعٌ متّزنٌ فوق قيدَين مكسورَين يُقال نصّاً',
          (tester) async {
        // ‏+١٠٠ و−١٠٠: `الفرق` صفرٌ بالجمع، والصفحةُ فيها كسران.
        final errors = await pump(tester, width,
            entries: balancedPair, totals: cancellingTotals);

        expect(find.text(_m(0)), findsWidgets,
            reason: 'فرقُ المجموع لا يُعرَض — وهو ما يطابق طرحَ العمودَين');
        expect(
          find.text('بينها قيدٌ غيرُ متوازن'),
          findsOneWidget,
          reason: 'الشريطُ يقول «متوازن» وتحته قيدان مكسوران — '
              'وهو عينُ ما جاء ليكشفه',
        );
        expect(errors, isEmpty, reason: 'عطبُ تخطيطٍ عند $w: $errors');

        await teardown(tester);
      });

      testWidgets('ومرساةٌ — صفحةٌ سليمةٌ لا تحمل التنبيه', (tester) async {
        // بلا هذه المرساة يمرّ الفحصُ أعلاه لو عُرض التنبيهُ دائماً.
        await pump(tester, width,
            entries: balancedPair, totals: balancedTotals);
        expect(find.text('بينها قيدٌ غيرُ متوازن'), findsNothing);

        await teardown(tester);
      });
    });
  }

  group('و«لا يُعكَس إلّا ما رُحِّل»', () {
    IconButton reverseButton(WidgetTester tester) => tester.widget<IconButton>(
          find.ancestor(
            of: find.byIcon(PhosphorIconsBold.arrowUUpLeft),
            matching: find.byType(IconButton),
          ),
        );

    testWidgets('قيدٌ مُرحَّلٌ — الزرُّ عاملٌ', (tester) async {
      await pump(
        tester,
        1280,
        entries: [_entry(id: 1, number: 'JV-0031', desc: 'مُرحَّل')],
        totals: const {1: (debit: 100.0, credit: 100.0)},
      );
      expect(reverseButton(tester).onPressed, isNotNull);
      await teardown(tester);
    });

    testWidgets('🔴 ومسوّدةٌ — الزرُّ معطَّلٌ بسببٍ ظاهر', (tester) async {
      // نقرةٌ واحدةٌ عليها كانت تُنشئ عكساً **مُرحَّلاً** لأصلٍ لم يدخل
      // الأستاذَ — فتتحرّك الأرصدةُ بلا ما يقابلها. والقاعدةُ محروسةٌ في
      // الـDAO؛ وهذا يمنع النقرةَ قبل أن تقع.
      await pump(
        tester,
        1280,
        entries: [
          _entry(
            id: 1,
            number: 'JV-0031',
            desc: 'مسودة',
            isPosted: false,
            needsApproval: true,
          )
        ],
        totals: const {1: (debit: 100.0, credit: 100.0)},
      );

      expect(reverseButton(tester).onPressed, isNull,
          reason: 'المسوّدةُ تُعكَس بنقرة — والأستاذُ يتحرّك بلا مقابل');
      expect(reverseButton(tester).tooltip, contains('مسودة'),
          reason: 'زرٌّ معطَّلٌ بلا سببٍ ظاهرٍ يبدو عُطلاً في البرنامج');
      // ومقصورٌ على الصفّ كذلك — الشريحةُ في المرشِّح تحمل نفسَ النصّ.
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('بانتظار الاعتماد'),
        ),
        findsOneWidget,
        reason: 'حالةُ القيد لا تُقرأ على صفّه',
      );

      await teardown(tester);
    });

    testWidgets('🔴 ومرشِّحُ «الحالة» يحلّ محلَّ بطاقةِ العدّ التي أخلت مكانَها',
        (tester) async {
      // بطاقةُ «بانتظار الاعتماد» في شريط الإجماليّات أخلت مكانَها لبطاقات
      // التصميم الأربع. وإسقاطُ العدّ بلا بديلٍ يترك القيودَ المنتظرةَ بلا
      // ما يجمعها — فالمرشِّحُ بديلُها، وهو **يُظهرها** لا يَعُدُّها.
      await pump(
        tester,
        1280,
        entries: [
          _entry(id: 1, number: 'JV-0031', desc: 'مُرحَّل'),
          _entry(
              id: 2,
              number: 'JV-0032',
              desc: 'مسودة',
              isPosted: false,
              needsApproval: true),
        ],
        totals: const {
          1: (debit: 100.0, credit: 100.0),
          2: (debit: 300.0, credit: 300.0),
        },
      );
      expect(find.text('JV-0031'), findsOneWidget);
      expect(find.text('JV-0032'), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byType(SegmentedButton<String>),
        matching: find.text('بانتظار الاعتماد'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('JV-0032'), findsOneWidget);
      expect(find.text('JV-0031'), findsNothing,
          reason: 'المرشِّحُ لا يُرشِّح — فلا بديلَ للعدّ الساقط');
      expect(find.text(_m(300)), findsWidgets,
          reason: 'الشريطُ لا يتبع الترشيحَ — وهو يصف ما تحته');

      await teardown(tester);
    });

    testWidgets('و«مرحّل» تُقال صراحةً لا بغياب شارة', (tester) async {
      await pump(
        tester,
        1280,
        entries: [_entry(id: 1, number: 'JV-0031', desc: 'مُرحَّل')],
        totals: const {1: (debit: 100.0, credit: 100.0)},
      );
      // ⚠️ **مقصورٌ على الصفّ**: «مرحّل» صارت أيضاً شريحةً في مرشِّح
      //    «الحالة»، فـ`find.text` وحدَه يجدها مرّتَين ويمرّ بلا شارةٍ على
      //    الصفّ إطلاقاً.
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('مرحّل'),
        ),
        findsOneWidget,
      );
      await teardown(tester);
    });
  });
}
