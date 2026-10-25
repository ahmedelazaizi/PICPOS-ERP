// F3 - OFFLINE: the main's HTTP server stops (data kept). The branch devices
// keep working with the credentials the main delivered, inside the grace
// window; an unknown user is refused; the injected clock ends the grace; when
// the main returns the outbox replays idempotently.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io' show HttpOverrides;

import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';

import '../helpers/fleet_harness.dart';

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  setUp(() async => fleet = await Fleet.build());
  tearDown(() => fleet.dispose());

  /// Both devices sign in online once (a fresh "verified by the main" stamp).
  Future<void> warmUp() async {
    expect(await fleet.login(fleet.cashier, 'cashier', kCashPw), isNotNull);
    expect(await fleet.login(fleet.accountant, 'accountant', kAcctPw), isNotNull);
    // a colleague who signed in once while the main was reachable
    expect(await fleet.login(fleet.cashier, 'branchadmin', kBranchAdminPw), isNotNull);
  }

  test('F3.1 main down: cashier and accountant sign in with the stored '
      'credentials inside the grace window; the cashier keeps selling (outbox)',
      () async {
    await warmUp();
    await fleet.mainDown();
    fleet.now = fleet.now.add(const Duration(days: 2));

    expect(await fleet.login(fleet.cashier, 'cashier', kCashPw), isNotNull);
    expect(await fleet.login(fleet.accountant, 'accountant', kAcctPw), isNotNull);
    expect(await fleet.login(fleet.cashier, 'branchadmin', kBranchAdminPw), isNotNull,
        reason: 'any delivered user of the branch may sign in on the cashier');
    expect(await fleet.loginDenied(fleet.cashier, 'cashier', 'not-his-password1'), isTrue);

    final queued = await fleet.sell(fleet.cashier,
        invoiceNo: 'OFF-1', globalId: 'gid-off-1', total: 40, username: 'cashier');
    expect(queued, isNull, reason: 'offline: parked in the outbox, no server id');
    final out = await fleet.cashier.db.select(fleet.cashier.db.syncOutbox).get();
    expect(out.where((o) => o.status == 'pending').length, 1);
    expect(out.single.payload, contains('gid-off-1'));
    expect(await fleet.main.db.select(fleet.main.db.salesInvoices).get(), isEmpty,
        reason: 'the main is down: nothing arrived');
  });

  test('F3.2 offline an UNKNOWN/unsynced user is rejected; a local-only user '
      'passes in SHADOW (logged) and is refused in ENFORCE', () async {
    await warmUp();
    // created on the main AFTER the devices synced: never delivered
    final id = await fleet.main.db.createUser(
        username: 'latecomer',
        password: 'Late#Fleet9876',
        displayName: 'late',
        roleId: (await fleet.main.db.getUserByUsername('cashier'))!.user.roleId);
    await fleet.main.db.setUserBranchAccess(id, [fleet.branch1]);
    await fleet.mainDown();

    expect(await fleet.loginDenied(fleet.cashier, 'latecomer', 'Late#Fleet9876'), isTrue,
        reason: 'unknown on the device and the main is unreachable');

    // a row that exists locally but was never verified by the main (no stamp)
    final local = await fleet.cashier.db.createUser(
        username: 'localonly',
        password: 'Local#Fleet111',
        displayName: 'local',
        roleId: (await fleet.cashier.db.getUserByUsername('cashier'))!.user.roleId);
    await fleet.cashier.db.setUserBranchAccess(local, [fleet.branch1]);

    final logged = <OfflineLoginVerdict>[];
    await fleet.use(fleet.cashier);
    await fleet.setGateMode(fleet.cashier, OfflineLoginMode.shadow);
    final shadow = await fleet
        .repo(fleet.cashier, onShadow: (v, _) => logged.add(v))
        .authenticateUser('localonly', 'Local#Fleet111');
    expect(shadow, isNotNull, reason: 'SHADOW only logs what ENFORCE would refuse');
    expect(logged.single.decision, OfflineLoginDecision.notProvisioned);

    await fleet.setGateMode(fleet.cashier, OfflineLoginMode.enforce);
    expect(await fleet.loginDenied(fleet.cashier, 'localonly', 'Local#Fleet111'), isTrue,
        reason: 'ENFORCE refuses a user the main never vouched for');
    // the provisioned user is unaffected by the switch
    expect(await fleet.login(fleet.cashier, 'cashier', kCashPw), isNotNull);
  });

  test('F3.3 past the grace window (injected clock) the offline login ends, '
      'in SHADOW and in ENFORCE; a reconnection renews it', () async {
    await warmUp();
    await fleet.mainDown();
    for (final mode in [OfflineLoginMode.shadow, OfflineLoginMode.enforce]) {
      await fleet.setGateMode(fleet.cashier, mode);
      fleet.now = fleet.now.add(const Duration(days: 3));
      expect(await fleet.login(fleet.cashier, 'cashier', kCashPw), isNotNull,
          reason: '$mode: day 3 is inside the 7 day grace');
    }
    fleet.now = fleet.now.add(const Duration(days: 8));
    for (final mode in [OfflineLoginMode.shadow, OfflineLoginMode.enforce]) {
      await fleet.setGateMode(fleet.cashier, mode);
      expect(await fleet.loginDenied(fleet.cashier, 'cashier', kCashPw), isTrue,
          reason: '$mode: an expired grace is a hard rejection');
    }
    // the main returns: online verification restarts the period
    await fleet.mainUp();
    expect(await fleet.login(fleet.cashier, 'cashier', kCashPw), isNotNull);
    await fleet.mainDown();
    fleet.now = fleet.now.add(const Duration(days: 2));
    expect(await fleet.login(fleet.cashier, 'cashier', kCashPw), isNotNull);
  });

  test('F3.4 the main restarts: the outbox replays, idempotently (one invoice, '
      'the same global id, no duplicate on a second replay)', () async {
    await warmUp();
    await fleet.startWorker(fleet.cashier);
    await fleet.mainDown();
    await fleet.login(fleet.cashier, 'cashier', kCashPw);
    await fleet.sell(fleet.cashier,
        invoiceNo: 'OFF-7', globalId: 'gid-off-7', total: 15, username: 'cashier');
    await fleet.sell(fleet.cashier,
        invoiceNo: 'OFF-8', globalId: 'gid-off-8', total: 25, username: 'cashier');
    expect((await fleet.cashier.db.select(fleet.cashier.db.syncOutbox).get()).length, 2);

    await fleet.mainUp();
    await fleet.drain(fleet.cashier);
    var rows = await fleet.main.db.select(fleet.main.db.salesInvoices).get();
    expect(rows.map((r) => r.globalId).toSet(), {'gid-off-7', 'gid-off-8'});
    expect(rows.length, 2);

    // replay the SAME outbox payloads again (lost acknowledgement)
    await fleet.cashier.db.customStatement(
        "UPDATE sync_outbox SET status = 'pending', attempts = 0");
    await fleet.drain(fleet.cashier);
    rows = await fleet.main.db.select(fleet.main.db.salesInvoices).get();
    expect(rows.length, 2, reason: 'no duplicate invoice on replay');
    expect(rows.map((r) => r.invoiceNumber).toSet(), {'OFF-7', 'OFF-8'});
    expect(rows.every((r) => r.userId == fleet.userIds['cashier']), isTrue);
  });
}
