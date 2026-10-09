import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_api_client/testing.dart';
import 'package:test/test.dart';

void main() {
  late PayloadSigner signer;
  late PayloadVerifier verifier;
  final asOf = DateTime.utc(2026, 2, 1, 8, 30);

  setUp(() async {
    signer = await PayloadSigner.fromSeed(List<int>.generate(32, (i) => i + 1));
    verifier = PayloadVerifier.fromBase64(await signer.publicKeyBase64());
  });

  group('PayloadSigner', () {
    test('seed round trip is deterministic and verifies', () async {
      final again = await PayloadSigner.fromSeed(List<int>.generate(32, (i) => i + 1));
      expect(await again.publicKeyBase64(), await signer.publicKeyBase64());
      final sig = await signer.sign({'b': '1.000', 'a': 2});
      expect(sig, startsWith('ed25519:'));
      expect(await verifier.verify({'a': 2, 'b': '1.000'}, sig), isTrue);
      expect(PayloadSigner.newSeed(), hasLength(32));
      expect(() => PayloadSigner.fromSeed([1, 2]), throwsFormatException);
    });
  });

  group('mobile password (cloud pbkdf2 format)', () {
    test('Arabic and Persian keyboard digits match ASCII credentials', () async {
      expect(normalizeCredential(' ١٢٣٤٥٦٧٨ '), '12345678');
      expect(normalizeCredential('۱۲۳۴۵۶۷۸'), '12345678');
      final hash = await hashMobilePassword('12345678', iterations: 1000);
      expect(await verifyMobilePassword(normalizeCredential('١٢٣٤٥٦٧٨'), hash), isTrue);
    });

    test('RFC 7914 PBKDF2-HMAC-SHA256 vector (c=1)', () async {
      final h = await hashMobilePassword('password', iterations: 1, salt: utf8.encode('salt'));
      final want = base64.encode([
        for (var i = 0; i < 64; i += 2)
          int.parse('120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b'.substring(i, i + 2), radix: 16)
      ]);
      expect(h, 'pbkdf2\$1\$${base64.encode(utf8.encode('salt'))}\$$want');
    });

    test('hash/verify round trip; wrong password and malformed fail', () async {
      final h = await hashMobilePassword('سر-المالك-1', iterations: 1000);
      expect(h.split(r'$'), hasLength(4));
      expect(await verifyMobilePassword('سر-المالك-1', h), isTrue);
      expect(await verifyMobilePassword('wrong', h), isFalse);
      expect(await verifyMobilePassword('x', 'argon2id\$x'), isFalse);
      expect(await verifyMobilePassword('x', r'pbkdf2$10$@@$@@'), isFalse);
    });
  });

  group('verifySnapshot', () {
    Future<SignedPayload> item({String kind = 'kpi.today', String scope = 'all'}) async =>
        SignedPayload.fromJson(await buildSignedSnapshot(signer,
            kind: kind, scope: scope, asOf: asOf, data: {'netSales': '12.500', 'invoiceCount': 4}));

    test('2026-10-03 microsecond snapshot verifies after server millisecond round trip', () async {
      final snapshot = await buildSignedSnapshot(signer,
          kind: 'kpi.today', scope: 'all',
          asOf: DateTime.utc(2026, 10, 3, 22, 21, 35, 328, 404),
          data: {'netSales': '12.500'});
      final serverAsOf = DateTime.fromMillisecondsSinceEpoch(
          DateTime.parse(snapshot['asOf'] as String).millisecondsSinceEpoch,
          isUtc: true).toIso8601String();
      final returned = SignedPayload.fromJson({...snapshot, 'asOf': serverAsOf});
      expect(await verifySnapshot(returned, verifier), isTrue);
    });

    test('genuine item verifies', () async {
      expect(await verifySnapshot(await item(), verifier), isTrue);
    });

    test('tampered figure fails', () async {
      final i = await item();
      final p = Map<String, Object?>.from(i.payload as Map)..['netSales'] = '99.000';
      final t = SignedPayload(kind: i.kind, scope: i.scope, asOf: i.asOf, payload: p, signature: i.signature);
      expect(await verifySnapshot(t, verifier), isFalse);
    });

    test('envelope swapped by the relay fails (kind, scope, asOf)', () async {
      final i = await item();
      for (final t in [
        SignedPayload(kind: 'kpi.month', scope: i.scope, asOf: i.asOf, payload: i.payload, signature: i.signature),
        SignedPayload(kind: i.kind, scope: 'branch:2', asOf: i.asOf, payload: i.payload, signature: i.signature),
        SignedPayload(
            kind: i.kind, scope: i.scope, asOf: i.asOf.add(const Duration(hours: 1)), payload: i.payload, signature: i.signature),
      ]) {
        expect(await verifySnapshot(t, verifier), isFalse);
      }
    });

    test('another key fails', () async {
      final other = await PayloadSigner.fromSeed(List<int>.filled(32, 9));
      expect(await verifySnapshot(await item(), PayloadVerifier.fromBase64(await other.publicKeyBase64())), isFalse);
    });
  });

  group('PairingOffer', () {
    test('manual entry normalizes the code and validates the URL', () {
      final o = PairingOffer.manual(url: ' https://cloud.example.com ', code: 'abcd-efgh');
      expect(o.code, 'ABCDEFGH');
      expect(o.cloudUrl.host, 'cloud.example.com');
      expect(() => PairingOffer.manual(url: 'ftp://x', code: 'ABCDEFGH'), throwsFormatException);
      expect(() => PairingOffer.manual(url: 'https://x', code: 'ABCDEFG0'), throwsFormatException); // 0 not allowed
    });

    test('QR round trip carries the signing key', () async {
      final key = await signer.publicKeyBase64();
      final qr = jsonEncode(PairingOffer(cloudUrl: Uri.parse('https://c.example'), code: 'ABCDEFGH', desktopSigningKey: key).toQrJson());
      final o = PairingOffer.fromQr(qr);
      expect(o.desktopSigningKey, key);
      expect(() => PairingOffer.fromQr('{"v":2}'), throwsFormatException);
      expect(() => PairingOffer.fromQr('not json'), throwsFormatException);
    });
  });

  group('CloudManageClient', () {
    late FakeTransport t;
    late CloudManageClient c;
    late List<Map<String, Object?>> items;

    setUp(() async {
      items = [
        await buildSignedSnapshot(signer, kind: 'kpi.today', scope: 'all', asOf: asOf, data: {'netSales': '1.000'}),
        {
          ...await buildSignedSnapshot(signer, kind: 'cash.position', scope: 'all', asOf: asOf, data: {'total': '5.000'}),
          'payload': {'total': '6.000', 'kind': 'cash.position', 'scope': 'all', 'asOf': asOf.toIso8601String()},
        },
      ];
      t = FakeTransport(TransportKind.cloud, handler: (r) {
        switch ('${r.method} ${r.path}') {
          case 'POST /manage/pair':
            return ApiResponse(200, jsonEncode({
              'deviceToken': 'tok',
              'deviceId': (r.body as Map)['deviceId'],
              'user': {'globalId': 'u1', 'username': 'owner', 'displayName': 'المالك'},
              'company': {'name': 'شركة', 'currency': 'JOD', 'decimals': 3},
              'desktopSigningKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
            }));
          case 'POST /manage/login':
            return ApiResponse(200, jsonEncode({
              'sessionToken': 'sess',
              'expiresAt': '2026-02-01T20:00:00.000Z',
              'user': {'globalId': 'u1', 'username': 'owner', 'permissions': ['mobile_admin_access', 'cond:treasury_view'], 'branchScope': [2]},
            }));
          case 'POST /manage/logout':
          case 'POST /manage/unpair':
            return const ApiResponse(204, '');
          case 'GET /manage/snapshots':
            if (r.headers['x-session-token'] != 'sess') return const ApiResponse(401, '{"error":"invalid_session"}');
            return ApiResponse(200, jsonEncode({'desktop': {'lastSeenAt': 1000}, 'serverTime': 2000, 'items': items}));
        }
        return const ApiResponse(404, '{"error":"not_found"}');
      });
      c = CloudManageClient(transport: t, headers: const ApiHeaderBuilder(appVersion: '0.2.0'));
    });

    test('pair → login → verified snapshots (tampered item dropped)', () async {
      final p = await c.pair(code: 'abcdefgh', deviceId: 'd1', deviceName: 'Pixel', appVersion: '0.2.0');
      expect(p.company.decimals, 3);
      expect(p.user!.displayName, 'المالك');
      expect((t.requests.first.body as Map)['code'], 'ABCDEFGH');
      expect(c.credentials.isPaired, isTrue);

      final s = await c.login(username: 'owner', password: 'x');
      expect(s.user.has('treasury_view'), isTrue);
      expect(s.user.isConditional('treasury_view'), isTrue);
      expect(s.user.branchScope, [2]);
      expect(t.requests[1].headers['authorization'], 'Bearer tok');
      expect(t.requests[1].headers.containsKey('x-session-token'), isFalse);

      final v = await c.verifiedSnapshots(verifier, kinds: ['kpi.today', 'cash.position']);
      expect(v.items.map((i) => i.kind), ['kpi.today']);
      expect(v.rejected, 1);
      expect(v.desktopLastSeenAt!.millisecondsSinceEpoch, 1000);
      expect(t.requests.last.query['kinds'], 'kpi.today,cash.position');
      final round = VerifiedSnapshots.fromJson(jsonDecode(jsonEncode(v.toJson())) as Map<String, Object?>);
      expect(round.find('kpi.today')!.payload, v.items.single.payload);
    });

    test('logout sends session headers and keeps device pairing', () async {
      c.credentials = const ApiCredentials(deviceId: 'd', deviceToken: 'tok', sessionToken: 'sess');
      await c.logout();
      expect(t.requests.single.path, ManageRoutes.logout);
      expect(t.requests.single.headers['x-session-token'], 'sess');
      expect(c.credentials.deviceToken, 'tok');
      expect(c.credentials.sessionToken, isNull);
    });

    test('unpair sends device credentials without a session', () async {
      c.credentials = const ApiCredentials(deviceId: 'd', deviceToken: 'tok');
      await c.unpair();
      expect(t.requests.single.path, ManageRoutes.unpair);
      expect(t.requests.single.headers['authorization'], 'Bearer tok');
      expect(t.requests.single.headers['x-device-id'], 'd');
      expect(t.requests.single.headers.containsKey('x-session-token'), isFalse);
    });

    test('failed logout clears in-memory session token', () async {
      c.credentials = const ApiCredentials(deviceId: 'd', deviceToken: 'tok', sessionToken: 'sess');
      t.failWith = ApiError.network('offline');
      await expectLater(c.logout(), throwsA(isA<ApiError>()));
      expect(c.credentials.sessionToken, isNull);
    });

    test('revoked device maps to deviceRevoked', () async {
      c.credentials = const ApiCredentials(deviceId: 'd', deviceToken: 't', sessionToken: 's');
      t.handler = (_) => const ApiResponse(401, '{"error":"device_revoked"}');
      await expectLater(c.verifiedSnapshots(verifier),
          throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.deviceRevoked)));
    });

    test('M-2/M-3 calls are explicit, not silent', () async {
      await expectLater(c.submitQuery(const QueryRequest(queryId: 'q', type: 'kpi.refresh')), throwsA(isA<ApiError>()));
    });
  });

  // Live contract test against the docker cloud (`CLOUD_URL`, admin key and
  // a desktop link are created through the test-stack admin API).
  final cloud = Platform.environment['CLOUD_URL'];
  group('live cloud', () {
    test('desktop pushes key/users/snapshots → phone pairs, logs in, verifies', () async {
      final base = Uri.parse(cloud!);
      final adminKey = Platform.environment['ADMIN_KEY'] ?? 'test-admin-key';
      final http.Client hc = http.Client();
      Future<Map<String, dynamic>> post(String path, Object body, Map<String, String> h, {int expect = 200}) async {
        final r = await hc.post(base.replace(path: path),
            headers: {'content-type': 'application/json', ...h}, body: jsonEncode(body));
        if (r.statusCode != expect) throw StateError('$path ${r.statusCode} ${r.body}');
        return r.body.isEmpty ? {} : (jsonDecode(r.body) as Map).cast();
      }

      final link = await post('/admin/desktop-links', {'companyGlobalId': '00000000-0000-4000-8000-000000000001'},
          {'x-admin-key': adminKey}, expect: 201);
      final desk = {'authorization': 'Bearer ${link['linkSecret']}', 'x-desktop-link': '${link['linkId']}'};
      await post('/desktop/link/signing-key', {'publicKey': await signer.publicKeyBase64()}, desk, expect: 204);
      final gid = 'live-${DateTime.now().microsecondsSinceEpoch}';
      await post('/desktop/users', {
        'users': [
          {
            'globalId': gid,
            'username': gid,
            'displayName': 'Live',
            'mobileEnabled': true,
            'mobilePasswordHash': await hashMobilePassword('live-password', iterations: 1000),
            'permissions': ['mobile_admin_access', 'dashboard_sales_today'],
            'branchScope': [],
            'version': 1,
          }
        ]
      }, desk);
      await post('/desktop/snapshots', {
        'items': [await buildSignedSnapshot(signer, kind: 'kpi.today', scope: 'all', asOf: DateTime.now(), data: {'netSales': '7.250'})]
      }, desk);
      final code = (await post('/desktop/admin-pairing-codes', {'userGlobalId': gid}, desk, expect: 201))['code'] as String;

      final client = CloudManageClient(
          transport: HttpApiTransport(kind: TransportKind.cloud, baseUri: base, policy: UrlPolicy.development),
          headers: const ApiHeaderBuilder(appVersion: 'live-test'));
      final p = await client.pair(code: code, deviceId: 'live-$gid', deviceName: 'live', appVersion: 'live');
      // The cloud may hold an older key from earlier live runs: pin ours.
      expect(p.desktopSigningKey, await signer.publicKeyBase64());
      await client.login(username: gid, password: 'live-password');
      final v = await client.verifiedSnapshots(verifier, kinds: ['kpi.today']);
      expect(v.rejected, 0);
      expect((v.find('kpi.today')!.payload as Map)['netSales'], '7.250');
      await post('/desktop/admin-devices/live-$gid/revoke', {}, desk);
      await expectLater(client.verifiedSnapshots(verifier),
          throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.deviceRevoked)));
      hc.close();
    });
  }, skip: cloud == null ? 'set CLOUD_URL to run against the docker cloud' : false);
}
