// M1 (plan 2026-10-24): device kinds are carried by the pairing CODE.
//  * a `mirror` is paired by code like any device (per-device token, branchless,
//    individually revocable) and works when the legacy shared token is gone;
//  * the code binds kind + branch; the device cannot pick either;
//  * route scope: a mirror has no point-of-sale (device_scope).
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/api/lan_device_route_policy.dart';
import 'package:picpos_erp/services/api/lan_pairing_authz.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';

import '../../helpers/lan_host_harness.dart';

void main() {
  late LanHost host;
  late HostFixture fx;

  setUp(() async {
    host = await LanHost.start();
    fx = await HostFixture.seed(host.db);
  });
  tearDown(() => host.close());

  LanPairingRequest req(String code, String id, {String? kind, int? branch}) =>
      LanPairingRequest(
        code: code,
        deviceId: id,
        deviceName: 'N',
        ip: '10.0.0.8',
        deviceKind: kind,
        branchId: branch,
      );

  group('code shape (issue time)', () {
    test('the pairable kinds are exactly client, mirror, warehouse, admin, pos',
        () {
      expect(kPairableDeviceKinds,
          {'client', 'mirror', 'warehouse', 'admin', 'pos'});
    });

    test('client needs a branch, mirror forbids one, unknown kinds and bad '
        'branches are refused', () async {
      await expectLater(host.issue(kind: 'client'), throwsArgumentError);
      await expectLater(
          host.issue(kind: 'mirror', branchId: fx.branch1), throwsArgumentError);
      await expectLater(host.issue(kind: 'toaster'), throwsArgumentError);
      await expectLater(host.issue(kind: 'pos', branchId: 0), throwsArgumentError);
      expect((await host.issue(kind: 'admin')).code, isNotEmpty);
    });

    test('the QR payload carries kind and branch', () async {
      final o = await host.issue(kind: 'client', branchId: fx.branch1);
      expect(o.qrPayload, contains('"kind":"client"'));
      expect(o.qrPayload, contains('"branchId":${fx.branch1}'));
    });
  });

  group('claim rules', () {
    test('a mirror code makes a branchless mirror device, and only that',
        () async {
      final o = await host.issue(kind: 'mirror');
      final wrong =
          await host.pairing.pair(req(o.code, 'm-1', kind: 'pos', branch: fx.branch2));
      expect(wrong.status, LanPairingStatus.kindMismatch);
      expect(await host.pairing.deviceById('m-1'), isNull,
          reason: 'a refused claim creates nothing and does not burn the code');
      // the device asks for a branch: ignored for a mirror
      final ok = await host.pairing.pair(req(o.code, 'm-1', branch: fx.branch1));
      expect(ok.status, LanPairingStatus.success);
      expect(ok.deviceKind, 'mirror');
      final d = (await host.pairing.deviceById('m-1'))!;
      expect([d.deviceKind, d.branchId, d.terminalCode, d.revoked],
          ['mirror', null, null, false]);
      expect(await host.pairing.verifyDeviceToken(token: ok.token!, deviceId: 'm-1'),
          isTrue);
    });

    test('a legacy (kind-less) code cannot make a mirror or client device',
        () async {
      final o = await host.issue();
      for (final kind in ['mirror', 'client', 'warehouse']) {
        expect((await host.pairing.pair(req(o.code, 'x-$kind', kind: kind, branch: fx.branch1))).status,
            LanPairingStatus.kindMismatch,
            reason: kind);
      }
      expect((await host.pairing.pair(req(o.code, 'legacy-admin', kind: 'admin'))).status,
          LanPairingStatus.success);
    });

    test('a client code binds the branch and a client request cannot move it',
        () async {
      final o = await host.issue(kind: 'client', branchId: fx.branch1);
      final r = await host.pairing.pair(req(o.code, 'c-1', branch: fx.branch2));
      expect(r.status, LanPairingStatus.success);
      expect([r.deviceKind, r.branchId], ['client', fx.branch1]);
      expect((await host.pairing.deviceById('c-1'))!.branchId, fx.branch1);
    });

    test('a client code for an unknown branch is refused', () async {
      final o = await host.issue(kind: 'client', branchId: 9999);
      expect((await host.pairing.pair(req(o.code, 'c-1'))).status,
          LanPairingStatus.branchUnavailable);
    });

    test('a pos code with a branch is bound to it (terminal code allocated); '
        'a pos code without one keeps the legacy device-named branch', () async {
      final bound = await host.issue(kind: 'pos', branchId: fx.branch2);
      final a = await host.pairing.pair(req(bound.code, 'p-1', branch: fx.branch3));
      expect(a.status, LanPairingStatus.success);
      expect([a.branchId, a.terminalCode], [fx.branch2, isNotNull]);

      final legacy = await host.issue(kind: 'pos');
      final b = await host.pairing.pair(req(legacy.code, 'p-2', branch: fx.branch3));
      expect(b.branchId, fx.branch3);
      final none = await host.issue(kind: 'pos');
      expect((await host.pairing.pair(req(none.code, 'p-3'))).status,
          LanPairingStatus.branchRequired);
    });
  });

  group('route scope (what a mirror device may call)', () {
    test('policy matrix', () {
      bool ok(String? kind, String path) => LanDeviceRoutePolicy.allows(kind, path);
      for (final p in ['/api/users', '/api/sync/pull', '/api/products', '/api/auth/session']) {
        expect(ok('mirror', p), isTrue, reason: p);
      }
      for (final p in [
        '/api/pos/anything',
        '/api/pos-terminals/register',
        '/api/sales/held',
        '/api/sales/held-items',
        '/api/m1/wh/session',
        '/api/table-requests',
      ]) {
        expect(ok('mirror', p), isFalse, reason: p);
      }
      expect(
          LanDeviceRoutePolicy.allows('mirror', '/api/pos-terminals', method: 'GET'),
          isTrue,
          reason: 'the registry is READ by the shared sync engine (FLEET-1)');
      expect(
          LanDeviceRoutePolicy.allows('mirror', '/api/pos-terminals', method: 'POST'),
          isFalse);
      expect(
          LanDeviceRoutePolicy.allows('mirror', '/api/pos-terminals/register',
              method: 'GET'),
          isFalse);
      for (final p in ['/api/m1/wh/desk/receipts', '/api/m1/wh/desk/receipts/x/convert']) {
        expect(ok('mirror', p), isTrue, reason: 'owner decision 2026-10-26: the receipts desk is open to a mirror: $p');
        expect(ok('warehouse', p), isTrue, reason: 'the phone prefix still reaches the route; runDesk refuses it: $p');
      }
      expect(ok('mirror', '/api/m1/wh/desks'), isFalse, reason: 'a prefix match, not a substring');
      expect(ok('mirror', '/api/m1/wh/po'), isFalse, reason: 'the phone API stays closed to a mirror');
      expect(ok('mirror', '/api/sales'), isTrue, reason: 'a prefix match, not a substring');
      expect(ok('pos', '/api/sales/held'), isTrue, reason: 'other kinds unchanged');
      expect(ok('client', '/api/pos-terminals/register'), isTrue);
      expect(ok('warehouse', '/api/users'), isFalse);
    });

    test('through the middleware: device_scope for POS, console reads pass',
        () async {
      final o = await host.issue(kind: 'mirror');
      final m = LanDevice(host.direct, 'm-1');
      expect((await m.pair(o.code)).status, 200);
      final pos = await m.post('/api/pos-terminals/register', {}, withSession: false);
      expect(pos.status, 403);
      expect(pos.body, contains('device_scope'));
      expect((await m.get('/api/pos-terminals', withSession: false)).status, 200,
          reason: 'FLEET-1: the console READS the terminal registry');
      expect((await m.get('/api/users', withSession: false)).status, 200);
      expect((await m.get('/api/branches', withSession: false)).status, 200);
      await m.dispose();
    });
  });

  group('lifecycle', () {
    test('works with the legacy window ENDED; revoke -> 401 device_revoked '
        'for that device only', () async {
      await host.pairing.endLegacyTransition();
      final m = LanDevice(host.direct, 'm-1');
      final other = LanDevice(host.direct, 'm-2');
      expect((await m.pair((await host.issue(kind: 'mirror')).code)).status, 200);
      expect((await other.pair((await host.issue(kind: 'mirror')).code)).status, 200);
      expect((await m.get('/api/users', withSession: false)).status, 200);
      expect(await ApiAuthMiddleware.verifyCredential(m.deviceToken!, 'm-1'), isTrue,
          reason: 'the realtime channel admits a mirror');

      await host.pairing.revoke('m-1', actorUserId: 1);
      final r = await m.get('/api/users', withSession: false);
      expect([r.status, r.body], [401, contains('device_revoked')]);
      expect((await other.get('/api/users', withSession: false)).status, 200);
      await m.dispose();
      await other.dispose();
    });

    test('pairing again after a revoke re-enables the device', () async {
      final m = LanDevice(host.direct, 'm-1');
      await m.pair((await host.issue(kind: 'mirror')).code);
      await host.pairing.revoke('m-1', actorUserId: 1);
      expect((await m.pair((await host.issue(kind: 'mirror')).code)).status, 200);
      expect((await m.get('/api/users', withSession: false)).status, 200);
      await m.dispose();
    });
  });
}
