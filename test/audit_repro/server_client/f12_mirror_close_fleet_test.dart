import 'dart:convert';
import 'dart:io' show HttpOverrides;

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import '../../helpers/fleet_harness.dart';

const _skip = 'audit repro — pending owner approval';

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  setUp(() async => fleet = await Fleet.build(accountant: false));
  tearDown(() => fleet.dispose());

  test('F12 mirror closes its local shift through real HTTP to the main',
      skip: _skip, () async {
    await Fleet.grantPermissions(
        fleet.main.db, 'مدير فروع (fleet)', ['pos_shift_open', 'pos_shift_close']);
    await fleet.login(fleet.mirror, 'manager', kManagerFleetPw);
    final userId = fleet.userIds['manager']!;
    const globalId = 'audit-f12-mirror-shift-1';

    // The mirror has a local shift row; the following CWI call opens its
    // server counterpart over the harness's real loopback HTTP transport.
    final localShiftId = await fleet.mirror.db.openShift(
        userId, 50, branchId: fleet.branch1, globalId: globalId);
    final serverShiftId = await ClientWriteInterceptor.openShift(
        userId, 50, localShiftId: localShiftId,
        branchId: fleet.branch1, globalId: globalId);
    expect(serverShiftId, isNotNull);
    final openedOnMain = await (fleet.main.db.select(fleet.main.db.shifts)
          ..where((row) => row.globalId.equals(globalId)))
        .getSingle();
    expect(openedOnMain.id, serverShiftId);
    expect(openedOnMain.status, 'open');

    // This is the same production write entry point used by POS close. The
    // current wire DTO has no click, snapshot, or closing-method fields.
    expect(await ClientWriteInterceptor.closeShift(
        userId: userId, actualCash: 45, actualCard: 7), isTrue);

    const localSnapshot = '{"actualCash":45,"actualCard":7,"actualClick":11,'
        '"systemCash":50,"clickVariance":11}';
    await fleet.mirror.db.closeShiftWithAudit(localShiftId, 45,
        closingMethod: 'audit-fleet', closingSnapshot: localSnapshot);
    final serverClosed = await (fleet.main.db.select(fleet.main.db.shifts)
          ..where((row) => row.globalId.equals(globalId)))
        .getSingle();
    final localClosed = await (fleet.mirror.db.select(fleet.mirror.db.shifts)
          ..where((row) => row.id.equals(localShiftId)))
        .getSingle();
    final serverMoves = await (fleet.main.db.select(fleet.main.db.safeTransactions)
          ..where((row) => row.userId.equals(userId)))
        .get();
    final mirrorMoves = await (fleet.mirror.db.select(fleet.mirror.db.safeTransactions)
          ..where((row) => row.userId.equals(userId)))
        .get();
    final serverJournals = await fleet.main.db.select(fleet.main.db.journalEntries).get();
    final mirrorJournals = await fleet.mirror.db.select(fleet.mirror.db.journalEntries).get();
    final serverAccounts = await fleet.main.db.select(fleet.main.db.accounts).get();
    final mirrorAccounts = await fleet.mirror.db.select(fleet.mirror.db.accounts).get();
    final serverBalances = serverAccounts.where((a) => a.balance != 0)
        .map((a) => '${a.code}:${a.balance}').join(',');
    final mirrorBalances = mirrorAccounts.where((a) => a.balance != 0)
        .map((a) => '${a.code}:${a.balance}').join(',');

    expect(serverClosed.status, 'closed');
    expect(serverClosed.expectedCash, 50);
    expect(serverClosed.actualCash, 45);
    expect(serverClosed.variance, -5);
    expect(serverClosed.closingSnapshot, isNull);
    expect(serverClosed.closingMethod, 'normal');
    expect(localClosed.closingSnapshot, localSnapshot);
    expect(localClosed.closingMethod, 'audit-fleet');
    expect(await fleet.mirror.db.select(fleet.mirror.db.syncOutbox).get(), isEmpty);
    // ignore: avoid_print
    print('[AUDIT-F12-FLEET] globalId=$globalId expected=${serverClosed.expectedCash}/'
        '${localClosed.expectedCash} variance=${serverClosed.variance}/${localClosed.variance} '
        'serverSnapshot=${serverClosed.closingSnapshot} localSnapshotClick=11 '
        'serverMethod=${serverClosed.closingMethod} localMethod=${localClosed.closingMethod} '
        'safeTx=${serverMoves.length}/${mirrorMoves.length} '
        'journalEntries=${serverJournals.length}/${mirrorJournals.length} '
        'stock_movements=${(await fleet.main.db.select(fleet.main.db.stockMovements).get()).length}/'
        '${(await fleet.mirror.db.select(fleet.mirror.db.stockMovements).get()).length} '
        'accounts.balance=[$serverBalances]/[$mirrorBalances]');
  });
}
