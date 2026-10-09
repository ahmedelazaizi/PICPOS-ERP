// م3-6 — عميل الويب من الطرف إلى الطرف على VM: دخول حقيقي ← تذكرة ← قناة drift
// ← `databaseProvider` المتجاوَز ← مزوّدات لوحة التحكم الحقيقية، مقابل خادم
// shelf حقيقي وقاعدة في الذاكرة (المستخدم المزروع admin/admin).
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/providers/dashboard_filter_provider.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/services/api/api_auth_middleware.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_session_token.dart';
import 'package:ural_erp/web/web_providers.dart';
import 'package:ural_erp/web/web_session.dart';

void main() {
  late AppDatabase db;
  late HttpServer server;
  late String baseUrl;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    ApiSessionToken.deriveKey('e2e-seed');
    ApiAuthMiddleware.setToken('bearer-xyz');
    db = AppDatabase.forTesting();
    await db.customSelect('select 1').get(); // افتح القاعدة قبل الخدمة
    final handler = const shelf.Pipeline()
        .addMiddleware(ApiAuthMiddleware.createMiddleware())
        .addHandler(ApiHandler(db).buildRouter().call);
    server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() async {
    await server.close(force: true);
    ApiSessionToken.clearKey();
    ApiAuthMiddleware.clearToken();
    await db.close();
  });

  test('دخول خاطئ يعطي رسالة عربية، والسيرفر غير متاح يعطي رسالة اتصال', () async {
    await expectLater(
      WebAuthClient().login(
          baseUrl: baseUrl, username: 'admin', password: 'wrong-pass'),
      throwsA(isA<WebAuthException>()
          .having((e) => e.failure, 'failure',
              WebAuthFailure.invalidCredentials)
          .having((e) => e.message, 'message', contains('غير صحيحة'))),
    );
    await expectLater(
      WebAuthClient().login(
          baseUrl: 'http://127.0.0.1:1', username: 'a', password: 'b'),
      throwsA(isA<WebAuthException>()
          .having((e) => e.failure, 'failure', WebAuthFailure.network)),
    );
  });

  test('دخول admin ثم قراءة مزوّدات اللوحة عبر القناة بلا خطأ سياسة', () async {
    final session = await WebAuthClient()
        .login(baseUrl: baseUrl, username: 'admin', password: 'admin');
    expect(session.permissionCodes, isNotEmpty);
    expect(session.roleIsSystem, isTrue);

    final container = ProviderContainer(overrides: webProviderOverrides);
    addTearDown(container.dispose);
    container.read(webSessionProvider.notifier).signIn(session);

    expect(container.read(authProvider).isAuthenticated, isTrue);
    final kpi = await container.read(dashboardKpiProvider.future);
    expect(kpi, isNotNull);

    // قراءةٌ مباشرة عبر databaseProvider المتجاوَز تعمل على بيانات المضيف.
    final webDb = container.read(databaseProvider);
    expect(webDb.isPostgres, isFalse);
    final viaWeb = await webDb.customSelect('select count(*) as n from units').get();
    final direct = await db.customSelect('select count(*) as n from units').get();
    expect(viaWeb.single.data['n'], direct.single.data['n']);
  });
}
