// م3-4 — مصادقة الويب في الخادم: رمز الجلسة (aud:'web' + sid + 12 ساعة)،
// التذكرة أحاديّة الاستعمال، وفحص Origin عبر ApiAuthMiddleware الحقيقي.
// يعمل على SQLite في الذاكرة (مستخدمون بتجزئة Argon2id حقيقية).

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_auth_middleware.dart';
import 'package:ural_erp/services/api/api_session_token.dart';
import 'package:ural_erp/services/api/api_user_context.dart';
import 'package:ural_erp/services/api/api_web_session_handler.dart';

void main() {
  const hour = 3600 * 1000;

  setUp(() {
    ApiSessionToken.deriveKey('web-seed');
    ApiSessionToken.clearRevokedForTesting();
    WebWsTicketStore.clear();
    WebOriginPolicy.configure(const []);
    ApiAuthMiddleware.setToken('bearer-xyz');
    ApiAuthMiddleware.webSessionPrefixes = <String>[];
  });

  tearDown(() {
    ApiSessionToken.clearKey();
    ApiAuthMiddleware.clearToken();
    WebWsTicketStore.clear();
    WebOriginPolicy.configure(const []);
    ApiAuthMiddleware.webSessionPrefixes = <String>[];
  });

  group('mintWeb / verifyWeb', () {
    test('رمز صالح يرجع uid وsid وانتهاءً بعد 12 ساعة بالضبط', () {
      final token = ApiSessionToken.mintWeb(7, nowMs: 1000);
      final claims = ApiSessionToken.verifyWeb(token, nowMs: 1000);
      expect(claims, isNotNull);
      expect(claims!.userId, 7);
      expect(claims.sid, isNotEmpty);
      expect(claims.expiresAtMs, 1000 + 12 * hour);
      expect(ApiSessionToken.webTtlMs, 12 * hour);
    });

    test('ينتهي عند 12 ساعة: قبلها صالح وعندها مرفوض', () {
      final token = ApiSessionToken.mintWeb(7, nowMs: 0);
      expect(ApiSessionToken.verifyWeb(token, nowMs: 12 * hour - 1), isNotNull);
      expect(ApiSessionToken.verifyWeb(token, nowMs: 12 * hour), isNull);
    });

    test('إلغاء sid يبطل الرمز دون غيره', () {
      final a = ApiSessionToken.mintWeb(7);
      final b = ApiSessionToken.mintWeb(7);
      final sidA = ApiSessionToken.verifyWeb(a)!.sid;
      expect(sidA, isNot(ApiSessionToken.verifyWeb(b)!.sid));
      ApiSessionToken.revokeSid(sidA);
      expect(ApiSessionToken.verifyWeb(a), isNull);
      expect(ApiSessionToken.verifyWeb(b), isNotNull);
    });

    test('توقيع مزوَّر أو رمز تالف أو null يفشل', () {
      final token = ApiSessionToken.mintWeb(7);
      expect(ApiSessionToken.verifyWeb('${token}x'), isNull);
      expect(ApiSessionToken.verifyWeb('garbage'), isNull);
      expect(ApiSessionToken.verifyWeb(null), isNull);
      ApiSessionToken.clearKey();
      expect(ApiSessionToken.verifyWeb(token), isNull);
    });

    test('الفصل بين الرمزين: رمز الجهاز لا يصلح للويب والعكس', () {
      final device = ApiSessionToken.mint(7);
      final web = ApiSessionToken.mintWeb(7);
      expect(ApiSessionToken.verifyWeb(device), isNull);
      expect(ApiSessionToken.verify(web), isNull);
      // السلوك القائم لرموز الجهاز لم يتغيّر (30 يوماً).
      expect(ApiSessionToken.verify(device), 7);
    });
  });

  group('التذكرة', () {
    WebSessionClaims claims() =>
        ApiSessionToken.verifyWeb(ApiSessionToken.mintWeb(5))!;

    test('تُستعمل مرة واحدة فقط', () {
      final t = WebWsTicketStore.issue(claims());
      final first = WebWsTicketStore.consume(t);
      expect(first, isNotNull);
      expect(first!.userId, 5);
      expect(WebWsTicketStore.consume(t), isNull);
    });

    test('تنتهي خلال 30 ثانية', () {
      final t = WebWsTicketStore.issue(claims(), nowMs: 0);
      expect(WebWsTicketStore.consume(t, nowMs: 30 * 1000), isNull);
      final t2 = WebWsTicketStore.issue(claims(), nowMs: 0);
      expect(WebWsTicketStore.consume(t2, nowMs: 29 * 1000), isNotNull);
    });

    test('مجهولة/فارغة/جلستها مُلغاة ترفض', () {
      expect(WebWsTicketStore.consume('nope'), isNull);
      expect(WebWsTicketStore.consume(''), isNull);
      expect(WebWsTicketStore.consume(null), isNull);
      final c = claims();
      final t = WebWsTicketStore.issue(c);
      ApiSessionToken.revokeSid(c.sid);
      expect(WebWsTicketStore.consume(t), isNull);
    });

    test('تذاكر مختلفة لكل طلب', () {
      final c = claims();
      expect(WebWsTicketStore.issue(c), isNot(WebWsTicketStore.issue(c)));
    });
  });

  group('Origin', () {
    shelf.Request req(String path, {Map<String, String>? headers}) =>
        shelf.Request('POST', Uri.parse('http://erp.local:8080$path'),
            headers: {'host': 'erp.local:8080', ...?headers});

    test('فارغة = نفس الأصل فقط', () {
      expect(WebOriginPolicy.isAllowed(req('/x')), isTrue); // بلا Origin
      expect(
        WebOriginPolicy.isAllowed(
            req('/x', headers: {'origin': 'http://erp.local:8080'})),
        isTrue,
      );
      expect(
        WebOriginPolicy.isAllowed(
            req('/x', headers: {'origin': 'https://evil.example'})),
        isFalse,
      );
      expect(
        WebOriginPolicy.isAllowed(req('/x', headers: {'origin': 'null'})),
        isFalse,
      );
    });

    test('القائمة المضبوطة تُضيف أصولاً مسموحة (مطابقة حرفية)', () {
      WebOriginPolicy.configure(['https://erp.example.com/']);
      expect(
        WebOriginPolicy.isAllowed(
            req('/x', headers: {'origin': 'https://erp.example.com'})),
        isTrue,
      );
      expect(
        WebOriginPolicy.isAllowed(
            req('/x', headers: {'origin': 'https://erp.example.com.evil.io'})),
        isFalse,
      );
    });

    group('عبر ApiAuthMiddleware', () {
      late shelf.Handler handler;
      late Map<String, Object?> seen;

      setUp(() {
        seen = {};
        handler = ApiAuthMiddleware.createMiddleware()((r) {
          seen['uid'] = r.context[ApiUserCtx.userIdKey];
          return shelf.Response.ok('inner');
        });
      });

      test('Origin غريب يُرفض 403 على /api/web/session و/webdb و/ws-ticket',
          () async {
        for (final path in [
          '/api/web/session',
          '/api/web/ws-ticket',
          '/webdb',
        ]) {
          final r = await handler(
              req(path, headers: {'origin': 'https://evil.example'}));
          expect(r.statusCode, 403, reason: path);
        }
      });

      test('نفس الأصل يمرّ إلى /api/web/session و/webdb بلا bearer', () async {
        for (final path in ['/api/web/session', '/webdb']) {
          final r = await handler(
              req(path, headers: {'origin': 'http://erp.local:8080'}));
          expect(r.statusCode, 200, reason: path);
        }
      });

      test('/api/web/ws-ticket يتطلب رمز ويب (لا bearer الجهاز)', () async {
        var r = await handler(req('/api/web/ws-ticket'));
        expect(r.statusCode, 401);
        r = await handler(req('/api/web/ws-ticket',
            headers: {'authorization': 'Bearer bearer-xyz'}));
        expect(r.statusCode, 401);
        // رمز جهاز ليس رمز ويب.
        r = await handler(req('/api/web/ws-ticket', headers: {
          ApiSessionToken.headerName: ApiSessionToken.mint(3),
        }));
        expect(r.statusCode, 401);

        r = await handler(req('/api/web/ws-ticket', headers: {
          ApiSessionToken.headerName: ApiSessionToken.mintWeb(3),
        }));
        expect(r.statusCode, 200);
        expect(seen['uid'], 3);
      });

      test('رمز ويب لا يفتح مسارات /api/* الأخرى ما لم تُسجَّل بادئتها',
          () async {
        final web = ApiSessionToken.mintWeb(3);
        var r = await handler(
            req('/api/products', headers: {ApiSessionToken.headerName: web}));
        expect(r.statusCode, 401); // لا bearer
        ApiAuthMiddleware.webSessionPrefixes = ['/api/products'];
        r = await handler(
            req('/api/products', headers: {ApiSessionToken.headerName: web}));
        expect(r.statusCode, 200);
        expect(seen['uid'], 3);
        // وAPI غير مسجَّل يبقى مغلقاً.
        r = await handler(
            req('/api/sales', headers: {ApiSessionToken.headerName: web}));
        expect(r.statusCode, 401);
      });
    });
  });

  group('POST /api/web/session و/api/web/ws-ticket', () {
    late AppDatabase db;
    late ApiWebSessionHandler handler;

    setUp(() async {
      db = AppDatabase.forTesting();
      handler = ApiWebSessionHandler(db);
      final roleId = await db.into(db.roles).insert(
            RolesCompanion.insert(
                name: 'محاسب', isSystemRole: const Value(false)),
          );
      await db.createUser(
        username: 'webuser',
        password: 'pw-web-1',
        displayName: 'Web User',
        roleId: roleId,
      );
    });

    tearDown(() => db.close());

    Future<shelf.Response> login(Map<String, dynamic> body) =>
        handler.login(shelf.Request(
          'POST',
          Uri.parse('http://localhost/api/web/session'),
          body: jsonEncode(body),
        ));

    test('اعتماد صحيح يرجع token وuserId والدور والأكواد وisPostgres', () async {
      final r = await login({'username': 'webuser', 'password': 'pw-web-1'});
      expect(r.statusCode, 200);
      final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
      final claims = ApiSessionToken.verifyWeb(body['token'] as String);
      expect(claims, isNotNull);
      expect(claims!.userId, body['userId']);
      expect(body['roleName'], 'محاسب');
      expect(body['permissionCodes'], isA<List>());
      expect(body['expiresInMs'], 12 * hour);
      expect(body['isPostgres'], isFalse);
    });

    test('كلمة مرور خاطئة 401 بلا token، وناقص 400', () async {
      var r = await login({'username': 'webuser', 'password': 'nope'});
      expect(r.statusCode, 401);
      expect(jsonDecode(await r.readAsString()), isNot(contains('token')));
      r = await login({'username': 'webuser'});
      expect(r.statusCode, 400);
    });

    test('ws-ticket بلا جلسة في السياق 401، ومعها تذكرة تُستهلك مرة', () async {
      var r = await handler.issueTicket(shelf.Request(
          'POST', Uri.parse('http://localhost/api/web/ws-ticket')));
      expect(r.statusCode, 401);

      final claims = ApiSessionToken.verifyWeb(ApiSessionToken.mintWeb(9))!;
      r = await handler.issueTicket(shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/web/ws-ticket'),
        context: {ApiWebCtx.claimsKey: claims},
      ));
      expect(r.statusCode, 200);
      final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
      expect(body['expiresInMs'], 30000);
      final ticket = body['ticket'] as String;
      expect(WebWsTicketStore.consume(ticket)?.userId, 9);
      expect(WebWsTicketStore.consume(ticket), isNull);
    });
  });
}
