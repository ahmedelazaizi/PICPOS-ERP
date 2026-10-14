// تحصين أمني: S-04 (admin الافتراضي)، 5.3 (/ws)، 8.1 (تسريب الأخطاء)،
// 2.2 (الإعفاء بالبادئة). كلها بلا شبكة (shelf Handler مباشر + SQLite في الذاكرة).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_auth_middleware.dart';
import 'package:ural_erp/services/api/api_errors.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_web_session_handler.dart';
import 'package:ural_erp/services/api/path_prefix_match.dart';
import 'package:ural_erp/services/api/ws_connection_guard.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeWs implements WebSocketChannel {
  int? cc;
  @override
  int? get closeCode => cc;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// الاسم يطابق ما يعتمد عليه ApiErrors.isInternal (نوع تشغيل drift/sqlite).
class SqliteException implements Exception {
  @override
  String toString() =>
      'SqliteException(1): no such column: secret_col, SQL logic error '
      '(code 1), SELECT secret_col FROM users';
}

void main() {
  group('2.2 مطابقة البادئة بحدّ فاصل', () {
    test('تطابق تامة أو يتبعها /', () {
      expect(matchesPathPrefix('/ws', '/ws'), isTrue);
      expect(matchesPathPrefix('/ws/x', '/ws'), isTrue);
      expect(matchesPathPrefix('/wsfoo', '/ws'), isFalse);
      expect(matchesPathPrefix('/menu-admin', '/menu'), isFalse);
      expect(matchesPathPrefix('/api/healthx', '/api/health'), isFalse);
      expect(matchesPathPrefix('/api/table-billing', '/api/table-bill'), isFalse);
      expect(matchesPathPrefix('/api/table-bill/tok/add', '/api/table-bill'),
          isTrue);
    });

    test('الميدلوير: /api/healthx لم يعد معفى بينما /api/health معفى', () async {
      ApiAuthMiddleware.setToken('tok-123');
      addTearDown(ApiAuthMiddleware.clearToken);
      final h = const shelf.Pipeline()
          .addMiddleware(ApiAuthMiddleware.createMiddleware())
          .addHandler((_) => shelf.Response.ok('inner'));
      final ok = await h(shelf.Request('GET', Uri.parse('http://x/api/health')));
      expect(ok.statusCode, 200);
      final bad =
          await h(shelf.Request('GET', Uri.parse('http://x/api/healthx')));
      expect(bad.statusCode, 401);
      final bad2 = await h(
          shelf.Request('GET', Uri.parse('http://x/api/pairing-secret')));
      expect(bad2.statusCode, 401);
    });
  });

  group('8.1 ApiErrors', () {
    test('خطأ بنية تحتية يُحجب ويحمل request_id', () async {
      final r = ApiErrors.fail(SqliteException(), 'Failed to x',
          st: StackTrace.current);
      expect(r.statusCode, 500);
      final body = await r.readAsString();
      final j = jsonDecode(body) as Map<String, dynamic>;
      expect(j['error'], 'internal_error');
      expect(j['request_id'], isA<String>());
      expect(body, isNot(contains('secret_col')));
      expect(body, isNot(contains('SELECT')));
    });

    test('رسالة الأعمال تبقى (OfflineSyncWorker يعتمد على نصها) بلا stack',
        () async {
      final r = ApiErrors.fail(
          Exception('Validation Error: item missing productId'),
          'Failed to process sale',
          st: StackTrace.current);
      final j = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
      expect(j['error'], contains('Validation Error: item missing productId'));
      expect(j['error'], isNot(contains('STACK')));
      expect(j['error'], isNot(contains('#0')));
      expect(
          ApiErrors.isInternal(StateError('treasury account not found on server')),
          isFalse);
    });

    test('statusCode يُحفظ', () {
      expect(ApiErrors.fail(SqliteException(), 'p', statusCode: 400).statusCode,
          400);
    });

    test('failJson يحفظ success:false ويحجب الداخلي', () async {
      final r = ApiErrors.failJson(SqliteException());
      final j = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
      expect(j['success'], false);
      expect(j['error'], 'internal_error');
    });

    test('الميدلوير يلتقط الاستثناء غير المعالَج برد عام', () async {
      final h = const shelf.Pipeline()
          .addMiddleware(ApiErrors.middleware())
          .addHandler((_) => throw StateError('C:\\secret\\path.dart boom'));
      final r = await h(shelf.Request('GET', Uri.parse('http://x/api/any')));
      expect(r.statusCode, 500);
      final body = await r.readAsString();
      final responseJson = jsonDecode(body) as Map<String, dynamic>;
      expect(responseJson['error'], 'internal_error');
      expect(responseJson['request_id'], isNotEmpty);
      expect(body, isNot(contains('secret')));
    });
  });

  group('5.3 WsConnectionGuard', () {
    setUp(() {
      WsConnectionGuard.resetForTest();
      WsConnectionGuard.maxTotal = 5;
      WsConnectionGuard.maxPerIp = 2;
      WebOriginPolicy.configure(const []);
      ApiAuthMiddleware.setToken('tok-123');
    });
    tearDown(() {
      WsConnectionGuard.resetForTest();
      WsConnectionGuard.maxTotal = 50;
      WsConnectionGuard.maxPerIp = 10;
      ApiAuthMiddleware.clearToken();
    });

    shelf.Request req(
            {Map<String, String> headers = const {}, String q = ''}) =>
        shelf.Request('GET', Uri.parse('http://host:1/ws$q'), headers: {
          'host': 'host:1',
          ...headers,
        });

    test('عميل أصيل بلا رمز ولا Origin يُقبل (سلوك قائم)', () async {
      expect(await WsConnectionGuard.check(req()), isNull);
    });

    test('Origin غريب يُرفض 403، ونفس الأصل يُقبل', () async {
      final bad = await WsConnectionGuard.check(
          req(headers: {'origin': 'https://evil.example'}));
      expect(bad?.statusCode, 403);
      expect(
          await WsConnectionGuard.check(
              req(headers: {'origin': 'http://host:1'})),
          isNull);
    });

    test('رمز مقدَّم خاطئ ⇒ 401، وصحيح ⇒ يُقبل', () async {
      final bad = await WsConnectionGuard.check(
          req(headers: {'authorization': 'Bearer nope'}));
      expect(bad?.statusCode, 401);
      expect(await WsConnectionGuard.check(req(q: '?token=nope')),
          isA<shelf.Response>());
      expect(
          await WsConnectionGuard.check(
              req(headers: {'authorization': 'Bearer tok-123'})),
          isNull);
      expect(await WsConnectionGuard.check(req(q: '?token=tok-123')), isNull);
    });

    test('حدّ العنوان ثم الحدّ الكلي، والاتصال المغلق يُقلَّم', () async {
      final a = _FakeWs(), b = _FakeWs();
      WsConnectionGuard.register(a, req());
      WsConnectionGuard.register(b, req());
      final third = await WsConnectionGuard.check(req());
      expect(third?.statusCode, 429);

      a.cc = 1000; // أُغلق ⇒ يتحرر المقعد
      expect(await WsConnectionGuard.check(req()), isNull);

      WsConnectionGuard.unregister(b);
      WsConnectionGuard.maxPerIp = 100;
      for (var i = 0; i < 5; i++) {
        WsConnectionGuard.register(_FakeWs(), req());
      }
      expect((await WsConnectionGuard.check(req()))?.statusCode, 429);
      expect(WsConnectionGuard.activeCount, 5);
    });
  });

  group('S-04 إعادة إنشاء admin عبر API', () {
    test('admin المُعاد إنشاؤه يُجبَر على تغيير كلمة المرور', () async {
      ApiAuthMiddleware.setToken('bearer-xyz');
      final db = AppDatabase.forTesting();
      addTearDown(() async {
        ApiAuthMiddleware.clearToken();
        await db.close();
      });
      await (db.delete(db.users)..where((u) => u.username.equals('admin')))
          .go();
      expect(
          await (db.select(db.users)..where((u) => u.username.equals('admin')))
              .get(),
          isEmpty);

      final h = const shelf.Pipeline()
          .addMiddleware(ApiAuthMiddleware.createMiddleware())
          .addHandler(ApiHandler(db).buildRouter().call);
      await h(shelf.Request('GET', Uri.parse('http://localhost/api/users'),
          headers: {'authorization': 'Bearer bearer-xyz'}));

      final admin = await (db.select(db.users)
            ..where((u) => u.username.equals('admin')))
          .getSingleOrNull();
      expect(admin, isNotNull, reason: 'المسار الاحتياطي يعيد إنشاءه');
      expect(admin!.forcePasswordChange, isTrue);
    });
  });
}
