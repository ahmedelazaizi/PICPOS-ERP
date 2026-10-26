// Cashier tablet (kind `pos`) on the LAN host: a branch-bound code with the
// certificate fingerprint in the payload, a per-device token (not the legacy
// bearer), role-aware login, a route scope a stolen token cannot leave and
// instant revocation. Real middleware + real handlers.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';

import '../helpers/lan_host_harness.dart';

void main() {
  late LanHost host;
  late HostFixture fx;
  late int cashierRole;
  String pw(String name) => 'Cash#Strong2026-$name';

  setUp(() async {
    ApiAuthMiddleware.closePairingWindow();
    host = await LanHost.start();
    fx = await HostFixture.seed(host.db);
    // A cashier terminal code is allocated per branch: the branch needs a code.
    await (host.db.update(host.db.branches)
          ..where((b) => b.id.equals(fx.branch1)))
        .write(const BranchesCompanion(code: Value('B1')));
    cashierRole = (await (host.db.select(host.db.roles)
              ..where((r) => r.name.equals('كاشير'))
              ..limit(1))
            .getSingle())
        .id;
  });
  tearDown(() async => host.close());

  Future<int> user(String name, int roleId, int branch) async {
    final id = await host.db.createUser(
        username: name, password: pw(name), displayName: name, roleId: roleId);
    await host.db.setUserBranchAccess(id, [branch]);
    return id;
  }

  Future<LanDevice> pairPos({int? branch, String id = 'pos-tablet-1'}) async {
    final offer = await host.issue(
        kind: 'pos', branchId: branch ?? fx.branch1, fingerprint: 'AB:CD:EF:01');
    final d = LanDevice(host.direct, id);
    final r = await d.pair(offer.code, kind: 'pos');
    expect(r.status, 200, reason: '$r');
    return d;
  }

  test('the payload is v2 kind=pos with https, the pin and the branch', () async {
    final offer =
        await host.issue(kind: 'pos', branchId: fx.branch1, fingerprint: 'AB:CD');
    final p = jsonDecode(offer.qrPayload) as Map;
    expect(p['kind'], 'pos');
    expect(p['url'], startsWith('https://'));
    expect(p['fp'], 'AB:CD');
    expect(p['branchId'], fx.branch1);
  });

  test('pairing is branch-bound by the CODE and returns a per-device token '
      'with the terminal; the code is one-time', () async {
    final offer =
        await host.issue(kind: 'pos', branchId: fx.branch1, fingerprint: 'AB:CD');
    final d = LanDevice(host.direct, 'pos-tablet-1');
    // The tablet asks for another branch: the code decides.
    final r = await d.pair(offer.code, kind: 'pos', branchId: fx.branch2);
    expect(r.status, 200, reason: '$r');
    expect(r.json['branchId'], fx.branch1);
    expect(r.json['terminalCode'], isNotNull);
    expect(r.json['token'], isNot('legacy-shared-token'));
    final row = await host.pairing.deviceById('pos-tablet-1');
    expect(row!.deviceKind, 'pos');
    expect(row.branchId, fx.branch1);
    expect((await LanDevice(host.direct, 'other').pair(offer.code, kind: 'pos')).status,
        401);
  });

  test('a code for another kind cannot be claimed as pos', () async {
    final offer = await host.issue(kind: 'mirror', fingerprint: 'AB:CD');
    final r = await LanDevice(host.direct, 'x').pair(offer.code, kind: 'pos');
    expect(r.status, 401);
  });

  test('a stolen pos token cannot reach the warehouse phone API or the '
      'branch-manager console', () async {
    final d = await pairPos();
    for (final path in ['/api/m1/wh/session', '/api/m1/wh/items', '/api/mirror/context']) {
      final r = await d.get(path, withSession: false);
      expect(r.status, 403, reason: '$path: $r');
      expect(r.body, contains('device_scope'));
    }
    // Its own sales surface is not blocked by the scope.
    final ok = await d.get('/api/products', withSession: false);
    expect(ok.status, isNot(403), reason: '$ok');
  });

  test('role-aware login: a user without pos_access gets no session on a '
      'cashier tablet; a cashier of the branch does; another branch does not',
      () async {
    final d = await pairPos();
    await user('cashier-ok', cashierRole, fx.branch1);
    await user('cashier-b2', cashierRole, fx.branch2);
    final noPos = await user('no-pos', (await host.db.select(host.db.roles).get())
        .firstWhere((r) => r.name.contains('(test)')).id, fx.branch1);
    expect(noPos, greaterThan(0));

    final ok = await d.login('cashier-ok', pw('cashier-ok'));
    expect(ok.status, 200, reason: '$ok');
    final wrongBranch = await d.login('cashier-b2', pw('cashier-b2'));
    expect(wrongBranch.status, 403);
    expect(wrongBranch.json['code'], 'branch_access_denied');
    final denied = await d.login('no-pos', pw('no-pos'));
    expect(denied.status, 403);
    expect(denied.json['code'], 'pos_access_denied');
  });

  test('revocation kills the tablet at once with 401 device_revoked',
      () async {
    final d = await pairPos();
    expect((await d.get('/api/products', withSession: false)).status, isNot(401));
    await host.pairing.revoke('pos-tablet-1', actorUserId: 1);
    final r = await d.get('/api/products', withSession: false);
    expect(r.status, 401);
    expect(r.body, contains('device_revoked'));
  });

  test('the legacy bearer is not what a paired tablet uses: a wrong device id '
      'with the pos token is refused', () async {
    final d = await pairPos();
    final stolen = LanDevice(host.direct, 'someone-else')
      ..deviceToken = d.deviceToken;
    expect((await stolen.get('/api/products', withSession: false)).status,
        isNot(200));
  });
}
