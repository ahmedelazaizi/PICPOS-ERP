// M2 + P5 against the whole fleet: a REAL main (shelf_io, loopback), devices
// installed through the production setup flow, the REAL ServerProxy /
// ClientWriteInterceptor on the device side.
//
//  * mirror write attribution: the main records the signed-in manager, never the
//    pairing admin; the console's current branch rides the wire (X-Branch-Id) and
//    the main refuses a branch outside his scope;
//  * honest read-only: a stale link REFUSES the write (nothing reaches the main,
//    nothing is queued); a revoked mirror is refused by the main;
//  * four-eyes on a branch device: refused alone, accepted with a DIFFERENT
//    manager's proof, self-approval refused; offline: the critical operation is
//    refused and a non-critical one falls back to the local check (audited).
@Timeout(Duration(minutes: 4))
library;

import 'dart:io' show HttpOverrides;

import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/providers/manager_approval_provider.dart';
import 'package:picpos_erp/domain/repositories/auth_repository.dart';
import 'package:picpos_erp/services/approval/approval_proof_carrier.dart';
import 'package:picpos_erp/services/approval/manager_approval_flow.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import 'package:picpos_erp/services/mirror_branch_context.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';
import 'package:picpos_erp/services/write_router.dart';

import '../helpers/fleet_harness.dart';

