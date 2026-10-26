// E2E تطبيق الكاشير (PicPos كاشير): المنفَّذ فعلًا اليوم: الاقتران وتسجيل الدخول
// مع خادم LAN (kind=pos، بصمة الشهادة، رمز لكل جهاز؛ test/pairing_test.dart) + قشرة
// (البيع/المعلّقة/الوردية/المرتجعات/الإعدادات) هي واجهة معاينة فقط. لذا:
//  • تدفق المستخدم الفعلي مغطّى كاملًا هنا (يعمل)؛
//  • كل تدفق لم يُنفَّذ بعد مكتوب كاختبار skip بسبب صريح، بدل اختراع سلوك.
//
// يُشغَّل: `flutter test test/e2e` من مجلد mobile_pos.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_pos/app.dart';
import 'package:picpos_pos/screens/onboarding_screen.dart';
import 'package:picpos_pos/shell/pos_shell.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../support.dart';

const _m5 = 'غير منفَّذ بعد في التطبيق (M-5: بيانات البيع عبر /api/m1/pos/*، '
    'docs/mobile/ARCHITECTURE-M.md §3.2). الاقتران والدخول منفَّذان؛ لا يوجد مخزن محلي ولا بيع حقيقي بعد.';

void main() {
  setUpAll(loadTestFonts);

  testWidgets('رحلة المستخدم: اقتران (فعّال) ← معاينة ← البيع الفارغ ← التبويبات ← الإعدادات ← العودة للاقتران',
      (tester) async {
    setSurface(tester, kTablet);
    await tester.pumpWidget(PicPosPosApp(settings: PicPosAppSettings()));
    await tester.pumpAndSettle();

    // شاشة الاقتران: الحقول وزر «ربط» وزر المسح فعّالة (الاقتران حقيقي؛ تغطيته
    // الكاملة في test/pairing_test.dart).
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'ربط')).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(find.byKey(const Key('onboarding.scan'))).onPressed, isNotNull);
    expect(tester.widgetList<TextField>(find.byType(TextField)).every((f) => f.enabled != false), isTrue);

    // معاينة التطبيق ← صفحة البيع: سلة فارغة، الإجمالي 0.000، زر الدفع معطّل.
    await tester.tap(find.byKey(const Key('onboarding.preview')));
    await tester.pumpAndSettle();
    expect(find.byType(PosShell), findsOneWidget);
    expect(find.text('السلة فارغة'), findsOneWidget);
    expect(find.text('0.000'), findsWidgets);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'الدفع')).onPressed, isNull);

    // كل تبويب يفتح بلا أخطاء ويعرض صفحة «قريبًا»/الإعدادات.
    for (final label in ['المعلّقة', 'الوردية', 'المرتجعات', 'الإعدادات']) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
    expect(find.byType(PosShell), findsOneWidget);
  });

  testWidgets('الإعدادات ← العودة لشاشة الاقتران (onOpenPairing)', (tester) async {
    setSurface(tester, kPhone);
    await tester.pumpWidget(PicPosPosApp(settings: PicPosAppSettings(), startInShell: true, initialDestination: 4));
    await tester.pumpAndSettle();
    final open = find.byKey(const Key('settings.openPairing'));
    expect(open, findsOneWidget);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  group('تدفقات لم تُنفَّذ بعد (skip مبرَّر)', () {
    test('جلب المنتجات والأسعار (/api/m1/pos/bootstrap, pull) إلى مخزن محلي', () {}, skip: _m5);
    test('فتح وردية ← بيع نقدي ← طباعة/إيصال ← إغلاق وردية بتسوية', () {}, skip: _m5);
    test('بيع بلا اتصال ثم مزامنة عند العودة (idempotency)', () {}, skip: _m5);
    test('مرتجع على فاتورة سابقة + تجاوز سعر (override) بموافقة', () {}, skip: _m5);
  });
}
