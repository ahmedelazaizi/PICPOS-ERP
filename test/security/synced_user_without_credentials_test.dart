// SEC-004 (audit 2026-10-23): a user row that arrives from the host WITHOUT
// credentials must never get the guessable `<username>123` password.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/strategies/user_sync_strategy.dart';
import 'package:picpos_erp/services/unusable_credential.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  test('credential-less synced user cannot log in with <username>123',
      () async {
    await UserSyncStrategy(db).syncFromJson({
      'users': [
        {
          'id': 77,
          'username': 'ahmed',
          'displayName': 'Ahmed',
          'roleId': 1,
          'isActive': true,
          'isLocked': false,
        }
      ]
    });

    final row = await (db.select(db.users)..where((u) => u.id.equals(77)))
        .getSingle();
    expect(row.forcePasswordChange, isTrue, reason: 'still flagged');
    expect(await db.authenticateUser('ahmed', 'ahmed123'), isNull);
    expect(await db.authenticateUser('ahmed', 'Ahmed123'), isNull);
    expect(await db.authenticateUser('ahmed', ''), isNull);
  });

  test('UnusableCredential mints distinct random secrets', () async {
    final a = await UnusableCredential.mint();
    final b = await UnusableCredential.mint();
    expect(a.hash, isNot(b.hash));
    expect(a.hash, startsWith(r'$argon2'));
  });

  test('no code path mints <username>123 any more', () {
    for (final f in [
      'lib/services/delta_pull_service.dart',
      'lib/services/sync/strategies/user_sync_strategy.dart',
    ]) {
      expect(File(f).readAsStringSync().contains(r'${username}123'), isFalse,
          reason: f);
    }
  });
}
