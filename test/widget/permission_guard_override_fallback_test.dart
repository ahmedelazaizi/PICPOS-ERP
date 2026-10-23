// إصلاح محرك — `allowManagerOverride` + `fallback` مع بعض.
//
// ── الباج ─────────────────────────────────────────────────────────────────
// ترتيب `PermissionGuard.build()` كان:
//     معاه الصلاحية → child
//     allowManagerOverride → _ManagerOverrideWrapper(child: child)
//     showDisabled → …
//     وإلا → fallback
// يعني أي حارس بيبعت الاتنين كان بيعرض **القيمة الحقيقية** لمين مالوش
// الصلاحية ويمتص الضغطة وبس، والـ`fallback` عمره ما اتعرض.
//
// الأربع مواقع اللي كانت بتبعت الاتنين كلها كروت لوحة التحكم في البراندين:
// `treasury_balance_view` (رصيد الخزنة) و`dashboard_profit` (صافي الربح)،
// وكلهم كاتبين `fallback: card(value: '---')`. يعني صلاحيتَي عرض ماليّتين
// مكانوش بيخبّوا حاجة أصلاً — نفس شكل البلاغ الأصلي «بغيّر الصلاحية وما
// بيحصلش حاجة».
//
// الاختبار ده بيثبت السلوك الجديد **وبيثبّت القديم** لمواقع الأزرار (اللي
// مالهاش `fallback`) عشان الإصلاح ما يكسرش مسار الموافقة بتاعها.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/widgets/permission_guard.dart';

const _kSecret = '12,345.00';
const _kMasked = '---';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget guarded,
    List<String> perms,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
        ],
        child: MaterialApp(home: Scaffold(body: Center(child: guarded))),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Widget displayCardGuard() => const PermissionGuard(
        permission: 'treasury_balance_view',
        allowManagerOverride: true,
        actionName: 'عرض أرصدة جميع الصناديق',
        fallback: Text(_kMasked),
        child: Text(_kSecret),
      );

  group('صلاحية عرض: fallback + allowManagerOverride', () {
    testWidgets('بدون الصلاحية: البديل هو المعروض والقيمة الحقيقية مخفية',
        (tester) async {
      await pump(tester, displayCardGuard(), const []);

      expect(find.text(_kMasked), findsOneWidget);
      expect(
        find.text(_kSecret),
        findsNothing,
        reason: 'ده كان الباج: القيمة كانت بتتعرض تحت AbsorbPointer',
      );
    });

    testWidgets('الضغط بيفتح ديالوج تصريح المسؤول', (tester) async {
      await pump(tester, displayCardGuard(), const []);

      await tester.tap(find.text(_kMasked));
      await tester.pumpAndSettle();

      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);
      // لسه مخفية — الكشف بعد الموافقة مش بعد فتح الديالوج.
      expect(find.text(_kSecret), findsNothing);
    });

    testWidgets('إلغاء الديالوج بيسيب القيمة مخفية', (tester) async {
      await pump(tester, displayCardGuard(), const []);

      await tester.tap(find.text(_kMasked));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      expect(find.text(_kSecret), findsNothing);
      expect(find.text(_kMasked), findsOneWidget);
    });

    testWidgets('معاه الصلاحية: القيمة ظاهرة والبديل مش موجود', (tester) async {
      await pump(tester, displayCardGuard(), const ['treasury_balance_view']);

      expect(find.text(_kSecret), findsOneWidget);
      expect(find.text(_kMasked), findsNothing);
    });

    testWidgets('مدير النظام: القيمة ظاهرة من غير الكود نفسه', (tester) async {
      await pump(tester, displayCardGuard(), const ['system_admin']);

      expect(find.text(_kSecret), findsOneWidget);
      expect(find.text(_kMasked), findsNothing);
    });
  });

  group('تثبيت السلوك القديم: أزرار بلا fallback', () {
    testWidgets('بدون الصلاحية: الزرار فاضل باين (عشان يتضغط ويُطلب عليه إذن)',
        (tester) async {
      var pressed = 0;
      await pump(
        tester,
        PermissionGuard(
          permission: 'sales_print',
          allowManagerOverride: true,
          actionName: 'طباعة',
          onGranted: () => pressed++,
          child: ElevatedButton(
            onPressed: () => pressed++,
            child: const Text('طباعة'),
          ),
        ),
        const [],
      );

      expect(find.text('طباعة'), findsOneWidget);

      // الضغطة ممتصّة: بتفتح ديالوج التصريح، وما بتنفّذش الفعل.
      await tester.tap(find.text('طباعة'));
      await tester.pumpAndSettle();
      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);
      expect(pressed, 0);
    });

    testWidgets('بدون override وبدون fallback: الابن مختفي تماماً',
        (tester) async {
      await pump(
        tester,
        const PermissionGuard(
          permission: 'sales_amounts_view',
          child: Text(_kSecret),
        ),
        const [],
      );

      expect(find.text(_kSecret), findsNothing);
    });
  });
}
