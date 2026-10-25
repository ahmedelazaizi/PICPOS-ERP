// UserSyncStrategy / delta users merge (plan P2 + P3):
//  * the host's forcePasswordChange flag is COPIED (REPRO-R6-a; the delta path
//    already did it - CHAR-R6-a2);
//  * a credential the host delivered is stamped (src=sync) on branch devices
//    only; a pull without credentials never touches a stamp or a hash;
//  * a credential-delivering snapshot drops the stamp of local users it no
//    longer contains (the row stays: invoices reference it).
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';
import 'package:picpos_erp/services/sync/strategies/user_sync_strategy.dart';

import '../../helpers/mirror_peer_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Peers p;

  CredentialStampStore stamps() => CredentialStampStore.forDb(p.client);
  Future<Map<int, CredentialStamp>> all() => stamps().readAll();

  setUp(() async {
    p = await createPeers();
    CredentialStampStore.debugClock = () => DateTime.utc(2026, 10, 24, 12);
  });
  tearDown(() async {
    CredentialStampStore.debugClock = null;
    ApiAuthMiddleware.closePairingWindow();
    // updateUserPassword fires a password-collision scan without awaiting it
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await p.dispose();
  });

  group('forcePasswordChange', () {
    test('REPRO-R6-a: the host flag reaches the device in a full sync '
        '(payload carries it, the strategy copies it)', () async {
      ApiAuthMiddleware.openPairingWindow();
      final json = await p.syncUsersFull();
      final row = (json['users'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((u) => u['username'] == 'cashier1');
      expect(row['forcePasswordChange'], isTrue);
      expect((await p.userOn(p.client, 'cashier1'))!.forcePasswordChange, isTrue);
      expect((await p.userOn(p.client, 'acct1'))!.forcePasswordChange, isFalse);
    });

    test('also when the pull has NO credentials (the flag is not a secret)',
        () async {
      await p.syncUsersFull(); // window closed
      expect((await p.userOn(p.client, 'cashier1'))!.forcePasswordChange, isTrue);
    });

    test('the host clears the flag -> the next sync clears it on the device',
        () async {
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      await p.host.updateUserPassword(
          userId: p.cashierId, newPassword: 'Changed#Pass789');
      await p.syncUsersFull();
      final u = (await p.userOn(p.client, 'cashier1'))!;
      expect(u.forcePasswordChange, isFalse);
      expect(await p.canLogin(p.client, 'cashier1', 'Changed#Pass789'), isTrue);
    });

    test('an older host that does not send the key keeps the previous rule '
        '(only a credential-less NEW user is flagged)', () async {
      final json = await p.hostGet('/api/users');
      for (final u in (json['users'] as List).cast<Map<String, dynamic>>()) {
        u.remove('forcePasswordChange');
      }
      await UserSyncStrategy(p.client).syncFromJson(json);
      expect((await p.userOn(p.client, 'cashier1'))!.forcePasswordChange, isTrue,
          reason: 'new credential-less user: unusable + flagged');
      ApiAuthMiddleware.openPairingWindow();
      final withCreds = await p.hostGet('/api/users');
      for (final u in (withCreds['users'] as List).cast<Map<String, dynamic>>()) {
        u.remove('forcePasswordChange');
      }
      await UserSyncStrategy(p.client).syncFromJson(withCreds);
      expect((await p.userOn(p.client, 'cashier1'))!.forcePasswordChange, isTrue,
          reason: 'absent key = no change');
    });

    test('CHAR-R6-a2: the delta pull path carries the flag too', () async {
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      await p.syncUsersDelta();
      expect((await p.userOn(p.client, 'cashier1'))!.forcePasswordChange, isTrue);
    });
  });

  group('stamps are written only where a credential was DELIVERED', () {
    test('branch device, credentials delivered: one sync stamp per delivered '
        'user, bound to the delivered hash', () async {
      p.asClient();
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      final s = await all();
      for (final name in ['admin', 'cashier1', 'acct1']) {
        final u = (await p.userOn(p.client, name))!;
        expect(s[u.id]!.src, StampSource.sync, reason: name);
        expect(s[u.id]!.fp, credentialFingerprint(u.passwordHash), reason: name);
      }
    });

    test('REPRO-R2 rule kept: a pull WITHOUT credentials writes no stamp and '
        'never wipes the delivered hash or its stamp', () async {
      p.asClient();
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      ApiAuthMiddleware.closePairingWindow();
      final before = await all();
      final hash = (await p.userOn(p.client, 'acct1'))!.passwordHash;
      await p.syncUsersFull(); // rows only
      await p.syncUsersDelta();
      expect((await p.userOn(p.client, 'acct1'))!.passwordHash, hash);
      expect(await all(), before);
    });

    test('standalone / main device: the same sync writes NO stamp (B.8)',
        () async {
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      expect(await all(), isEmpty);
      expect(await p.client.getSettingValue(CredentialStampStore.bootstrappedKey), isNull);
    });

    test('delta pull with credentials stamps on a branch device only',
        () async {
      p.asClient();
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersDelta();
      expect((await all()).length, greaterThanOrEqualTo(3));
      for (final s in (await all()).values) {
        expect(s.src, StampSource.sync);
      }
      SyncInterceptor.instance = null;
      await stamps().revoke(1);
      await p.syncUsersDelta();
      expect((await all()).containsKey(1), isFalse,
          reason: 'not a branch device any more: nothing stamped');
    });

    test('the host changes a password -> the next credential-bearing sync '
        'replaces the stamp (new hash, new clock)', () async {
      p.asClient();
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      final old = (await all())[p.accountantId]!;
      await p.host.updateUserPassword(userId: p.accountantId, newPassword: 'Rotated#Pw123');
      await p.syncUsersFull();
      final now = (await all())[p.accountantId]!;
      expect(now.fp, isNot(old.fp));
      expect(await p.canLogin(p.client, 'acct1', 'Rotated#Pw123'), isTrue);
    });
  });

  group('snapshot reconciliation', () {
    test('a credential-delivering snapshot drops the stamp of a local user '
        'it no longer contains; the ROW stays', () async {
      p.asClient();
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      expect((await all()).containsKey(p.accountantId), isTrue);
      // the main removed acct1 from this device's scope
      final json = await p.hostGet('/api/users');
      (json['users'] as List).removeWhere((u) => (u as Map)['username'] == 'acct1');
      await UserSyncStrategy(p.client).syncFromJson(json);
      expect((await all()).containsKey(p.accountantId), isFalse);
      expect(await p.userOn(p.client, 'acct1'), isNotNull,
          reason: 'invoices reference the row');
      expect((await all()).containsKey(p.cashierId), isTrue);
    });

    test('a snapshot WITHOUT credentials does not reconcile anything',
        () async {
      p.asClient();
      ApiAuthMiddleware.openPairingWindow();
      await p.syncUsersFull();
      ApiAuthMiddleware.closePairingWindow();
      final json = await p.hostGet('/api/users');
      (json['users'] as List).removeWhere((u) => (u as Map)['username'] == 'acct1');
      await UserSyncStrategy(p.client).syncFromJson(json);
      expect((await all()).containsKey(p.accountantId), isTrue);
    });
  });
}
