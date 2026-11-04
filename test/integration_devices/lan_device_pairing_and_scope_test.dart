// Integration review 2026-11-04 (docs/integration/2026-11-04-device-app-integration-review.md).
//
// The REAL LAN pipeline (ApiRateLimiter -> ApiAuthMiddleware -> ApiHandler
// router, in-memory SQLite host) served over a loopback socket, driven exactly
// as a phone / tablet / branch desktop drives it: pairing code -> device bearer
// -> session token -> routes allowed by the device KIND.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:picpos_erp/services/api/api_rate_limiter.dart';
import 'package:picpos_erp/services/api/client_address.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';

import '../helpers/lan_host_harness.dart';

const _fingerprint =
    'aa11bb22cc33dd44ee55ff6600778899aa11bb22cc33dd44ee55ff6600778899';

void main() {
  late LanHost host;
  late HostFixture fx;
  late String base;
  late DateTime now;
  final devices = <LanDevice>[];

  LanDevice newDevice(String id) {
    final d = LanDevice(host.overHttp(base), id, rolesFrom: host.db);
    devices.add(d);
    return d;
  }

  setUp(() async {
    now = DateTime.now();
    host = await LanHost.start(now: () => now);
    fx = await HostFixture.seed(host.db);
    base = await host.serve();
  });

  tearDown(() async {
    for (final d in devices) {
      await d.dispose();
    }
    devices.clear();
    await host.close();
  });

  group('pairing a new device with a one-time code', () {
    test(
      'a correct code pairs once; the same code cannot pair a second device',
      () async {
        final offer = await host.issue(kind: 'client', branchId: fx.branch1);
        expect(offer.code, matches(RegExp(r'^[A-HJ-NP-Z2-9]{8}$')));

        final first = await newDevice('tab-1').pair(offer.code);
        expect(first.status, 200, reason: '$first');
        expect(first.json['token'], isA<String>());
        expect(first.json['branchId'], fx.branch1);

        final replay = await newDevice('tab-2').pair(offer.code);
        expect(replay.status, 401, reason: '$replay');
        expect(await host.pairing.deviceById('tab-2'), isNull);
      },
    );

    test(
      'a wrong code is refused with 401 and does not burn the valid code',
      () async {
        final offer = await host.issue(kind: 'client', branchId: fx.branch1);
        final d = newDevice('tab-1');

        final wrong = await d.pair('ZZZZ2222');
        expect(wrong.status, 401);
        expect(wrong.json['error'], 'رمز الإقران غير صحيح أو منتهي');
        expect(d.deviceToken, isNull);

        // Lower-case input of the right code is accepted (codes are normalised).
        final right = await d.pair(offer.code.toLowerCase());
        expect(right.status, 200, reason: '$right');
      },
    );

    test('a code is refused after its 10-minute lifetime', () async {
      final offer = await host.issue(kind: 'client', branchId: fx.branch1);
      now = now.add(LanPairingService.pairingTtl + const Duration(seconds: 1));

      final expired = await newDevice('tab-1').pair(offer.code);
      expect(expired.status, 401);
      expect(await host.pairing.deviceById('tab-1'), isNull);
    });

    test(
      'a warehouse code only pairs a device that declares the warehouse kind',
      () async {
        final offer = await host.issue(
          kind: 'warehouse',
          branchId: fx.branch2,
          fingerprint: _fingerprint,
        );

        final asPos = await newDevice('wh-1').pair(offer.code, kind: 'pos');
        expect(asPos.status, 401);
        expect(asPos.json['error'], 'رمز الإقران لا يخصّ هذا النوع من الأجهزة');

        final asWarehouse = await newDevice(
          'wh-1b',
        ).pair(offer.code, kind: 'warehouse');
        expect(asWarehouse.status, 200, reason: '$asWarehouse');
        expect(
          (await host.pairing.deviceById('wh-1b'))!.deviceKind,
          'warehouse',
        );
      },
    );

    test('the sixth pairing attempt from one address within 10 minutes is 429, '
        'even with the right code', () async {
      final offer = await host.issue(kind: 'client', branchId: fx.branch1);
      final d = newDevice('tab-1');
      for (var i = 0; i < LanPairingService.maxAttemptsPerIp; i++) {
        expect((await d.pair('WRONG${i}AA')).status, 401);
      }
      final blocked = await d.pair(offer.code);
      expect(blocked.status, 429);

      // The window is rolling: after it passes the right code works again.
      now = now.add(
        LanPairingService.attemptWindow + const Duration(seconds: 1),
      );
      final fresh = await host.issue(kind: 'client', branchId: fx.branch1);
      expect((await d.pair(fresh.code)).status, 200);
    });

    test('INT-11: behind a configured trusted proxy the pairing budget is per '
        'real client, not one budget shared by everyone behind the proxy',
        () async {
      ClientAddress.configureTrustedProxies(['127.0.0.1']);
      addTearDown(() => ClientAddress.configureTrustedProxies(const []));
      final offer = await host.issue(kind: 'client', branchId: fx.branch1);
      Future<int> pairVia(String clientIp, String code, String deviceId) async =>
          (await http.post(
            Uri.parse('$base/api/pair'),
            headers: {
              'content-type': 'application/json',
              'x-forwarded-for': clientIp,
            },
            body: jsonEncode({
              'pairingCode': code,
              'deviceId': deviceId,
              'deviceName': deviceId,
            }),
          )).statusCode;

      for (var i = 0; i < LanPairingService.maxAttemptsPerIp; i++) {
        expect(await pairVia('10.0.0.66', 'WRONG${i}AA', 'guesser'), 401);
      }
      expect(await pairVia('10.0.0.66', offer.code, 'guesser'), 429);
      // A different shop device behind the same proxy still pairs.
      expect(await pairVia('10.0.0.7', offer.code, 'tab-ok'), 200);
    });
  });

  group('route policy by device kind (403 device_scope)', () {
    Future<LanDevice> paired(String id, String kind) async {
      final offer = switch (kind) {
        'warehouse' => await host.issue(
          kind: kind,
          branchId: fx.branch2,
          fingerprint: _fingerprint,
        ),
        'pos' => await host.issue(kind: kind, branchId: fx.branch2),
        'mirror' => await host.issue(kind: kind),
        _ => await host.issue(kind: kind, branchId: fx.branch1),
      };
      final d = newDevice(id);
      final r = await d.pair(offer.code, kind: kind == 'mirror' ? null : kind);
      expect(r.status, 200, reason: '$kind pairing: $r');
      return d;
    }

    const cases = <(String kind, String method, String path, bool denied)>[
      ('warehouse', 'GET', '/api/products', true),
      ('warehouse', 'GET', '/api/sync/pull?table=products', true),
      ('warehouse', 'GET', '/api/m1/wh/session', false),
      // INT-01: the credential-less display feeds do not open a hole in the
      // policy for a device that DOES present its bearer.
      ('warehouse', 'GET', '/api/menu', true),
      ('warehouse', 'GET', '/api/cfd/stream', true),
      ('pos', 'GET', '/api/m1/wh/session', true),
      ('pos', 'GET', '/api/mirror/context', true),
      ('pos', 'GET', '/api/products', false),
      ('mirror', 'POST', '/api/pos-terminals/register', true),
      ('mirror', 'GET', '/api/sales/held', true),
      ('mirror', 'GET', '/api/pos-terminals', false),
      ('client', 'GET', '/api/pos-terminals', false),
    ];

    for (final c in cases) {
      test(
        '${c.$1} ${c.$2} ${c.$3} -> ${c.$4 ? 'device_scope' : 'passes the policy'}',
        () async {
          final d = await paired('dev-${c.$1}', c.$1);
          final r = c.$2 == 'GET' ? await d.get(c.$3) : await d.post(c.$3, {});
          if (c.$4) {
            expect(r.status, 403, reason: '$r');
            expect(r.json['error'], 'device_scope');
          } else {
            expect(
              r.json['error'] == 'device_scope' && r.status == 403,
              isFalse,
              reason: '$r',
            );
          }
        },
      );
    }
  });

  group('device bearer + user session', () {
    Future<LanDevice> pairedClient() async {
      final offer = await host.issue(kind: 'client', branchId: fx.branch1);
      final d = newDevice('desk-2');
      expect((await d.pair(offer.code)).status, 200);
      return d;
    }

    const transactionalPull = '/api/sync/pull?table=sales_invoices';

    test('an expired or forged session token reads a transactional table as an '
        'anonymous caller (no rows, no watermark)', () async {
      final d = await pairedClient();
      expect((await d.login('admin', kHostAdminPw)).status, 200);

      final fresh = await d.get(transactionalPull);
      expect(fresh.status, 200);
      expect(fresh.json['serverTime'], isA<int>());

      final thirteenHoursAgo = DateTime.now()
          .subtract(const Duration(hours: 13))
          .millisecondsSinceEpoch;
      final realSession = d.session!;
      for (final bad in [
        ApiSessionToken.mint(1, nowMs: thirteenHoursAgo),
        '${realSession.substring(0, realSession.length - 2)}xx',
      ]) {
        d.session = bad;
        final r = await d.get(transactionalPull);
        expect(r.status, 200);
        expect(r.json['rows'], isEmpty);
        expect(r.json['serverTime'], isNull, reason: 'token: $bad');
      }
    });

    test('a request without the device bearer is 401; a revoked device is 401 '
        'device_revoked', () async {
      final d = await pairedClient();
      final noBearer = await d.transport(
        'GET',
        '/api/products',
        const {},
        null,
      );
      expect(noBearer.status, 401);

      await host.pairing.revoke('desk-2', actorUserId: 1);
      final revoked = await d.get('/api/products');
      expect(revoked.status, 401);
      expect(revoked.json['error'], 'device_revoked');
    });

    test(
      'the API rate limiter answers 429 with retry-after once a class budget '
      'is spent, without touching other classes',
      () async {
        final d = await pairedClient();
        final readClass = ApiRateLimiter.classifyPath('/api/products');
        final otherClass = ApiRateLimiter.classifyPath('/api/sales');
        expect(
          otherClass,
          isNot(readClass),
          reason: 'the isolation check needs two different classes',
        );
        final saved = ApiRateLimiter.limitFor(readClass);
        addTearDown(() => ApiRateLimiter.configureClass(readClass, saved));
        ApiRateLimiter.reset();
        ApiRateLimiter.configureClass(readClass, 3);

        for (var i = 0; i < 3; i++) {
          expect((await d.get('/api/products')).status, isNot(429));
        }
        final limited = await http.get(
          Uri.parse('$base/api/products'),
          headers: d.headers(),
        );
        expect(limited.statusCode, 429);
        expect(limited.headers['retry-after'], '60');
        expect(limited.headers['x-ratelimit-class'], readClass.name);
        expect((jsonDecode(limited.body) as Map)['error'], 'Too many requests');

        expect((await d.get('/api/sales')).status, isNot(429));
      },
    );
  });
}
