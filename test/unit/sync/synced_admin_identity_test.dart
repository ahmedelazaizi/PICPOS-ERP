// Admin identity on a paired device (users/login/sync plan P0, ADM-006):
// the host `admin` must map onto the local bootstrap `admin` row — one active
// admin, whichever id / global_id the host uses — never sit next to it.
//
// Promoted from test/repro_mirror (REPRO-R7-b, REPRO-R7-e).
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';

import '../../helpers/mirror_peer_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Peers p;

  setUp(() async => p = await createPeers());
  tearDown(() async => p.dispose());

  Future<List<User>> activeAdmins() => (p.client.select(p.client.users)
        ..where((u) => u.username.equals('admin') & u.isActive.equals(true)))
      .get();

  test('full sync then delta (window open): exactly ONE active admin',
      () async {
    ApiAuthMiddleware.openPairingWindow();
    await p.syncUsersFull();
    await p.syncUsersDelta();
    expect((await activeAdmins()).map((a) => a.id).toList(), [1]);
    expect(await p.canLogin(p.client, 'admin', kAdminCustomPw), isTrue);
    expect(await p.canLogin(p.client, 'admin', 'admin'), isFalse,
        reason: 'the seeded admin/admin hash must not remain valid');
  });

  test('the delta pull alone adopts the host global_id onto the local admin '
      '(no renumbered duplicate)', () async {
    ApiAuthMiddleware.openPairingWindow();
    await p.syncUsersDelta();
    final admins = await (p.client.select(p.client.users)
          ..where((u) => u.username.equals('admin')))
        .get();
    expect(admins, hasLength(1));
    final host = (await p.userOn(p.host, 'admin'))!;
    expect(admins.single.globalId, host.globalId);
    expect(admins.single.id, lessThan(1000000000));
  });

  test('repeated syncs keep a single admin (idempotency)', () async {
    ApiAuthMiddleware.openPairingWindow();
    for (var i = 0; i < 3; i++) {
      await p.syncUsersFull();
      await p.syncUsersDelta();
    }
    final all = await (p.client.select(p.client.users)
          ..where((u) => u.username.like('%admin%')))
        .get();
    expect(all, hasLength(1));
  });

  test('host admin at id != 1 (PG sequence moved it): mapped onto the local '
      'row, host password works, default does not', () async {
    await p.host.customStatement('UPDATE users SET id = 5 WHERE id = 1');
    ApiAuthMiddleware.openPairingWindow();
    await p.syncUsersFull();
    expect(await p.canLogin(p.client, 'admin', kAdminCustomPw), isTrue);
    expect(await p.canLogin(p.client, 'admin', 'admin'), isFalse);
    final admins = await (p.client.select(p.client.users)
          ..where((u) => u.username.equals('admin')))
        .get();
    expect(admins, hasLength(1));
    expect(admins.single.id, 1, reason: 'the local bootstrap id is kept');
    expect(admins.single.isActive, isTrue);
    // idempotent
    await p.syncUsersFull();
    expect(await p.canLogin(p.client, 'admin', kAdminCustomPw), isTrue);
  });

  test('id != 1 with the window CLOSED: no credentials arrive but the local '
      'admin is not renamed/disabled and no duplicate appears', () async {
    await p.host.customStatement('UPDATE users SET id = 5 WHERE id = 1');
    await p.syncUsersFull();
    final admins = await (p.client.select(p.client.users)
          ..where((u) => u.username.equals('admin')))
        .get();
    expect(admins, hasLength(1));
    expect(admins.single.isActive, isTrue);
    expect(admins.single.username, 'admin');
  });

  test('a non-admin offline duplicate is still deactivated and donates its '
      'hash (existing dedupe behaviour unchanged)', () async {
    // local user created offline with another id, same username as a host user
    await p.client.into(p.client.users).insert(UsersCompanion.insert(
          username: 'cashier1',
          passwordHash: 'x',
          passwordSalt: const Value('y'),
          displayName: 'offline',
          id: const Value(777),
        ));
    ApiAuthMiddleware.openPairingWindow();
    await p.syncUsersFull();
    final dup = await (p.client.select(p.client.users)
          ..where((u) => u.id.equals(777)))
        .getSingle();
    expect(dup.isActive, isFalse);
    expect(dup.username, startsWith('__dup_777_'));
  });
}
