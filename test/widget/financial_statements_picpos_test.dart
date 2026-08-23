// test/widget/financial_statements_picpos_test.dart
//
// اختبارُ **تركيب** القوائم المالية بهويّة PicPos.
//
// ⚠️ الشاشةُ ستُّ تبويباتٍ داخل `TabBarView`، وهو يطلب ارتفاعاً محدَّداً.
// وضعُه في جسمٍ يُلَفّ في تمريرةٍ يجعله يطلب ارتفاعاً لا نهائيّاً فينهار —
// وهو عطبُ الخزينة البيضاء نفسُه، ولا يظهر في بناء الإصدار إلّا بياضاً.
//
// ⚠️ ويُقاس بعرضَين: فيضٌ ثابتٌ = خليّةٌ ضيّقة، ومتغيّرٌ = حسابُ أعمدة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/branch_scope_provider.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/accounting_picpos/financial_statements_picpos_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // ⚠️ الشاشةُ تحجب نفسَها حتى يُحسم نطاقُ الفروع — بلا هذا تبقى
          //    على مؤشّر التحميل ولا يُقاس تركيبٌ أصلاً.
          branchScopeProvider
              .overrideWith((ref) async => const BranchScope.fullAccess()),
        ],
        child: const MaterialApp(home: FinancialStatementsPicPosScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  for (final width in [1280.0, 1920.0]) {
    testWidgets('تُبنى بلا استثناءِ تخطيطٍ عند عرض ${width.toInt()}',
        (tester) async {
      await pump(tester, width);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
  }

  testWidgets('وتحمل التبويباتِ الستّةَ بأسمائها', (tester) async {
    await pump(tester, 1920);

    // ⚠️ لا يُكتفى بـ«لم تنهر»: شاشةٌ تُرسم فارغةً تمرّ على ذلك الشرط.
    expect(find.text('القوائم المالية'), findsWidgets);
    expect(find.text('ميزان المراجعة'), findsOneWidget);
    expect(find.text('قائمة الدخل (P&L)'), findsOneWidget);
    expect(find.text('الميزانية العمومية'), findsOneWidget);
    expect(find.text('التدفقات النقدية'), findsOneWidget);
    expect(find.text('تقادم الذمم'), findsOneWidget);
    expect(find.text('مطابقة الترحيل'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
