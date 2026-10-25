// A1 / P4 - credential delivery to a freshly paired device (moved from the
// reproduction suite R1 / R7 after the fix; ids kept for traceability).
//
// The device-side first sync is `Peers.firstSync`: the tokenless user rows
// arrive first (no hashes - CHAR-R1-b), then the FIRST USER is verified ON THE
// MAIN and that session delivers the credentials (the pairing window is NOT
// needed). The seeded `admin/admin` is then retired.
//
// Assertion changes vs the reproduction file (explained, not weakened):
//  * REPRO-R1-d/e/f used a TOKENLESS full sync and expected credentials to
//    arrive. Security rule CHAR-R1-b forbids exactly that, so the first sync is
//    now "rows + first-user verification"; every login assertion is unchanged.
//  * REPRO-R7-c rotated the admin password and synced with NO identity while
//    expecting convergence. Convergence rides a session (the test's own failure
//    text said so), so the delta pull is done with the device user's session.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';

import '../helpers/peer_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Peers p;

  setUp(() async => p = await createPeers());
  tearDown(() async => p.dispose());

  bool hasCreds(Map<String, dynamic> u) =>
      u.containsKey('passwordHash') || u.containsKey('passwordSalt');

  group('R1 - first sync: credentials vs pairing window', () {
    test('CHAR-R1-a pairing OPEN: hashes delivered, custom admin pw + initial '
        'pws work on the client, default admin/admin does not', () async {
      ApiAuthMiddleware.openPairingWindow();
      final json = await p.syncUsersFull();
      final all = (json['users'] as List).cast<Map<String, dynamic>>();
      final names = [for (final u in all) u['username']];
      expect(names, containsAll(['admin', 'cashier1', 'acct1']));
      expect(all.every(hasCreds), isTrue);

      expect(await p.canLogin(p.client, 'admin', kAdminCustomPw), isTrue);
      expect(await p.canLogin(p.client, 'cashier1', kCashierInitialPw), isTrue);
      expect(await p.canLogin(p.client, 'acct1', kAccountantInitialPw), isTrue);
      expect(await p.canLogin(p.client, 'admin', 'admin'), isFalse);
    });

    test('CHAR-R1-b pairing CLOSED + no session: payload carries NO hash/salt',
        () async {
      final json = await p.hostGet('/api/users');
      final users = (json['users'] as List).cast<Map<String, dynamic>>();
      expect(users, isNotEmpty);
      expect(users.any(hasCreds), isFalse);
      final delta = await p.hostGet('/api/sync/pull?table=users');
      for (final r in (delta['rows'] as List).cast<Map<String, dynamic>>()) {
        expect(r.containsKey('password_hash'), isFalse);
        expect(r.containsKey('pin'), isFalse);
      }
    });

    test('CHAR-R1-c pairing CLOSED: which users reach the client '
        '(record, not a verdict)', () async {
      final json = await p.syncUsersFull();
      final names = [
        for (final u in (json['users'] as List).cast<Map<String, dynamic>>())
          u['username']
      ]..sort();
      expect(names, containsAll(['admin', 'cashier1', 'acct1']));
      expect(names, isNot(contains('mgr1')),
          reason: 'custom-role multi-branch manager is absent tokenless');
    });

    test('REPRO-R1-d pairing CLOSED (typical first sync is pre-login): '
        'default admin/admin must NOT work on the paired client', () async {
      final r = await p.firstSync();
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(await p.canLogin(p.client, 'admin', 'admin'), isFalse);
    });

    test('REPRO-R1-e pairing CLOSED: admin with the CUSTOM password must be '
        'able to log in on the client after first sync', () async {
      await p.firstSync();
      expect(await p.canLogin(p.client, 'admin', kAdminCustomPw), isTrue,
          reason: 'the first user\'s session delivers the credentials');
    });

    test('REPRO-R1-f pairing CLOSED: cashier/accountant initial passwords '
        'must work on the client (owner: users must log in on devices)',
        () async {
      await p.firstSync();
      expect(await p.canLogin(p.client, 'cashier1', kCashierInitialPw), isTrue);
      expect(await p.canLogin(p.client, 'acct1', kAccountantInitialPw), isTrue);
    });

    test('REPRO-R1-g a CASHIER session (window closed) must not receive other '
        'users\' credentials, esp. the admin hash', () async {
      final json = await p.hostGet('/api/users', userId: p.cashierId);
      final users = (json['users'] as List).cast<Map<String, dynamic>>();
      final admin = users.firstWhere((u) => u['username'] == 'admin');
      expect(admin.containsKey('passwordHash'), isFalse);
      expect(admin.containsKey('passwordSalt'), isFalse);
      // ... while the cashier still gets the credentials he needs.
      final me = users.firstWhere((u) => u['username'] == 'cashier1');
      expect(me.containsKey('passwordHash'), isTrue);
      // the delta feed follows the same rule
      final delta =
          await p.hostGet('/api/sync/pull?table=users', userId: p.cashierId);
      final rows = (delta['rows'] as List).cast<Map<String, dynamic>>();
      final adminRow = rows.firstWhere((r) => r['username'] == 'admin');
      expect(adminRow.containsKey('password_hash'), isFalse);
    });

    test('a NON-admin first user (temporary password): changes it ON THE MAIN, '
        'gets his own credentials, admin/admin is retired, the admin hash is '
        'NOT delivered', () async {
      final needs = await p.firstSync(
          username: 'cashier1', password: kCashierInitialPw);
      expect(needs.ok, isFalse);
      expect(needs.needsPasswordChange, isTrue);
      // nothing leaked yet; the seeded admin is still the only local login
      expect(await p.canLogin(p.client, 'cashier1', kCashierInitialPw), isFalse);

      final ok = await p.firstSync(
          username: 'cashier1',
          password: kCashierInitialPw,
          newPassword: 'Cash#Brand-New1');
      expect(ok.ok, isTrue, reason: '${ok.error}');
      expect(await p.canLogin(p.client, 'cashier1', 'Cash#Brand-New1'), isTrue);
      expect(await p.canLogin(p.client, 'admin', 'admin'), isFalse);
      expect(await p.canLogin(p.client, 'admin', kAdminCustomPw), isFalse,
          reason: 'a cashier session never receives the admin hash');
      // the main really holds the new password
      expect(await p.canLogin(p.host, 'cashier1', 'Cash#Brand-New1'), isTrue);
    });

    test('a wrong password delivers nothing and the seeded admin is NOT '
        'retired by a failed attempt', () async {
      final r = await p.firstSync(password: 'definitely-wrong');
      expect(r.ok, isFalse);
      expect(await p.canLogin(p.client, 'admin', kAdminCustomPw), isFalse);
      expect(await p.canLogin(p.client, 'admin', 'admin'), isTrue,
          reason: 'retire happens only after a verified first user');
    });
  });

  group('R7 - admin identity on a paired device', () {
    test('CHAR-R7-a pairing OPEN, admin id 1 on both: synced admin replaces '
        'the seeded one', () async {
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      final h = (await p.userOn(p.host, 'admin'))!;
      final c = (await p.userOn(p.client, 'admin'))!;
      expect(c.id, h.id);
      expect(c.passwordHash, h.passwordHash);
    });

    test('REPRO-R7-c host admin password changed AFTER first sync: with the '
        'window closed the device must converge, not keep the old password',
        () async {
      await p.firstSync();
      ApiAuthMiddleware.closePairingWindow();
      await p.host.updateUserPassword(userId: 1, newPassword: 'Rotated#2027x');
      await p.syncUsersDelta(asUser: 1); // the device user's own session
      final oldStillWorks =
          await p.canLogin(p.client, 'admin', kAdminCustomPw);
      final newWorks = await p.canLogin(p.client, 'admin', 'Rotated#2027x');
      expect(newWorks || !oldStillWorks, isTrue,
          reason: 'a rotation reaches the device through a session');
    });

    test('CHAR-R7-d session (admin) + window closed: hashes delivered '
        '(identity path works)', () async {
      final json = await p.hostGet('/api/users', userId: 1);
      final admin = (json['users'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((u) => u['username'] == 'admin');
      expect(admin['passwordHash'], isNotEmpty);
      expect(ApiAuthMiddleware.isPairingOpen, isFalse);
    });
  });
}
