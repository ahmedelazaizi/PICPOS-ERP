// F11 - DEFECTS found while building the fleet, all FIXED in the tree and kept
// as regression pins (no skips): F11.1/F11.2 (FLEET-1/3: the two missing GET
// routes), F11.3/F11.4 (FLEET-2/5).
// Details: docs/audits/2026-10-24-mirror-and-admin-login/FLEET-E2E-RESULTS.md.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io' show HttpOverrides;

import 'package:flutter_test/flutter_test.dart';

import '../helpers/fleet_harness.dart';

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  setUp(() async => fleet = await Fleet.build(mirror: false, accountant: true));
  tearDown(() => fleet.dispose());

  Future<T> unshimmed<T>(Future<T> Function() body) async {
    fleet.shimOn = false;
    try {
      return await body();
    } finally {
      fleet.shimOn = true;
    }
  }

  test('F11.1 GET /api/pos-terminals answers a paired client (the first sync '
      'pulls it)', () async {
    final cashier = await fleet.peer(fleet.cashier);
    final r = await unshimmed(() => cashier.get('/api/pos-terminals', withSession: false));
    expect(r.status, 200, reason: 'a paired client\'s first sync GETs it: $r');
    expect(r.json['pos_terminals'], isA<List>());
  });



  test('F11.2 GET /api/sale-bom-consumptions answers a paired client', () async {
    final cashier = await fleet.peer(fleet.cashier);
    final r = await unshimmed(
        () => cashier.get('/api/sale-bom-consumptions', withSession: false));
    expect(r.status, 200, reason: '$r');
    expect(r.json['sale_bom_consumptions'], isA<List>());
  });

  test('F11.3 (FLEET-2 resolved in the tree - regression pin) /api/user-branch-access is scoped to the caller: a B1 device '
      'does not receive the B2 employee\'s access rows', () async {
    final acct = await fleet.peer(fleet.accountant);
    await acct.login('accountant', kAcctPw);
    final r = await unshimmed(() => acct.get('/api/user-branch-access'));
    expect(r.status, 200, reason: '$r');
    final owners = {
      for (final row in (r.json['user_branch_access'] as List)) (row as Map)['userId']
    };
    expect(owners, isNot(contains(fleet.userIds['b2emp'])),
        reason: 'the B2 employee is not in the B1 users feed; his access row '
            'must not travel either');
  });

  test('F11.4 (FLEET-5 resolved in the tree - regression pin) the first-user verification delivers the branch-access rows '
      'with the credentials: the first sign-in works with no extra pull',
      () async {
    final f = fleet;
    // a fresh device: install WITHOUT the harness workaround
    final d = f.mirror; // unused slot, re-used as a client
    d.kind = 'client';
    final rep = await f.installClient(d, 'cashier', kCashPw, closeAccessGap: false);
    expect(rep.ok, isTrue, reason: '$rep');
    await f.mainDown();
    expect(await f.login(d, 'cashier', kCashPw), isNotNull,
        reason: 'the branch check runs on the delivered rows');
  });
}
