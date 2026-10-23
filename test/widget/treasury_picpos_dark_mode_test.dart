// حارسُ لمعانٍ لشريط تبويبات الخزينة — يقيس اللونَ **المرسوم** لا النصَّ.
//
// ═══ لماذا هذا فوق الحارس البنيويّ ═══
//
// `test/structural/dark_mode_surface_tokens_test.dart` يمنع أسماءَ الألوانِ
// الفاتحةِ في المصدر. لكنّه لا يرى ما يُرسَم فعلاً: رمزٌ جديدٌ بقيمةٍ فاتحةٍ
// لم تدخل قائمتَه يمرُّ صامتاً. وهذا يضخُّ الودجتَ ويقرأ سطحَها.
//
// والخزينةُ هي الدرسُ نفسُه الذي كلّف بلاغاً: `treasury_picpos_screen.dart`
// فيه **صفرُ** ألوانٍ صريحةٍ ومع ذلك كانت الشاشةُ فاتحةً في الغامق، لأنّ
// العطبَ في ودجتاتها. فالقياسُ على الودجت لا على الشاشة.
//
// ⚠️ **وضعٌ واحدٌ لكلِّ اختبار.** ضخُّ الوضعَين في اختبارٍ واحدٍ لا يقيس
// شيئاً: الودجتُ `const` يُعاد استعمالُ نسختِها فلا يُعاد بناءُ العنصر،
// فيُقرأ لونُ الضخّة الأولى مرّتين — وقد أعطى ذلك «أبيضُ في الغامق» وهو
// خطأُ قياسٍ لا عطبُ كود.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/presentation/treasury_picpos/widgets/treasury_tab_bar_picpos.dart';

/// يضخُّ الشريطَ بوضعٍ واحدٍ ويُرجع لونَ كرتِه الخارجيّ.
///
/// الكرتُ يُعرَف بنصفِ قطرِه ١٤ لا بترتيبه في الشجرة: ترتيبٌ يتبدّل بإعادةِ
/// تنسيقٍ يجعل الاختبارَ يقيس صندوقاً آخرَ ويمرُّ كاذباً.
Future<Color?> _barColor(WidgetTester tester, Brightness brightness) async {
  final search = TextEditingController();
  addTearDown(search.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: DefaultTabController(
            length: 2,
            child: Builder(
              builder: (context) => TreasuryTabBarPicpos(
                key: const Key('probe'),
                controller: DefaultTabController.of(context),
                tabs: const [
                  (label: 'الصناديق', icon: PhosphorIconsBold.wallet),
                  (label: 'الحركات', icon: PhosphorIconsBold.arrowsDownUp),
                ],
                searchController: search,
                onSearchChanged: (_) {},
                searchQuery: '',
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  final containers = tester.widgetList<Container>(
    find.descendant(
      of: find.byKey(const Key('probe')),
      matching: find.byType(Container),
    ),
  );
  final outer = containers.firstWhere((c) {
    final d = c.decoration;
    return d is BoxDecoration && d.borderRadius == BorderRadius.circular(14);
  });
  return (outer.decoration as BoxDecoration).color;
}

void main() {
  group('شريطُ تبويبات الخزينة يتبع الوضع', () {
    testWidgets('الفاتحُ فاتحٌ فعلاً', (tester) async {
      final light = await _barColor(tester, Brightness.light);
      expect(light, isNotNull);
      // اللمعانُ مقياسٌ موضوعيٌّ لا يربط الاختبارَ بقيمةٍ بعينها.
      expect(light!.computeLuminance(), greaterThan(0.7));
    });

    testWidgets('والغامقُ داكنٌ فعلاً لا فاتحٌ باسمٍ آخر', (tester) async {
      final dark = await _barColor(tester, Brightness.dark);
      expect(dark, isNotNull);
      expect(
        dark!.computeLuminance(),
        lessThan(0.2),
        reason: 'شريطٌ فاتحٌ في الوضع الغامق = لونٌ مثبَّتٌ لا يتبع الثيم — '
            'وهو بعينه بلاغُ المالك 2026-08-24 عن شاشة الخزينة.',
      );
    });
  });
}
