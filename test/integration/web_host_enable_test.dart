// م3-9 — تفعيل المضيف للوصول من المتصفّح:
//   1. تقديم ملفات `build/web` من نفس الأصل (index.html fallback، 404 للملف
//      المفقود، حماية من الخروج عن الجذر، لا تقديم عند التعطيل).
//   2. تفعيل كتابات جلسة الويب (`enableWebSessionWrites`) مع استثناء
//      `/api/sales/held` من بادئة `/api/sales`.
//   3. سياسة Origin (`WebOriginPolicy`): غريب 403، ضمن القائمة/نفس الأصل يمرّ.
//   4. إعداد `NetworkService.configureWebAccess` يُحفَظ ويُحمَّل، والبوّابة
//      تُقفل `/webdb` و`/api/web/*` (404) عند التعطيل.
//
// خادم shelf حقيقي على loopback وقاعدة SQLite في الذاكرة. لا ملفات بناء حقيقية:
// مجلد مؤقّت بملفات صغيرة.
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_auth_middleware.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_rate_limiter.dart';
import 'package:ural_erp/services/api/api_session_token.dart';
import 'package:ural_erp/services/api/api_web_session_handler.dart';
import 'package:ural_erp/services/api/web_static_handler.dart';
import 'package:ural_erp/services/network_service.dart';

