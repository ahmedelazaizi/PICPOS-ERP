// B-MIG-1 (B1) — real runtime migration bug.
//
// The `ALTER TABLE parties ADD COLUMN account_id` lived in _migrateEpoch2,
// which runOnUpgrade only calls when `from < 81`. A DB upgrading from v81-v102
// therefore NEVER got parties.account_id, and party_dao / accounting_dao_writes
// threw at runtime when reading `parties.accountId`.
//
// The defensive schema-safety pass (ensureSchemaDefaults, run on every SQLite
// boot) must guarantee the column exists regardless of the upgrade path. This
// test simulates a v81-v102 DB (parties without account_id) and asserts the
// pass restores it.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  test('ensureSchemaDefaults restores parties.account_id (B-MIG-1)', () async {
    final db = AppDatabase.forTesting();
    // Force the schema to open, then rewrite `parties` to the legacy shape a
    // v81-v102 DB had: no account_id column.
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement('DROP TABLE parties');
    await db.customStatement(
        'CREATE TABLE parties (id INTEGER PRIMARY KEY, name TEXT NOT NULL)');

    // Sanity: the column really is gone.
    var threw = false;
    try {
      await db.customSelect('SELECT account_id FROM parties').get();
    } catch (_) {
      threw = true;
    }
    expect(threw, isTrue, reason: 'legacy shape must lack account_id');

    // The defensive pass must add it back.
    await db.ensureSchemaDefaults();

    // Now the column resolves without throwing.
    final rows = await db.customSelect('SELECT account_id FROM parties').get();
    expect(rows, isEmpty);

    await db.close();
  });
}
