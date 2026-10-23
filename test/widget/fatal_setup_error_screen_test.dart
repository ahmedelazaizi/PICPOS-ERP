// ═══════════════════════════════════════════════════════════════════════════
// FATAL SETUP ERROR SCREEN TESTS — Spec 125 (T021)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/screens/fatal_setup_error_screen.dart';
import 'package:picpos_erp/services/deployment/reconcile_result.dart';
import 'package:picpos_erp/services/network_service.dart';

void main() {
  group('FatalSetupErrorScreen', () {
    testWidgets('displays reasonAr text from ReconcileInconsistent',
        (tester) async {
      const result = ReconcileInconsistent(
        reasonAr: 'النظام مسجّل كمرآة لكن ارتباط السيرفر مفقود.',
        reasonCode: ReconcileReasonCode.mirrorPairingMissing,
        dbMode: NetworkMode.mirror,
      );
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: FatalSetupErrorScreen(result: result),
          ),
        ),
      );
      expect(find.text('النظام يحتاج لإعادة الإعداد'), findsOneWidget);
      expect(find.text(result.reasonAr), findsOneWidget);
    });

    testWidgets('shows both action buttons', (tester) async {
      const result = ReconcileInconsistent(
        reasonAr: 'مشكلة افتراضية',
        reasonCode: 'TEST',
        dbMode: NetworkMode.client,
      );
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: FatalSetupErrorScreen(result: result),
          ),
        ),
      );
      expect(find.textContaining('ادخل خيارات المطور'), findsOneWidget);
      expect(find.textContaining('إعادة اعداد البدء'), findsOneWidget);
    });

    testWidgets('shows reasonCode + dbMode (Arabic) + support hint',
        (tester) async {
      const result = ReconcileInconsistent(
        reasonAr: 'تفصيل',
        reasonCode: 'MIRROR_PAIRING_MISSING',
        dbMode: NetworkMode.mirror,
      );
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: FatalSetupErrorScreen(result: result),
          ),
        ),
      );
      expect(find.textContaining('MIRROR_PAIRING_MISSING'), findsOneWidget);
      expect(find.textContaining('مرآة'), findsWidgets);
      expect(find.textContaining('الدعم الفنى'), findsOneWidget);
    });

    testWidgets('action callbacks fire when buttons tapped', (tester) async {
      var devTools = 0;
      var reset = 0;
      const result = ReconcileInconsistent(
        reasonAr: 'مشكلة',
        reasonCode: 'TEST',
        dbMode: NetworkMode.standalone,
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: FatalSetupErrorScreen(
              result: result,
              onEnterDevTools: () => devTools++,
              onResetWizard: () => reset++,
            ),
          ),
        ),
      );
      await tester.tap(find.textContaining('ادخل خيارات المطور'));
      await tester.pumpAndSettle();
      expect(devTools, 1);
      expect(reset, 0);

      await tester.tap(find.textContaining('إعادة اعداد البدء'));
      await tester.pumpAndSettle();
      expect(devTools, 1);
      expect(reset, 1);
    });

    testWidgets('PopScope prevents accidental back-pop (full blocker)',
        (tester) async {
      const result = ReconcileInconsistent(
        reasonAr: 'مشكلة',
        reasonCode: 'TEST',
        dbMode: NetworkMode.client,
      );
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: FatalSetupErrorScreen(result: result),
          ),
        ),
      );
      // Verify the screen has a PopScope ancestor with canPop=false.
      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });
  });

  group('FatalSetupErrorApp', () {
    testWidgets('boots a minimal RTL MaterialApp around the screen',
        (tester) async {
      const result = ReconcileInconsistent(
        reasonAr: 'مشكلة',
        reasonCode: 'TEST',
        dbMode: NetworkMode.mirror,
      );
      await tester.pumpWidget(const FatalSetupErrorApp(result: result));
      expect(find.byType(FatalSetupErrorScreen), findsOneWidget);
      expect(find.text('النظام يحتاج لإعادة الإعداد'), findsOneWidget);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // SPEC 130 — PG Schema Parity Fatal screen extension
  // ═════════════════════════════════════════════════════════════════════════
  group('FatalSetupErrorScreen — Spec 130 PG schema parity', () {
    testWidgets('pgSchemaParity kind shows PG-specific title + subtitle',
        (tester) async {
      const result = ReconcileInconsistent(
        kind: ReconcileFatalKind.pgSchemaParity,
        reasonAr: 'صلاحيات قاعدة البيانات غير كافية.',
        reasonCode: ReconcileReasonCode.pgSchemaParity,
        dbMode: NetworkMode.server,
      );
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(home: FatalSetupErrorScreen(result: result)),
        ),
      );
      expect(find.text('فشل التهيئة الذاتية لقاعدة البيانات'), findsOneWidget);
      expect(find.textContaining('انحراف فى مخطط قاعدة بيانات PostgreSQL'),
          findsOneWidget);
      expect(find.text(result.reasonAr), findsOneWidget);
    });

    testWidgets('pgSchemaParity kind shows 3 buttons (retry + 2 default)',
        (tester) async {
      var retry = 0;
      var devTools = 0;
      var reset = 0;
      const result = ReconcileInconsistent(
        kind: ReconcileFatalKind.pgSchemaParity,
        reasonAr: 'فشل',
        reasonCode: ReconcileReasonCode.pgSchemaParity,
        dbMode: NetworkMode.server,
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: FatalSetupErrorScreen(
              result: result,
              onRetrySelfHeal: () => retry++,
              onEnterDevTools: () => devTools++,
              onResetWizard: () => reset++,
            ),
          ),
        ),
      );

      // Verify all 3 buttons present.
      expect(find.textContaining('إعادة محاولة الإصلاح الذاتى'),
          findsOneWidget);
      expect(find.textContaining('ادخل خيارات المطور'), findsOneWidget);
      expect(find.textContaining('إعادة اعداد البدء'), findsOneWidget);

      // Tap retry → only retry callback fires.
      await tester.tap(find.textContaining('إعادة محاولة الإصلاح الذاتى'));
      await tester.pumpAndSettle();
      expect(retry, 1);
      expect(devTools, 0);
      expect(reset, 0);
    });

    testWidgets(
        'modeStateMismatch kind shows only 2 buttons (no retry — regression '
        'guard for Spec 125 widget contract)',
        (tester) async {
      const result = ReconcileInconsistent(
        // default kind = modeStateMismatch
        reasonAr: 'فشل ربط الميرور',
        reasonCode: ReconcileReasonCode.mirrorPairingMissing,
        dbMode: NetworkMode.mirror,
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: FatalSetupErrorScreen(
              result: result,
              // Even when onRetrySelfHeal is supplied, the button is hidden
              // unless kind == pgSchemaParity. This pins the visual
              // separation between Spec 125 and Spec 130 Fatal modes.
              onRetrySelfHeal: () {},
            ),
          ),
        ),
      );

      expect(find.textContaining('إعادة محاولة الإصلاح الذاتى'), findsNothing);
      expect(find.textContaining('ادخل خيارات المطور'), findsOneWidget);
      expect(find.textContaining('إعادة اعداد البدء'), findsOneWidget);
      // And the title stays Spec 125's wording.
      expect(find.text('النظام يحتاج لإعادة الإعداد'), findsOneWidget);
    });

    testWidgets('pgSchemaParity exposes details list under expander',
        (tester) async {
      const result = ReconcileInconsistent(
        kind: ReconcileFatalKind.pgSchemaParity,
        reasonAr: 'فشل',
        reasonCode: ReconcileReasonCode.pgSchemaParity,
        dbMode: NetworkMode.server,
        details: [
          'entity: table:category_station_mappings',
          'CREATE TABLE failed: permission denied for relation public',
        ],
      );
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(home: FatalSetupErrorScreen(result: result)),
        ),
      );
      // Expander present with count.
      expect(find.textContaining('تفاصيل تشخيصية (2)'), findsOneWidget);
    });
  });

  // Spec 131 — mirrorCacheDivergence kind
  group('FatalSetupErrorScreen — Spec 131 mirror cache divergence', () {
    testWidgets(
        'mirrorCacheDivergence kind shows Arabic title + subtitle + red theme',
        (tester) async {
      const result = ReconcileInconsistent(
        kind: ReconcileFatalKind.mirrorCacheDivergence,
        reasonAr: 'تعارض فى بيانات المرآة: لم يتم العثور على مخزن برقم 2.',
        reasonCode: ReconcileReasonCode.mirrorCacheDivergence,
        dbMode: NetworkMode.mirror,
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: FatalSetupErrorScreen(
              result: result,
              onMirrorRepair: () {},
            ),
          ),
        ),
      );

      // Title pins the Spec 131 Arabic wording.
      expect(find.text('تعارض فى بيانات المرآة'), findsOneWidget);
      // Subtitle pins the Spec 131 Arabic wording.
      expect(
          find.textContaining('بعض البيانات الأساسية محلياً لا تطابق السيرفر'),
          findsOneWidget);
      // The reason text bubble carries the dynamic per-event detail.
      expect(find.textContaining('لم يتم العثور على مخزن برقم 2'),
          findsOneWidget);
    });

    testWidgets(
        'mirrorCacheDivergence kind shows the primary re-pair button when '
        'onMirrorRepair is provided', (tester) async {
      const result = ReconcileInconsistent(
        kind: ReconcileFatalKind.mirrorCacheDivergence,
        reasonAr: 'divergence',
        reasonCode: ReconcileReasonCode.mirrorCacheDivergence,
        dbMode: NetworkMode.mirror,
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: FatalSetupErrorScreen(
              result: result,
              onMirrorRepair: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('إعادة المزامنة مع السيرفر'), findsOneWidget);
      // The other two default buttons stay visible.
      expect(find.textContaining('ادخل خيارات المطور'), findsOneWidget);
      expect(find.textContaining('إعادة اعداد البدء'), findsOneWidget);
      // The PG-parity retry button stays HIDDEN — strict separation between
      // kinds (regression guard).
      expect(find.textContaining('إعادة محاولة الإصلاح الذاتى'), findsNothing);
    });

    testWidgets('onMirrorRepair fires when the primary button is tapped',
        (tester) async {
      var pressed = 0;
      const result = ReconcileInconsistent(
        kind: ReconcileFatalKind.mirrorCacheDivergence,
        reasonAr: 'divergence',
        reasonCode: ReconcileReasonCode.mirrorCacheDivergence,
        dbMode: NetworkMode.mirror,
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: FatalSetupErrorScreen(
              result: result,
              onMirrorRepair: () => pressed++,
            ),
          ),
        ),
      );
      await tester.tap(find.textContaining('إعادة المزامنة مع السيرفر'));
      await tester.pump();
      expect(pressed, 1);
    });

    testWidgets(
        'mirrorCacheDivergence renders details under the expander with the '
        'kind + requested_id + cached_ids + origin breadcrumb pieces',
        (tester) async {
      const result = ReconcileInconsistent(
        kind: ReconcileFatalKind.mirrorCacheDivergence,
        reasonAr: 'divergence',
        reasonCode: ReconcileReasonCode.mirrorCacheDivergence,
        dbMode: NetworkMode.mirror,
        details: [
          'kind=warehouse',
          'requested_id=2',
          'cached_ids=1',
          'origin=pre-flight',
        ],
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: FatalSetupErrorScreen(
              result: result,
              onMirrorRepair: () {},
            ),
          ),
        ),
      );
      // Expander shows count.
      expect(find.textContaining('تفاصيل تشخيصية (4)'), findsOneWidget);
    });
  });
}
