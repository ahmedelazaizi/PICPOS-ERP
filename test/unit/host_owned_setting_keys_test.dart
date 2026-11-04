// S-01: host-owned settings can't be written via POST /api/settings or sync.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_data_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';
import 'package:picpos_erp/services/sync/host_owned_setting_keys.dart';
import 'package:picpos_erp/services/sync/strategies/setting_sync_strategy.dart';

void main() {
  late AppDatabase db;
  late ApiDataHandler handler;
  late int adminId;

  setUp(() async {
    db = AppDatabase.forTesting();
    handler = ApiDataHandler(db, {});
    adminId = (await (db.select(db.users)
              ..where((u) => u.username.equals('admin')))
            .getSingle())
        .id;
  });
  tearDown(() async => db.close());

  Request post(Map<String, dynamic> body) => Request(
        'POST',
        Uri.parse('http://localhost:8080/api/settings'),
        body: jsonEncode(body),
        context: {ApiUserCtx.userIdKey: adminId},
      );

  test('list covers the report keys', () {
    for (final k in const [
      'lan_legacy_token_enabled',
      'lan_legacy_transition_started_at',
      'lan_legacy_transition_days',
      'lan_legacy_transition_ended',
      'trial_policy',
      'install_date',
      'license_key',
      'admin_password_customized',
      'table_bill_legacy_accepted',
    ]) {
      expect(isHostOwnedSettingKey(k), isTrue, reason: k);
    }
    expect(isHostOwnedSettingKey('company_name'), isFalse);
  });

  test('API rejects host-owned keys, saves the others', () async {
    await db.setSetting('lan_legacy_token_enabled', 'false');
    final res = await handler.postSettings(post({
      'lan_legacy_token_enabled': 'true',
      'lan_legacy_transition_days': '3650',
      'trial_policy': 'x',
      'install_date': '2000-01-01',
      'company_name': 'Acme',
    }));
    final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(res.statusCode, 200);
    expect(body['saved'], 1);
    expect(body['blocked'], containsAll([
      'lan_legacy_token_enabled',
      'lan_legacy_transition_days',
      'trial_policy',
      'install_date',
    ]));
    expect(await db.getSettingValue('lan_legacy_token_enabled'), 'false');
    expect(await db.getSettingValue('lan_legacy_transition_days'), isNull);
    expect(await db.getSettingValue('trial_policy'), isNull);
    expect(await db.getSettingValue('company_name'), 'Acme');
  });

  test('internal db.setSetting still writes host-owned keys', () async {
    await db.setSetting('lan_legacy_token_enabled', 'true');
    expect(await db.getSettingValue('lan_legacy_token_enabled'), 'true');
  });

  test('sync ignores host-owned keys but applies business settings', () async {
    await db.setSetting('lan_legacy_token_enabled', 'false');
    await SettingSyncStrategy(db).syncFromJson({
      'settings': {
        'lan_legacy_token_enabled': 'true',
        'license_key': 'forged',
        'company_name': 'FromHost',
      },
    });
    expect(await db.getSettingValue('lan_legacy_token_enabled'), 'false');
    expect(await db.getSettingValue('license_key'), isNull);
    expect(await db.getSettingValue('company_name'), 'FromHost');
  });
}
