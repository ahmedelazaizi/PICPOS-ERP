import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_api_client/testing.dart';
import 'package:test/test.dart';

void main() {
  group('canonicalJson', () {
    test('sorts keys recursively, no whitespace, UTF-8 kept', () {
      final v = {
        'b': 1,
        'a': {'z': true, 'y': null, 'x': ['ص', 2]},
        'A': 'الصندوق',
      };
      expect(canonicalJson(v), '{"A":"الصندوق","a":{"x":["ص",2],"y":null,"z":true},"b":1}');
    });

    test('key order of the input does not matter', () {
      expect(canonicalJson({'x': 1, 'y': 2}), canonicalJson({'y': 2, 'x': 1}));
    });

    test('keys sort by UTF-16 code units (RFC 8785)', () {
      expect(canonicalJson({'é': 1, 'z': 2, 'Z': 3, '1': 4}), '{"1":4,"Z":3,"z":2,"é":1}');
    });

    test('escapes quotes and control characters', () {
      expect(canonicalJson({'k': 'a"b\n'}), r'{"k":"a\"b\n"}');
    });

    test('DateTime becomes ISO-8601 UTC', () {
      final local = DateTime.utc(2026, 2, 1, 8, 12, 3).toLocal();
      expect(canonicalJson({'asOf': local}), '{"asOf":"2026-02-01T08:12:03.000Z"}');
    });

    test('rejects doubles (amounts must be decimal strings)', () {
      expect(() => canonicalJson({'amount': 1.5}), throwsA(isA<CanonicalJsonException>()));
    });

    test('rejects non-string keys', () {
      expect(() => canonicalJson({1: 'x'}), throwsA(isA<CanonicalJsonException>()));
    });
  });

  group('Ed25519 PayloadVerifier', () {
    late SimpleKeyPair pair;
    late PayloadVerifier verifier;
    final payload = {
      'currency': 'JOD',
      'decimals': 3,
      'rows': [
        {'accountCode': '1101', 'name': 'الصندوق', 'debit': '1250.500', 'credit': '300.000'},
      ],
      'balanced': true,
    };

    setUp(() async {
      pair = await Ed25519().newKeyPair();
      final pub = await pair.extractPublicKey();
      verifier = PayloadVerifier.fromBase64(base64.encode(pub.bytes));
    });

    test('accepts a desktop signature over the canonical payload', () async {
      final sig = await signPayloadForTest(payload, pair);
      expect(sig, startsWith('ed25519:'));
      expect(await verifier.verify(payload, sig), isTrue);
    });

    test('a re-ordered but equal payload still verifies', () async {
      final sig = await signPayloadForTest(payload, pair);
      final reordered = jsonDecode(jsonEncode({'balanced': true, ...payload}));
      expect(await verifier.verify(reordered, sig), isTrue);
    });

    test('a changed figure fails', () async {
      final sig = await signPayloadForTest(payload, pair);
      final tampered = jsonDecode(jsonEncode(payload)) as Map<String, Object?>;
      ((tampered['rows'] as List).first as Map)['debit'] = '9250.500';
      expect(await verifier.verify(tampered, sig), isFalse);
    });

    test('another key fails', () async {
      final other = await Ed25519().newKeyPair();
      expect(await verifier.verify(payload, await signPayloadForTest(payload, other)), isFalse);
    });

    test('malformed signatures are "not verified", never a throw', () async {
      for (final s in [null, '', 'rsa:abc', 'ed25519:%%%', 'ed25519:${base64.encode([1, 2, 3])}']) {
        expect(await verifier.verify(payload, s), isFalse, reason: '$s');
      }
      final sig = await signPayloadForTest(payload, pair);
      expect(await verifier.verify({'amount': 1.5}, sig), isFalse);
    });

    test('rejects a public key of the wrong size', () {
      expect(() => PayloadVerifier.fromBase64(base64.encode([1, 2, 3])), throwsFormatException);
    });
  });

  group('ApiHeaderBuilder', () {
    const b = ApiHeaderBuilder(appVersion: '0.1.0+1', locale: 'en');
    const creds = ApiCredentials(deviceId: 'dev-1', deviceToken: 'tok', sessionToken: 'sess', stepUpToken: 'up');

    test('session write with idempotency and step-up', () {
      final h = b.build(creds, idempotencyKey: 'cmd-1', stepUp: true);
      expect(h, {
        'authorization': 'Bearer tok',
        'x-device-id': 'dev-1',
        'x-session-token': 'sess',
        'x-idempotency-key': 'cmd-1',
        'x-step-up': 'up',
        'x-app-version': '0.1.0+1',
        'accept-language': 'en',
        'content-type': 'application/json; charset=utf-8',
      });
    });

    test('device-only call omits the session', () {
      final h = b.build(creds, session: false, json: false);
      expect(h.containsKey('x-session-token'), isFalse);
      expect(h.containsKey('content-type'), isFalse);
      expect(h.containsKey('x-idempotency-key'), isFalse);
    });

    test('refuses unpaired, missing session or missing step-up', () {
      expect(() => b.build(const ApiCredentials()), throwsArgumentError);
      expect(() => b.build(creds.signedOut()), throwsArgumentError);
      expect(() => b.build(creds.signedOut().copyWith(sessionToken: 's'), stepUp: true), throwsArgumentError);
    });

    test('financial commands need step-up', () {
      expect(CommandTypes.needsStepUp('voucher.receipt.create'), isTrue);
      expect(CommandTypes.needsStepUp('leave.approve'), isFalse);
      expect(CommandTypes.needsStepUp('unknown.type'), isFalse);
    });
  });

  group('ApiError mapping', () {
    test('documented shape {error:{code,message}}', () {
      final e = ApiError.fromResponse(422, '{"error":{"code":"validation_failed","message":"x","field":"amount"}}');
      expect((e.kind, e.code, e.message, e.field), (ApiErrorKind.rejected, 'validation_failed', 'x', 'amount'));
      expect(e.retryable, isFalse);
    });

    test('current cloud shape {error:"code"} and retry-after', () {
      final e = ApiError.fromResponse(429, '{"error":"rate_limited"}', {'retry-after': '30'});
      expect(e.kind, ApiErrorKind.rateLimited);
      expect(e.retryAfter, const Duration(seconds: 30));
      expect(e.retryable, isTrue);
    });

    test('401 device_revoked vs session expiry', () {
      expect(ApiError.fromResponse(401, '{"error":"device_revoked"}').kind, ApiErrorKind.deviceRevoked);
      expect(ApiError.fromResponse(401, '{"error":"session_expired"}').kind, ApiErrorKind.unauthorized);
    });

    test('status-only and non-JSON bodies', () {
      expect(ApiError.fromResponse(403, '').code, 'permission_denied');
      final e = ApiError.fromResponse(502, '<html>bad gateway</html>');
      expect((e.kind, e.code, e.retryable), (ApiErrorKind.unavailable, 'http_502', true));
      expect(ApiError.fromResponse(503, '{"error":{"code":"desktop_offline"}}').code, 'desktop_offline');
      expect(ApiError.fromResponse(409, '{"error":"stale"}').kind, ApiErrorKind.conflict);
      expect(ApiError.fromResponse(404, '{}').kind, ApiErrorKind.notFound);
    });

    test('network errors are transport failures', () {
      final e = ApiError.network(Exception('down'));
      expect(e.transportFailure && e.retryable, isTrue);
    });
  });

  group('UrlPolicy', () {
    test('release allows https only', () {
      expect(UrlPolicy.release.allows(Uri.parse('https://cloud.example.com')), isTrue);
      expect(UrlPolicy.release.allows(Uri.parse('http://10.0.2.2:18080')), isFalse);
      expect(UrlPolicy.release.allows(Uri.parse('ftp://x')), isFalse);
    });

    test('development allows cleartext to emulator host, loopback and 192.168/16 only', () {
      for (final ok in ['http://10.0.2.2:18080', 'http://localhost', 'http://127.0.0.1:8080', 'http://192.168.1.20:8080']) {
        expect(UrlPolicy.development.allows(Uri.parse(ok)), isTrue, reason: ok);
      }
      for (final bad in ['http://example.com', 'http://10.0.0.5', 'http://192.169.1.1', 'http://8.8.8.8', 'http://192.168.1.999']) {
        expect(UrlPolicy.development.allows(Uri.parse(bad)), isFalse, reason: bad);
      }
    });

    test('HttpApiTransport refuses a disallowed base URL', () {
      expect(
        () => HttpApiTransport(kind: TransportKind.cloud, baseUri: Uri.parse('http://example.com'), policy: UrlPolicy.release),
        throwsA(isA<UrlPolicyException>()),
      );
    });
  });

  group('HttpApiTransport', () {
    test('joins path, sends JSON body and headers, decodes UTF-8', () async {
      late http.Request seen;
      final t = HttpApiTransport(
        kind: TransportKind.cloud,
        baseUri: Uri.parse('https://cloud.example.com/base/'),
        policy: UrlPolicy.release,
        client: MockClient((r) async {
          seen = r;
          return http.Response.bytes(utf8.encode('{"name":"الصندوق"}'), 200);
        }),
      );
      final res = await t.send(const ApiRequest('POST', '/manage/queries',
          query: {'waitMs': '20000'}, body: {'a': 1}, headers: {'x-device-id': 'd'}));
      expect(seen.url.toString(), 'https://cloud.example.com/base/manage/queries?waitMs=20000');
      expect(seen.body, '{"a":1}');
      expect(seen.headers['x-device-id'], 'd');
      expect((res.json as Map)['name'], 'الصندوق');
    });

    test('maps non-2xx and client exceptions', () async {
      final t = HttpApiTransport(
        kind: TransportKind.lan,
        baseUri: Uri.parse('https://192.168.1.10:8443'),
        policy: UrlPolicy.release,
        client: MockClient((r) async => http.Response('{"error":"device_revoked"}', 401)),
      );
      await expectLater(t.send(const ApiRequest('GET', '/x')),
          throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.deviceRevoked)));
      final down = HttpApiTransport(
        kind: TransportKind.lan,
        baseUri: Uri.parse('https://192.168.1.10:8443'),
        policy: UrlPolicy.release,
        client: MockClient((r) async => throw http.ClientException('refused')),
      );
      await expectLater(down.send(const ApiRequest('GET', '/x')),
          throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.network)));
    });
  });

  group('TransportSelector', () {
    late FakeTransport lan;
    late FakeTransport cloud;
    late FakeLanProbe probe;
    late FakeClock clock;

    TransportSelector selector({bool withCloud = true, bool withLan = true}) => TransportSelector(
          lan: withLan ? lan : null,
          lanProbe: withLan ? probe : null,
          cloud: withCloud ? cloud : null,
          clock: clock.call,
          probeTimeout: const Duration(milliseconds: 50),
        );

    setUp(() {
      lan = FakeTransport(TransportKind.lan);
      cloud = FakeTransport(TransportKind.cloud);
      probe = FakeLanProbe();
      clock = FakeClock();
    });

    test('LAN first when the desktop answers with TLS', () async {
      final c = await selector().select();
      expect(c.mode, ConnectionMode.local);
      expect(c.transport, same(lan));
    });

    test('cloud when LAN unreachable, plain HTTP, old API level or slow', () async {
      probe.error = Exception('refused');
      expect((await selector().select()).reason, 'lan_unreachable');
      probe
        ..error = null
        ..info = const LanInfo(serverId: 's', apiLevel: 1, tls: false);
      expect((await selector().select()).reason, 'lan_no_tls');
      probe.info = const LanInfo(serverId: 's', apiLevel: 0, tls: true);
      expect((await selector().select()).reason, 'lan_api_level');
      probe
        ..info = null
        ..hang = true;
      final slow = await selector().select();
      expect((slow.mode, slow.reason), (ConnectionMode.cloud, 'lan_unreachable'));
    });

    test('offline without any usable transport; LAN-only (M-B) without desktop', () async {
      probe.error = Exception('x');
      expect((await selector(withCloud: false).select()).mode, ConnectionMode.offline);
      expect((await selector(withCloud: false, withLan: false).select()).reason, 'lan_not_configured');
    });

    test('probe result is cached for the TTL, then re-probed', () async {
      final s = selector();
      await s.select();
      await s.select();
      expect(probe.calls, 1);
      clock.advance(const Duration(seconds: 61));
      await s.select();
      expect(probe.calls, 2);
      await s.select(forceProbe: true);
      expect(probe.calls, 3);
    });

    test('run() retries once on the cloud after a LAN transport failure, same key', () async {
      final s = selector();
      lan.failWith = ApiError.network(Exception('reset'));
      final modes = <ConnectionMode>[];
      final out = await s.run((c) async {
        modes.add(c.mode);
        await c.transport!.send(const ApiRequest('POST', '/cmd', headers: {'x-idempotency-key': 'cmd-1'}));
        return c.mode;
      });
      expect(out, ConnectionMode.cloud);
      expect(modes, [ConnectionMode.local, ConnectionMode.cloud]);
      expect(lan.requests.single.headers['x-idempotency-key'], 'cmd-1');
      expect(cloud.requests.single.headers['x-idempotency-key'], 'cmd-1');
      // LAN is now marked failed: the next selection goes to the cloud without probing.
      expect((await s.select()).mode, ConnectionMode.cloud);
      expect(probe.calls, 1);
    });

    test('run() does not fall back on a server rejection', () async {
      final s = selector();
      lan.handler = (_) => const ApiResponse(403, '{"error":"permission_denied"}');
      await expectLater(s.run((c) => c.transport!.send(const ApiRequest('GET', '/x'))),
          throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.forbidden)));
      expect(cloud.requests, isEmpty);
    });

    test('run() offline throws a network error', () async {
      probe.error = Exception('x');
      await expectLater(selector(withCloud: false).run((c) async => 1), throwsA(isA<ApiError>()));
    });

    test('TransportLanProbe reads /api/m1/info', () async {
      lan.handler = (r) => ApiResponse(200, '{"serverId":"desk","apiLevel":1,"tls":true,"companyName":"متجر"}');
      final info = await TransportLanProbe(lan).probe();
      expect(lan.requests.single.path, M1Routes.info);
      expect((info.serverId, info.apiLevel, info.tls, info.companyName), ('desk', 1, true, 'متجر'));
    });
  });

  group('contracts', () {
    test('routes encode ids', () {
      expect(ManageRoutes.query('a/b'), '/manage/queries/a%2Fb');
      expect(M1Routes.customerBalance('g 1'), '/api/m1/pos/customers/g%201/balance');
    });

    test('request bodies follow §2.2', () {
      expect(const QueryRequest(queryId: 'q', type: QueryTypes.trialBalance, params: {'from': '2026-01-01'}).toJson(),
          {'queryId': 'q', 'type': 'report.trial_balance', 'params': {'from': '2026-01-01'}});
      expect(const CommandRequest(commandId: 'c', type: 'leave.approve', expectedVersion: 3).toJson()['expectedVersion'], 3);
      expect(parseRemoteStatus('done'), RemoteStatus.done);
      expect(parseRemoteStatus('weird'), RemoteStatus.queued);
    });

    test('conditional grants (cond:) are honoured', () {
      const u = MobileUser(globalId: 'g', username: 'u', displayName: 'U', permissions: ['reports_view', 'cond:pos_discount']);
      expect(u.has('pos_discount'), isTrue);
      expect(u.isConditional('pos_discount'), isTrue);
      expect(u.isConditional('reports_view'), isFalse);
      expect(u.has('treasury_view'), isFalse);
    });

    test('duplicate push counts as done', () {
      expect(const PushResult(PushStatus.duplicate).done, isTrue);
      expect(const PushResult(PushStatus.rejected, code: 'totals_mismatch').done, isFalse);
    });

    test('signed payload parses', () {
      final p = SignedPayload.fromJson({'kind': 'kpi.today', 'scope': 'all', 'asOf': '2026-02-01T08:12:03Z', 'payload': {}, 'signature': 'ed25519:x'});
      expect(p.asOf.isUtc, isTrue);
      expect(p.kind, 'kpi.today');
    });
  });
}
