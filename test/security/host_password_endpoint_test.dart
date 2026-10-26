// ═══════════════════════════════════════════════════════════════════════════
// REPRO R5 / R6 — offline login policy on a paired device, and the
// force-password-change flow.
//
// All REPRO-R5-* / REPRO-R6-* tests of this file are now GREEN and were moved
// (users/login/sync plan P2 + P3, 2026-10-24):
//
//   CHAR-R5-a..h, REPRO-R5-f  -> test/unit/auth/offline_login_branch_device_test.dart
//   (R5-g admin follows the grace, REPRO-R5-e/notProvisioned, shadow/enforce)
//   REPRO-R6-a, CHAR-R6-a2    -> test/unit/sync/user_sync_stamps_and_force_flag_test.dart
//   REPRO-R6-b/d (change from the device reaches the host, not undone by sync)
//                              -> test/integration/online_login_lifecycle_test.dart
//   REPRO-R6-c/e/g            -> test/unit/auth/admin_user_ops_routing_test.dart
//
// What remains here is the one characterization that still documents HOST
// behaviour (the administrative endpoint) and needs no device.
// NOT registered in CI / structural lists on purpose.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter_test/flutter_test.dart';

import '../helpers/peer_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Peers p;

  setUp(() async => p = await createPeers());
  tearDown(() async {
    // updateUserPassword fires a password-collision scan without awaiting it
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await p.dispose();
  });

  test('CHAR-R6-f the host endpoint exists and works: POST '
      '/api/users/<id>/password (admin identity)', () async {
    final r = await p.hostRaw('POST', '/api/users/${p.cashierId}/password',
        userId: 1, body: {'password': 'Hostset#Pass456'});
    expect(r.statusCode, inInclusiveRange(200, 299),
        reason: await r.readAsString());
    expect(await p.canLogin(p.host, 'cashier1', 'Hostset#Pass456'), isTrue);
  });
}
