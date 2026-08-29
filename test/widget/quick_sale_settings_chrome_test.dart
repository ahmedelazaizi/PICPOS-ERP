// حارسُ هيكلِ «ديالوج البيع السريع» — §٣ من بلاغ المالك 2026-08-29.
//
// المصدرُ `invoice_templates/design/PicPos Quick Sale Dialog.dc.html` بأمر
// المالك 2026-08-28 («ملفّاتُ التصميم هي المصدرُ المعتمَد»)، فأيُّ انحرافٍ
// خطأُ تنفيذٍ لا اختلافُ مدرستَين.
//
// ═══ ما يقيسه هذا الملفّ ═══
//
// الهيكلَ وحدَه — لا منطقَ الإعدادات. `pos_settings_widget.dart` يحمل منطقاً
// حقيقيّاً (‏حدودُ الضريبة · بلاطاتُ الصلاحية · مهلةُ الجلسة)، ونسخُه فوركاً
// كان يضاعفه. فالهيكلُ يُبنى ودجتاتٍ خالصةً هنا، والمنطقُ يبقى مصدراً واحداً.
//
// ⚠️ **وشارةُ المفتاح ليست زينة**: التصميمُ يعرض `{{ r.key }}` بخطٍّ أحاديِّ
// العرض في كلِّ صفّ — وهو ما يجعل المديرَ يربط ما يراه بما يُكتب في القاعدة.
// وغيابُها انحرافٌ عن التصميم لا تبسيطٌ له.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_surface.dart';
import 'package:ural_erp/presentation/settings_picpos/widgets/quick_sale_settings_chrome.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Future<Color> _pump(WidgetTester tester, Brightness brightness, Widget child,
    {double width = 900}) async {
  late Color card;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Builder(builder: (context) {
            card = context.picposCard;
            return Center(child: SizedBox(width: width, child: child));
          }),
        ),
      ),
    ),
  );
  await tester.pump();
  return card;
}

void main() {
  // أقسامُ الديالوج — `SECTIONS` في التصميم. تُثبَّت هنا لأنّ الشريطَ
  // الجانبيَّ يعرض عددَ إعداداتِ كلِّ قسم، والعددُ جزءٌ من التصميم لا زينة.
  group('أقسامُ الديالوج الخمسة', () {
    test('بعناوين التصميم وألوانِه، ومجموعُ إعداداتها ٣٧', () {
      expect(kQuickSaleSections.map((s) => s.title).toList(), const [
        'إعدادات البيع السريع الرئيسية',
        'إعدادات منطقة التصنيفات',
        'إعدادات شبكة المنتجات',
        'إعدادات الإيصال',
        'إعدادات نقطة بيع الطاولات',
      ]);

      expect(kQuickSaleSections.map((s) => s.tint).toList(), const [
        Color(0xFF0250D3),
        Color(0xFF22C55E),
        Color(0xFF4A80E8),
        Color(0xFF8B5CF6),
        Color(0xFFF59E0B),
      ]);

      expect(
        kQuickSaleSections.fold<int>(0, (a, s) => a + s.settingCount),
        37,
        reason: 'التصميمُ يعدّ ٣٧ مفتاحاً موزّعةً ١٧+٧+٣+٤+٦، وكلُّها موجودةٌ '
            'في المستودع سلفاً — فالبندُ إعادةُ تنسيقٍ لا بناءُ إعدادات.',
      );
    });
  });

  group('صفُّ الإعداد على التصميم', () {
    Widget row() => const QuickSaleSettingRow(
          icon: PhosphorIconsBold.barcode,
          tint: Color(0xFF0250D3),
          title: 'التركيز الدائم على حقل الباركود',
          settingKey: 'pos_focus_barcode',
          sub: 'يعيد المؤشّرَ إلى حقل الباركود بعد كلِّ إضافة',
          control: SizedBox(width: 40, height: 20),
        );

    testWidgets('يعرض العنوانَ والشرحَ وشارةَ المفتاح', (tester) async {
      await _pump(tester, Brightness.light, row());

      expect(find.text('التركيز الدائم على حقل الباركود'), findsOneWidget);
      expect(find.text('يعيد المؤشّرَ إلى حقل الباركود بعد كلِّ إضافة'),
          findsOneWidget);
      expect(
        find.text('pos_focus_barcode'),
        findsOneWidget,
        reason: 'شارةُ المفتاح في التصميم (`{{ r.key }}`) — بها يربط المديرُ '
            'الصفَّ بما يُكتب في القاعدة.',
      );
    });

    testWidgets('وحبرُه مقروءٌ في الوضع الغامق', (tester) async {
      final card = await _pump(tester, Brightness.dark, row());

      final title =
          tester.widget<Text>(find.text('التركيز الدائم على حقل الباركود'));
      expect(_contrast(title.style!.color!, card), greaterThan(4.5));
    });
  });

  group('بلاطةُ الشريط الجانبيّ', () {
    testWidgets('تعرض العددَ ونقطةَ التغيير غيرِ المحفوظ', (tester) async {
      await _pump(
        tester,
        Brightness.dark,
        const QuickSaleNavTile(
          icon: PhosphorIconsBold.shoppingCart,
          tint: Color(0xFF0250D3),
          title: 'إعدادات البيع السريع الرئيسية',
          settingCount: 17,
          selected: true,
          dirty: true,
        ),
      );

      expect(find.text('إعدادات البيع السريع الرئيسية'), findsOneWidget);
      expect(find.text('١٧ إعداد'), findsOneWidget,
          reason: 'التصميمُ يكتب «{{ n.count }} إعداد» — والأرقامُ عربيّةٌ '
              'كبقيّةِ الواجهة.');
      expect(find.byKey(const Key('nav-dirty-dot')), findsOneWidget,
          reason: 'نقطةُ `#F59E0B` تدلُّ على قسمٍ فيه تغييرٌ لم يُحفَظ.');
    });

    testWidgets('ولا نقطةَ حين لا تغيير', (tester) async {
      await _pump(
        tester,
        Brightness.dark,
        const QuickSaleNavTile(
          icon: PhosphorIconsBold.shoppingCart,
          tint: Color(0xFF0250D3),
          title: 'إعدادات الإيصال',
          settingCount: 4,
          selected: false,
          dirty: false,
        ),
      );

      expect(find.byKey(const Key('nav-dirty-dot')), findsNothing);
    });
  });
}
