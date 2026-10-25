// CredentialStampStore (plan P3 / B.3): the per-user stamp bound to the hash.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';

import 'stamp_test_support.dart';

void main() {
  late MemBacking backing;
  late DateTime now;
  CredentialStampStore store() =>
      CredentialStampStore(backing, clock: () => now);

  const h1 = r'$argon2id$v=19$m=19456,t=2,p=1$s1$h1';
  const h2 = r'$argon2id$v=19$m=19456,t=2,p=1$s2$h2';

  setUp(() {
    backing = MemBacking();
    now = DateTime.utc(2026, 10, 24, 12);
  });

  test('fingerprint = first 16 hex of sha256(hash); stable and hash-specific', () {
    final fp = credentialFingerprint(h1);
    expect(fp, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(credentialFingerprint(h1), fp);
    expect(credentialFingerprint(h2), isNot(fp));
  });

  test('stored format: {"<userId>": {"at": iso-utc, "fp": 16hex, "src": ...}} '
      'under offline_cred_stamps_v1', () async {
    await store().stampFromSync(7, h1);
    final raw = backing.values['offline_cred_stamps_v1']!;
    expect(raw, contains('"7":{"at":"2026-10-24T12:00:00.000Z"'));
    expect(raw, contains('"fp":"${credentialFingerprint(h1)}"'));
    expect(raw, contains('"src":"sync"'));
  });

  test('stamping again with the same hash is idempotent and never moves '
      '`at` backwards (clock rollback cannot shorten or extend)', () async {
    await store().stampFromSync(7, h1);
    now = now.add(const Duration(days: 2));
    await store().stampFromSync(7, h1);
    final later = (await store().read(7))!;
    expect(later.at, now);
    now = now.subtract(const Duration(days: 1));
    await store().stampSession(7, h1);
    expect((await store().read(7))!.at, later.at);
    expect((await store().readAll()).length, 1);
  });

  test('a different hash replaces the stamp (new credential, new clock)',
      () async {
    await store().stampFromSync(7, h1);
    now = now.add(const Duration(days: 1));
    await store().stampSession(7, h2);
    final s = (await store().read(7))!;
    expect(s.fp, credentialFingerprint(h2));
    expect(s.src, StampSource.session);
  });

  test('server time is used only when it is within the 10 min tolerance of the '
      'device clock (a skewed clock must not lock or extend anyone)', () async {
    await store().stampFromSync(1, h1,
        serverTime: now.add(const Duration(minutes: 4)));
    expect((await store().read(1))!.at, now.add(const Duration(minutes: 4)));
    await store().stampFromSync(2, h1,
        serverTime: now.add(const Duration(hours: 5)));
    expect((await store().read(2))!.at, now, reason: 'skew > 10 min: device clock');
    await store().stampFromSync(3, h1,
        serverTime: now.subtract(const Duration(days: 9)));
    expect((await store().read(3))!.at, now);
  });

  test('rejected is replaced by a fresh confirmation', () async {
    await store().markRejected(7, h1);
    expect((await store().read(7))!.src, StampSource.rejected);
    now = now.subtract(const Duration(hours: 1));
    await store().stampSession(7, h1);
    expect((await store().read(7))!.src, StampSource.session);
  });

  test('revoke removes only that user', () async {
    await store().stampFromSync(1, h1);
    await store().stampFromSync(2, h1);
    await store().revoke(1);
    expect((await store().readAll()).keys, [2]);
  });

  test('snapshot reconciliation drops stamps of local users absent from a '
      'credential-delivering snapshot, and only those', () async {
    for (final id in [1, 2, 3]) {
      await store().stampFromSync(id, h1);
    }
    final dropped = await store().reconcileSnapshot({1, 2}, [1, 2, 3, 4]);
    expect(dropped, 1);
    expect((await store().readAll()).keys.toSet(), {1, 2});
    expect(await store().reconcileSnapshot({1, 2}, [1, 2, 3, 4]), 0,
        reason: 'idempotent');
  });

  test('corrupt JSON is read as no stamps and then repaired by the next write',
      () async {
    backing.values['offline_cred_stamps_v1'] = '[1,2,';
    expect(await store().readAll(), isEmpty);
    await store().stampFromSync(1, h1);
    expect((await store().readAll()).keys, [1]);
  });

  test('entries that are not valid stamps are skipped, not fatal', () async {
    backing.values['offline_cred_stamps_v1'] =
        '{"1":{"at":"nope","fp":"x","src":"sync"},"2":5,"x":{},'
        '"3":{"at":"2026-10-24T12:00:00Z","fp":"abc","src":"weird"}}';
    expect(await store().readAll(), isEmpty);
  });

  test('a failed write throws (no silent success) and leaves the old value',
      () async {
    await store().stampFromSync(1, h1);
    backing.failing = true;
    await expectLater(store().stampFromSync(2, h1), throwsA(isA<StateError>()));
    backing.failing = false;
    expect((await store().readAll()).keys, [1]);
  });

  test('concurrent stamping from sync and from login never loses an update',
      () async {
    await Future.wait([
      for (var i = 1; i <= 20; i++) store().stampFromSync(i, h1),
    ]);
    expect((await store().readAll()).length, 20);
  });

  test('legacy secure-storage entries become session stamps once, bound to '
      'the current hash', () async {
    final at = now.subtract(const Duration(days: 2));
    final n = await store().adoptLegacyVerifications(
        {'5': at.toIso8601String(), 'bad': 'x', '6': 'not-a-date'},
        {5: h1, 6: h1});
    expect(n, 1);
    final s = (await store().read(5))!;
    expect([s.at, s.fp, s.src], [at, credentialFingerprint(h1), StampSource.session]);
    expect(
        await store().adoptLegacyVerifications({'5': at.toIso8601String()}, {5: h1}),
        0,
        reason: 'second run is a no-op');
  });

  test('max-seen: written to the device-local key, read back, garbage ignored',
      () async {
    expect(await store().readMaxSeen(), isNull);
    await store().writeMaxSeen(now);
    expect(backing.values['offline_login_max_seen_v1'], '2026-10-24T12:00:00.000Z');
    expect(await store().readMaxSeen(), now);
    backing.values['offline_login_max_seen_v1'] = 'zzz';
    expect(await store().readMaxSeen(), isNull);
  });
}
