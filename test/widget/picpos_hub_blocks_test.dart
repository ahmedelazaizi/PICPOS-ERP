// لبناتُ شاشات التصميم الجديدة — المؤشّرُ والجدولُ وبطاقةُ الكيان.
//
// ═══ لماذا يُقاس عرضان لكلّ لبنة ═══
//
// الثلاثةُ **شبكاتٌ ذاتُ عرضٍ محسوب**: صفُّ المؤشّرات يقسّم المتاحَ على
// عددِ الأعمدة، والجدولُ يقسّمه على أوزان الأعمدة، وشبكةُ البطاقات كذلك.
// وحسابٌ خاطئٌ لا يظهر في التحليل — يظهر شريطاً أصفرَ وأسودَ في التشغيل.
//
// وقد وقع هذا فعلاً في هذه الجلسة مرّتين (‏٧ ثمّ ١٠٧ بكسل) في مصفوفة
// الصلاحيات، وأمسكه اختبارُ التركيب وحدَه. فكلُّ لبنةٍ هنا تُقاس على عرضٍ
// يتّسع وعرضٍ لا يتّسع، ويُشترط ألّا ترمي الشجرةُ شيئاً في الحالتين.
//
// ⚠️ **ولا يكفي «لم تنهر»**: كلُّ فحصٍ يؤكّد ظهورَ المحتوى المقصود — فشجرةٌ
// فارغةٌ لا ترمي شيئاً وتمرّ.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_data_table.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_entity_card.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_hub_kpi.dart';

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

  group('صفُّ المؤشّرات', () {
    Widget row() => const PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: Icons.store_rounded,
              label: 'الفروع النشطة',
              value: '٣',
              tint: AppColors.primary,
              delta: '١',
              vs: 'من ٤ مسجلة',
            ),
            PicPosHubKpi(
              icon: Icons.inventory_2_rounded,
              label: 'قيمة المخزون',
              value: '1,920,600',
              tint: AppColors.warning,
              delta: '٤٪',
              vs: 'بالتكلفة',
            ),
            PicPosHubKpi(
              icon: Icons.warning_amber_rounded,
              label: 'أصناف تحت الحد',
              value: '١٤',
              tint: AppColors.error,
              delta: '٣',
              up: false,
            ),
            PicPosHubKpi(
              icon: Icons.link_rounded,
              label: 'بلا فرق',
              value: '٥',
              tint: AppColors.success,
              delta: '—',
              vs: 'ومخزن واحد عام',
            ),
          ],
        );

    for (final e in const [('عرضٌ يتّسع', wide), ('عرضٌ ضيّق', narrow)]) {
      testWidgets('${e.$1} — بلا فيض', (tester) async {
        await show(tester, row(), e.$2);
        expect(tester.takeException(), isNull);
        expect(find.text('الفروع النشطة'), findsOneWidget);
        expect(find.text('1,920,600'), findsOneWidget);
      });
    }

    testWidgets('«—» تُعدّ لا فرقاً فيُخفى السهمُ ويبقى نصُّ المقارنة',
        (tester) async {
      await show(tester, row(), wide);
      // أربعةُ مؤشّراتٍ وواحدٌ منها بلا فرق ⇒ ثلاثةُ أسهمٍ لا أربعة.
      final up = find.byIcon(Icons.trending_up_rounded);
      final down = find.byIcon(Icons.trending_down_rounded);
      expect(
        tester.widgetList(up).length + tester.widgetList(down).length,
        3,
        reason: 'رُسم سهمٌ لمؤشّرٍ فرقُه «—» — والمشغّلُ يقرأ السهمَ اتّجاهاً.',
      );
      expect(find.text('ومخزن واحد عام'), findsOneWidget);
    });
  });

  group('جدولُ البيانات', () {
    Widget table({List<String>? totals}) => PicPosDataTable(
          title: 'المخازن',
          subtitle: 'المخزن يتبع فرعاً واحداً',
          columns: const [
            PicPosTableColumn('المخزن', flex: 1.9),
            PicPosTableColumn('الفرع المرتبط', flex: 1.3),
            PicPosTableColumn('النوع', flex: 1.4),
            PicPosTableColumn('الأصناف',
                flex: 1.1, align: PicPosCellAlign.end),
            PicPosTableColumn('حصة من المخزون', flex: 1.5),
            PicPosTableColumn('إجراء', flex: 1.1),
          ],
          chips: const [
            PicPosTableChip(label: 'كل المخازن', count: '٦'),
            PicPosTableChip(label: 'بها نقص', count: '٤'),
          ],
          selectedChip: 0,
          rows: [
            const PicPosTableRow(cells: [
              PicPosTextCell('المخزن الرئيسي',
                  sub: 'افتراضي للفرع',
                  icon: Icons.warehouse_rounded,
                  tint: AppColors.primary),
              PicPosTextCell('المعادي'),
              PicPosPillCell('بيع', AppColors.success),
              PicPosTextCell('٣٨٤٠'),
              PicPosBarCell('٦١.٥٪', 0.615, AppColors.warning),
              PicPosButtonCell('تعديل',
                  icon: Icons.edit_rounded, tint: AppColors.primary),
            ]),
            const PicPosTableRow(cells: [
              PicPosTextCell('مخزن التالف'),
              PicPosTextCell('المعادي'),
              PicPosPillCell('محجوز', AppColors.error),
              PicPosTextCell('٦٠'),
              PicPosTrendCell('٢.٣٪', up: false),
              PicPosButtonCell('عرض',
                  icon: Icons.visibility_rounded, tint: AppColors.primary),
            ]),
          ],
          totals: totals,
        );

    for (final e in const [('عرضٌ يتّسع', wide), ('عرضٌ ضيّق', narrow)]) {
      testWidgets('${e.$1} — بلا فيض والمحتوى ظاهر', (tester) async {
        await show(tester, table(), e.$2);
        expect(tester.takeException(), isNull);
        expect(find.text('المخزون'), findsNothing); // ليس عنواناً هنا
        expect(find.text('المخازن'), findsWidgets);
        expect(find.text('المخزن الرئيسي'), findsOneWidget);
        expect(find.text('بيع'), findsOneWidget);
        expect(find.text('٦١.٥٪'), findsOneWidget);
        expect(find.text('تعديل'), findsOneWidget);
      });
    }

    testWidgets('صفُّ المجاميع يُرسَم بطول الأعمدة', (tester) async {
      await show(
        tester,
        table(totals: const ['٦ مخازن', '', '', '٤٧٤٠', '', '']),
        wide,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('٦ مخازن'), findsOneWidget);
      expect(find.text('٤٧٤٠'), findsOneWidget);
    });

    testWidgets('⚠️ ومجاميعُ بطولٍ مخالفٍ تُوقِف البناءَ بدل أن تُزيح الخانات',
        (tester) async {
      // لو مرّت لانزاحت كلُّ خانةٍ عن عمودها وقُرئ رقمٌ تحت عنوانٍ ليس له.
      //
      // ⚠️ **والتقاطُها بـ`takeException` لا بـ`throwsA`**: التأكيدُ يقع داخلَ
      //    `build` فيلتقطه إطارُ الاختبار ولا يخرج من `pumpWidget` استثناءً
      //    يُمسَك بالمُطابِق. وأوّلُ صياغةٍ فشلت لهذا السبب لا لأنّ الحارسَ
      //    غيرُ عامل.
      await show(tester, table(totals: const ['واحد']), wide);
      expect(tester.takeException(), isA<AssertionError>(),
          reason: 'صفُّ مجاميعَ بطولٍ مخالفٍ مرّ بلا اعتراض.');
    });

    testWidgets('جدولٌ بلا صفوفٍ يقول ذلك ولا يظهر فارغاً', (tester) async {
      await show(
        tester,
        const PicPosDataTable(
          title: 'المخازن',
          columns: [PicPosTableColumn('المخزن'), PicPosTableColumn('الفرع')],
          rows: [],
        ),
        wide,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('لا صفوفَ لعرضها'), findsOneWidget);
    });
  });

  group('بطاقةُ الكيان', () {
    Widget card({VoidCallback? onOpen}) => PicPosEntityCard(
          title: 'مسار شرق القاهرة',
          subtitle: 'المعادي · المقطم · دار السلام',
          tint: AppColors.success,
          icon: Icons.route_rounded,
          status: 'متقدم على الهدف',
          statusTint: AppColors.success,
          stats: const [
            PicPosEntityStat('العملاء', '٢٤'),
            PicPosEntityStat('زيارات الشهر', '١٨', tint: AppColors.success),
            PicPosEntityStat('المبيعات', '42,600', tint: AppColors.success),
          ],
          chips: const [
            PicPosEntityChip(Icons.person_rounded, 'يوسف طارق'),
            PicPosEntityChip(Icons.flag_rounded, '١١٢٪ من الهدف'),
          ],
          onOpen: onOpen,
        );

    for (final e in const [('عرضٌ يتّسع', wide), ('عرضٌ ضيّق', narrow)]) {
      testWidgets('${e.$1} — بلا فيض والمحتوى ظاهر', (tester) async {
        await show(
          tester,
          PicPosEntityCardGrid(children: [card(), card()]),
          e.$2,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('مسار شرق القاهرة'), findsNWidgets(2));
        expect(find.text('٢٤'), findsNWidgets(2));
        expect(find.text('يوسف طارق'), findsNWidgets(2));
      });
    }

    testWidgets('«الملف الكامل» لا يظهر بلا وجهةٍ تُفتَح', (tester) async {
      await show(tester, card(), wide);
      expect(find.text('الملف الكامل'), findsNothing,
          reason: 'سطرٌ يَعِد بتفصيلٍ ولا يفتح شيئاً.');

      var opened = 0;
      await show(tester, card(onOpen: () => opened++), wide);
      expect(find.text('الملف الكامل'), findsOneWidget);
      await tester.tap(find.text('مسار شرق القاهرة'));
      await tester.pumpAndSettle();
      expect(opened, 1, reason: 'البطاقةُ تعرض السطرَ ولا تستجيب للنقر.');
    });
  });
}
