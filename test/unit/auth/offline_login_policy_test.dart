// OfflineLoginPolicy (plan P3): decisions come from credential stamps bound to
// the hash; grace is counted from the stamp; clock rollback is caught by two
// independent stores; `neverVerified` no longer exists (-> notProvisioned).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';

import 'stamp_test_support.dart';

void main() {
  late MemSecure secure;
  late MemBacking backing;
  late DateTime now;
  int? grace;

  OfflineLoginPolicy make() => OfflineLoginPolicy(
        store: secure,
        stamps: CredentialStampStore(backing, clock: () => now),
        readGraceDays: () async => grace,
        clock: () => now,
      );

  setUp(() {
    secure = MemSecure();
    backing = MemBacking();
    now = DateTime.utc(2026, 10, 1, 9);
    grace = 7;
  });

  const hashA = r'$argon2id$v=19$m=19456,t=2,p=1$aaaa$bbbb';

  test('inside the grace -> allowed, after it -> expired (7 days)', () async {
    final p = make();
    await p.recordVerified(12, passwordHash: hashA);
    now = now.add(const Duration(days: 6, hours: 23));
    expect((await p.check(12, passwordHash: hashA)).decision,
        OfflineLoginDecision.allowed);
    now = now.add(const Duration(hours: 2));
    final v = await p.check(12, passwordHash: hashA);
    expect(v.decision, OfflineLoginDecision.expired);
    expect(v.graceDays, 7);
  });

  test('a new verification starts a new period', () async {
    final p = make();
    await p.recordVerified(12, passwordHash: hashA);
    now = now.add(const Duration(days: 8));
    expect((await p.check(12, passwordHash: hashA)).decision,
        OfflineLoginDecision.expired);
    await p.recordVerified(12, passwordHash: hashA);
    now = now.add(const Duration(days: 3));
    expect((await p.check(12, passwordHash: hashA)).allowed, isTrue);
  });

  test('grace is configurable (1..365), defaults to 7', () async {
    final p = make();
    await p.recordVerified(5, passwordHash: hashA);
    grace = 1;
    now = now.add(const Duration(days: 2));
    expect((await p.check(5, passwordHash: hashA)).decision,
        OfflineLoginDecision.expired);
    grace = null;
    expect((await p.check(5, passwordHash: hashA)).graceDays, 7);
    grace = 9999;
    expect((await p.check(5, passwordHash: hashA)).graceDays,
        OfflineLoginPolicy.maxGraceDays);
    grace = 0;
    expect((await p.check(5, passwordHash: hashA)).graceDays, 7);
  });

  test('rolling the device clock back is rejected (10 min tolerance)', () async {
    final p = make();
    await p.recordVerified(12, passwordHash: hashA);
    now = now.add(const Duration(days: 5));
    expect((await p.check(12, passwordHash: hashA)).allowed, isTrue);
    now = now.subtract(const Duration(days: 4));
    expect((await p.check(12, passwordHash: hashA)).decision,
        OfflineLoginDecision.clockRolledBack);
    now = now.add(const Duration(days: 4)).subtract(const Duration(minutes: 5));
    expect((await p.check(12, passwordHash: hashA)).allowed, isTrue,
        reason: 'within tolerance');
  });

  test('max-seen lives in TWO stores: clearing either one keeps the protection',
      () async {
    final p = make();
    await p.recordVerified(12, passwordHash: hashA);
    now = now.add(const Duration(days: 5));
    await p.check(12, passwordHash: hashA); // both stores now know "day 5"
    final secureCopy = secure.json;
    now = now.subtract(const Duration(days: 4));

    secure.json = null; // secure storage wiped
    expect((await make().check(12, passwordHash: hashA)).decision,
        OfflineLoginDecision.clockRolledBack,
        reason: 'the device-local setting still knows');

    secure.json = secureCopy; // restored; now the setting is wiped instead
    backing.values.remove(CredentialStampStore.maxSeenKey);
    expect((await make().check(12, passwordHash: hashA)).decision,
        OfflineLoginDecision.clockRolledBack,
        reason: 'the secure copy still knows');
  });
  test('a stamp dated in the future is a rollback signal', () async {
    final p = make();
    await p.recordVerified(12, passwordHash: hashA);
    now = now.subtract(const Duration(hours: 1));
    expect((await p.check(12, passwordHash: hashA)).decision,
        OfflineLoginDecision.clockRolledBack);
  });

  test('no stamp -> notProvisioned (never a free pass), and another user\'s '
      'stamp does not count', () async {
    final p = make();
    await p.recordVerified(12, passwordHash: hashA);
    final v = await p.check(99, passwordHash: hashA);
    expect(v.decision, OfflineLoginDecision.notProvisioned);
    expect(v.allowed, isFalse);
  });

  test('a stamp copied onto another user id does not match its hash',
      () async {
    final p = make();
    await p.recordVerified(12, passwordHash: hashA);
    final s = CredentialStampStore(backing, clock: () => now);
    final all = await s.readAll();
    backing.values[CredentialStampStore.stampsKey] =
        '{"12":${_j(all[12]!)},"13":${_j(all[12]!)}}';
    expect(
        (await make().check(13, passwordHash: r'$argon2id$v=19$m=1,t=1,p=1$x$y'))
            .decision,
        OfflineLoginDecision.credentialChanged);
  });

  test('stamp bound to a hash: another hash -> credentialChanged', () async {
    final p = make();
    await p.recordVerified(12, passwordHash: hashA);
    expect((await p.check(12, passwordHash: '${hashA}x')).decision,
        OfflineLoginDecision.credentialChanged);
  });

  test('the main\'s explicit "no" survives going offline', () async {
    final stamps = CredentialStampStore(backing, clock: () => now);
    await stamps.markRejected(12, hashA);
    final v = await make().check(12, passwordHash: hashA);
    expect(v.decision, OfflineLoginDecision.rejectedByMain);
    expect(v.rejectedIn(OfflineLoginMode.shadow), isTrue,
        reason: 'binding in both modes');
    // a fresh hash delivered later is a different credential
    expect((await make().check(12, passwordHash: '${hashA}2')).decision,
        OfflineLoginDecision.credentialChanged);
  });

  test('legacy secure-storage verification is adopted once as a session stamp',
      () async {
    secure.json = '{"12":"${now.toUtc().toIso8601String()}"}';
    final p = make();
    expect((await p.check(12, passwordHash: hashA)).allowed, isTrue);
    expect((await CredentialStampStore(backing).read(12))!.src,
        StampSource.session);
  });

  test('corrupt or unreadable stamp storage: corrupt = no stamps, '
      'unreadable = notProvisioned', () async {
    backing.values[CredentialStampStore.stampsKey] = '{not json';
    expect((await make().check(1, passwordHash: hashA)).decision,
        OfflineLoginDecision.notProvisioned);
    backing.failing = true;
    expect((await make().check(1, passwordHash: hashA)).decision,
        OfflineLoginDecision.notProvisioned);
  });

  test('which decisions each mode rejects', () {
    for (final d in OfflineLoginDecision.values) {
      final v = OfflineLoginVerdict(d, graceDays: 7);
      final hard = {
        OfflineLoginDecision.expired,
        OfflineLoginDecision.clockRolledBack,
        OfflineLoginDecision.rejectedByMain,
      }.contains(d);
      expect(v.rejectedIn(OfflineLoginMode.enforce), d != OfflineLoginDecision.allowed,
          reason: d.name);
      expect(v.rejectedIn(OfflineLoginMode.shadow), hard, reason: d.name);
    }
  });

  test('the mode setting parses defensively; default is shadow', () {
    expect(OfflineLoginMode.parse(null), OfflineLoginMode.shadow);
    expect(OfflineLoginMode.parse('garbage'), OfflineLoginMode.shadow);
    expect(OfflineLoginMode.parse(' ENFORCE '), OfflineLoginMode.enforce);
  });

  test('every login path goes through the session gate (source guard)', () {
    final src = File('lib/data/repositories/auth_repository_impl.dart')
        .readAsStringSync();
    expect('_acquireServerSession('.allMatches(src).length, greaterThanOrEqualTo(4));
    expect(src, contains('_gate.afterLocalSuccess('));
    expect(src, contains("'offline_login_grace_days'"));
    expect(src, isNot(contains('neverVerified')));
  });
}

String _j(CredentialStamp s) =>
    '{"at":"${s.at.toUtc().toIso8601String()}","fp":"${s.fp}","src":"${s.src.name}"}';
