// حالة القبول 2 (رئيسي + باقة كاملة + فرعان): تهيئة PG ثم مراجعة غير قابلة للتجاوز
// ثم كتابة الخادم ← تسليح PG ← النمط ← setup_completed، وصفحة النجاح بزر «إعادة
// التشغيل الآن» ومعلومات اتصال الفروع. بلا exit(0) قبل صفحة النجاح.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_path.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_controller.dart';

import 'first_run_server_kit.dart';
import 'first_run_test_kit.dart';

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  testWidgets('رئيسي كامل: الترتيب والمدخلات والنجاح وإعادة التشغيل', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);
    await fillHqUntilReview(tester);

    // المراجعة تعرض الفروع والمستخدمين دون كلمات المرور.
    expect(find.text('BR-01'), findsWidgets);
    expect(find.textContaining('cash.amm'), findsOneWidget);
    expect(find.textContaining('Cashier#Pass1'), findsNothing);

    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));

    final order = h.events;
    final iWrite = order.indexOf('server-write');
    final iArm = order.indexOf('pg-arm');
    final iMode = order.indexOf('mode:server');
    final iDone = order.indexOf('save:setup_completed');
    expect(iWrite, isNonNegative);
    expect(iWrite, lessThan(iArm));
    expect(iArm, lessThan(iMode));
    expect(iMode, lessThan(iDone), reason: 'setup_completed آخر كتابة');
    expect(h.provisioning.armed, 1);

    final input = h.writer.lastInput!;
    expect(input.companyName, 'شركة الأمل');
    expect(input.currency, 'JOD');
    expect(input.businessProfile, 'unified');
    expect(input.branches.single.code, 'BR-01');
    expect(input.users.single.username, 'cash.amm');
    expect(input.users.single.scope, 'BR-01');
    expect(input.users.single.roleName, 'كاشير');
    expect(input.users.single.password, 'Cashier#Pass1');
    expect(input.adminPassword, 'S3cretPass');
    expect(input.offlineDays, 7);
    expect(h.writer.lastConfig!.host, 'localhost');
    expect(h.writer.lastConfig!.password, 'pg-secret');

    // نجاح: لا زر ابدأ؛ زر إعادة التشغيل ومعلومات اتصال الفروع.
    expect(find.byKey(const Key('first_run_success_title')), findsOneWidget);
    expect(find.byKey(const Key('first_run_start')), findsNothing);
    expect(find.text('192.168.1.20:8080'), findsOneWidget);
    expect(h.restarted, isFalse);
    await tapKey(tester, 'first_run_restart');
    expect(h.restarted, isTrue);
    await h.teardown(tester);
  });

  testWidgets('فشل كتابة الخادم يبقى على المراجعة بلا تسليح ولا setup_completed',
      (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    h.writer.failWith = StateError('disk full');
    await h.pump(tester);
    await fillHqUntilReview(tester);
    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('first_run_failure')), findsOneWidget);
    expect(h.provisioning.armed, 0);
    expect(h.events, isNot(contains('save:setup_completed')));
    expect(h.events, isNot(contains('mode:server')));

    // إعادة المحاولة بعد زوال العطل تنجح.
    h.writer.failWith = null;
    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('first_run_success_title')), findsOneWidget);
    expect(h.provisioning.armed, 1);
    await h.teardown(tester);
  });

  testWidgets('لا تقدّم من التخزين قبل نجاح تهيئة PostgreSQL، وتعديل الحقل يبطلها',
      (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    h.provisioning.provisionError = 'password authentication failed';
    await h.pump(tester);
    await tapKey(tester, 'first_run_path_hq');
    await tapKey(tester, 'first_run_next');
    await tapKey(tester, 'first_run_pack_pos');
    await enterKey(tester, 'first_run_company_name', 'شركة');
    await tapKey(tester, 'first_run_currency_EGP');
    await tapKey(tester, 'first_run_next'); // storage
    expect(find.byKey(const Key('first_run_pg_host')), findsOneWidget);

    // بلا تهيئة: «التالي» معطّل.
    FilledButton next() =>
        tester.widget<FilledButton>(find.byKey(const Key('first_run_next')));
    expect(next().onPressed, isNull);

    await tapKey(tester, 'first_run_pg_provision');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('first_run_pg_error')), findsOneWidget);
    expect(next().onPressed, isNull);

    // نجاح ⇒ يُفتح، ثم تعديل المضيف ⇒ يُغلق من جديد.
    h.provisioning.provisionError = null;
    await tapKey(tester, 'first_run_pg_provision');
    await tester.pump(const Duration(milliseconds: 50));
    expect(next().onPressed, isNotNull);
    await enterKey(tester, 'first_run_pg_host', '10.0.0.5');
    expect(next().onPressed, isNull);
    final c = h.container.read(firstRunControllerProvider);
    expect(c.draft.checks.provisioned, isFalse);
    expect(c.draft.path, FirstRunPath.hq);
    await h.teardown(tester);
  });

  testWidgets('كلمة مستخدم قصيرة أو مكررة تمنع التقدّم برسالة', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);
    await fillHqUntilReview(tester, userPassword: 'short');
    // fillHqUntilReview لا يتجاوز users بكلمة قصيرة؛ ما زلنا على الخطوة.
    expect(find.byKey(const Key('first_run_blocked_hint')), findsOneWidget);
    expect(find.textContaining('8 أحرف'), findsWidgets);
    await h.teardown(tester);
  });
}
