// شاشةُ «الشيكات والأوراق التجارية» — نسخةُ PicPos.
//
// ⚠️ **أخطرُ ما هنا ليس التخطيطَ بل ترشيحَ الحالات.** خمسُ تبويباتٍ تقسّم
// نفسَ الأوراق باتّجاهٍ وحالة، وحرفٌ خاطئٌ في اسم حالةٍ يُخفي أوراقاً من
// جدولٍ بلا أيّ أثرٍ ظاهر — لا استثناءَ ولا فراغَ يلفت النظر، صفٌّ ناقصٌ
// وحسب. فتُقاس هنا القسمةُ نفسُها لا الشكلُ وحدَه.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/commercial_papers_repository.dart'
    show ICommercialPapersRepository;
import 'package:ural_erp/presentation/settings_picpos/screens/cheques_picpos_screen.dart';

CommercialPaperData _paper(
  int id,
  String number, {
  required String direction,
  required String status,
  double amount = 1000,
  DateTime? due,
  String type = 'cheque',
}) =>
    CommercialPaperData(
      id: id,
      paperNumber: number,
      type: type,
      direction: direction,
      partyId: 5,
      amount: amount,
      issueDate: DateTime(2026, 8, 1),
      // ⚠️ **الافتراضُ نسبيٌّ لا تاريخٌ ثابت.** كان `DateTime(2026, 9, 1)`،
      //    فلمّا بلغه التقويمُ صارت كلُّ ورقةٍ بلا `due:` مستحقّةً اليومَ ثمّ
      //    متأخّرةً غداً — وسقط الفحصُ لسببٍ ليس في الكود. والتجهيزةُ التي
      //    تتعفّن بمرور الوقت تُخفي العطبَ وتخترعه معاً.
      dueDate: due ?? DateTime.now().add(const Duration(days: 30)),
      status: status,
      createdAt: DateTime(2026, 8, 1),
      rowVersion: 0,
    );

class _FakeRepo implements ICommercialPapersRepository {
  _FakeRepo(this.papers, this.history);

  final List<CommercialPaperData> papers;
  final List<PaperStatusHistoryData> history;

  @override
  Stream<List<CommercialPaperData>> watchCommercialPapers({
    String? direction,
    String? status,
  }) =>
      Stream.value(papers);

  @override
  Stream<List<PaperStatusHistoryData>> watchPaperHistory(int paperId) =>
      Stream.value(history.where((h) => h.paperId == paperId).toList());

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  final past = DateTime.now().subtract(const Duration(days: 10));
  final soon = DateTime.now().add(const Duration(days: 3));

  final papers = [
    _paper(1, '8842', direction: 'received', status: 'pending', amount: 18000,
        due: soon),
    _paper(2, '9014', direction: 'received', status: 'deposited',
        amount: 12000),
    _paper(3, '7710', direction: 'received', status: 'cashed', amount: 9400),
    _paper(4, '5540', direction: 'received', status: 'bounced', amount: 8400,
        due: past),
    _paper(5, '6621', direction: 'issued', status: 'pending', amount: 24000,
        due: past, type: 'promissory_note'),
    _paper(6, '4418', direction: 'issued', status: 'endorsed', amount: 6200),
  ];

  final history = [
    PaperStatusHistoryData(
      id: 1,
      paperId: 1,
      fromStatus: 'pending',
      toStatus: 'deposited',
      changedAt: DateTime(2026, 8, 12),
      changedBy: 1,
      notes: 'أُودعت ببنك مصر',
    ),
  ];

