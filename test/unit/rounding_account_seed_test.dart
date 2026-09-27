// ═══════════════════════════════════════════════════════════════════════════
// Spec 139 — rounding-difference account (4319) seed + backfill self-heal
// ═══════════════════════════════════════════════════════════════════════════
//
// T019 automation (check 5): an EXISTING (pre-139) install must gain the 4319
// «فروق تقريب» account without a schema migration. The boot self-heal in
// `runBeforeOpen` (database_startup.dart, non-client) re-runs the idempotent COA
// seed, whose `_acct` guards every INSERT with `WHERE NOT EXISTS`. This suite
// pins that a missing 4319 is restored and that the restore is a no-op for the
// rest of the tree (no duplication) — the exact property the self-heal relies on.
//
// Uses `AppDatabase.forTesting()` WITHOUT wiping, so the full seeded chart of
// accounts (incl. 4319) is present, mirroring a real install.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
  });

  test('fresh install seeds 4319 «فروق تقريب» (revenue/detail, parent 43)',
      () async {
    final acc = await db.getAccountByCode('4319');
    expect(acc, isNotNull, reason: '4319 present out of the box');
    expect(acc!.name, 'فروق تقريب');
    expect(acc.accountType, 'revenue');
    expect(acc.accountNature, 'detail',
        reason: 'postable leaf — getLeafAccountByPurpose returns it directly');
    // Parent is the «الإيرادات الأخرى» group (code 43).
    final parent = await (db.select(db.accounts)
          ..where((a) => a.code.equals('43')))
        .getSingleOrNull();
    expect(parent, isNotNull);
    expect(acc.parentId, parent!.id);
  });

  test('self-heal: an existing install missing 4319 regains it, once, no dup',
      () async {
    // Simulate a pre-139 install: drop 4319 but keep the rest of the tree. FK
    // is enforced in tests now — force the deletion with FK momentarily off.
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await (db.delete(db.accounts)..where((a) => a.code.equals('4319'))).go();
    await db.customStatement('PRAGMA foreign_keys = ON');
    expect(await db.getAccountByCode('4319'), isNull);
    final countBefore = (await db.select(db.accounts).get()).length;

    // The boot self-heal path is an idempotent re-seed (WHERE NOT EXISTS).
    await db.seedChartOfAccounts();

    final restored = await db.getAccountByCode('4319');
    expect(restored, isNotNull, reason: '4319 restored on an existing install');
    expect(restored!.accountType, 'revenue');
    expect((await db.select(db.accounts).get()).length, countBefore + 1,
        reason: 'only 4319 was inserted — the rest of the tree is untouched');

    // Running it a second time changes nothing (fully idempotent).
    await db.seedChartOfAccounts();
    expect((await db.select(db.accounts).get()).length, countBefore + 1);
  });
}
