// حالة القبول 4 (فرع غير متصل قبل المزامنة): تفشل المزامنة الأولى ⇒ شرح واضح، «التالي»
// معطّل، ولا setup_completed. وعند عودة الاتصال تنجح الإعادة ويُكمل المسار.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'first_run_test_kit.dart';

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  testWidgets('بلا اتصال: المزامنة لا تتقدّم ولا يكتمل الإعداد', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    h.persistence.branches = [testBranch(7, 'فرع عمّان', 'AMM')];
    await h.pump(tester);
    await tapKey(tester, 'first_run_path_branch');
    await tapKey(tester, 'first_run_next');
    await enterKey(tester, 'first_run_link_endpoint', '192.168.1.10');
    await enterKey(tester, 'first_run_link_device', 'POS-1');
    await enterKey(tester, 'first_run_link_code', 'ABCD2345');
    await tapKey(tester, 'first_run_link_connect');
    await tester.pump(const Duration(milliseconds: 50));
    await tapKey(tester, 'first_run_next'); // storage
    await tapKey(tester, 'first_run_next'); // firstSync

    h.link.online = false;
    await tapKey(tester, 'first_run_sync_start');
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('first_run_sync_offline')), findsOneWidget);
    expect(find.textContaining('دون اتصال بالسيرفر الرئيسي'), findsWidgets);
    FilledButton next() =>
        tester.widget<FilledButton>(find.byKey(const Key('first_run_next')));
    expect(next().onPressed, isNull);
    await tapKey(tester, 'first_run_next');
    expect(find.byKey(const Key('first_run_sync_start')), findsOneWidget,
        reason: 'بقي على المزامنة');
    expect(h.events, isNot(contains('save:setup_completed')));
    expect(h.events, isNot(contains('mode:client')));

    // عودة الاتصال: تنجح الإعادة ويُفتح التقدّم.
    h.link.online = true;
    await tapKey(tester, 'first_run_sync_start');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('first_run_sync_offline')), findsNothing);
    expect(next().onPressed, isNotNull);
    expect(h.link.syncCalls, 2);
    await h.teardown(tester);
  });

  testWidgets('فشل المزامنة نفسها (اتصال سليم) لا يرفع علم المزامنة', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);
    await tapKey(tester, 'first_run_path_branch');
    await tapKey(tester, 'first_run_next');
    await enterKey(tester, 'first_run_link_endpoint', '192.168.1.10');
    await enterKey(tester, 'first_run_link_device', 'POS-1');
    await enterKey(tester, 'first_run_link_code', 'ABCD2345');
    await tapKey(tester, 'first_run_link_connect');
    await tester.pump(const Duration(milliseconds: 50));
    await tapKey(tester, 'first_run_next');
    await tapKey(tester, 'first_run_next');
    h.link.syncOk = false;
    await tapKey(tester, 'first_run_sync_start');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('sync failed'), findsOneWidget);
    FilledButton next() =>
        tester.widget<FilledButton>(find.byKey(const Key('first_run_next')));
    expect(next().onPressed, isNull);
    await h.teardown(tester);
  });

  testWidgets('رمز إقران خاطئ لا يربط ولا يفتح المزامنة', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    h.link.pairOk = false;
    await h.pump(tester);
    await tapKey(tester, 'first_run_path_branch');
    await tapKey(tester, 'first_run_next');
    await enterKey(tester, 'first_run_link_endpoint', '192.168.1.10');
    await enterKey(tester, 'first_run_link_device', 'POS-1');
    await enterKey(tester, 'first_run_link_code', 'WRONG123');
    await tapKey(tester, 'first_run_link_connect');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('bad code'), findsOneWidget);
    expect(find.byKey(const Key('first_run_link_badge')), findsNothing);
    FilledButton next() =>
        tester.widget<FilledButton>(find.byKey(const Key('first_run_next')));
    expect(next().onPressed, isNull);
    await h.teardown(tester);
  });
}