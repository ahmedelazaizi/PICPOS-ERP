// حالة القبول 6 (جهاز إضافي في الفرع) + الحالة 12 (المرآة داخل v2).
//
// الجهاز الإضافي = عميل آخر للرئيسي بنفس الفرع: يُقرن باسمه ورمزه، يتخطى أي إنشاء
// مستخدم/مدير/شركة محلية، ويُنهي بنمط client. (رمز الطرفية المختلف لكل جهاز يُخصَّص في
// الخادم عند الإقران — يُقاس في اختبارات إقران LAN، لا هنا.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_path.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_controller.dart';

import 'first_run_test_kit.dart';

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  testWidgets('جهاز إضافي: اسم ورمز مستقلان، بلا مستخدم/مدير/شركة محلية', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    h.persistence.branches = [testBranch(7, 'فرع عمّان', 'AMM')];
    await h.pump(tester);
    await tapKey(tester, 'first_run_path_branch');
    await tapKey(tester, 'first_run_next');
    await enterKey(tester, 'first_run_link_endpoint', '192.168.1.10');
    await enterKey(tester, 'first_run_link_device', 'POS-AMM-02');
    await enterKey(tester, 'first_run_link_code', 'ZXCV5678');
    await tapKey(tester, 'first_run_link_connect');
    await tester.pump(const Duration(milliseconds: 50));
    await tapKey(tester, 'first_run_next'); // storage
    await tapKey(tester, 'first_run_branch_role_additional');
    expect(find.byKey(const Key('first_run_branch_additional_note')), findsOneWidget);
    await tapKey(tester, 'first_run_next'); // firstSync
    await tapKey(tester, 'first_run_sync_start');
    await tester.pump(const Duration(milliseconds: 50));
    await tapKey(tester, 'first_run_next'); // account
    await enterKey(tester, 'first_run_account_username', 'cash.amm');
    await enterKey(tester, 'first_run_account_password', 'Good#Pass1');
    await tapKey(tester, 'first_run_account_verify');
    await tester.pump(const Duration(milliseconds: 50));
    await tapKey(tester, 'first_run_next');
    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));

    expect(h.link.lastDeviceName, 'POS-AMM-02');
    expect(h.link.lastCode, 'ZXCV5678');
    expect(
        h.container.read(firstRunControllerProvider).draft.branchRole.name,
        'additional');
    final p = h.persistence;
    expect(p.clientBranchId, 7);
    expect(p.calls, isNot(contains('adminpw')));
    expect(p.calls, isNot(contains('createBranch')));
    expect(p.settings.containsKey('company_name'), isFalse);
    expect(p.calls, contains('mode:client'));
    expect(find.byKey(const Key('first_run_success_title')), findsOneWidget);
    await h.teardown(tester);
  });

  testWidgets('المرآة داخل v2: ربط بمدير ثم مراجعة ثم mirror عبر المعتمد', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);
    await tester.ensureVisible(find.byKey(const Key('first_run_advanced')));
    await tester.tap(find.byKey(const Key('first_run_advanced')));
    await tester.pumpAndSettle();
    await tapKey(tester, 'first_run_path_mirror');
    expect(h.container.read(firstRunControllerProvider).draft.path,
        FirstRunPath.mirror);
    await tapKey(tester, 'first_run_next'); // → link
    await enterKey(tester, 'first_run_link_endpoint', '192.168.1.10');
    await enterKey(tester, 'first_run_link_admin', 'admin');
    await enterKey(tester, 'first_run_link_admin_password', 'Mirror#Pass1');
    await tapKey(tester, 'first_run_link_connect');
    await tester.pump(const Duration(milliseconds: 50));
    expect(h.link.mirrorAdmin, 'admin');
    expect(h.container.read(firstRunControllerProvider).secrets.accountPassword,
        isEmpty);
    await tapKey(tester, 'first_run_next'); // → review (3 خطوات)
    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));

    final order = h.events;
    expect(order.indexOf('pair-mirror'), lessThan(order.indexOf('mode:mirror')));
    expect(order.indexOf('mode:mirror'),
        lessThan(order.indexOf('save:setup_completed')));
    expect(h.persistence.settings['deployment_mode'], 'mirror');
    expect(find.byKey(const Key('first_run_success_title')), findsOneWidget);
    await h.teardown(tester);
  });

  testWidgets('مرآة بكلمة مدير خاطئة لا تُربط', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);
    await tester.ensureVisible(find.byKey(const Key('first_run_advanced')));
    await tester.tap(find.byKey(const Key('first_run_advanced')));
    await tester.pumpAndSettle();
    await tapKey(tester, 'first_run_path_mirror');
    await tapKey(tester, 'first_run_next');
    await enterKey(tester, 'first_run_link_endpoint', '192.168.1.10');
    await enterKey(tester, 'first_run_link_admin', 'admin');
    await enterKey(tester, 'first_run_link_admin_password', 'nope');
    await tapKey(tester, 'first_run_link_connect');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('bad admin'), findsOneWidget);
    expect(find.byKey(const Key('first_run_link_badge')), findsNothing);
    await h.teardown(tester);
  });
}