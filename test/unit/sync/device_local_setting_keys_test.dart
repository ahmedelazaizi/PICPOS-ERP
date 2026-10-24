// P0 / A0: device-local setting keys.
//  * `login_lockouts_v1` — a terminal's lockout counters must never be pushed to
//    or overwritten from other devices (users/login/sync plan P0).
//  * The DeploymentModeCommitter's own keys (ADP-013, REPRO-R4-g) — a client
//    must not inherit the host's `server_setup_completed` / `last_committed_mode`.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/deployment/settings_keys.dart';
import 'package:picpos_erp/services/login_lockout_store.dart';
import 'package:picpos_erp/services/sync/strategies/setting_sync_strategy.dart';

void main() {
  test('every key owned by DeploymentModeCommitter is device-local', () {
    final leaking = [
      for (final k in DeploymentSettingsKeys.ownedKeys)
        if (!isDeviceLocalSettingKey(k)) k
    ];
    expect(leaking, isEmpty);
  });

  test('login lockout counters are device-local', () {
    expect(isDeviceLocalSettingKey(LoginLockoutStore.settingKey), isTrue);
    expect(LoginLockoutStore.settingKey, 'login_lockouts_v1');
  });

  test('negative: ordinary business settings still sync', () {
    expect(isDeviceLocalSettingKey('company_name'), isFalse);
    expect(isDeviceLocalSettingKey('offline_login_grace_days'), isFalse);
  });

  test('a host settings payload does not overwrite the adoption keys, lockouts '
      'or the mode, but still delivers business settings', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await db.setSetting('last_committed_mode', 'client');
    await db.setSetting('server_setup_completed', '');
    await db.setSetting('login_lockouts_v1', '{"local":1}');
    await SettingSyncStrategy(db).syncFromJson({
      'settings': {
        'last_committed_mode': 'server',
        'server_setup_completed': 'true',
        'standalone_setup_completed': 'true',
        'login_lockouts_v1': '{"host":2}',
        'company_name': 'HQ Co',
      }
    });
    expect(await db.getSettingValue('last_committed_mode'), 'client');
    expect(await db.getSettingValue('server_setup_completed'), '');
    expect(await db.getSettingValue('standalone_setup_completed'), isNull);
    expect(await db.getSettingValue('login_lockouts_v1'), '{"local":1}');
    expect(await db.getSettingValue('company_name'), 'HQ Co');
  });
}
