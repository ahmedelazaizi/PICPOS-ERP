// عطب شاشة الإعدادات: `type 'double' is not a subtype of type 'bool?'`.
//
// اللوح يعطي الـListView مفتاح `PageStorageKey('settings-<id>')` كي يحتفظ كل
// قسم بموضع تمريره. المفتاح ده بيتورَّث: `PageStorageBucket._allKeys` بيمشي من
// الودجت لفوق ويلمّ كل `PageStorageKey` في الطريق — فالـ`Scrollable` بيكتب
// إزاحة التمرير (double) تحت `[settings-<id>]`، وأي `ExpansionTile` جوّه نفس
// اللوح **بلا مفتاح خاص به** بيحسب نفس المعرِّف بالظبط، فيقرأ الإزاحة
// `as bool?` في `_ExpansibleState.initState` ← انفجار وقت التشغيل.
//
// الاصطدام ثنائي الاتجاه: لو الـtile كتب `true` أولاً، بقى
// `ScrollPosition.restoreScrollOffset` هو اللي بينفجر بـ`as double?`.
//
// رُصد في لوج المالك 2026-08-12: ثلاثة أجزاء من الإعدادات اختفت خلف صندوق خطأ
// أحمر — اتنين متتاليين في «النظام والمظهر» وواحد تحت «اختبار الاتصال».

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/settings_picpos/widgets/settings_section_pane.dart';

void main() {
  Widget host(List<Widget> children) => MaterialApp(
        home: Scaffold(
          body: SettingsSectionPane(
            sectionId: 'system',
            children: children,
          ),
        ),
      );

  // مفتاح مختلف في كل مرحلة ⇒ عنصر جديد ⇒ `initState` يشتغل من جديد، وهو
  // بالظبط اللي بيحصل في التطبيق لما الـtile يخرج من الشاشة بالتمرير
  // (children الـListView كسولة) ويرجع، أو لما المستخدم يبدّل قسم ويرجع.
  List<Widget> paneChildren(String tileKey) => [
        // أطول من نافذة العرض (600) + cacheExtent (250) ⇒ الـtile مش مبنيّ
        // عند التركيب الأول، وبيتبني أول ما التمرير يوصّله للشاشة.
        const SizedBox(height: 900),
        ExpansionTile(
          key: ValueKey(tileKey),
          title: const Text('قسم قابل للطيّ'),
          children: const [Text('محتوى')],
        ),
      ];

  testWidgets(
    'ExpansionTile داخل لوح القسم لا يقرأ إزاحة التمرير على أنها bool',
    (tester) async {
      await tester.pumpWidget(host(paneChildren('a')));
      expect(tester.takeException(), isNull, reason: 'التركيب الأول نظيف');

      // تمريرة حقيقية — عند نهايتها ينفّذ `ScrollPosition.didEndScroll`
      // ‏`saveScrollOffset()` فيكتب الإزاحة في دلو PageStorage.
      await tester.drag(find.byType(Scrollable), const Offset(0, -500));
      await tester.pumpAndSettle();

      // إعادة تركيب الـtile بعد أن صارت الإزاحة محفوظة.
      await tester.pumpWidget(host(paneChildren('b')));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: '_ExpansibleState.initState قرأ إزاحة التمرير as bool?',
      );
      expect(find.text('قسم قابل للطيّ'), findsOneWidget);
    },
  );

  testWidgets(
    'اللوح يحتفظ بموضع التمرير لكل قسم بعد التبديل والعودة',
    (tester) async {
      await tester.pumpWidget(host(paneChildren('a')));
      await tester.drag(find.byType(Scrollable), const Offset(0, -500));
      await tester.pumpAndSettle();
      final saved = tester.state<ScrollableState>(find.byType(Scrollable));
      final offset = saved.position.pixels;
      expect(offset, greaterThan(0), reason: 'التمرير فعلاً حصل');

      // قسم آخر ثم عودة — لوح جديد بنفس المُعرِّف.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsSectionPane(
              sectionId: 'other',
              children: paneChildren('a'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(paneChildren('a')));
      await tester.pumpAndSettle();

      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        offset,
        reason: 'PageStorageKey للّوح لسه بيسترجع الإزاحة',
      );
    },
  );
}