class _RepoApprover implements LocalApproverPort {
  _RepoApprover(this.repo);
  final IAuthRepository repo;
  @override
  Future<LocalApprover?> authenticate(String input) async {
    final u = await repo.authenticateByPasswordOrCard(input);
    if (u == null) return null;
    return LocalApprover(
      id: u.user.id,
      name: u.user.displayName,
      permissions: await repo.getUserPermissionCodes(u.user.id),
    );
  }
}

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  setUp(() async {
    // the owner's grants exist BEFORE the devices are installed (role permissions
    // reach a device with its first sync)
    fleet = await Fleet.startMain();
    await Fleet.grantPermissions(fleet.main.db, 'مدير فروع (fleet)', ['pos_expense']);
    await Fleet.grantPermissions(
        fleet.main.db, 'مسؤول فرع (fleet)', ['users_manage', 'pos_expense']);
    expect((await fleet.installClient(fleet.cashier, 'cashier', kCashPw)).ok, isTrue,
        reason: '${fleet.cashier.report}');
    expect((await fleet.installMirror(fleet.mirror, 'manager', kManagerFleetPw)).ok,
        isTrue,
        reason: '${fleet.mirror.report}');
    MirrorBranchContext.instance.reset();
    ApprovalProofCarrier.instance.debugReset();
  });
  tearDown(() async {
    MirrorBranchContext.instance.reset();
    ApprovalProofCarrier.instance.debugReset();
    await fleet.dispose();
  });

  Future<List<SafeTransactionData>> hostTx(String gid) =>
      (fleet.main.db.select(fleet.main.db.safeTransactions)
            ..where((t) => t.globalId.equals(gid)))
          .get();

  group('branch-manager console (mirror)', () {
    test('M2.1 the manager\'s scope comes from the main; the write is recorded '
        'under HIM, not the pairing admin', () async {
      expect(await fleet.login(fleet.mirror, 'manager', kManagerFleetPw), isNotNull);
      final ctx = await ServerProxy.instance.fetchMirrorContext();
      expect(ctx, isNotNull);
      expect(ctx!.branches.map((b) => b.id), containsAll([fleet.branch1, fleet.branch2]));
      await MirrorBranchContext.instance.applyContext(ctx);
      expect(await MirrorBranchContext.instance.select(fleet.branch2), isTrue);

      final id = await ClientWriteInterceptor.createExpense(
        amount: 12,
        category: 'console',
        globalId: 'gid-console-1',
        userId: fleet.userIds['manager'],
      );
      expect(id, isNotNull, reason: 'online: the main answered');
      final rows = await hostTx('gid-console-1');
      expect(rows.length, 1);
      expect(rows.single.userId, fleet.userIds['manager'],
          reason: 'the main stamps the SESSION user');
      expect(rows.single.userId, isNot(1));
    });

    test('M2.1b a caller naming ANOTHER user is refused by the main (nothing recorded)',
        () async {
      await fleet.login(fleet.mirror, 'manager', kManagerFleetPw);
      await expectLater(
        ClientWriteInterceptor.createExpense(
            amount: 3, category: 'hostile', globalId: 'gid-console-hostile', userId: 1),
        throwsA(isA<MirrorOfflineException>()
            .having((e) => e.toString(), 'msg', contains('actor_mismatch'))),
      );
      expect(await hostTx('gid-console-hostile'), isEmpty);
    });

    test('M2.2 the current branch travels on every call; a branch outside '
        'the scope is refused by the main', () async {
      await fleet.login(fleet.mirror, 'manager', kManagerFleetPw);
      MirrorBranchContext.instance
          .debugSet(branches: [MirrorBranch(id: fleet.branch2, name: 'B2')], current: fleet.branch2);
      expect(await ServerProxy.instance.fetchMirrorContext(), isNotNull,
          reason: 'branch 2 is his');
      MirrorBranchContext.instance
          .debugSet(branches: const [MirrorBranch(id: 9999, name: 'X')], current: 9999);
      expect(await ServerProxy.instance.fetchMirrorContext(), isNull,
          reason: 'X-Branch-Id: 9999 is outside his scope -> 403 from the main');
    });

    test('M2.3 a stale link REFUSES the write: nothing reaches the main, '
        'nothing is queued', () async {
      await fleet.login(fleet.mirror, 'manager', kManagerFleetPw);
      MirrorState.instance.debugSetForTests(
        serverDisplayName: 'hq',
        lastHandshakeAt: DateTime.now().toUtc().subtract(const Duration(minutes: 9)),
      );
      await expectLater(
        ClientWriteInterceptor.createExpense(
            amount: 7, category: 'offline', globalId: 'gid-console-off'),
        throwsA(isA<MirrorOfflineException>()
            .having((e) => e.isRefusal, 'isRefusal', isTrue)),
      );
      expect(await hostTx('gid-console-off'), isEmpty);
      expect(
          (await fleet.mirror.db.select(fleet.mirror.db.syncOutbox).get())
              .where((o) => o.status == 'pending'),
          isEmpty,
          reason: 'a console has no outbox');
    });

    test('M2.4 a REVOKED mirror is refused by the main', () async {
      await fleet.login(fleet.mirror, 'manager', kManagerFleetPw);
      await fleet.main.pairing.revoke(fleet.mirror.deviceId!, actorUserId: 1);
      await expectLater(
        ClientWriteInterceptor.createExpense(
            amount: 7, category: 'revoked', globalId: 'gid-console-rev'),
        throwsA(isA<MirrorOfflineException>()),
      );
      expect(await hostTx('gid-console-rev'), isEmpty);
    });
  });

  group('four-eyes on a branch device', () {
    ManagerApprovalFlow flowFor({required bool mirror}) => ManagerApprovalFlow(
          wire: const ServerApprovalPort(),
          local: _RepoApprover(fleet.repo(fleet.cashier)),
          requesterId: () => fleet.userIds['cashier'],
          isClientMode: () => true,
          isMirror: () => mirror,
        );

    Future<void> renameB2(String name) => ServerProxy.instance
        .put('/api/users/${fleet.userIds['b2emp']}', {'displayName': name});

    test('P5.1 alone: refused. With a DIFFERENT manager\'s proof: accepted; '
        'with his own password: refused', () async {
      await fleet.login(fleet.cashier, 'cashier', kCashPw);
      await expectLater(renameB2('Nope'), throwsA(predicate((e) => '$e'.contains('403'))));

      final self = await flowFor(mirror: false)
          .approve(input: kCashPw, permission: PermissionCodes.usersManage);
      expect(self.kind, ManagerApprovalKind.selfApproval);

      final ok = await flowFor(mirror: false)
          .approve(input: kBranchAdminPw, permission: PermissionCodes.usersManage);
      expect(ok.approved, isTrue, reason: '${ok.kind}');
      expect(ApprovalProofCarrier.instance.proof, isNotNull);

      await renameB2('Renamed with approval');
      final u = await fleet.main.db.getUserById(fleet.userIds['b2emp']!);
      expect(u!.user.displayName, 'Renamed with approval');
      final audit = [
        for (final l in await fleet.main.db.select(fleet.main.db.activityLogs).get())
          l.action
      ];
      expect(audit, containsAll(['manager_approval', 'manager_approval_used']));
    });

    test('P5.2 a manager who lacks the authority cannot approve', () async {
      await fleet.login(fleet.cashier, 'cashier', kCashPw);
      final d = await flowFor(mirror: false)
          .approve(input: kManagerFleetPw, permission: PermissionCodes.usersManage);
      expect(d.kind, ManagerApprovalKind.notAuthorised,
          reason: 'the console manager does not hold users_manage');
      expect(ApprovalProofCarrier.instance.proof, isNull);
    });

    test('P5.3 main unreachable: a CRITICAL operation is refused, a non-critical '
        'one falls back to the local check and is audited offline', () async {
      // the branch manager signed in here earlier (online), so his credential is
      // known to this device; then the cashier works and the main goes away
      await fleet.login(fleet.cashier, 'branchadmin', kBranchAdminPw);
      await fleet.login(fleet.cashier, 'cashier', kCashPw);
      NetworkService.instance.setServerAddress('127.0.0.1', port: 1); // dead
      final critical = PermissionCodes.criticalFinancialOps.first;
      final refused = await flowFor(mirror: false)
          .approve(input: kBranchAdminPw, permission: critical);
      expect(refused.kind, ManagerApprovalKind.offlineRefusedCritical);

      final local = await flowFor(mirror: false).approve(
          input: kBranchAdminPw, permission: PermissionCodes.posExpense);
      expect(local.approved, isTrue, reason: '${local.kind}');
      expect(local.offline, isTrue);
      expect(ApprovalProofCarrier.instance.proof, isNull,
          reason: 'no proof offline: nothing for the main to verify later');
    });
  });
}
