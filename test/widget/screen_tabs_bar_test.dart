// شريطُ التابات — بلاغُ المالك 2026-09-12: «عند الضغط عليه لا يتم التنقل
// الى الشاشة المضغوط عليها ولا يفتح اكثر من تابين».
//
// ⚠️ **والبلاغان وصفٌ دقيقٌ لعطبَين في `AppBreadcrumbs`**، ولذلك يُقاس هنا
// **أنّ النقرَ يُبلِّغ** و**أنّ أكثرَ من تابَين يُرسَم** — لا أنّ الشريط
// «لم ينهر». فحارسٌ يكتفي بالبناء كان يمرّ أخضرَ على الشريط الخامل نفسِه.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/presentation/shell/screen_tabs_bar.dart';
import 'package:picpos_erp/presentation/widgets/notifications/providers/notification_provider.dart';

final _tabs = <ScreenTabView>[
  const ScreenTabView(
      index: 0, label: 'الرئيسية', icon: PhosphorIconsBold.house),
  const ScreenTabView(
      index: 1, label: 'نقطة البيع', icon: PhosphorIconsBold.storefront),
  const ScreenTabView(
      index: 11, label: 'التقارير', icon: PhosphorIconsBold.chartBar),
  const ScreenTabView(
      index: 4, label: 'الأصناف', icon: PhosphorIconsBold.package),
];

Future<void> _pump(
  WidgetTester tester, {
  required int active,
  required void Function(int) onSelect,
  required void Function(int) onClose,
  VoidCallback? onHome,
  List<ScreenTabView>? tabs,
  double width = 900,
}) async {
  tester.view.physicalSize = Size(width, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        unreadNotificationsCountProvider
            .overrideWith((ref) => Stream.value(0)),
      ],
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ScreenTabsBar(
              tabs: tabs ?? _tabs,
              active: active,
              onSelect: onSelect,
              onClose: onClose,
              onHome: onHome,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('يرسم كلَّ التابات — لا اثنَين', (tester) async {
    await _pump(tester, active: 1, onSelect: (_) {}, onClose: (_) {});
    expect(_tabs.length, greaterThan(2), reason: 'المرساةُ نفسُها ضعيفة');
    for (final t in _tabs) {
      expect(find.text(t.label), findsOneWidget, reason: t.label);
    }
  });

  testWidgets('والنقرُ على تابٍ يُبلِّغ فهرسَ شاشته — عينُ ما بلّغ عنه المالك',
      (tester) async {
    final picked = <int>[];
    await _pump(tester, active: 1, onSelect: picked.add, onClose: (_) {});

    await tester.tap(find.text('التقارير'));
    await tester.pumpAndSettle();
    expect(picked, [11]);

    await tester.tap(find.text('الأصناف'));
    await tester.pumpAndSettle();
    expect(picked, [11, 4]);
  });

  testWidgets('والنقرُ على التاب النشط يُبلِّغ أيضاً', (tester) async {
    // فتحُ شاشةٍ فرعيّةٍ داخلَ التاب ثمّ نقرُه يُعيد إلى جذره — ومنعُ
    // البلاغ يجعل التابَ النشطَ ميّتاً كما كان فتاتُ الخبز بالضبط.
    final picked = <int>[];
    await _pump(tester, active: 1, onSelect: picked.add, onClose: (_) {});
    await tester.tap(find.text('نقطة البيع'));
    await tester.pumpAndSettle();
    expect(picked, [1]);
  });

  testWidgets('وزرُّ الإغلاق يُبلِّغ الإغلاق لا التنشيط', (tester) async {
    final selected = <int>[];
    final closed = <int>[];
    await _pump(tester, active: 11, onSelect: selected.add, onClose: closed.add);

    // زرُّ الإغلاق يظهر على النشط بلا تمرير.
    final xs = find.byIcon(PhosphorIconsBold.x);
    expect(xs, findsOneWidget, reason: 'لا زرَّ إغلاقٍ على التاب النشط');
    await tester.tap(xs);
    await tester.pumpAndSettle();

    expect(closed, [11]);
    expect(selected, isEmpty, reason: 'الإغلاقُ نشّط التابَ أيضاً');
  });

  testWidgets('وتابٌ غيرُ قابلٍ للإغلاق لا زرَّ له', (tester) async {
    await _pump(
      tester,
      active: 0,
      onSelect: (_) {},
      onClose: (_) {},
      tabs: [
        const ScreenTabView(
          index: 0,
          label: 'الرئيسية',
          icon: PhosphorIconsBold.house,
          closable: false,
        ),
      ],
    );
    expect(find.byIcon(PhosphorIconsBold.x), findsNothing);
  });

  testWidgets('وزرُّ البيت يُبلِّغ', (tester) async {
    var home = 0;
    await _pump(
      tester,
      active: 11,
      onSelect: (_) {},
      onClose: (_) {},
      onHome: () => home++,
    );
    await tester.tap(find.byIcon(PhosphorIconsBold.house).first);
    await tester.pumpAndSettle();
    expect(home, 1);
  });

  testWidgets('وجرسُ التنبيهات باقٍ — لم يُفقَد مع فتات الخبز', (tester) async {
    await _pump(tester, active: 1, onSelect: (_) {}, onClose: (_) {});
    expect(find.byIcon(PhosphorIconsRegular.bell), findsOneWidget,
        reason: 'الجرسُ كان ساكناً في `AppBreadcrumbs` وسقط مع استبداله');
  });

  testWidgets('ولا بترَ ولا فيضٌ في نافذةٍ ضيّقة', (tester) async {
    // ⚠️ ثمانيةُ تابات بعناوينَ عربيّةٍ تتجاوز ١٣٦٦ بكسل. و`Row` بلا تمريرٍ
    // يرمي `RenderFlex overflowed` — خطأً في زمن التشغيل لا يراه المستخدم.
    final many = [
      for (var i = 0; i < 8; i++)
        ScreenTabView(
          index: i,
          label: 'شاشةٌ ذاتُ عنوانٍ طويلٍ رقم $i',
          icon: PhosphorIconsBold.package,
        ),
    ];
    await _pump(
      tester,
      active: 0,
      onSelect: (_) {},
      onClose: (_) {},
      tabs: many,
      width: 700,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('والنشطُ وحدَه مُميَّز', (tester) async {
    await _pump(tester, active: 11, onSelect: (_) {}, onClose: (_) {});
    // عرضُ التاب النشط يحمل خطّاً سفليّاً بلون العلامة؛ والمقياسُ الأمتنُ
    // أن زرَّ الإغلاق يظهر على النشط وحدَه بلا تمرير.
    expect(find.byIcon(PhosphorIconsBold.x), findsOneWidget);
  });
}
