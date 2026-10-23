// رسمُ الأعمدة — `PicPosReportChart`.
//
// ═══ ما يحمي هذا الملفّ ═══
//
// الرسمُ لبنةٌ **ذاتُ ارتفاعٍ محسوب**: كلُّ عمودٍ كسرٌ من ذروةِ السلسلة.
// وهذا يجمع خطرَين لا يمسكهما التحليل:
//
//  ‏١) **القسمةُ على صفر.** فترةٌ بلا بيعٍ ⇒ الذروةُ صفر ⇒ `NaN` في
//     `heightFactor` تُسقط الإطار. وهي حالةٌ يوميّةٌ لا استثناء.
//  ‏٢) **الفيضُ عند الضيق.** التصميمُ مرسومٌ على ١٩٢٠، ولوحُ الكاشير أضيق.
//
// وفوقهما: النسبةُ يجب أن تكون **مقيسةً من القيم**. عمودان قيمتاهما ١٠٠
// و٥٠ لا بدّ أن يظهرا بارتفاعَين مختلفَين فعلاً — وإلّا فالرسمُ زينةٌ لا
// يقول شيئاً، وهو أسوأُ من لا رسم.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_report_chart.dart';

void main() {
  Future<void> show(WidgetTester tester, Widget child, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const wide = Size(1400, 900);
  const narrow = Size(420, 800);

  const series = [
    PicPosChartSeries(label: 'الإيراد', color: Color(0xFF0250D3)),
  ];

  Widget chart(List<PicPosChartBar> bars) => PicPosReportChart(
        title: 'الإيراد الشهري',
        subtitle: 'آخر ٦ أشهر',
        bars: bars,
        series: series,
      );

  final six = [
    const PicPosChartBar(label: 'مارس', value: 100, display: '١٠٠'),
    const PicPosChartBar(label: 'أبريل', value: 50, display: '٥٠'),
    const PicPosChartBar(label: 'مايو', value: 75, display: '٧٥'),
    const PicPosChartBar(label: 'يونيو', value: 20, display: '٢٠'),
    const PicPosChartBar(label: 'يوليو', value: 90, display: '٩٠'),
    const PicPosChartBar(label: 'أغسطس', value: 60, display: '٦٠'),
  ];

  for (final entry in {'عريض': wide, 'ضيّق': narrow}.entries) {
    testWidgets('يُركَّب بلا فيضٍ على عرضٍ ${entry.key}', (tester) async {
      await show(tester, chart(six), entry.value);
      expect(tester.takeException(), isNull);
      // لا يكفي «لم تنهر» — المحتوى المقصود ظاهر.
      expect(find.text('الإيراد الشهري'), findsOneWidget);
      expect(find.text('مارس'), findsOneWidget);
      expect(find.text('أغسطس'), findsOneWidget);
      expect(find.text('الإيراد'), findsOneWidget);
    });
  }

  testWidgets('الارتفاعُ يتبع القيمةَ — لا زينةَ متساوية', (tester) async {
    await show(tester, chart(six), wide);
    // العمودُ الملوَّنُ الوحيدُ داخلَ كلّ `FractionallySizedBox`.
    final boxes = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .toList();
    expect(boxes.length, six.length,
        reason: 'عددُ الأعمدة المرسومة يخالف عددَ القيم');
    final factors = boxes.map((b) => b.heightFactor!).toList();
    // ١٠٠ هي الذروةُ فكسرُها واحدٌ صحيح، و٥٠ نصفُه بالضبط.
    expect(factors[0], closeTo(1.0, 0.001));
    expect(factors[1], closeTo(0.5, 0.001));
    expect(factors[3], closeTo(0.2, 0.001));
    for (final f in factors) {
      expect(f.isNaN, isFalse, reason: 'كسرٌ NaN يُسقط الإطار');
    }
  });

  testWidgets('كلُّ القيم أصفارٌ — لا قسمةَ على صفرٍ ولا انهيار',
      (tester) async {
    await show(
      tester,
      chart(const [
        PicPosChartBar(label: 'السبت', value: 0, display: '٠'),
        PicPosChartBar(label: 'الأحد', value: 0, display: '٠'),
        PicPosChartBar(label: 'الاثنين', value: 0, display: '٠'),
      ]),
      wide,
    );
    expect(tester.takeException(), isNull);
    final factors = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .map((b) => b.heightFactor!)
        .toList();
    expect(factors, hasLength(3));
    for (final f in factors) {
      expect(f.isNaN, isFalse);
      // خطٌّ رفيعٌ يُقرأ — لا فراغٌ يوهم بأن لا عمودَ أصلاً.
      expect(f, greaterThan(0));
    }
    // والمحورُ يبقى مقروءاً.
    expect(find.text('الأحد'), findsOneWidget);
  });

  testWidgets('بلا أعمدةٍ — سطرُ تفسيرٍ لا بطاقةٌ فارغة', (tester) async {
    await show(tester, chart(const []), wide);
    expect(tester.takeException(), isNull);
    expect(find.text('لا بيانات في هذه الفترة'), findsOneWidget);
    expect(find.byType(FractionallySizedBox), findsNothing);
    // والرأسُ يبقى — الفراغُ في البيانات لا في هويّة الرسم.
    expect(find.text('الإيراد الشهري'), findsOneWidget);
  });

  testWidgets('السلسلتان تُقاسان على ذروةٍ واحدة', (tester) async {
    await show(
      tester,
      const PicPosReportChart(
        title: 'الإيراد مقابل التكلفة',
        bars: [
          PicPosChartBar(
              label: 'مارس', value: 100, display: '١٠٠', secondValue: 40),
          PicPosChartBar(
              label: 'أبريل', value: 80, display: '٨٠', secondValue: 20),
        ],
        series: [
          PicPosChartSeries(label: 'الإيراد', color: Color(0xFF0250D3)),
          PicPosChartSeries(label: 'التكلفة', color: Color(0xFFF59E0B)),
        ],
      ),
      wide,
    );
    expect(tester.takeException(), isNull);
    final factors = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .map((b) => b.heightFactor!)
        .toList();
    // عمودان × سلسلتان.
    expect(factors, hasLength(4));
    // الذروةُ ١٠٠ للسلسلتين معاً: لو قِيست كلُّ سلسلةٍ وحدَها لصار ٤٠ ذروةً
    // فبدت التكلفةُ مساويةً للإيراد.
    expect(factors[0], closeTo(1.0, 0.001));
    expect(factors[1], closeTo(0.4, 0.001));
    expect(factors[2], closeTo(0.8, 0.001));
    expect(factors[3], closeTo(0.2, 0.001));
    expect(find.text('التكلفة'), findsOneWidget);
  });
}
