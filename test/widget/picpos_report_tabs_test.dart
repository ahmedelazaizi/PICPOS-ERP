// تبويباتُ شاشة التقرير على هويّة PicPos.
//
// ═══ العطبُ المحروس ═══
//
// شريطُ التبويبات الجديدُ **لا يملك الحالة** — يقرأ `TabController` الذي
// تملكه الشاشةُ ويكتب فيه. ولو ملَكها لصار للشاشة مصدرا حقيقةٍ للتبويب
// المفتوح: الشريطُ يقول واحداً و`TabBarView` يعرض آخر، بلا خطأٍ ولا انهيار
// — فقط محتوىً لا يطابق عنوانَه.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_report_tabs.dart';

void main() {
  const tabs = <PicPosReportTab>[
    (label: 'ملخص', icon: PhosphorIconsBold.gauge, badge: null),
    (label: 'الفواتير', icon: PhosphorIconsBold.receipt, badge: '٤٨٧'),
    (label: 'حسب الكاشير', icon: null, badge: null),
  ];

  Future<TabController> pump(
    WidgetTester tester, {
    int initialIndex = 0,
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    late TabController controller;
    await tester.pumpWidget(MaterialApp(
      home: DefaultTabController(
        length: tabs.length,
        initialIndex: initialIndex,
        child: Builder(builder: (context) {
          controller = DefaultTabController.of(context);
          return Scaffold(
            body: PicPosReportTabs(controller: controller, tabs: tabs),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('يرسم كلَّ تبويبٍ بعنوانه، والشارةَ حيث تُعطى', (tester) async {
    await pump(tester);
    for (final t in tabs) {
      expect(find.text(t.label), findsOneWidget);
    }
    expect(find.text('٤٨٧'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsBold.gauge), findsOneWidget);
  });

  testWidgets('والنشطُ وحدَه بخطٍّ سفليٍّ بلون العلامة', (tester) async {
    await pump(tester, initialIndex: 1);

    int underlined() => tester
        .widgetList<Container>(find.descendant(
          of: find.byType(PicPosReportTabs),
          matching: find.byType(Container),
        ))
        .where((c) {
          final d = c.decoration;
          if (d is! BoxDecoration) return false;
          return d.border?.bottom.color == AppColors.primary;
        })
        .length;

    expect(underlined(), 1,
        reason: 'الخطُّ السفليُّ يجب أن يقع على تبويبٍ واحدٍ — أكثرُ من واحدٍ '
            'يعني أنّ الشريطَ لا يقرأ التبويبَ المفتوح.');
  });

  testWidgets('واللمسُ يكتب في متحكّم الشاشة لا في حالةٍ خاصّة',
      (tester) async {
    final controller = await pump(tester);
    expect(controller.index, 0);

    await tester.tap(find.text('حسب الكاشير'));
    await tester.pumpAndSettle();

    expect(controller.index, 2,
        reason: 'الشريطُ لم يكتب في `TabController` — فمحتوى `TabBarView` '
            'يبقى على التبويب القديم بينما يبدو الشريطُ منتقلاً.');
  });

  testWidgets('ولا يفيض بستّة تبويباتٍ طويلةٍ على شاشةٍ ضيّقة',
      (tester) async {
    tester.view.physicalSize = const Size(700, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: DefaultTabController(
        length: 6,
        child: Builder(builder: (context) {
          return Scaffold(
            body: PicPosReportTabs(
              controller: DefaultTabController.of(context),
              tabs: const [
                (label: 'ميزان المراجعة', icon: null, badge: null),
                (label: 'قائمة الدخل (P&L)', icon: null, badge: null),
                (label: 'الميزانية العمومية', icon: null, badge: null),
                (label: 'التدفقات النقدية', icon: null, badge: null),
                (label: 'تقادم الذمم', icon: null, badge: null),
                (label: 'مطابقة الترحيل', icon: null, badge: null),
              ],
            ),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'ستّةُ تبويباتٍ بعناوينَ طويلةٍ هي حالُ القوائم المالية — '
            'وصفٌّ ثابتٌ يفيض عليها.');
  });
}
