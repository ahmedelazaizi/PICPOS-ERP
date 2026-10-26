// Login leftover #1 (unit side): the shadow log that tells the owner what
// `enforce` would refuse, the "N days left" standing that drives the banner,
// and the gate writing the log. Injected clocks; no network.
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';
import 'package:picpos_erp/services/auth/offline_login_standing.dart';
import 'package:picpos_erp/services/auth/shadow_login_log.dart';
import 'package:picpos_erp/services/sync/strategies/setting_sync_strategy.dart';

class _MemStore implements OfflineLoginStore {
  String? v;
  @override
  Future<String?> read() async => v;
  @override
  Future<void> write(String json) async => v = json;
}

class _MemBacking implements StampBacking {
  final m = <String, String>{};
  @override
  Future<String?> read(String key) async => m[key];
  @override
  Future<void> write(String key, String value) async => m[key] = value;
}

OfflineLoginVerdict _v(OfflineLoginDecision d,
        {DateTime? at, int grace = 7}) =>
    OfflineLoginVerdict(d, graceDays: grace, lastVerified: at);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('standingOf (pure)', () {
    final now = DateTime.utc(2026, 10, 24, 12);

    test('plenty of time: hidden', () {
      final s = standingOf(
          _v(OfflineLoginDecision.allowed, at: now.subtract(const Duration(days: 2))),
          now);
      expect(s.kind, OfflineStandingKind.hidden);
    });

    test('exactly 2 days left: warns with 2', () {
      final s = standingOf(
          _v(OfflineLoginDecision.allowed, at: now.subtract(const Duration(days: 5))),
          now);
      expect(s.kind, OfflineStandingKind.expiring);
      expect(s.daysLeft, 2);
    });

    test('one day and a bit left rounds UP to 2; hours left count as 1', () {
      expect(
          standingOf(
                  _v(OfflineLoginDecision.allowed,
                      at: now.subtract(const Duration(days: 5, hours: 12))),
                  now)
              .daysLeft,
          2);
      final last = standingOf(
          _v(OfflineLoginDecision.allowed,
              at: now.subtract(const Duration(days: 6, hours: 20))),
          now);
      expect(last.kind, OfflineStandingKind.expiring);
      expect(last.daysLeft, 1);
    });

    test('just past the grace: expired (even if the policy said allowed)', () {
      final s = standingOf(
          _v(OfflineLoginDecision.allowed,
              at: now.subtract(const Duration(days: 7, minutes: 1))),
          now);
      expect(s.kind, OfflineStandingKind.expired);
      expect(s.daysLeft, 0);
    });

    test('policy expired / clock rolled back: expired', () {
      expect(standingOf(_v(OfflineLoginDecision.expired), now).kind,
          OfflineStandingKind.expired);
      expect(standingOf(_v(OfflineLoginDecision.clockRolledBack), now).kind,
          OfflineStandingKind.expired);
    });

    test('never delivered / hash changed / rejected: no countdown', () {
      for (final d in [
        OfflineLoginDecision.notProvisioned,
        OfflineLoginDecision.credentialChanged,
        OfflineLoginDecision.rejectedByMain,
      ]) {
        expect(standingOf(_v(d), now).kind, OfflineStandingKind.hidden, reason: '$d');
      }
    });

    test('a custom grace (3 days) warns from day one', () {
      final s = standingOf(
          _v(OfflineLoginDecision.allowed,
              at: now.subtract(const Duration(days: 1)), grace: 3),
          now);
      expect(s.kind, OfflineStandingKind.expiring);
      expect(s.daysLeft, 2);
    });
  });

  group('policy.standing() uses the real stamps and the injected clock', () {
    late DateTime now;
    late CredentialStampStore stamps;
    late OfflineLoginPolicy policy;
    const hash = r'$argon2id$v=19$m=1,t=1,p=1$c$h';

    setUp(() {
      now = DateTime.utc(2026, 10, 24, 12);
      stamps = CredentialStampStore(_MemBacking(), clock: () => now);
      policy = OfflineLoginPolicy(
        store: _MemStore(),
        stamps: stamps,
        readGraceDays: () async => null,
        clock: () => now,
      );
    });

    test('a stamp 6 days old: 1 day left; 8 days old: expired; fresh: hidden',
        () async {
      await stamps.stampFromSync(7, hash, serverTime: now);
      expect((await policy.standing(7, passwordHash: hash)).kind,
          OfflineStandingKind.hidden);

      now = now.add(const Duration(days: 6));
      final s = await policy.standing(7, passwordHash: hash);
      expect(s.kind, OfflineStandingKind.expiring);
      expect(s.daysLeft, 1);

      now = now.add(const Duration(days: 2));
      expect((await policy.standing(7, passwordHash: hash)).kind,
          OfflineStandingKind.expired);
    });

    test('renewing with the main (session) restarts the countdown', () async {
      await stamps.stampFromSync(7, hash, serverTime: now);
      now = now.add(const Duration(days: 6));
      expect((await policy.standing(7, passwordHash: hash)).visible, isTrue);
      await policy.recordVerified(7, passwordHash: hash);
      expect((await policy.standing(7, passwordHash: hash)).visible, isFalse);
    });
  });

  group('ShadowLoginLog', () {
    late AppDatabase db;
    late DateTime now;
    late ShadowLoginLog log;

    setUp(() async {
      DiagnosticLogger.enableTestMode();
      db = AppDatabase.forTesting();
      await db.getBranches();
      now = DateTime.utc(2026, 10, 24, 12);
      log = ShadowLoginLog(db, clock: () => now);
    });
    tearDown(() async => db.close());

    test('summarises what enforce would refuse, per decision and account',
        () async {
      await log.record(OfflineLoginDecision.notProvisioned, 2);
      await log.record(OfflineLoginDecision.notProvisioned, 2);
      await log.record(OfflineLoginDecision.credentialChanged, 3);
      await log.record(OfflineLoginDecision.allowed, 9); // ignored

      final s = await log.summary(days: 30);
      expect(s.total, 3);
      expect(s.accounts, 2);
      expect(s.byDecision[OfflineLoginDecision.notProvisioned], 2);
      expect(s.byDecision[OfflineLoginDecision.credentialChanged], 1);
      expect(s.isClean, isFalse);
    });

    test('only the last N days count', () async {
      await log.record(OfflineLoginDecision.notProvisioned, 2);
      now = now.add(const Duration(days: 10));
      await log.record(OfflineLoginDecision.credentialChanged, 3);

      expect((await log.summary(days: 7)).total, 1);
      expect((await log.summary(days: 30)).total, 2);
    });

    test('bounded: at most maxEntries, newest kept; entries past retention '
        'are dropped', () async {
      await log.record(OfflineLoginDecision.notProvisioned, 1);
      now = now.add(ShadowLoginLog.retention + const Duration(days: 1));
      for (var i = 0; i < ShadowLoginLog.maxEntries + 25; i++) {
        await log.record(OfflineLoginDecision.credentialChanged, i);
      }
      final s = await log.summary(days: 365);
      expect(s.total, ShadowLoginLog.maxEntries);
      expect(s.byDecision.containsKey(OfflineLoginDecision.notProvisioned),
          isFalse);
    });

    test('empty / garbage storage is a clean summary, never an exception',
        () async {
      expect((await log.summary()).isClean, isTrue);
      await db.setSetting(ShadowLoginLog.settingKey, '{not json');
      expect((await log.summary()).isClean, isTrue);
      await log.record(OfflineLoginDecision.notProvisioned, 1);
      expect((await log.summary()).total, 1);
    });

    test('clear() empties it', () async {
      await log.record(OfflineLoginDecision.notProvisioned, 1);
      await log.clear();
      expect((await log.summary()).isClean, isTrue);
    });

    test('the log key is device-local (never synced between devices)', () {
      expect(kDeviceLocalSettingKeys, contains(ShadowLoginLog.settingKey));
      expect(kDeviceLocalSettingKeys, contains(OfflineLoginMode.settingKey));
    });
  });
}
