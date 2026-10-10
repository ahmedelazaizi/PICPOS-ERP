/// Week-10 Unit Tests — ApiRateLimiter
///
/// 8 tests that verify the fixed-window rate-limiter that protects the
/// embedded Shelf HTTP server from abuse:
///
///   • Requests within the limit are allowed (200)
///   • The (limit + 1)-th request returns 429
///   • 429 response carries correct headers (Retry-After, X-RateLimit-*)
///   • Exempt paths (health, ws, cfd, menu) bypass the limiter
///   • Window reset clears the counter so requests are allowed again
///   • Different IPs have independent buckets
///   • isLimited() helper reports correctly
///   • configure() changes limit and window for the shared state
library;

import 'dart:io' show HttpConnectionInfo, InternetAddress;

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:ural_erp/services/api/api_rate_limiter.dart';
import 'package:ural_erp/services/api/client_address.dart';

/// A dummy handler that always returns 200 OK.
Response _ok(Request _) => Response.ok('ok');

class _ConnInfo implements HttpConnectionInfo {
  _ConnInfo(String ip) : remoteAddress = InternetAddress(ip);

  @override
  final InternetAddress remoteAddress;

  @override
  int get remotePort => 40000;

  @override
  int get localPort => 8080;
}

/// Build a fake request for [path] coming from the real connection [ip].
/// [headers] carry client-controlled values (XFF etc.) the limiter must ignore.
Request _req(String path,
    {String ip = '10.0.0.1', Map<String, String> headers = const {}}) {
  return Request(
    'GET',
    Uri.parse('http://localhost$path'),
    headers: headers,
    context: {'shelf.io.connection_info': _ConnInfo(ip)},
  );
}