void main() {
  late Directory webDir;
  late AppDatabase db;
  HttpServer? server;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    ApiSessionToken.deriveKey('host-enable-seed');
    ApiAuthMiddleware.setToken('bearer-xyz');
    webDir = Directory.systemTemp.createTempSync('picpos_web_');
    File('${webDir.path}/index.html').writeAsStringSync('<html>PICPOS-INDEX</html>');
    File('${webDir.path}/main.dart.js').writeAsStringSync('console.log(1);');
    File('${webDir.path}/flutter_service_worker.js').writeAsStringSync('//sw');
    Directory('${webDir.path}/assets').createSync();
    File('${webDir.path}/assets/AssetManifest.json').writeAsStringSync('{}');
    // ملف خارج الجذر لاختبار الخروج عنه.
    File('${webDir.parent.path}/picpos_outside_secret.txt')
        .writeAsStringSync('SECRET');
  });

  tearDownAll(() {
    ApiAuthMiddleware.disableWebSessionWrites();
    WebOriginPolicy.configure(const []);
    ApiSessionToken.clearKey();
    try {
      webDir.deleteSync(recursive: true);
      File('${webDir.parent.path}/picpos_outside_secret.txt').deleteSync();
    } catch (_) {}
  });

  setUp(() async {
    ApiRateLimiter.reset();
    db = AppDatabase.forTesting();
    await db.customSelect('select 1').get();
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
    await db.close();
  });

  Future<String> serve({String? staticDir, shelf.Middleware? extra}) async {
    var p = const shelf.Pipeline();
    if (extra != null) p = p.addMiddleware(extra);
    final handler = p
        .addMiddleware(ApiRateLimiter.createMiddleware())
        .addMiddleware(ApiAuthMiddleware.createMiddleware())
        .addHandler(ApiHandler(db, webStaticDir: staticDir).buildRouter().call);
    server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    return 'http://127.0.0.1:${server!.port}';
  }

  group('تقديم الملفات الثابتة', () {
    test('hasBuild يتطلب index.html', () {
      expect(WebStaticHandler.hasBuild(webDir.path), isTrue);
      expect(WebStaticHandler.hasBuild('${webDir.path}/assets'), isFalse);
      expect(WebStaticHandler.hasBuild(null), isFalse);
      expect(WebStaticHandler.hasBuild('  '), isFalse);
    });

    test('الجذر ومسار بلا امتداد يعيدان index.html (بلا مصادقة)', () async {
      final base = await serve(staticDir: webDir.path);
      final root = await http.get(Uri.parse('$base/'));
      expect(root.statusCode, 200);
      expect(root.body, contains('PICPOS-INDEX'));
      expect(root.headers['content-type'], contains('text/html'));
      expect(root.headers['cache-control'], 'no-cache');

      final spa = await http.get(Uri.parse('$base/reports/sales'));
      expect(spa.statusCode, 200);
      expect(spa.body, contains('PICPOS-INDEX'));
    });

    test('ملفات موجودة بنوعها الصحيح، والمفقود بامتداد 404', () async {
      final base = await serve(staticDir: webDir.path);
      final js = await http.get(Uri.parse('$base/main.dart.js'));
      expect(js.statusCode, 200);
      expect(js.headers['content-type'], contains('javascript'));
      expect(js.headers['x-content-type-options'], 'nosniff');

      final nested = await http.get(Uri.parse('$base/assets/AssetManifest.json'));
      expect(nested.statusCode, 200);

      final sw = await http.get(Uri.parse('$base/flutter_service_worker.js'));
      expect(sw.headers['cache-control'], 'no-cache');

      final missing = await http.get(Uri.parse('$base/nope.png'));
      expect(missing.statusCode, 404);
    });

    test('لا خروج عن الجذر', () async {
      final base = await serve(staticDir: webDir.path);
      for (final path in [
        '/../picpos_outside_secret.txt',
        '/%2e%2e/picpos_outside_secret.txt',
        '/assets/..%2f..%2fpicpos_outside_secret.txt',
      ]) {
        final r = await http.get(Uri.parse('$base$path'));
        expect(r.body, isNot(contains('SECRET')), reason: path);
      }
    });

    test('الـAPI والقنوات لا تسقط إلى index.html', () async {
      final base = await serve(staticDir: webDir.path);
      final api = await http.get(Uri.parse('$base/api/does-not-exist'));
      expect(api.body, isNot(contains('PICPOS-INDEX')));
      final ws = await http.get(Uri.parse('$base/webdb'));
      expect(ws.body, isNot(contains('PICPOS-INDEX')));
    });

    test('بلا مجلد (معطّل) لا يُقدَّم شيء', () async {
      final base = await serve(staticDir: null);
      final r = await http.get(Uri.parse('$base/'));
      expect(r.statusCode, 404);
      expect(r.body, isNot(contains('PICPOS-INDEX')));
    });

    test('مجلد بلا index.html لا يُقدَّم', () async {
      final empty = Directory.systemTemp.createTempSync('picpos_empty_');
      addTearDown(() => empty.deleteSync(recursive: true));
      final base = await serve(staticDir: empty.path);
      final r = await http.get(Uri.parse('$base/'));
      expect(r.statusCode, 404);
    });

    test('ملفات ثابتة كثيرة لا تُحجب بمحدّد المعدّل', () async {
      final base = await serve(staticDir: webDir.path);
      for (var i = 0; i < 150; i++) {
        final r = await http.get(Uri.parse('$base/main.dart.js'));
        expect(r.statusCode, 200, reason: 'طلب $i');
      }
    });

    test('POST على مسار ثابت مرفوض', () async {
      final base = await serve(staticDir: webDir.path);
      final r = await http.post(Uri.parse('$base/main.dart.js'));
      expect(r.statusCode, isNot(200));
    });
  });

  group('كتابات جلسة الويب', () {
    setUp(() {
      ApiAuthMiddleware.disableWebSessionWrites();
      WebOriginPolicy.configure(const []);
    });

    test('webWriteDeniedPrefixes يستثني /api/sales/held فقط من /api/sales', () {
      ApiAuthMiddleware.enableWebSessionWrites();
      expect(ApiAuthMiddleware.webSessionPrefixes, contains('/api/sales'));
      expect(ApiAuthMiddleware.webWriteDeniedPrefixes, contains('/api/sales/held'));
    });

    test('افتراضياً (معطّل) رمز الويب لا يفتح /api/receipts', () async {
      final base = await serve(staticDir: webDir.path);
      final token = ApiSessionToken.mintWeb(1);
      final r = await http.post(Uri.parse('$base/api/receipts'),
          headers: {ApiSessionToken.headerName: token});
      // لا مسار ويب → يسقط إلى فحص Bearer.
      expect(r.statusCode, 401);
      expect(r.body, contains('Authorization'));
    });

    test('بعد التفعيل: رمز ويب صالح يمرّ فحص الجلسة على /api/sales/return', () async {
      ApiAuthMiddleware.enableWebSessionWrites();
      final base = await serve(staticDir: webDir.path);
      final token = ApiSessionToken.mintWeb(1);
      final r = await http.post(Uri.parse('$base/api/sales/return'),
          headers: {ApiSessionToken.headerName: token});
      expect(r.body, isNot(contains('Invalid or expired')));
      expect(r.body, isNot(contains('Origin not allowed')));
      expect(r.body, isNot(contains('Missing or invalid Authorization')));
    });

    test('بعد التفعيل: /api/sales/held يبقى مغلقاً لرمز الويب', () async {
      ApiAuthMiddleware.enableWebSessionWrites();
      final base = await serve(staticDir: webDir.path);
      final token = ApiSessionToken.mintWeb(1);
      for (final p in ['/api/sales/held', '/api/sales/held-items']) {
        final r = await http.post(Uri.parse('$base$p'),
            headers: {ApiSessionToken.headerName: token});
        expect(r.statusCode, 401, reason: p);
        expect(r.body, contains('Authorization'), reason: p);
      }
    });

    test('بعد التفعيل: رمز غير صالح → 401 جلسة ويب', () async {
      ApiAuthMiddleware.enableWebSessionWrites();
      final base = await serve(staticDir: webDir.path);
      final r = await http.post(Uri.parse('$base/api/receipts'),
          headers: {ApiSessionToken.headerName: 'garbage'});
      expect(r.statusCode, 401);
      expect(r.body, contains('Invalid or expired web session'));
    });

    test('disableWebSessionWrites يعيد الإغلاق', () {
      ApiAuthMiddleware.enableWebSessionWrites();
      expect(ApiAuthMiddleware.webSessionPrefixes, isNotEmpty);
      ApiAuthMiddleware.disableWebSessionWrites();
      expect(ApiAuthMiddleware.webSessionPrefixes, isEmpty);
    });
  });

  group('سياسة Origin', () {
    setUp(() {
      ApiAuthMiddleware.enableWebSessionWrites();
      WebOriginPolicy.configure(['https://erp.example.com/']);
    });

    Future<http.Response> post(String base, Map<String, String> h) {
      final token = ApiSessionToken.mintWeb(1);
      return http.post(Uri.parse('$base/api/receipts'),
          headers: {ApiSessionToken.headerName: token, ...h});
    }

    test('أصل غريب → 403', () async {
      final base = await serve(staticDir: webDir.path);
      final r = await post(base, {'origin': 'https://evil.example.org'});
      expect(r.statusCode, 403);
      expect(r.body, contains('Origin not allowed'));
    });

    test('أصل ضمن القائمة (يُطبَّع) يمرّ', () async {
      final base = await serve(staticDir: webDir.path);
      final r = await post(base, {'origin': 'https://ERP.example.com'});
      expect(r.statusCode, isNot(403));
      expect(r.body, isNot(contains('Origin not allowed')));
    });

    test('نفس الأصل (origin = host) يمرّ بلا قائمة', () async {
      WebOriginPolicy.configure(const []);
      final base = await serve(staticDir: webDir.path);
      final host = base.replaceFirst('http://', '');
      final r = await post(base, {'origin': base, 'host': host});
      expect(r.body, isNot(contains('Origin not allowed')));
    });

    test('أصل غريب مع قائمة فارغة → 403', () async {
      WebOriginPolicy.configure(const []);
      final base = await serve(staticDir: webDir.path);
      final r = await post(base, {'origin': 'https://erp.example.com'});
      expect(r.statusCode, 403);
    });
  });

  group('NetworkService.configureWebAccess', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      await NetworkService.instance.configureWebAccess(enabled: false);
      ApiAuthMiddleware.disableWebSessionWrites();
      WebOriginPolicy.configure(const []);
    });

    test('الافتراضي معطّل', () async {
      await NetworkService.instance.configureWebAccess(enabled: false);
      expect(NetworkService.instance.webAccessEnabled, isFalse);
      expect(NetworkService.instance.webAllowedOrigins, isEmpty);
      expect(NetworkService.instance.webStaticDir, isNull);
    });

    test('يُحفَظ ويُحمَّل ويُنظَّف الإدخال', () async {
      final ns = NetworkService.instance;
      await ns.configureWebAccess(
        enabled: true,
        allowedOrigins: [' https://a.example.com ', '', 'https://b.example.com'],
        staticDir: ' ${webDir.path} ',
      );
      expect(ns.webAccessEnabled, isTrue);
      expect(ns.webAllowedOrigins,
          ['https://a.example.com', 'https://b.example.com']);
      expect(ns.webStaticDir, webDir.path);
      expect(ns.resolveWebStaticDir(), webDir.path);

      // إعادة تحميل من SharedPreferences.
      await ns.configureWebAccess(enabled: false);
      expect(ns.webAccessEnabled, isFalse);
      await ns.configureWebAccess(
          enabled: true, allowedOrigins: ['https://a.example.com']);
      await ns.loadSettings();
      expect(ns.webAccessEnabled, isTrue);
      expect(ns.webAllowedOrigins, ['https://a.example.com']);
    });

    test('تطبيق التفعيل يفتح الكتابات ويضبط Origin، والتعطيل يغلقها', () async {
      final ns = NetworkService.instance;
      await ns.configureWebAccess(
        enabled: true,
        allowedOrigins: ['https://erp.example.com'],
      );
      ns.applyWebAccessForTests();
      expect(ApiAuthMiddleware.webSessionPrefixes, isNotEmpty);
      expect(WebOriginPolicy.allowedOrigins, {'https://erp.example.com'});

      await ns.configureWebAccess(enabled: false);
      ns.applyWebAccessForTests();
      expect(ApiAuthMiddleware.webSessionPrefixes, isEmpty);
      expect(WebOriginPolicy.allowedOrigins, isEmpty);
    });

    test('البوّابة: معطّل → /webdb و/api/web/* بـ404، وغيرها يمرّ', () async {
      final ns = NetworkService.instance;
      await ns.configureWebAccess(enabled: false);
      final base = await serve(
        staticDir: webDir.path,
        extra: ns.webGateMiddlewareForTests,
      );
      expect((await http.get(Uri.parse('$base/webdb'))).statusCode, 404);
      expect(
          (await http.post(Uri.parse('$base/api/web/session'))).statusCode, 404);
      // الملفات الثابتة وغيرها لا تتأثر بالبوّابة.
      expect((await http.get(Uri.parse('$base/'))).statusCode, 200);

      await ns.configureWebAccess(enabled: true);
      final base2 = await (() async {
        await server?.close(force: true);
        return serve(staticDir: webDir.path, extra: ns.webGateMiddlewareForTests);
      })();
      final enabled = await http.post(Uri.parse('$base2/api/web/session'));
      expect(enabled.body, isNot(contains('Web access disabled')));
    });
  });
}
