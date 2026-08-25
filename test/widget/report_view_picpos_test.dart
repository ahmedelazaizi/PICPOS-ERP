// عارضُ التقرير — `ReportViewPicposScreen`.
//
// ═══ ما يحمي هذا الملفّ ═══
//
// العارضُ يركّب خمسَ لبناتٍ في عمودٍ واحدٍ داخلَ `TabBarView`، وهذا أخصبُ
// موضعٍ لأعطال التخطيط: الشريطُ والتبويباتُ في `subHeader` والجسمُ في
// `Expanded`، والرسمُ ذو ارتفاعٍ ثابتٍ والجدولُ ذو عرضٍ محسوب. ووقعت في
// المستودع ستُّ أعطالِ تخطيطٍ في جلسةٍ واحدةٍ لم يمسكها التحليلُ إطلاقاً.
//
// وفوق التخطيط، ثلاثةُ عقودٍ سلوكيّةٍ تُقاس هنا:
//
//  ‏١) **الشارةُ لا تُكتَب قبل قياسها.** تظهر بعد تحميل التبويبة لا قبله —
//     رقمٌ يُكتب قبل الاستعلام رقمٌ يكذب.
//  ‏٢) **التبويبةُ الفارغةُ تقول لماذا** بدل بطاقاتٍ فارغةٍ تبدو عطلاً.
//  ‏٣) **الإخفاقُ يُعرَض ولا يُبتلَع** — استعلامٌ يرمي كان سيترك دوّارةً
//     تدور إلى الأبد.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_data_table.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_hub_kpi.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_report_chart.dart';
import 'package:ural_erp/presentation/reports_picpos/screens/report_view_picpos_screen.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    PicPosReportDefinition def,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ReportViewPicposScreen(definition: def),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const wide = Size(1500, 950);
  const narrow = Size(760, 900);

  PicPosReportTabContent fullContent() => const PicPosReportTabContent(
        badge: '٣',
        kpis: [
          PicPosHubKpi(
            icon: Icons.percent_rounded,
            label: 'الهامش الإجمالي',
            value: '٢٢.٧٪',
            tint: AppColors.primary,
            vs: 'عن المدى',
          ),
          PicPosHubKpi(
            icon: Icons.trending_up_rounded,
            label: 'صافي الربح',
            value: '12,400',
            tint: AppColors.success,
            vs: 'المبيعات ناقص التكلفة',
          ),
        ],
        chart: PicPosReportChart(
          title: 'المبيعات لكلّ تصنيف',
          subtitle: 'ثلاثةُ تصنيفات',
          series: [PicPosChartSeries(label: 'المبيعات', color: AppColors.primary)],
          bars: [
            PicPosChartBar(label: 'مخبوزات', value: 900, display: '٩٠٠'),
            PicPosChartBar(label: 'ألبان', value: 400, display: '٤٠٠'),
            PicPosChartBar(label: 'مشروبات', value: 250, display: '٢٥٠'),
          ],
        ),
        table: PicPosDataTable(
          title: 'الربحُ لكلّ تصنيف',
          columns: [
            PicPosTableColumn('التصنيف', flex: 2),
            PicPosTableColumn('المبيعات', flex: 1, align: PicPosCellAlign.end),
          ],
          rows: [
            PicPosTableRow(
              cells: [PicPosTextCell('مخبوزات'), PicPosTextCell('900')],
            ),
          ],
        ),
      );

  PicPosReportDefinition define({
    required Future<PicPosReportTabContent> Function() first,
    Future<PicPosReportTabContent> Function()? second,
  }) =>
      PicPosReportDefinition(
        id: 'test',
        title: 'هامش الربح',
        subtitle: 'تكلفةُ المبيعات وصافي الربح',
        icon: Icons.percent_rounded,
        tabs: [
          PicPosReportTabDef(
            id: 'a',
            label: 'التصنيفات',
            icon: Icons.pie_chart_rounded,
            note: 'الربحُ = المبيعات ناقص التكلفة.',
            load: (_, _) => first(),
          ),
          if (second != null)
            PicPosReportTabDef(
              id: 'b',
              label: 'هامش الربح',
              icon: Icons.percent_rounded,
              load: (_, _) => second(),
            ),
        ],
      );

  for (final entry in {'عريض': wide, 'ضيّق': narrow}.entries) {
    testWidgets('يُركَّب بلا فيضٍ على عرضٍ ${entry.key}', (tester) async {
      await show(tester, define(first: () async => fullContent()), entry.value);
      expect(tester.takeException(), isNull);
      // لا يكفي «لم تنهر» — الترويسةُ والتبويبةُ والمحتوى ظاهرةٌ فعلاً.
      expect(find.text('هامش الربح'), findsWidgets);
      expect(find.text('التصنيفات'), findsWidgets);
      expect(find.text('الربحُ = المبيعات ناقص التكلفة.'), findsOneWidget);
      expect(find.text('الهامش الإجمالي'), findsOneWidget);
      expect(find.text('المبيعات لكلّ تصنيف'), findsOneWidget);
      expect(find.text('الربحُ لكلّ تصنيف'), findsOneWidget);
    });
  }

  testWidgets('الشارةُ تظهر بعد التحميل لا قبله', (tester) async {
    final gate = Completer<PicPosReportTabContent>();
    tester.view.physicalSize = wide;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ReportViewPicposScreen(
            definition: define(first: () => gate.future),
          ),
        ),
      ),
    );
    await tester.pump();

    // قبلَ التحميل: دوّارةٌ ولا شارة.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('٣'), findsNothing,
        reason: 'شارةٌ ظهرت قبل أن يُقاس عددُها');

    gate.complete(fullContent());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('٣'), findsOneWidget, reason: 'الشارةُ لم تصل التبويبة');
  });

  testWidgets('تبويبةٌ بلا بيانات تقول لماذا', (tester) async {
    await show(
      tester,
      define(first: () async => const PicPosReportTabContent()),
      wide,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('لا بيانات في هذه الفترة'), findsOneWidget);
    expect(find.text('غيّرِ المدى من الشريط أعلاه'), findsOneWidget);
    // والتبويباتُ تبقى — الفراغُ في البيانات لا في الشاشة.
    expect(find.text('التصنيفات'), findsWidgets);
  });

  testWidgets('الإخفاقُ يُعرَض ولا يُبتلَع في دوّارةٍ أبديّة', (tester) async {
    await show(
      tester,
      define(first: () async => throw StateError('عمودٌ مفقود')),
      wide,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('تعذّر حسابُ التقرير'), findsOneWidget);
    expect(find.textContaining('عمودٌ مفقود'), findsOneWidget);
  });

  testWidgets('كلُّ تبويبةٍ تُحمَّل مرّةً واحدةً — والعودةُ لا تُعيد', (tester) async {
    var firstLoads = 0;
    var secondLoads = 0;
    await show(
      tester,
      define(
        first: () async {
          firstLoads++;
          return fullContent();
        },
        second: () async {
          secondLoads++;
          return const PicPosReportTabContent();
        },
      ),
      wide,
    );

    // كلُّ التبويبات تُحمَّل عند الفتح — **مرّةً واحدةً لكلٍّ**. والسببُ أنّ
    // الشارةَ تقع على تبويبةٍ لم تُفتَح، ولا تصدق إلّا إن قِيست.
    expect(firstLoads, 1);
    expect(secondLoads, 1, reason: 'تبويبةٌ بلا تحميلٍ = شارةٌ لا تُقاس');

    await tester.tap(find.text('هامش الربح').last);
    await tester.pumpAndSettle();

    expect(secondLoads, 1, reason: 'الاستعلامُ أُعيد عند فتح التبويبة');
    // ⚠️ الفحصُ الجوهريّ: التخزينُ بمفتاحِ (تبويبة، مدى) — العودةُ لا تُعيد
    // الاستعلام. بلا ذلك يُعاد مع كلّ إعادةِ بناءٍ في `TabBarView`.
    await tester.tap(find.text('التصنيفات').last);
    await tester.pumpAndSettle();
    expect(firstLoads, 1, reason: 'الاستعلامُ أُعيد عند العودة للتبويبة');
  });
}
