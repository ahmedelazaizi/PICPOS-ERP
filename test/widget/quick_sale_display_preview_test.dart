// لوحةُ معاينة ديالوج البيع السريع — §٣.
//
// المصدرُ: لوحةُ المعاينة اليمنى في
// `invoice_templates/design/PicPos Quick Sale Dialog.dc.html` («مقياس ٥٠٪»).
//
// ═══ لماذا تستحقّ اختباراً ═══
//
// قيمتُها كلُّها في أنّها **مربوطةٌ بالقيم**: المديرُ يجرّ «عرض التسمية» فيرى
// الرقعةَ تتّسع. ومعاينةٌ ترسم مقاساتٍ ثابتةً تبدو صحيحةً وهي تكذب — وهذا
// أسوأُ من غياب المعاينة، لأنّه يجعل المديرَ يثق برقمٍ لم يُطبَّق.
//
// فالتوكيدُ هنا على **الربط** لا على الشكل: عرضُ رقعة التسمية = القيمةُ
// المُمرَّرة، وعددُ أعمدة الشبكة = العددُ المُمرَّر.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/settings_picpos/widgets/quick_sale_display_preview.dart';

Future<void> _pump(
  WidgetTester tester,
  QuickSaleDisplayPreview preview, {
  double width = 420,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(child: SizedBox(width: width, child: preview)),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('المعاينةُ مربوطةٌ بالمقاسات', () {
    testWidgets('عرضُ رقعة التسمية يتبع القيمةَ المُمرَّرة', (tester) async {
      await _pump(tester, const QuickSaleDisplayPreview(catLabelWidth: 52));
      final narrow = tester
          .widget<SizedBox>(find.byKey(const Key('preview-cat-label')).first)
          .width;

      await _pump(tester, const QuickSaleDisplayPreview(catLabelWidth: 78));
      final wide = tester
          .widget<SizedBox>(find.byKey(const Key('preview-cat-label')).first)
          .width;

      expect(narrow, 52);
      expect(wide, 78);
      expect(wide, greaterThan(narrow!),
          reason: 'المعاينةُ التي لا تتّسع مع القيمة تكذب على المدير.');
    });

    testWidgets('وعددُ أعمدة الشبكة يتبع الإعداد', (tester) async {
      await _pump(tester, const QuickSaleDisplayPreview(gridColumns: 4));
      expect(find.byKey(const Key('preview-tile')), findsNWidgets(8),
          reason: 'المعاينةُ ترسم صفَّين، فأربعةُ أعمدةٍ ⇒ ثمانيةُ مربّعات.');

      await _pump(tester, const QuickSaleDisplayPreview(gridColumns: 6));
      expect(find.byKey(const Key('preview-tile')), findsNWidgets(12));
    });

    testWidgets('وإخفاءُ الشريط العلويّ يُزيله من المعاينة', (tester) async {
      await _pump(tester, const QuickSaleDisplayPreview(showTopBar: true));
      expect(find.byKey(const Key('preview-topbar')), findsOneWidget);

      await _pump(tester, const QuickSaleDisplayPreview(showTopBar: false));
      expect(find.byKey(const Key('preview-topbar')), findsNothing);
    });
  });

  group('لا تنهار', () {
    for (final width in <double>[300, 420]) {
      testWidgets('عند عرض ${width.toInt()}', (tester) async {
        await _pump(tester, const QuickSaleDisplayPreview(), width: width);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('وفي الوضع الغامق', (tester) async {
      await _pump(tester, const QuickSaleDisplayPreview(),
          brightness: Brightness.dark);
      expect(tester.takeException(), isNull);
    });
  });
}
