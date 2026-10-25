// P5 (plan 2026-10-24): four-eyes manager approval decided on the MAIN, against a
// REAL in-process host (production router + middleware over a loopback socket).
//
//  * same-user approval is rejected, a different user with authority is accepted;
//  * the approver must hold the permission outright (critical operations are not
//    covered by the system-admin shortcut) and the branch the call is made for;
//  * the proof is signed and verified by the main: forged / expired / foreign
//    proofs are refused, a replay of the SAME operation is idempotent, another
//    operation cannot reuse it, and a proof outlives neither its approver's
//    rights nor its requester;
//  * every grant and refusal is on the audit trail.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/approval_proof.dart';
import 'package:picpos_erp/services/api/server_login_throttle.dart';

import '../helpers/lan_host_harness.dart';

const _op = 'pos_expense';

void main() {
  late LanHost host;
  late HostFixture fx;
  late LanDevice req; // branch-2 cashier on a branch-2 device
  late int approverId;
  const approverPw = 'Appr#Strong123';
  final devices = <LanDevice>[];

  setUp(() async {
    ApprovalProofStore.resetForTesting();
    host = await LanHost.start();
    fx = await HostFixture.seed(host.db);
    final base = await host.serve();
    final http = host.overHttp(base);

    final perms = await host.db.getAllPermissions();
    final roleId = await host.db.into(host.db.roles).insert(
        RolesCompanion.insert(name: 'معتمد (test)'));
    await host.db.setRolePermissions(roleId, [
      for (final p in perms)
        if (p.code == _op) p.id
    ]);
    approverId = await host.db.createUser(
        username: 'appr',
        password: approverPw,
        displayName: 'Approver',
        roleId: roleId);
    await host.db.setUserBranchAccess(approverId, [fx.branch1, fx.branch2]);

    req = LanDevice(http, 'c-b2', rolesFrom: host.db);
    devices.add(req);
    expect(
        (await req.pair((await host.issue(kind: 'client', branchId: fx.branch2)).code))
            .status,
        200);
    expect((await req.login('b2cashier', HostFixture.b2Pw)).status, 200);
  });

  tearDown(() async {
    for (final d in devices) {
      await d.dispose();
    }
    devices.clear();
    await host.close();
  });

  Future<ApiResp> grant({
    String permission = _op,
    String? user = 'appr',
    String? password = approverPw,
    String? card,
    LanDevice? as,
  }) =>
      (as ?? req).post('/api/approvals/grant', {
        'permission': permission,
        'username': ?user,
        'password': ?password,
        'cardCode': ?card,
      });

  Future<ApiResp> expense(
    String gid, {
    String? proof,
    String idem = 'idem-1',
    LanDevice? as,
  }) {
    final d = as ?? req;
    return d.transport(
      'POST',
      '/api/expenses',
      {
        ...d.headers(),
        'x-idempotency-key': idem,
        'x-approval-proof': ?proof,
      },
      jsonEncode({
        'amount': 40,
        'category': 'four-eyes',
        'globalId': gid,
        'userId': d == req ? fx.cashierB2Id : null,
      }),
    );
  }

  Future<List<String>> auditActions() async => [
        for (final l in await host.db.select(host.db.activityLogs).get()) l.action
      ];

  group('who may approve', () {
    test('the requester cannot approve his own action', () async {
      final r = await grant(user: 'b2cashier', password: HostFixture.b2Pw);
      expect([r.status, r.code], [403, 'self_approval']);
      expect(await auditActions(), contains('manager_approval_denied'));
    });

    test('a different user who holds the permission is accepted, with proof '
        'and metadata', () async {
      final r = await grant();
      expect(r.status, 200, reason: '$r');
      expect(r.json['approverId'], approverId);
      expect(r.json['requesterId'], fx.cashierB2Id);
      expect(r.json['permission'], _op);
      expect(r.json['critical'], isFalse);
      expect(r.json['proof'], isA<String>());
      expect(r.json['expiresAt'] as int,
          greaterThan(DateTime.now().millisecondsSinceEpoch));
    });

    test('an approver without the permission is refused', () async {
      final r = await grant(user: 'acct1', password: HostFixture.acctPw);
      expect([r.status, r.code], [403, 'approver_not_authorised']);
    });

    test('a critical operation is not covered by the system-admin shortcut',
        () async {
      final critical = PermissionCodes.criticalFinancialOps.first;
      final r = await grant(
          permission: critical, user: 'admin', password: kHostAdminPw);
      expect([r.status, r.code], [403, 'approver_not_authorised']);
    });

    test('an approver outside the branch of the call is refused', () async {
      final perms = await host.db.getAllPermissions();
      final roleId = await host.db.into(host.db.roles).insert(
          RolesCompanion.insert(name: 'معتمد فرع 3'));
      await host.db.setRolePermissions(
          roleId, [for (final p in perms) if (p.code == _op) p.id]);
      final far = await host.db.createUser(
          username: 'far', password: 'Far#Strong12345', displayName: 'Far', roleId: roleId);
      await host.db.setUserBranchAccess(far, [fx.branch3]);
      final r = await grant(user: 'far', password: 'Far#Strong12345');
      expect([r.status, r.code], [403, 'branch_access_denied']);
    });

    test('bad credentials: 401, and the attempts are rate-limited (429)',
        () async {
      ServerLoginThrottle.reset();
      for (var i = 0; i < 8; i++) {
        final r = await grant(password: 'wrong-$i');
        if (r.status == 429) break;
        expect(r.status, 401);
      }
      final locked = await grant();
      expect([locked.status, locked.code], [429, 'locked_out']);
    });

    test('no session, unknown permission, no credential: refused', () async {
      expect((await grant(as: LanDevice(req.transport, 'c-x'))).status, anyOf(401, 403));
      final noSession = await req.post(
          '/api/approvals/grant', {'permission': _op, 'password': approverPw},
          withSession: false);
      expect([noSession.status, noSession.code], [401, 'session_required']);
      final unknown = await grant(permission: 'no_such_permission');
      expect([unknown.status, unknown.code], [400, 'unknown_permission']);
      final none = await req.post('/api/approvals/grant', {'permission': _op});
      expect([none.status, none.code], [400, 'invalid_request']);
    });
  });

  group('the signed proof', () {
    test('without a proof the cashier is refused; with it the operation runs, '
        'under the cashier', () async {
      expect((await expense('gid-a')).status, 403);
      final proof = (await grant()).json['proof'] as String;
      final ok = await expense('gid-a', proof: proof);
      expect(ok.status, 200, reason: '$ok');
      final row = await (host.db.select(host.db.safeTransactions)
            ..where((t) => t.globalId.equals('gid-a')))
          .getSingle();
      expect(row.userId, fx.cashierB2Id);
      expect(await auditActions(), containsAll(['manager_approval', 'manager_approval_used']));
    });

    test('a forged or tampered proof is refused', () async {
      final proof = (await grant()).json['proof'] as String;
      final dot = proof.indexOf('.');
      final tampered = '${proof.substring(0, dot)}.${'A' * (proof.length - dot - 1)}';
      final forgedClaims = base64Url.encode(utf8.encode(jsonEncode({
        'v': 1,
        'op': _op,
        'req': fx.cashierB2Id,
        'apr': 1,
        'iat': 1,
        'exp': 99999999999999,
        'nid': 'ff' * 16,
      })));
      for (final bad in [tampered, '$forgedClaims.${proof.substring(dot + 1)}', 'garbage', '.']) {
        final r = await expense('gid-f', proof: bad);
        expect([r.status, r.code], [403, 'approval_invalid'], reason: bad);
      }
    });

    test('an expired proof is refused', () async {
      final old = ApprovalProof.mint(
        permission: _op,
        requesterId: fx.cashierB2Id,
        approverId: approverId,
        deviceId: 'c-b2',
        nowMs: DateTime.now().millisecondsSinceEpoch - const Duration(minutes: 30).inMilliseconds,
      )!;
      final r = await expense('gid-e', proof: old);
      expect([r.status, r.code], [403, 'approval_expired']);
    });

    test('a proof is bound to its requester, its permission and its device',
        () async {
      final proof = (await grant()).json['proof'] as String;
      // another user (no permission of his own) on the same device
      final plain = await (host.db.select(host.db.roles)
            ..where((r) => r.name.equals('موظف فرع (test)')))
          .getSingle();
      final thief = await host.db.createUser(
          username: 'thief',
          password: 'Thief#Strong123',
          displayName: 'T',
          roleId: plain.id);
      await host.db.setUserBranchAccess(thief, [fx.branch2]);
      final other = LanDevice(req.transport, 'c-b2', rolesFrom: host.db)
        ..deviceToken = req.deviceToken;
      devices.add(other);
      expect((await other.login('thief', 'Thief#Strong123')).status, 200);
      final theft = await expense('gid-t', proof: proof, as: other);
      expect(theft.status, 403);
      // another permission
      final wrongOp = await req.transport(
        'DELETE',
        '/api/expenses/1',
        {...req.headers(), 'x-approval-proof': proof},
        null,
      );
      expect([wrongOp.status, wrongOp.code], [403, 'approval_mismatch']);
    });

    test('a replay of the SAME operation is idempotent; another operation '
        'cannot reuse the proof', () async {
      final proof = (await grant()).json['proof'] as String;
      final first = await expense('gid-r', proof: proof, idem: 'k-1');
      expect(first.status, 200);
      final replay = await expense('gid-r', proof: proof, idem: 'k-1');
      expect(replay.status, 200, reason: '$replay');
      expect(replay.json['duplicate'], isTrue,
          reason: 'the same operation is deduplicated, not repeated');
      final other = await expense('gid-r2', proof: proof, idem: 'k-2');
      expect([other.status, other.code], [403, 'approval_already_used']);
    });

    test('a call WITHOUT an idempotency key spends the proof for good (it cannot '
        'prove it is a retry)', () async {
      final proof = (await grant()).json['proof'] as String;
      Future<ApiResp> bare(String gid) => req.transport(
            'POST',
            '/api/expenses',
            {...req.headers(), 'x-approval-proof': proof},
            jsonEncode({'amount': 40, 'category': 'x', 'globalId': gid}),
          );
      expect((await bare('gid-nk')).status, 200);
      final again = await bare('gid-nk');
      expect([again.status, again.code], [403, 'approval_already_used']);
    });

    test('a replay after a RESTART of the main is still recognised (audit '
        'trail), even after the proof expired', () async {
      final proof = (await grant()).json['proof'] as String;
      expect((await expense('gid-s', proof: proof, idem: 'k-9')).status, 200);
      ApprovalProofStore.resetForTesting(); // memory lost, audit rows remain
      final c = ApprovalProof.parse(proof)!;
      // pretend the proof has long expired: only the recorded use can save it
      final decision = await ApprovalGate.authorise(
        _fakeRequest(proof, 'k-9'),
        host.db,
        fx.cashierB2Id,
        _op,
        nowMs: c.expiresAtMs + const Duration(days: 1).inMilliseconds,
      );
      expect(decision!.isGranted, isTrue);
      expect(decision.replay, isTrue);
    });

    test('a proof stops working when the approver loses his authority',
        () async {
      final proof = (await grant()).json['proof'] as String;
      await (host.db.update(host.db.users)..where((u) => u.id.equals(approverId)))
          .write(const UsersCompanion(isActive: Value(false)));
      final r = await expense('gid-x', proof: proof);
      expect([r.status, r.code], [403, 'approval_approver_invalid']);
    });
  });
}

/// Minimal request for [ApprovalGate.authorise] (device id matches the proof).
shelf.Request _fakeRequest(String proof, String idem) => shelf.Request(
      'POST',
      Uri.parse('http://lan.test/api/expenses'),
      headers: {'x-approval-proof': proof, 'x-idempotency-key': idem},
      context: {'lanDeviceId': 'c-b2'},
    );