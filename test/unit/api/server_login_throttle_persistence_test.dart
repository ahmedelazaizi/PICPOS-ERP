// FLEET-6: the main's failed-login lockout survives a restart of the main.
// A "restart" = a new process on the SAME database: memory is gone, the
// `settings` row stays, and `configure` reloads it.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/api/server_login_throttle.dart';
import 'package:picpos_erp/services/sync/strategies/setting_sync_strategy.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await ServerLoginThrottle.restartForTesting();
    ServerLoginThrottle.configure(db);
    await ServerLoginThrottle.flush();
  });

  tearDown(() async {
    await ServerLoginThrottle.restartForTesting();
    await db.close();
  });

  Future<void> restart() async {
    await ServerLoginThrottle.restartForTesting();
    ServerLoginThrottle.configure(db);
    await ServerLoginThrottle.flush();
  }

  test('the setting key is host-local: never synced', () {
    expect(isDeviceLocalSettingKey(ServerLoginThrottle.settingKey), isTrue);
  });

  test('a lockout survives a restart (new throttle state, same database)',
      () async {
    for (var i = 0; i < ServerLoginThrottle.maxAttempts; i++) {
      ServerLoginThrottle.recordFailure('u:cashier');
    }
    expect(ServerLoginThrottle.isLockedOut('u:cashier'), isTrue);

    await restart();

    expect(ServerLoginThrottle.isLockedOut('u:cashier'), isTrue,
        reason: 'reloaded from ${ServerLoginThrottle.settingKey}');
    expect(ServerLoginThrottle.isLockedOut('u:other'), isFalse);
  });

  test('a partial failure count survives too, and one more failure locks',
      () async {
    for (var i = 0; i < ServerLoginThrottle.maxAttempts - 1; i++) {
      ServerLoginThrottle.recordFailure('u:a');
    }
    await restart();
    expect(ServerLoginThrottle.isLockedOut('u:a'), isFalse);
    ServerLoginThrottle.recordFailure('u:a');
    expect(ServerLoginThrottle.isLockedOut('u:a'), isTrue);
  });

  test('a successful login clears the stored counter', () async {
    for (var i = 0; i < ServerLoginThrottle.maxAttempts; i++) {
      ServerLoginThrottle.recordFailure('u:b');
    }
    ServerLoginThrottle.recordSuccess('u:b');
    await restart();
    expect(ServerLoginThrottle.isLockedOut('u:b'), isFalse);
  });

  test('entries older than the lockout window are not reloaded', () async {
    final old = DateTime.now()
        .subtract(ServerLoginThrottle.lockoutDuration + const Duration(minutes: 1))
        .millisecondsSinceEpoch;
    await db.setSetting(
        ServerLoginThrottle.settingKey,
        jsonEncode({
          'u:old': [ServerLoginThrottle.maxAttempts, old],
          'u:fresh': [
            ServerLoginThrottle.maxAttempts,
            DateTime.now().millisecondsSinceEpoch
          ],
        }));
    await restart();
    expect(ServerLoginThrottle.isLockedOut('u:old'), isFalse);
    expect(ServerLoginThrottle.isLockedOut('u:fresh'), isTrue);
  });

  test('the stored map is bounded and stale rows are dropped on write',
      () async {
    final old = DateTime.now()
        .subtract(ServerLoginThrottle.lockoutDuration + const Duration(minutes: 1))
        .millisecondsSinceEpoch;
    await db.setSetting(ServerLoginThrottle.settingKey,
        jsonEncode({'u:stale': [1, old]}));
    for (var i = 0; i < ServerLoginThrottle.maxEntries + 50; i++) {
      ServerLoginThrottle.recordFailure('u:$i');
    }
    await ServerLoginThrottle.flush();
    final stored = jsonDecode(
            (await db.getSettingValue(ServerLoginThrottle.settingKey))!)
        as Map<String, dynamic>;
    expect(stored.length, lessThanOrEqualTo(ServerLoginThrottle.maxEntries));
    expect(stored, isNot(contains('u:stale')));
  });

  test('corrupt stored state is ignored, not fatal', () async {
    await db.setSetting(ServerLoginThrottle.settingKey, '{not json');
    await restart();
    expect(ServerLoginThrottle.isLockedOut('u:x'), isFalse);
    ServerLoginThrottle.recordFailure('u:x');
    await ServerLoginThrottle.flush();
    expect(jsonDecode((await db.getSettingValue(ServerLoginThrottle.settingKey))!),
        isA<Map>());
  });
}
