// مساعداتُ مساري المقرّ والفرع في اختبارات الإعداد الأول: إكمالُ الخطوات حتى
// المراجعة بالمزيّفات المحقونة في `FirstRunHarness`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'first_run_test_kit.dart';

Future<void> selectInDropdown(
  WidgetTester tester,
  String key,
  String label,
) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// يُنجز خطواتِ المقرّ الستّ حتى صفحة المراجعة: باقة كاملة + فرع + تهيئة PG +
/// مستخدم كاشير بنطاق فرع.
Future<void> fillHqUntilReview(
  WidgetTester tester, {
  String company = 'شركة الأمل',
  String branchCode = 'BR-01',
  String branchName = 'فرع عمّان',
  String adminPassword = 'S3cretPass',
  bool addUser = true,
  String userPassword = 'Cashier#Pass1',
}) async {
  await tapKey(tester, 'first_run_path_hq');
  await tapKey(tester, 'first_run_next'); // mode → company
  await tapKey(tester, 'first_run_pack_full');
  await enterKey(tester, 'first_run_company_name', company);
  await tapKey(tester, 'first_run_currency_JOD');
  await tapKey(tester, 'first_run_hq_branch_add');
  await enterKey(tester, 'first_run_hq_branch_code_0', branchCode);
  await enterKey(tester, 'first_run_hq_branch_name_0', branchName);
  await tapKey(tester, 'first_run_next'); // company → storage (PG)
  await enterKey(tester, 'first_run_pg_password', 'pg-secret');
  await tapKey(tester, 'first_run_pg_provision');
  await tester.pump(const Duration(milliseconds: 50));
  await tapKey(tester, 'first_run_next'); // storage → users
  await enterKey(tester, 'first_run_admin_password', adminPassword);
  await enterKey(tester, 'first_run_admin_password_confirm', adminPassword);
  await enterKey(tester, 'first_run_dev_password', 'dev123');
  await enterKey(tester, 'first_run_dev_password_confirm', 'dev123');
  if (addUser) {
    await tapKey(tester, 'first_run_hq_user_add');
    await enterKey(tester, 'first_run_hq_user_name_0', 'كاشير عمّان');
    await enterKey(tester, 'first_run_hq_user_username_0', 'cash.amm');
    await selectInDropdown(tester, 'first_run_hq_user_role_0', 'كاشير');
    await selectInDropdown(tester, 'first_run_hq_user_scope_0', 'BR-01 — $branchName');
    await enterKey(tester, 'first_run_hq_user_password_0', userPassword);
  }
  await tapKey(tester, 'first_run_next'); // users → prep
  await tapKey(tester, 'first_run_next'); // prep → review
}

/// يُنجز خطواتِ الفرع حتى المراجعة: رابط + مزامنة + فرع + حساب.
Future<void> fillBranchUntilReview(
  WidgetTester tester, {
  String endpoint = '192.168.1.10',
  String code = 'ABCD2345',
  String password = 'Good#Pass1',
  String username = 'cash.amm',
}) async {
  await tapKey(tester, 'first_run_path_branch');
  await tapKey(tester, 'first_run_next'); // mode → link
  await enterKey(tester, 'first_run_link_endpoint', endpoint);
  await enterKey(tester, 'first_run_link_device', 'POS-AMM-01');
  await enterKey(tester, 'first_run_link_code', code);
  await tapKey(tester, 'first_run_link_connect');
  await tester.pump(const Duration(milliseconds: 50));
  await tapKey(tester, 'first_run_next'); // link → storage
  await tapKey(tester, 'first_run_next'); // storage → firstSync
  await tapKey(tester, 'first_run_sync_start');
  await tester.pump(const Duration(milliseconds: 50));
  await tapKey(tester, 'first_run_next'); // firstSync → account
  await enterKey(tester, 'first_run_account_username', username);
  await enterKey(tester, 'first_run_account_password', password);
  await tapKey(tester, 'first_run_account_verify');
  await tester.pump(const Duration(milliseconds: 50));
  await tapKey(tester, 'first_run_next'); // account → review
}