  Future<void> open(
    WidgetTester tester,
    Size size, {
    List<CommercialPaperData>? papersOverride,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          commercialPapersRepositoryProvider
              .overrideWithValue(_FakeRepo(papersOverride ?? papers, history)),
          allPartiesProvider
              .overrideWith((ref) => Stream.value(const <Party>[])),
        ],
        child: const MaterialApp(home: ChequesPicposScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('التركيبُ على عرضين', () {
    for (final e in const [
      ('عرضٌ يتّسع', Size(1500, 900)),
      ('عرضٌ ضيّق', Size(820, 760)),
    ]) {
      testWidgets('${e.$1} — بلا فيضٍ ولا انهيار', (tester) async {
        await open(tester, e.$2);
        expect(tester.takeException(), isNull,
            reason: 'انهيارُ تخطيطٍ عند العرض ${e.$2.width}');
        expect(find.text('الشيكات والأوراق التجارية'), findsOneWidget);
        expect(find.text('8842'), findsWidgets);
        await teardownTree(tester);
      });
    }
  });

  testWidgets('⚠️ القسمةُ بالاتّجاه صحيحةٌ — لا ورقةَ تظهر في الجهة الخطأ',
      (tester) async {
    await open(tester, const Size(1500, 900));
    // أربعُ واردةٍ واثنتان صادرتان.
    expect(find.text('4'), findsWidgets);
    // والورقةُ الصادرةُ لا تظهر في تبويبة الواردة.
    expect(find.text('6621'), findsNothing,
        reason: 'ورقةٌ صادرةٌ ظهرت في جدول الواردة.');

    await tester.tap(find.text('الصادرة').first);
    await tester.pumpAndSettle();
    expect(find.text('6621'), findsWidgets);
    expect(find.text('8842'), findsNothing,
        reason: 'ورقةٌ واردةٌ ظهرت في جدول الصادرة.');
    await teardownTree(tester);
  });

  testWidgets('والحالاتُ الستُّ مسمّاةٌ — لا كودٌ خامٌّ يظهر للمشغّل',
      (tester) async {
    await open(tester, const Size(1500, 900));
    expect(find.text('بالخزنة'), findsWidgets);
    expect(find.text('مودع'), findsWidgets);
    expect(find.text('محصَّل'), findsWidgets);
    // ولا اسمٌ إنجليزيٌّ خامّ.
    expect(find.text('pending'), findsNothing);
    expect(find.text('deposited'), findsNothing);
    await teardownTree(tester);
  });

  testWidgets('جدولُ الاستحقاق يعرض المفتوحةَ وحدَها ويُعلّم المتأخّرة',
      (tester) async {
    await open(tester, const Size(1500, 900));
    await tester.tap(find.text('جدول الاستحقاق').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // المفتوحةُ ثلاثٌ: ‏8842(pending) · 9014(deposited) · 6621(pending).
    expect(find.text('3 ورقة'), findsOneWidget);
    // والمحصَّلةُ والمرتجعةُ والمظهَّرةُ ليست فيه — لا مطالباتٍ انتهت.
    expect(find.text('7710'), findsNothing,
        reason: 'ورقةٌ محصَّلةٌ ظهرت في جدول الاستحقاق.');
    expect(find.text('5540'), findsNothing,
        reason: 'ورقةٌ مرتجعةٌ ظهرت في جدول الاستحقاق.');

    // ⚠️ والتأخّرُ يُقال نصّاً لا لوناً وحدَه — اللونُ لا يُقرَأ مطبوعاً.
    expect(find.text('متأخّرة عن موعدها'), findsOneWidget);
    // وتسميةُ المؤشّر تبقى مستقلّةً عن نصّ الصفّ.
    expect(find.text('تجاوزت الاستحقاق'), findsOneWidget);
    await teardownTree(tester);
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 🔴 المستحقُّ **اليومَ** ليس متأخّراً
  // ═══════════════════════════════════════════════════════════════════════
  //
  // كان الشرطُ `dueDate.isBefore(DateTime.now())`، و`dueDate` يُخزَّن عند
  // منتصف الليل — فورقةٌ مستحقّةٌ اليومَ تُعَدّ متأخّرةً منذ أوّل دقيقةٍ من
  // يومها، في بطاقة المؤشّر وفي سطر الجدول معاً. والبنكُ يقبلها ذلك اليوم.
  //
  // ولم يظهر العطبُ قبلَ 2026-09-01 لأنّ تجهيزةَ هذا الملفّ كانت تكتب تاريخاً
  // ثابتاً في المستقبل — فلمّا بلغه التقويمُ انكشف. والحارسُ هنا **نسبيٌّ**
  // كي لا يتعفّن مثلَه.

  testWidgets('🔴 ورقةٌ مستحقّةٌ اليومَ لا تُعَدّ متأخّرةً', (tester) async {
    final now = DateTime.now();
    final todayPapers = [
      _paper(1, '8842', direction: 'received', status: 'pending',
          amount: 18000, due: DateTime(now.year, now.month, now.day)),
    ];

    await open(tester, const Size(1500, 900), papersOverride: todayPapers);
    await tester.tap(find.text('جدول الاستحقاق').first);
    await tester.pumpAndSettle();

    // مرساة: الورقةُ في الجدول فعلاً — وإلّا مرَّ التوكيدُ السلبيُّ على فراغ.
    expect(find.text('8842'), findsOneWidget,
        reason: 'الورقةُ المفتوحةُ يجب أن تُعرَض');

    expect(find.text('متأخّرة عن موعدها'), findsNothing,
        reason: 'مستحقٌّ اليومَ ≠ متأخّر — الشرطُ يقارن ببداية اليوم لا باللحظة');
    expect(find.text('0'), findsWidgets,
        reason: 'وبطاقةُ «تجاوزت الاستحقاق» تقول صفراً — والحدُّ نفسُه في '
            'البطاقة والصفّ');
    await teardownTree(tester);
  });

  testWidgets('وسجلُّ الحالات يعرض انتقالاتِ الورقة المختارة', (tester) async {
    await open(tester, const Size(1500, 900));
    await tester.tap(find.text('سجل الحالات').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('أُودعت ببنك مصر'), findsOneWidget);
    await teardownTree(tester);
  });
}
