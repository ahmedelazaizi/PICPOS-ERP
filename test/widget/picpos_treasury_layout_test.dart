// تخطيطُ جسم شاشة الخزينة — **حارسُ الشاشة الفارغة**.
//
// ═══ 🔴 عطبٌ شُحن، وبلاغُ المالك هو الذي أمسكه ═══
//
// بعد نقل الأزرار إلى شبكة ٢×٢، صار الصفُّ العلويُّ:
//
//     Column(...) > LayoutBuilder > Row(crossAxisAlignment: stretch)
//
// وفي `Column` يأخذ الابنُ غيرُ المرن ارتفاعاً **غيرَ محدود**. و`stretch`
// في `Row` تُلزم الأبناءَ بملء المحور العرضيّ — أي ارتفاعاً لا نهائيّاً.
// فتُرمى في طور التخطيط، وفي بناء الإصدار **لا تظهر الشاشةُ الحمراء**: يُرسم
// بياضٌ. وهذا بالضبط ما رآه المالك — ترويسةٌ وبحثٌ وجسمٌ فارغ.
//
// ⚠️ **ولماذا لم يمسكه اختبار:** كلُّ اختباراتي كانت على الودجتات **مفردةً**
// (البطاقة · الصفّ · الشبكة)، وكلُّها تمرّ لأن العطبَ ليس فيها بل في
// **تركيبها**. وهو نفسُ درسِ «اختبارٌ على نسخةٍ موازيةٍ يُثبت النسخةَ لا
// التوصيلة» — فُرِض هنا على مستوى التخطيط لا الودجت.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/treasury_picpos/widgets/treasury_actions_grid_picpos.dart';

void main() {
  /// نفسُ تركيب جسم الشاشة: عمودٌ ← بانٍ ← صفٌّ فيه مرنٌ وثابتُ العرض.
  Widget body({required CrossAxisAlignment rowCross, bool intrinsic = false}) {
    Widget row = Row(
      crossAxisAlignment: rowCross,
      children: [
        Expanded(
          child: Container(height: 70, color: const Color(0xFF012258)),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 300,
          child: TreasuryActionsGridPicpos(
            onReceipt: () {},
            onPayment: () {},
            onSafes: () {},
            onReconcile: () {},
          ),
        ),
      ],
    );
    if (intrinsic) row = IntrinsicHeight(child: row);

    // ⚠️ `ProviderScope` إلزاميّ: الشبكةُ تحمل `PermissionGuard` وهي
    // `ConsumerWidget`. وبدونه يُرمى `StateError` قبل أن يصل التخطيطُ أصلاً —
    // فيُقرأ العطبُ خطأَ تخطيطٍ وهو خطأُ تركيبِ اختبار.
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(builder: (context, _) => row),
                const SizedBox(height: 12),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // الحارسُ الحقيقيّ: التركيبُ المشحونُ يجب أن يُرسم بلا استثناء.
  testWidgets('الصفُّ العلويُّ يُرسم بلا استثناءٍ في التخطيط', (tester) async {
    await tester.pumpWidget(
      body(rowCross: CrossAxisAlignment.stretch, intrinsic: true),
    );
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'جسمُ الخزينة يجب أن يُرسم — البياضُ كان عطبَ تخطيطٍ لا بيانات');
    expect(find.text('سند قبض'), findsOneWidget);
    expect(find.text('مراجعة الأرصدة'), findsOneWidget);
  });

  // ⚠️ **الطرفُ الذي يُثبت أن الحارسَ يقيس شيئاً**: بلا `IntrinsicHeight`
  // يعود العطبُ نفسُه. فلو أزال أحدٌ الغلافَ لاحقاً سقط الاختبارُ الأوّل.
  testWidgets('بلا حدٍّ للارتفاع: `stretch` ترمي — وهو العطبُ المشحون',
      (tester) async {
    Object? layoutException;
    try {
      await tester.pumpWidget(
        body(rowCross: CrossAxisAlignment.stretch, intrinsic: false),
      );
      await tester.pump();
    } catch (error) {
      layoutException = error;
    }
    layoutException ??= tester.takeException();

    expect(layoutException, isNotNull,
        reason: 'ارتفاعٌ غيرُ محدودٍ مع stretch يجب أن يرمي — وإلّا فالحارسُ '
            'الأوّل لا يحرس شيئاً');
  });

  testWidgets('البطاقاتُ الأربعُ كلُّها مرسومة', (tester) async {
    await tester.pumpWidget(
      body(rowCross: CrossAxisAlignment.stretch, intrinsic: true),
    );
    await tester.pump();

    for (final t in [
      'سند قبض',
      'سند صرف',
      'إدارة الصناديق',
      'مراجعة الأرصدة',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });
}
