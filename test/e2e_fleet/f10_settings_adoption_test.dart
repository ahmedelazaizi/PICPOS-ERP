// F10 - SETTINGS ADOPTION: what the owner configured at the main (company,
// currency, business profile, tax, offline grace) arrives and is APPLIED on
// every device; per-device keys are never overwritten; secrets never travel.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io' show HttpOverrides;

import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';

import '../helpers/fleet_harness.dart';

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  setUp(() async => fleet = await Fleet.build());
  tearDown(() => fleet.dispose());

  const adopted = {
    'company_name': 'شركة الأسطول',
    'system_currency': 'JOD',
    'business_profile': 'retail',
    'business_type': 'retail',
    'tax_enabled': 'true',
    'tax_rate': '16.0',
    'offline_login_grace_days': '7',
  };

  test('F10.1 company / currency / profile / tax arrive from the main on '
      'every device after the first sync', () async {
    for (final d in fleet.devices) {
      for (final e in adopted.entries) {
        expect(await d.db.getSettingValue(e.key), e.value, reason: '${d.label}: ${e.key}');
      }
      expect(await d.db.getSettingValue('company_global_id'),
          await fleet.main.db.getSettingValue('company_global_id'),
          reason: '${d.label}: the same company identity');
    }
  });

  test('F10.2 per-device keys are never overwritten and secrets never '
      'travel', () async {
    for (final d in fleet.devices) {
      expect(await d.db.getSettingValue('network_mode'), d.isMirror ? 'mirror' : 'client',
          reason: '${d.label}: keeps its OWN mode, not the main\'s `server`');
      expect(await d.db.getSettingValue('setup_completed'), 'true');
      expect(await d.db.getSettingValue('admin_password_hash'), anyOf(isNull, isEmpty),
          reason: '${d.label}: no admin hash in settings');
      expect(await d.db.getSettingValue('developer_password_hash'), anyOf(isNull, isEmpty),
          reason: '${d.label}: no developer hash in settings');
    }
    // a later sync with a changed main does not clobber them either
    await fleet.login(fleet.cashier, 'cashier', kCashPw);
    await fleet.syncTables(fleet.cashier, ['settings']);
    expect(await fleet.cashier.db.getSettingValue('network_mode'), 'client');
  });

  test('F10.3 a change at the main (rename, currency, grace days) reaches the '
      'devices after a sync and is applied: the new grace governs offline login',
      () async {
    await fleet.main.db.setSetting('company_name', 'شركة الأسطول المحدّثة');
    await fleet.main.db.setSetting('system_currency', 'USD');
    await fleet.main.db.setSetting('offline_login_grace_days', '3');

    await fleet.login(fleet.cashier, 'cashier', kCashPw);
    await fleet.login(fleet.accountant, 'accountant', kAcctPw);
    for (final d in [fleet.cashier, fleet.accountant]) {
      expect(await d.db.getSettingValue('company_name'), 'شركة الأسطول', reason: 'before the sync');
      await fleet.syncTables(d, ['settings']);
      expect(await d.db.getSettingValue('company_name'), 'شركة الأسطول المحدّثة');
      expect(await d.db.getSettingValue('system_currency'), 'USD');
      expect(await d.db.getSettingValue('offline_login_grace_days'), '3');
    }

    // applied: with 3 grace days, day 4 offline is already refused
    await fleet.setGateMode(fleet.cashier, OfflineLoginMode.enforce);
    await fleet.mainDown();
    fleet.now = fleet.now.add(const Duration(days: 2));
    expect(await fleet.login(fleet.cashier, 'cashier', kCashPw), isNotNull);
    fleet.now = fleet.now.add(const Duration(days: 2));
    expect(await fleet.loginDenied(fleet.cashier, 'cashier', kCashPw), isTrue,
        reason: 'the adopted 3 day grace governs (the old 7 would still allow it)');
  });
}