// F7 - REVOCATION: the main revokes the cashier's device; it is refused on
// every route, on login (online AND offline), its queued sales never land, and
// the other devices are untouched.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io' show HttpOverrides;

import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/domain/repositories/auth_repository.dart';

import '../helpers/fleet_harness.dart';
import '../helpers/lan_host_harness.dart' show ApiResp;

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  setUp(() async => fleet = await Fleet.build());
  tearDown(() => fleet.dispose());

  test('F7.1 a revoked cashier device is refused on every route; the other '
      'devices keep working', () async {
    final cashier = await fleet.peer(fleet.cashier);
    expect((await cashier.get('/api/users', withSession: false)).status, 200);

    await fleet.main.pairing.revoke(fleet.cashier.deviceId!, actorUserId: 1);

    for (final probe in <Future<ApiResp>>[
      cashier.get('/api/users', withSession: false),
      cashier.get('/api/sync/pull?table=products', withSession: false),
      cashier.post('/api/auth/session', {'username': 'cashier', 'password': kCashPw},
          withSession: false),
      cashier.post('/api/sales', {'invoiceNumber': 'X', 'total': 1}, withSession: false),
    ]) {
      final r = await probe;
      expect(r.status, 401, reason: '$r');
      expect(r.body, contains('device_revoked'));
    }

    final acct = await fleet.peer(fleet.accountant);
    expect((await acct.get('/api/users', withSession: false)).status, 200);
    final mirror = await fleet.peer(fleet.mirror);
    expect((await mirror.get('/api/users', withSession: false)).status, 200);
    expect(await fleet.login(fleet.accountant, 'accountant', kAcctPw), isNotNull);
    expect(await fleet.login(fleet.mirror, 'manager', kManagerFleetPw), isNotNull);
  });

  test('F7.2 the revoked device cannot sign anyone in - online, and offline '
      'once the revocation was seen', () async {
    await fleet.main.pairing.revoke(fleet.cashier.deviceId!, actorUserId: 1);
    await expectLater(
        fleet.login(fleet.cashier, 'cashier', kCashPw),
        throwsA(isA<AuthRejectedException>()
            .having((e) => e.message, 'message', contains('أُلغي اعتماد هذا الجهاز'))));
    await fleet.mainDown();
    await expectLater(
        fleet.login(fleet.cashier, 'cashier', kCashPw),
        throwsA(isA<AuthRejectedException>()
            .having((e) => e.message, 'message', contains('أُلغي اعتماد هذا الجهاز'))),
        reason: 'the flag is remembered: an outage does not undo a revocation');
  });

  test('F7.3 a sale the revoked device queued never reaches the main', () async {
    await fleet.login(fleet.cashier, 'cashier', kCashPw);
    await fleet.startWorker(fleet.cashier);
    await fleet.mainDown();
    await fleet.sell(fleet.cashier,
        invoiceNo: 'REV-1', globalId: 'gid-rev-1', total: 9, username: 'cashier');
    await fleet.main.pairing.revoke(fleet.cashier.deviceId!, actorUserId: 1);
    await fleet.mainUp();
    // a bounded drain attempt (the worker must not be able to push)
    for (var i = 0; i < 5; i++) {
      await fleet.drain(fleet.cashier).timeout(const Duration(seconds: 5),
          onTimeout: () {});
    }
    expect(await fleet.main.db.select(fleet.main.db.salesInvoices).get(), isEmpty,
        reason: 'revoked: the queued invoice is not accepted');
  });
}