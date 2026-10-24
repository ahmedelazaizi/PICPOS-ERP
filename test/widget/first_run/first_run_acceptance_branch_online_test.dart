// حالة القبول 3 (فرع + اتصال ناجح): إقران ← مزامنة أولى ← اختيار الفرع ← تحقق حقيقي
// من الحساب (جلسة خادم شرط) ← إنهاء بلا أي كتابة شركة/مستخدم محلي، و
// setup_completed آخر كتابة. لا خطوة ترخيص.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_steps.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_controller.dart';

import 'first_run_server_kit.dart';
import 'first_run_test_kit.dart';

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  testWidgets('فرع متصل: التسلسل والكتابات الدنيا ونجاح بمعلومات الاتصال', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    h.persistence.branches = [testBranch(7, 'فرع عمّان', 'AMM')];
    await h.pump(tester);
    await fillBranchUntilReview(tester);

    // الفرع الوحيد اختير تلقائياً، ورمز الإقران مُسح بعد النجاح (لا أسرار باقية).
    final ui = h.container.read(firstRunControllerProvider);
    expect(ui.draft.selectedBranchId, 7);
    expect(ui.secrets.pairingCode, isEmpty);
    expect(ui.secrets.accountPassword, isEmpty);
    expect(h.link.lastCode, 'ABCD2345');
    expect(h.link.lastDeviceName, 'POS-AMM-01');
    expect(h.verifier.lastBranchId, 7);

    // لا أسرار في المسودة المحفوظة.
    final saved = h.settings.values['setup_draft_v2'] ?? '';
    for (final secret in ['ABCD2345', 'Good#Pass1']) {
      expect(saved.contains(secret), isFalse, reason: secret);
    }

    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));

    final order = h.events;
    expect(order.indexOf('pair'), lessThan(order.indexOf('sync')));
    expect(order.indexOf('sync'), lessThan(order.indexOf('verify')));
    expect(order.indexOf('verify'), lessThan(order.indexOf('mode:client')));
    expect(order.indexOf('mode:client'),
        lessThan(order.indexOf('save:setup_completed')));

    final p = h.persistence;
    expect(p.clientBranchId, 7);
    expect(p.settings['invoice_code_prefix'], 'AMM-POS');
    expect(p.settings['deployment_mode'], 'client');
    // لا شركة ولا فرع ولا مدير ولا مستخدم محلي.
    expect(p.settings.containsKey('company_name'), isFalse);
    expect(p.calls, isNot(contains('createBranch')));
    expect(p.calls, isNot(contains('adminpw')));
    expect(p.calls, isNot(contains('devpw')));
    expect(h.writer.writes, 0);
    expect(h.provisioning.armed, 0);

    expect(find.byKey(const Key('first_run_success_title')), findsOneWidget);
    // A0 (ADP-002): network modes must restart (sync starts at boot).
    expect(find.byKey(const Key('first_run_start')), findsNothing);
    expect(find.byKey(const Key('first_run_restart')), findsOneWidget);
    expect(find.byKey(const Key('first_run_success_connection')), findsOneWidget);
    expect(find.textContaining('192.168.1.10'), findsWidgets);
    await tapKey(tester, 'first_run_restart');
    expect(h.restarted, isTrue);
    expect(h.started, isFalse);
    await h.teardown(tester);
  });

  testWidgets('الخطوات الست للفرع بلا ترخيص، والمزامنة قبل الحساب', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);
    await tapKey(tester, 'first_run_path_branch');
    final steps = h.container
        .read(firstRunControllerProvider)
        .draft
        .path;
    expect(stepsFor(steps), hasLength(6));
    expect(find.text('2 من 6'), findsNothing); // العداد في الرأس بصيغة p0 من p1
    expect(find.byKey(const Key('first_run_step_counter')), findsOneWidget);
    await h.teardown(tester);
  });

  testWidgets('كلمة خاطئة أو بلا جلسة خادم ⇒ لا تحقق ولا تقدّم (SEC-004)', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    h.persistence.branches = [testBranch(7, 'فرع عمّان', 'AMM')];
    await h.pump(tester);
    await fillBranchUntilReview(tester, password: 'wrong-pass');
    expect(find.byKey(const Key('first_run_account_error')), findsOneWidget);
    expect(find.byKey(const Key('first_run_account_badge')), findsNothing);
    expect(find.byKey(const Key('first_run_finish')), findsNothing);
    // كلمة المرور لا تبقى بعد المحاولة الفاشلة.
    expect(h.container.read(firstRunControllerProvider).secrets.accountPassword,
        isEmpty);

    h.verifier.serverSession = false;
    await enterKey(tester, 'first_run_account_password', 'Good#Pass1');
    await tapKey(tester, 'first_run_account_verify');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('no server session'), findsOneWidget);
    expect(
        h.container.read(firstRunControllerProvider).draft.checks.accountVerified,
        isFalse);

    h.verifier.serverSession = true;
    await enterKey(tester, 'first_run_account_password', 'Good#Pass1');
    await tapKey(tester, 'first_run_account_verify');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('first_run_account_result')), findsOneWidget);
    expect(find.textContaining('كاشير / فرع عمّان'), findsOneWidget);
    await h.teardown(tester);
  });

  testWidgets('تعديل العنوان بعد الربط يبطل الربط والمزامنة والحساب', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    h.persistence.branches = [testBranch(7, 'فرع عمّان', 'AMM')];
    await h.pump(tester);
    await fillBranchUntilReview(tester);
    await tapKey(tester, 'first_run_step_1');
    await enterKey(tester, 'first_run_link_endpoint', '10.9.9.9');
    final c = h.container.read(firstRunControllerProvider).draft.checks;
    expect((c.linked, c.firstSyncDone, c.accountVerified), (false, false, false));
    await h.teardown(tester);
  });
}