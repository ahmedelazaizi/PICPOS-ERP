// F6 - MIRROR (the multi-branch manager's console): a per-device token (never
// the legacy shared one), `mirror_console` required, the manager sees both
// branches, writes are authorised on the main or refused honestly - never kept
// silently on the mirror - and the offline behaviour is read-only.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io' show HttpOverrides;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';

import '../helpers/fleet_harness.dart';
import '../helpers/lan_host_harness.dart';

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  setUp(() async {
    LegacyTokenTelemetry.instance.reset();
    fleet = await Fleet.build(accountant: false);
  });
  tearDown(() => fleet.dispose());

  test('F6.1 the mirror holds its OWN device token, bound to its id and kind; '
      'the legacy shared token is never used for it', () async {
    final row = await fleet.main.pairing.deviceById(fleet.mirror.deviceId!);
    expect(row!.deviceKind, 'mirror');
    final mirror = await fleet.peer(fleet.mirror);
    expect(mirror.deviceToken, isNotEmpty);
    expect(mirror.deviceToken, isNot('legacy-shared-token'));
    expect((await mirror.get('/api/users', withSession: false)).status, 200);

    // the token is useless under another device's identity
    final cashier = await fleet.peer(fleet.cashier);
    final spoof = LanDevice(fleet.main.overHttp(fleet.base), cashier.id)
      ..deviceToken = mirror.deviceToken;
    expect((await spoof.get('/api/users', withSession: false)).status, isNot(200),
        reason: 'a token only works for the device it was issued to');

    await fleet.login(fleet.mirror, 'manager', kManagerFleetPw);
    expect(LegacyTokenTelemetry.instance.requestsByDevice.keys,
        isNot(contains(fleet.mirror.deviceId)),
        reason: 'the mirror never rides the legacy shared bearer');
  });

  test('F6.2 mirror_console is required: a cashier is refused by the main; '
      'losing the permission ends the manager\'s next sign-in', () async {
    final mirror = await fleet.peer(fleet.mirror);
    final no = await mirror.login('cashier', kCashPw);
    expect(no.status, 403);
    expect(no.code, 'mirror_console_denied');
    expect((await mirror.login('manager', kManagerFleetPw)).status, 200);

    final role = (await fleet.main.db.getUserByUsername('manager'))!.user.roleId!;
    await fleet.main.db.setRolePermissions(role, const []);
    final after = LanDevice(fleet.main.overHttp(fleet.base), mirror.id)
      ..deviceToken = mirror.deviceToken;
    final r = await after.login('manager', kManagerFleetPw);
    expect(r.status, 403, reason: '$r');
    expect(r.code, 'mirror_console_denied');
  });

  test('F6.3 the manager of B1+B2 holds the users of BOTH branches with their '
      'credentials, and nobody outside his scope', () async {
    final db = fleet.mirror.db;
    expect(await db.authenticateUser('cashier', kCashPw), isNotNull);
    expect(await db.authenticateUser('b2emp', kB2Pw), isNotNull,
        reason: 'a B2 user reaches the manager\'s mirror');
    expect(await db.authenticateUser('manager', kManagerFleetPw), isNotNull);
    expect(await db.authenticateUser('admin', kMainAdminPw), isNull);

    final b3 = await fleet.main.db.into(fleet.main.db.branches).insert(
        BranchesCompanion.insert(name: 'Branch 3', code: const Value('B3')));
    final id = await fleet.main.db.createUser(
        username: 'outsider',
        password: 'Out#Fleet99887',
        displayName: 'o',
        roleId: (await fleet.main.db.getUserByUsername('b2emp'))!.user.roleId);
    await fleet.main.db.setUserBranchAccess(id, [b3]);
    final mirror = await fleet.peer(fleet.mirror);
    await mirror.login('manager', kManagerFleetPw);
    final feed = await mirror.get('/api/users');
    final names = [for (final u in (feed.json['users'] as List)) (u as Map)['username']];
    expect(names, containsAll(['cashier', 'accountant', 'b2emp', 'manager']));
    expect(names, isNot(contains('outsider')));
  });

  test('F6.4 mirror writes: refused honestly without the permission, pushed '
      'to the main with it, never kept locally, never queued; offline they '
      'are refused', () async {
    await fleet.login(fleet.mirror, 'manager', kManagerFleetPw);
    Future<int?> sellFromMirror(String no) => fleet.sell(fleet.mirror,
        invoiceNo: no, globalId: 'gid-$no', total: 12, username: 'manager');
    // The only rows a mirror may hold are COPIES the main accepted (the write
    // path pulls the main's state back after a successful push); never a row
    // the main refused, and never an outbox entry.
    Future<void> expectNothingLocal({Set<String> acceptedByMain = const {}}) async {
      expect(await fleet.mirror.db.select(fleet.mirror.db.syncOutbox).get(), isEmpty,
          reason: 'a mirror has no outbox by design');
      final local = await fleet.mirror.db.select(fleet.mirror.db.salesInvoices).get();
      expect(local.map((r) => r.globalId).toSet().difference(acceptedByMain), isEmpty,
          reason: 'nothing is kept on the mirror that the main did not accept');
    }

    // 1. the manager role has no sales_create: the main refuses, the mirror says so
    await expectLater(sellFromMirror('MIR-1'), throwsA(anything));
    expect(await fleet.main.db.select(fleet.main.db.salesInvoices).get(), isEmpty);
    await expectNothingLocal();

    // 2. authorised: pushed to the main under the manager's identity
    await Fleet.grantPermissions(fleet.main.db, 'مدير فروع (fleet)', ['sales_create']);
    final id = await sellFromMirror('MIR-2');
    expect(id, isNotNull);
    final rows = await fleet.main.db.select(fleet.main.db.salesInvoices).get();
    expect(rows.single.globalId, 'gid-MIR-2');
    expect(rows.single.userId, fleet.userIds['manager']);
    await expectNothingLocal(acceptedByMain: {'gid-MIR-2'});

    // 3. offline: refused (read-only console), still nothing local, nothing queued
    await fleet.mainDown();
    await expectLater(sellFromMirror('MIR-3'), throwsA(anything));
    await expectNothingLocal(acceptedByMain: {'gid-MIR-2'});
    expect((await fleet.main.db.select(fleet.main.db.salesInvoices).get()).length, 1);
  });

  test('F6.5 offline the mirror signs the manager in inside the grace window '
      'and reads its local copy', () async {
    await fleet.login(fleet.mirror, 'manager', kManagerFleetPw);
    await fleet.mainDown();
    fleet.now = fleet.now.add(const Duration(days: 2));
    expect(await fleet.login(fleet.mirror, 'manager', kManagerFleetPw), isNotNull);
    expect((await fleet.mirror.db.select(fleet.mirror.db.branches).get()).length, 2,
        reason: 'the local copy is readable');
    fleet.now = fleet.now.add(const Duration(days: 8));
    expect(await fleet.loginDenied(fleet.mirror, 'manager', kManagerFleetPw), isTrue);
    expect(ServerProxy.instance.hasSessionToken(), isFalse);
  });
}