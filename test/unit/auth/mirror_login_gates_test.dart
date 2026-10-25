// MIR-002 / MIR-020 (plan P0): a MIRROR device must get the same login-time
// recovery as a client, and must not run the boot-time admin heal.
//
//  * login: "local auth failed -> ask the host (B.6.3)" lives in the session gate
//    (client AND mirror); the post-login refresh of role / defaultScreen /
//    permissions in login_screen runs for client AND mirror;
//  * main.dart: `_bootTimeAdminHeal` (resets admin to admin/admin when the hash
//    is structurally corrupt) is skipped on client AND mirror — the credentials
//    there are host-authoritative;
//  * a mirror boot pull before login (no session, window closed) never erases
//    the mirror's credentials (CRED-WIPE).
//
// Static-source checks are anchored on the guard expression itself, so a
// refactor of the guard (not of surrounding lines) is what they pin.
// Promoted from test/repro_mirror (REPRO-R3-e/f/g/k).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';

import '../../helpers/mirror_peer_harness.dart';

String _lineWith(String file, Pattern anchor) {
  final lines = File(file).readAsLinesSync();
  final i = lines.indexWhere((l) => l.contains(anchor));
  expect(i, greaterThanOrEqualTo(0), reason: 'guard not found in $file');
  return lines[i];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('static guards', () {
    const login = 'lib/presentation/screens/login_screen.dart';

    test('the "unknown user -> ask the main" fallback (plan P2, B.6.3) lives in '
        'the gate and covers client AND mirror (SyncInterceptor.isClientMode)', () {
      const gate = 'lib/data/repositories/auth_session_gate.dart';
      final src = File(gate).readAsStringSync();
      final body = src.substring(src.indexOf('Future<UserWithRole?> verifyViaMain'));
      expect(body.substring(0, 700), contains('SyncInterceptor.isClientMode'));
      expect(src, isNot(contains('NetworkService.instance.isClient')));
    });

    test('post-login refresh covers mirror', () {
      final l = _lineWith(login, 'user != null && (NetworkService.instance.isClient');
      expect(l, contains('NetworkService.instance.isMirror'));
    });

    test('the login screen runs no users/full sync on a typo at all (that pull '
        'was the CRED-WIPE trigger)', () {
      final src = File(login).readAsStringSync();
      expect(src, isNot(contains('performFullSync')));
      expect(src, isNot(contains("performTableSync(serverUrl, 'users')\n")));
    });

    test('boot-time admin heal is skipped on client and mirror', () {
      final l = _lineWith('lib/main.dart',
          'if (!NetworkService.instance.isClient &&');
      expect(l, contains('!NetworkService.instance.isMirror'));
      expect(File('lib/main.dart').readAsStringSync(),
          contains('await _bootTimeAdminHeal(sharedDb);'));
    });
  });

  group('mirror boot pull (needs the peer harness)', () {
    late Peers p;
    setUp(() async => p = await createPeers());
    tearDown(() async => p.dispose());

    test('users re-delivered tokenless before login do not erase the mirror '
        'credentials (admin AND the Argon2 cashier)', () async {
      p.asMirror();
      await p.syncUsersFull(asUser: 1); // pairing flow: admin token -> hashes
      expect(await p.canLogin(p.client, 'mgr1', kManagerPw), isTrue);
      ApiAuthMiddleware.closePairingWindow();
      await p.syncUsersFull(); // boot: no session, window closed
      await p.syncUsersDelta();
      expect(await p.canLogin(p.client, 'cashier1', kCashierInitialPw), isTrue);
      expect(await p.canLogin(p.client, 'acct1', kAccountantInitialPw), isTrue);
      expect(await p.canLogin(p.client, 'admin', kAdminCustomPw), isTrue);
      expect(await p.canLogin(p.client, 'mgr1', kManagerPw), isTrue);
    });
  });
}
