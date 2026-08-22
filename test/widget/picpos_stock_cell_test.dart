// خليّةُ المخزون في فورك PicPos — الرصيدُ و«حد أدنى …» وشريطُ الامتلاء.
//
// ما يُقاس هنا هو ما **يكذب بصمتٍ** لو انحرف: شريطٌ يُرسم بلا مرجعٍ يقيس
// إليه. حدُّ المخزون الأدنى افتراضُه صفرٌ في القاعدة، فرسمُ شريطٍ لكلّ صنفٍ
// كان سيُظهر «امتلاءً» لا معنى له على أغلب الكتالوج.
//
// ⚠️ **والمُختبَرُ هو ودجتُ الإنتاج نفسُها** ([StockCellPicpos])، لا نسخةٌ
// موازيةٌ تعيد بناءَ منطقِها. كُتبت هذه الاختباراتُ أوّلاً على مكافئٍ محلّيٍّ
// ثمّ رُدَّت: مكافئٌ يمرّ أخضرَ ولو انفصلت الودجتُ عن الدالّة تماماً، فيُثبت
// النسخةَ لا التوصيلة — وهو ما يحذّر منه رأسُ
// `task_8_products_grid_permission_gates_test`. ولذلك صارت الودجتُ عامّةً
// بـ`@visibleForTesting` بدل أن يُعاد بناؤها هنا.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/presentation/inventory_picpos/widgets/stock_balances_table_picpos.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    required double stock,
    required double minStock,
    bool trackInventory = true,
    double width = 160,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: SizedBox(
              width: width,
              child: StockCellPicpos(
                stock: stock,
                minStock: minStock,
                trackInventory: trackInventory,
                stockColor: AppColors.success,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  LinearProgressIndicator barOf(WidgetTester tester) =>
      tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );

  group('الشريطُ يظهر حين يوجد مرجعٌ فقط', () {
    testWidgets('حدٌّ أدنى موجبٌ ⇒ شريطٌ بنسبةٍ محسوبة', (tester) async {
      await show(tester, stock: 5, minStock: 10);
      expect(barOf(tester).value, closeTo(0.5, 1e-9));
    });

    // ⚠️ الحارسُ الأهمّ: العمودُ افتراضُه صفرٌ في القاعدة، فبدونه كان كلُّ
    // صنفٍ يحمل شريطاً يدّعي قياساً لا مرجعَ له.
    testWidgets('حدٌّ أدنى صفريٌّ ⇒ لا شريطَ ولا نصَّ حدٍّ', (tester) async {
      await show(tester, stock: 5, minStock: 0);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('حد أدنى'), findsNothing);
    });

    testWidgets('صنفٌ لا يُتابَع مخزونُه ⇒ لا شريط', (tester) async {
      await show(tester, stock: 5, minStock: 10, trackInventory: false);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('رصيدٌ أضعافَ الحدِّ ⇒ ممتلئٌ لا يتجاوز', (tester) async {
      await show(tester, stock: 500, minStock: 10);
      expect(barOf(tester).value, closeTo(1.0, 1e-9));
    });

    testWidgets('رصيدٌ سالبٌ ⇒ فارغٌ لا معكوس', (tester) async {
      await show(tester, stock: -8, minStock: 10);
      expect(barOf(tester).value, closeTo(0.0, 1e-9));
    });
  });

  group('نصُّ الخليّة', () {
    testWidgets('يعرض الرصيدَ والحدَّ الأدنى معاً', (tester) async {
      await show(tester, stock: 12, minStock: 10);
      expect(find.text('12.0'), findsOneWidget);
      expect(find.text('حد أدنى 10'), findsOneWidget);
    });

    testWidgets('لا يفيض عند عرضٍ ضيّقٍ بأرقامٍ كبيرة', (tester) async {
      await show(tester, stock: 987654.3, minStock: 123456, width: 120);
      expect(tester.takeException(), isNull,
          reason: 'الخليّةُ تقصُّ بالحذف لا تفيض بالشريط الأصفر');
    });
  });
}
