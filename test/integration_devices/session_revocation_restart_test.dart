// Integration review 2026-11-04, round 2 — INT-13: a revoked session stays
// revoked across a host restart.
//
// ApiSessionToken keeps its revocation lists in process memory. A restart of
// the main emptied them, so a web session that logged out, and every session
// of a user whose password changed or who was disabled (`revokeUser`),
// verified again until its `exp` (12 h; 30 days for pre-`iat` device tokens).
//
// "Restart" here is what a new process does to this state: the in-memory
// lists are gone (`clearRevokedForTesting`) and the server constructs a new
// `ApiHandler` over the same database. The file uses only APIs that predate
// the fix, so it compiles — and fails — on the pre-fix tree.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';

import '../helpers/lan_host_harness.dart';

/// Polls [done] for up to 5 s (the write-behind and the reload are async; on
/// the pre-fix tree the condition never holds and the assertions below fail).
Future<void> _until(Future<bool> Function() done) async {
  for (var i = 0; i < 100; i++) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}


void main() {
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    ApiSessionToken.setKeyForTesting('int13-restart-key');
    ApiSessionToken.clearRevokedForTesting();
  });

  test('a logged-out web session and a revoked user stay rejected after the '
      'host restarts on the same database', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get(); // open + seed before the clock
    ApiHandler(db); // server start

    final web = ApiSessionToken.mintWeb(5);
    final device = ApiSessionToken.mint(6);
    final claims = ApiSessionToken.verifyWeb(web)!;
    expect(ApiSessionToken.verify(device), 6);

    // Logout of the web session; password change / disable of user 6.
    ApiSessionToken.revokeSid(claims.sid, expiresAtMs: claims.expiresAtMs);
    ApiSessionToken.revokeUser(6);
    expect(ApiSessionToken.verifyWeb(web), isNull, reason: 'anchor');
    expect(ApiSessionToken.verify(device), isNull, reason: 'anchor');
    await _until(() async {
      final r = await db.customSelect(
        "SELECT value FROM settings WHERE key LIKE 'api_session_revocations%'",
      ).get();
      final v = r.isEmpty ? '' : '${r.first.data['value']}';
      return v.contains(claims.sid) && v.contains('"6"');
    });

    // Restart.
    ApiSessionToken.clearRevokedForTesting();
    expect(ApiSessionToken.verifyWeb(web), isNotNull,
        reason: 'anchor: the memory is really gone');
    ApiHandler(db);
    await _until(() async => ApiSessionToken.verifyWeb(web) == null);

    expect(ApiSessionToken.verifyWeb(web), isNull,
        reason: 'the logged-out web session verified again after a restart');
    expect(ApiSessionToken.verify(device), isNull,
        reason: "the revoked user's device session verified again after a "
            'restart');
    // A session minted AFTER the revocation is unaffected.
    await Future<void>.delayed(const Duration(milliseconds: 2));
    expect(ApiSessionToken.verify(ApiSessionToken.mint(6)), 6);
  });

  test('the stored revocations are host-local: GET /api/settings does not '
      'serve them', () async {
    final host = await LanHost.start();
    addTearDown(host.close);
    await HostFixture.seed(host.db);
    ApiSessionToken.revokeUser(77);
    Future<List<Object?>> stored() async => (await host.db.customSelect(
          "SELECT key FROM settings WHERE key LIKE 'api_session_revocations%'",
        ).get())
            .map((r) => r.data['key'])
            .toList();
    await _until(() async => (await stored()).isNotEmpty);
    expect(await stored(), hasLength(1),
        reason: 'the revocation is written to the host settings table');

    final d = LanDevice(host.direct, 'settings-reader', rolesFrom: host.db);
    addTearDown(d.dispose);
    final offer = await host.issue(kind: 'mirror');
    expect((await d.pair(offer.code)).status, 200);
    expect((await d.login('admin', kHostAdminPw)).status, 200);
    final r = await d.get('/api/settings');
    expect(r.status, 200, reason: '$r');
    final keys = (r.json['settings'] as Map).keys.map((k) => '$k');
    expect(keys, isNotEmpty, reason: 'anchor: settings are served');
    expect(keys.where((k) => k.startsWith('api_session_revocations')), isEmpty);
  });
}