void main() {
  setUp(() {
    // Each test starts with a clean slate and the default limit (120/60s)
    ApiRateLimiter.reset();
    ApiRateLimiter.configure(limit: 5, window: const Duration(seconds: 60));
  });

  tearDown(ApiRateLimiter.reset);

  // ── Basic allow / deny ───────────────────────────────────────────────────

  test('requests within the limit are forwarded (200)', () async {
    final mw = ApiRateLimiter.createMiddleware();
    final handler = mw(_ok);

    for (var i = 0; i < 5; i++) {
      final resp = await handler(_req('/api/products'));
      expect(resp.statusCode, 200,
          reason: 'request #${i + 1} must be allowed');
    }
  });

  test('the (limit + 1)-th request is rejected with 429', () async {
    final mw = ApiRateLimiter.createMiddleware();
    final handler = mw(_ok);

    for (var i = 0; i < 5; i++) {
      await handler(_req('/api/products'));
    }

    final blocked = await handler(_req('/api/products'));
    expect(blocked.statusCode, 429);
  });

  test('429 response body contains "Too many requests" error field', () async {
    final mw = ApiRateLimiter.createMiddleware();
    final handler = mw(_ok);
    for (var i = 0; i < 6; i++) {
      await handler(_req('/api/products'));
    }
    final blocked = await handler(_req('/api/products'));
    final body = await blocked.readAsString();
    expect(body, contains('Too many requests'));
  });

  test('429 response includes Retry-After and X-RateLimit-Limit headers',
      () async {
    final mw = ApiRateLimiter.createMiddleware();
    final handler = mw(_ok);
    for (var i = 0; i < 6; i++) {
      await handler(_req('/api/products'));
    }
    final blocked = await handler(_req('/api/products'));
    expect(blocked.headers['retry-after'], isNotNull);
    expect(blocked.headers['x-ratelimit-limit'], '5');
  });

  // ── Exempt paths ─────────────────────────────────────────────────────────

  test('health endpoint bypasses rate limiter even when bucket is full',
      () async {
    final mw = ApiRateLimiter.createMiddleware();
    final handler = mw(_ok);

    // Exhaust the bucket for this IP
    for (var i = 0; i < 10; i++) {
      await handler(_req('/api/products'));
    }

    // Health check must still pass
    final health = await handler(_req('/api/health'));
    expect(health.statusCode, 200);
  });

  test('WebSocket path /ws bypasses rate limiter', () async {
    final mw = ApiRateLimiter.createMiddleware();
    final handler = mw(_ok);
    for (var i = 0; i < 10; i++) {
      await handler(_req('/api/sales'));
    }
    final wsResp = await handler(_req('/ws'));
    expect(wsResp.statusCode, 200);
  });

  // ── IP isolation ─────────────────────────────────────────────────────────

  test('different IPs have independent buckets', () async {
    final mw = ApiRateLimiter.createMiddleware();
    final handler = mw(_ok);

    // Exhaust bucket for IP A
    for (var i = 0; i < 6; i++) {
      await handler(_req('/api/products', ip: '10.0.0.1'));
    }
    final blockedA = await handler(_req('/api/products', ip: '10.0.0.1'));
    expect(blockedA.statusCode, 429, reason: 'IP A should be rate-limited');

    // IP B still has a full budget
    final allowedB = await handler(_req('/api/products', ip: '10.0.0.2'));
    expect(allowedB.statusCode, 200, reason: 'IP B must not be affected');
  });

  // ── isLimited helper ─────────────────────────────────────────────────────

  test('isLimited() returns true after bucket is exhausted', () async {
    final mw = ApiRateLimiter.createMiddleware();
    final handler = mw(_ok);

    expect(ApiRateLimiter.isLimited('10.0.0.5'), isFalse,
        reason: 'should not be limited before any requests');

    for (var i = 0; i < 6; i++) {
      await handler(_req('/api/products', ip: '10.0.0.5'));
    }

    expect(ApiRateLimiter.isLimited('10.0.0.5'), isTrue,
        reason: 'should be limited after exceeding quota');
  });

  // ─── Feature 011 — per-endpoint classes ────────────────────────────────

  group('Per-endpoint classification (Feature 011)', () {
    test('classifyPath maps known critical/telemetry/read paths', () {
      // Critical writes — sales, parties, journals, etc.
      expect(ApiRateLimiter.classifyPath('/api/sales'),
          RateLimitClass.critical);
      expect(ApiRateLimiter.classifyPath('/api/sales/123'),
          RateLimitClass.critical);
      expect(ApiRateLimiter.classifyPath('/api/parties'),
          RateLimitClass.critical);
      expect(ApiRateLimiter.classifyPath('/api/journals'),
          RateLimitClass.critical);
      expect(ApiRateLimiter.classifyPath('/api/purchases/return'),
          RateLimitClass.critical);
      expect(ApiRateLimiter.classifyPath('/api/safes/transaction'),
          RateLimitClass.critical);

      // Telemetry — activity logs (the high-volume offender)
      expect(ApiRateLimiter.classifyPath('/api/activity-logs'),
          RateLimitClass.telemetry);
      expect(ApiRateLimiter.classifyPath('/api/activity-logs/push'),
          RateLimitClass.telemetry);

      // Reads
      expect(ApiRateLimiter.classifyPath('/api/products'),
          RateLimitClass.read);
      expect(ApiRateLimiter.classifyPath('/api/sync/pull'),
          RateLimitClass.read);
      expect(ApiRateLimiter.classifyPath('/api/branches'),
          RateLimitClass.read);
    });

    test('unmapped path falls back to defaultClass', () {
      expect(ApiRateLimiter.classifyPath('/api/something-new-not-yet-mapped'),
          RateLimitClass.defaultClass);
    });

    test('longer prefix wins over shorter prefix', () {
      // `/api/safes/transaction` (critical) must beat `/api/safes` (read).
      // Without longest-first ordering this would silently misclassify
      // safe transactions as cheap reads.
      expect(ApiRateLimiter.classifyPath('/api/safes/transaction'),
          RateLimitClass.critical);
      expect(ApiRateLimiter.classifyPath('/api/safes'), RateLimitClass.read);
      expect(ApiRateLimiter.classifyPath('/api/sales/return'),
          RateLimitClass.critical);
      expect(ApiRateLimiter.classifyPath('/api/sales'),
          RateLimitClass.critical);
    });

    test('flooding telemetry does not block critical writes (FEATURE 011 CORE)',
        () async {
      // Real-world bug we're fixing: the user's mirror flooded the
      // global bucket with activity_logs, then sales/purchases/parties
      // from the SAME IP got 429'd. With per-class buckets, the critical
      // class still has its full budget regardless of telemetry traffic.
      ApiRateLimiter.configureClass(RateLimitClass.telemetry, 2);
      ApiRateLimiter.configureClass(RateLimitClass.critical, 5);

      final mw = ApiRateLimiter.createMiddleware();
      final handler = mw(_ok);

      // Exhaust telemetry
      for (var i = 0; i < 3; i++) {
        await handler(_req('/api/activity-logs/push'));
      }
      final telemetryBlocked = await handler(_req('/api/activity-logs/push'));
      expect(telemetryBlocked.statusCode, 429,
          reason: 'telemetry should be limited after 2 reqs (limit=2)');

      // Critical writes from the SAME IP still work — independent bucket
      for (var i = 0; i < 5; i++) {
        final resp = await handler(_req('/api/sales'));
        expect(resp.statusCode, 200,
            reason: 'critical write #${i + 1} must succeed despite '
                'telemetry being throttled');
      }
    });

    test('429 response carries x-ratelimit-class header naming the class',
        () async {
      ApiRateLimiter.configureClass(RateLimitClass.critical, 2);
      final mw = ApiRateLimiter.createMiddleware();
      final handler = mw(_ok);

      for (var i = 0; i < 2; i++) {
        await handler(_req('/api/sales'));
      }
      final blocked = await handler(_req('/api/sales'));
      expect(blocked.statusCode, 429);
      expect(blocked.headers['x-ratelimit-class'], 'critical');
    });

    test('configureClass updates only the requested class', () {
      ApiRateLimiter.configureClass(RateLimitClass.telemetry, 999);
      expect(ApiRateLimiter.limitFor(RateLimitClass.telemetry), 999);
      // Other classes still hold whatever configure(limit:5) set them to.
      expect(ApiRateLimiter.limitFor(RateLimitClass.critical), 5);
    });
  });

  // ── بند الأمن 1/د: عنوان الاتصال الفعلي لا ترويسات العميل ─────────────────
  group('client address (spoof-resistant)', () {
    tearDown(() => ClientAddress.configureTrustedProxies(const []));

    test('XFF / X-Real-IP / Host المزوَّرة لا تُنتج سطلاً جديداً', () async {
      final handler = ApiRateLimiter.createMiddleware()(_ok);
      for (var i = 0; i < 5; i++) {
        final r = await handler(_req('/api/products', ip: '10.0.0.9', headers: {
          'x-forwarded-for': '1.1.1.$i',
          'x-real-ip': '2.2.2.$i',
          'host': 'forged$i.example',
        }));
        expect(r.statusCode, 200);
      }
      // السادس بقيمٍ مزوَّرة جديدة ما زال من نفس الاتصال ⇒ 429.
      final blocked = await handler(_req('/api/products', ip: '10.0.0.9',
          headers: {'x-forwarded-for': '9.9.9.9'}));
      expect(blocked.statusCode, 429);
      expect(ApiRateLimiter.trackedIps, 1);
    });

    test('وكيل موثوق مضبوط صراحةً: يُؤخذ عنوان العميل من XFF', () async {
      ClientAddress.configureTrustedProxies(['10.0.0.2']);
      final handler = ApiRateLimiter.createMiddleware()(_ok);
      for (var i = 0; i < 5; i++) {
        await handler(_req('/api/products',
            ip: '10.0.0.2', headers: {'x-forwarded-for': '203.0.113.7'}));
      }
      final blocked = await handler(_req('/api/products',
          ip: '10.0.0.2', headers: {'x-forwarded-for': '203.0.113.7'}));
      expect(blocked.statusCode, 429);
      // عميلٌ آخر خلف نفس الوكيل لا يتأثّر.
      final other = await handler(_req('/api/products',
          ip: '10.0.0.2', headers: {'x-forwarded-for': '203.0.113.8'}));
      expect(other.statusCode, 200);
    });

    test('مع وكيلٍ موثوق: XFF المزوَّر من اتصال غير موثوق يُهمَل', () {
      ClientAddress.configureTrustedProxies(['10.0.0.2']);
      final r = _req('/x', ip: '10.0.0.77',
          headers: {'x-forwarded-for': '1.2.3.4'});
      expect(ClientAddress.of(r), '10.0.0.77');
    });

    test('تتبّع العناوين محدود بسقف ويُنظَّف', () async {
      final handler = ApiRateLimiter.createMiddleware()(_ok);
      for (var i = 0; i < ApiRateLimiter.maxTrackedIps + 300; i++) {
        await handler(_req('/api/products', ip: '10.${i >> 16}.${(i >> 8) & 255}.${i & 255}'));
      }
      expect(ApiRateLimiter.trackedIps, lessThanOrEqualTo(ApiRateLimiter.maxTrackedIps));
    });
  });
}
