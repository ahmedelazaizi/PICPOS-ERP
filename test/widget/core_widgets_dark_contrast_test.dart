// حارسُ تباينٍ لودجتات `lib/core/widgets` العامّة: كانت تكتب ألوان الفاتح
// الثابتة (textPrimary/textMuted/surface) فيصير نصُّ «لا توجد فواتير» شبهَ
// أسودَ على خلفيّةٍ داكنة. وضعٌ واحد لكلِّ اختبار.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/theme/core_surface_colors.dart';
import 'package:picpos_erp/core/widgets/app_empty_state.dart';
import 'package:picpos_erp/core/widgets/app_error_boundary.dart';
import 'package:picpos_erp/core/widgets/app_osk.dart';
import 'package:picpos_erp/core/widgets/app_state_view.dart';
import 'package:picpos_erp/core/widgets/shimmer_loading.dart';

import '../support/contrast_audit.dart';

void main() {
  final surfaces = <String, Widget Function()>{
    'AppEmptyState': () => AppEmptyState(
          icon: PhosphorIconsBold.receipt,
          title: 'لا توجد فواتير مبيعات',
          description: 'ستظهر الفواتير هنا بعد إتمام أول عملية بيع',
          actionLabel: 'إضافة',
          onAction: () {},
        ),
    'AppStateView(isEmpty)': () => const AppStateView(
          isLoading: false,
          isEmpty: true,
          emptyMessage: 'لا توجد فواتير مبيعات',
          emptyDescription: 'جرّب تغيير الفلتر',
          child: SizedBox(),
        ),
    'AppStateView(error)': () => AppStateView(
          isLoading: false,
          isEmpty: false,
          emptyMessage: 'x',
          error: 'تعذّر التحميل',
          onRetry: () {},
          child: const SizedBox(),
        ),
    'AppErrorWidget': () => AppErrorWidget(
          title: 'حدث خطأ',
          message: 'Exception: something failed',
          onRetry: () {},
        ),
    'InlineErrorCard': () => inlineErrorCardForTest(
          FlutterErrorDetails(exception: Exception('boom')),
        ),
    'AppOSK': () => SizedBox(
          width: 400,
          height: 1000,
          child: AppOSK(controller: TextEditingController()),
        ),
  };

  // الداكن فقط: الفاتحُ يجب أن يبقى مطابقاً حرفيّاً (فيه حالاتٌ حدّيّة قديمة
  // كوصفٍ رماديّ ٤٫٤٢:١ لا تُمَسّ عمداً) فيُثبَّت بالاختبار التالي لا بالتباين.
  for (final e in surfaces.entries) {
    testWidgets('${e.key} — بلا مخالفات تباين (dark)', (tester) async {
      await tester.pumpWidget(auditApp(
        brightness: Brightness.dark,
        home: Scaffold(body: Align(child: e.value())),
      ));
      await tester.pump();

      expect(find.byType(RichText), findsWidgets);
      final v = auditContrast(tester);
      // يوقف مؤقّتات الـshimmer.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(v, isEmpty, reason: describeViolations(v));
    });
  }

  // الـshimmer بلا نصٍّ فلا يقيسه المدقّق: نتحقّق من أنه يرسم بأسطح الداكن
  // (كرتٌ داكن + هيكل أفتح منه) لا ببياضٍ ثابت يلمع في الوضع الداكن.
  for (final dark in [true, false]) {
    testWidgets('ShimmerLoading يتبع الثيم (${dark ? "dark" : "light"})',
        (tester) async {
      await tester.pumpWidget(auditApp(
        brightness: dark ? Brightness.dark : Brightness.light,
        home: Scaffold(
          body: Column(children: [
            SizedBox(width: 300, height: 200, child: ShimmerLoading.card()),
            SizedBox(width: 400, height: 200, child: ShimmerLoading.list(itemCount: 2)),
          ]),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      final boxes = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>();
      final cardColor = dark ? AppColors.cardDark : Colors.white;
      expect(boxes.any((d) => d.color == cardColor), isTrue);
      if (dark) {
        expect(boxes.any((d) => d.color == Colors.white), isFalse);
      }
      final skeleton = dark ? AppColors.borderDark : AppColors.surface;
      expect(
        boxes.any((d) =>
            d.gradient is LinearGradient &&
            (d.gradient as LinearGradient).colors.first == skeleton),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('الفاتح مطابق حرفيّاً للثوابت القديمة', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(auditApp(
      brightness: Brightness.light,
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    expect(ctx.coreTextPrimary, AppColors.textPrimary);
    expect(ctx.coreTextMuted, AppColors.textMuted);
    expect(ctx.coreCard, Colors.white);
    expect(ctx.coreSkeleton, AppColors.surface);
    expect(ctx.coreStatusText(AppColors.error), AppColors.error);
    expect(ctx.coreSoftIcon(AppColors.primary, 0.4),
        AppColors.primary.withValues(alpha: 0.4));
  });

  testWidgets('لا نصَّ بخطٍّ ≤10 في الحالات الخاطئة', (tester) async {
    await tester.pumpWidget(auditApp(
      brightness: Brightness.light,
      home: Scaffold(
        body: inlineErrorCardForTest(
          FlutterErrorDetails(exception: Exception('boom')),
        ),
      ),
    ));
    final sizes = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text.style?.fontSize ?? 14);
    expect(sizes.every((s) => s > 10), isTrue);
  });
}
