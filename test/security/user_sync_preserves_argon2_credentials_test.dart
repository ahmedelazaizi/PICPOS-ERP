// CRED-WIPE (users/login/sync plan, phase P0).
//
// A users sync that arrives WITHOUT credentials (no verified session and the
// pairing window closed — i.e. the login-screen refetch after a typo, the boot
// pull before login, any delta pull) must NEVER replace a valid local
// credential. Argon2id rows legitimately have `password_salt == ''`, so the old
// `salt.isNotEmpty` guard classified every modern row as broken and overwrote it
// with an unusable credential.
//
// Promoted from test/repro_mirror (REPRO-R2-a/b/c).
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/sync/strategies/user_sync_strategy.dart';

import '../helpers/mirror_peer_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Peers p;

  setUp(() async => p = await createPeers());
  tearDown(() async => p.dispose());

  Future<void> provisionWithOpenWindow() async {
    ApiAuthMiddleware.openPairingWindow();
    await p.syncUsersFull();
    ApiAuthMiddleware.closePairingWindow();
    expect(await p.canLogin(p.client, 'cashier1', kCashierInitialPw), isTrue,
        reason: 'precondition: credentials were delivered');
  }

  test('precondition: synced Argon2 rows store salt == ""', () async {
    await provisionWithOpenWindow();
    final u = (await p.userOn(p.client, 'cashier1'))!;
    expect(u.passwordHash, startsWith(r'$argon2'));
    expect(u.passwordSalt, isEmpty);
  });

  group('full sync / login-screen fallback', () {
    test('credential-less full sync after a wrong password keeps the hash',
        () async {
      await provisionWithOpenWindow();
      expect(await p.canLogin(p.client, 'cashier1', 'wrong-password'), isFalse);
      await p.syncUsersFull(); // window closed, tokenless
      expect(await p.canLogin(p.client, 'cashier1', kCashierInitialPw), isTrue);
      expect(await p.canLogin(p.client, 'acct1', kAccountantInitialPw), isTrue);
      expect(await p.canLogin(p.client, 'admin', kAdminCustomPw), isTrue);
    });

    test('repeating the credential-less sync is idempotent', () async {
      await provisionWithOpenWindow();
      final before = (await p.userOn(p.client, 'cashier1'))!;
      await p.syncUsersFull();
      await p.syncUsersFull();
      await p.syncUsersFull();
      final after = (await p.userOn(p.client, 'cashier1'))!;
      expect(after.passwordHash, before.passwordHash);
      expect(after.passwordSalt, before.passwordSalt);
      expect(after.forcePasswordChange, before.forcePasswordChange);
    });

    test('a credential-less sync does not wipe a device-local PIN', () async {
      await provisionWithOpenWindow();
      final id = (await p.userOn(p.client, 'cashier1'))!.id;
      await p.client.customStatement(
          "UPDATE users SET pin = 'local-pin-hash' WHERE id = ?", [id]);
      await p.syncUsersFull();
      expect((await p.userOn(p.client, 'cashier1'))!.pin, 'local-pin-hash');
    });

    test('credentials that ARE delivered later still replace the local hash '
        '(server stays the source of truth)', () async {
      await provisionWithOpenWindow();
      await p.host.updateUserPassword(userId: p.cashierId, newPassword: 'Rotated#Pass99');
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      expect(await p.canLogin(p.client, 'cashier1', 'Rotated#Pass99'), isTrue);
      expect(await p.canLogin(p.client, 'cashier1', kCashierInitialPw), isFalse);
    });

    test('a NEW user arriving without credentials gets an unusable credential '
        'and a forced change (SEC-004 unchanged)', () async {
      await provisionWithOpenWindow();
      await p.host.createUser(
          username: 'newbie',
          password: 'Newbie#Pass123',
          displayName: 'n',
          roleId: p.cashierRoleId);
      await p.syncUsersFull();
      final u = (await p.userOn(p.client, 'newbie'))!;
      expect(u.passwordHash, isNotEmpty);
      expect(u.forcePasswordChange, isTrue);
      expect(await p.canLogin(p.client, 'newbie', 'Newbie#Pass123'), isFalse);
      expect(await p.canLogin(p.client, 'newbie', 'newbie123'), isFalse);
      // The existing users are untouched by the same sync.
      expect(await p.canLogin(p.client, 'cashier1', kCashierInitialPw), isTrue);
    });
  });

  group('delta pull', () {
    test('credential-less delta rows keep the hash and do not re-flag the user',
        () async {
      await provisionWithOpenWindow();
      final rows = await p.syncUsersDelta(); // window closed
      expect(rows, isNotEmpty);
      expect(await p.canLogin(p.client, 'cashier1', kCashierInitialPw), isTrue);
      expect(await p.canLogin(p.client, 'admin', kAdminCustomPw), isTrue);
      final u = (await p.userOn(p.client, 'cashier1'))!;
      // The host flag (initial password, must change) is carried as sent; the
      // user is NOT locked out: the credential works so the change dialog opens.
      expect(u.forcePasswordChange && !await p.canLogin(p.client, 'cashier1', kCashierInitialPw), isFalse);
    });

    test('repeated credential-less delta pulls are idempotent', () async {
      await provisionWithOpenWindow();
      await p.syncUsersDelta();
      final once = (await p.userOn(p.client, 'acct1'))!.passwordHash;
      await p.syncUsersDelta();
      await p.syncUsersDelta();
      expect((await p.userOn(p.client, 'acct1'))!.passwordHash, once);
      expect(await p.canLogin(p.client, 'acct1', kAccountantInitialPw), isTrue);
    });

    test('interruption: a failed delta row does not damage other users',
        () async {
      await provisionWithOpenWindow();
      final rows = await p.syncUsersDelta();
      // A malformed row (no id) in the middle of a batch must not corrupt the
      // already-applied users.
      try {
        await p.client.customStatement('SELECT 1');
        await UserSyncStrategy(p.client).syncFromJson({
          'users': [
            {'id': p.cashierId, 'username': 'cashier1'},
            {'username': 'broken-row-without-id'},
          ]
        });
      } catch (_) {/* the malformed row aborts the batch — expected */}
      expect(rows, isNotEmpty);
      expect(await p.canLogin(p.client, 'cashier1', kCashierInitialPw), isTrue);
      expect(await p.canLogin(p.client, 'acct1', kAccountantInitialPw), isTrue);
    });
  });
}
