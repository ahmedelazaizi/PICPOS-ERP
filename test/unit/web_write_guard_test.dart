// م3-9 — WebWriteGuard: الديسكتوب لا يتأثر، والويب يمنع الكتابة برسالة عربية.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/web/web_session.dart';
import 'package:picpos_erp/web/web_write_guard.dart';

WebSession _session() => WebSession(
      baseUrl: 'https://erp.example.com',
      token: 't',
      userId: 1,
      username: 'u',
      displayName: 'U',
      roleId: 1,
      roleName: 'r',
      roleIsSystem: false,
      permissionCodes: const [],
      isPostgres: false,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

void main() {
  tearDown(() {
    WebSession.treatAsWebForTesting = false;
    WebSession.active = null;
  });

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) {
          captured = c;
          return const SizedBox();
        }),
      ),
    ));
    return captured;
  }

  testWidgets('الديسكتوب: allow=true و wrap يعيد المعالج نفسه', (tester) async {
    final ctx = await pumpHost(tester);
    expect(WebWriteGuard.isWeb, isFalse);
    expect(WebWriteGuard.allow(ctx, feature: 'x'), isTrue);
    void action() {}
    expect(identical(WebWriteGuard.wrap(ctx, action), action), isTrue);
    expect(WebWriteGuard.wrap(ctx, null), isNull);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('الويب: allow=false مع SnackBar عربي ولا ينفَّذ المعالج', (tester) async {
    WebSession.treatAsWebForTesting = true;
    WebSession.active = _session();
    final ctx = await pumpHost(tester);
    expect(WebWriteGuard.isWeb, isTrue);

    var ran = false;
    final wrapped = WebWriteGuard.wrap(ctx, () => ran = true, feature: 'دفاتر السندات');
    expect(wrapped, isNotNull);
    wrapped!();
    await tester.pump();
    expect(ran, isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('غير مدعومة في نسخة الويب'), findsOneWidget);
    expect(find.textContaining('دفاتر السندات'), findsOneWidget);
  });

  testWidgets('الويب: wrapAsync و allow بلا ميزة', (tester) async {
    WebSession.treatAsWebForTesting = true;
    WebSession.active = _session();
    final ctx = await pumpHost(tester);
    var ran = false;
    await WebWriteGuard.wrapAsync(ctx, () async => ran = true)!();
    expect(ran, isFalse);
    expect(WebWriteGuard.allow(ctx), isFalse);
    expect(WebWriteGuard.message(), isNot(contains(':')));
  });

  test('المتصفّح بلا جلسة نشطة ليس عميل ويب', () {
    WebSession.treatAsWebForTesting = true;
    WebSession.active = null;
    expect(WebWriteGuard.isWeb, isFalse);
  });
}
