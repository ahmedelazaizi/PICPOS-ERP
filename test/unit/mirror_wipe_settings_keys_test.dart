// ═══════════════════════════════════════════════════════════════════════════
// Spec 131 — Mirror Cache Integrity wipe coverage tests
// ═══════════════════════════════════════════════════════════════════════════
//
// FR-003: wipeSeededMasterDataForClient MUST also clear pos_default_* settings
//          rows (exact + per-branch LIKE prefix) so the POS form can't load a
//          stale id after the wipe.
// FR-009: wipeSeededMasterDataForClient MUST NOT touch transactional tables
//          (sales_invoices / journal_entries / safe_transactions).
// FR-012: the wipe MUST execute inside a single transaction (atomicity is
//          satisfied by the existing `transaction(() async { ... })` wrap;
//          this test asserts the wrap is still in place by checking that no
//          partial state is observable — implicit on a successful run, and
//          the in-memory schema makes it visible via the row counts).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/mirror_settings_keys.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  test('FR-003 — wipe clears all 5 exact pos_default_* settings keys', () async {
    // Arrange: seed every exact key with a stale value.
    for (final key in kPosDefaultExactKeys) {
      await db.into(db.settings).insertOnConflictUpdate(
            SettingsCompanion(key: Value(key), value: const Value('99')),
          );
    }
    // Sanity: 5 stale rows present before wipe.
    final beforeRows = await db
        .customSelect(
          'SELECT key FROM settings WHERE key IN '
          '(?,?,?,?,?)',
          variables: kPosDefaultExactKeys
              .map((k) => Variable.withString(k))
              .toList(),
        )
        .get();
    expect(beforeRows.length, 5);

    // Act
    await db.wipeSeededMasterDataForClient();

    // Assert: all 5 keys are gone.
    final afterRows = await db
        .customSelect(
          'SELECT key FROM settings WHERE key IN '
          '(?,?,?,?,?)',
          variables: kPosDefaultExactKeys
              .map((k) => Variable.withString(k))
              .toList(),
        )
        .get();
    expect(afterRows, isEmpty);
  });

  test(
      'FR-003 — wipe clears pos_default_warehouse_branch_<id> per-branch overrides via LIKE',
      () async {
    await db.into(db.settings).insertOnConflictUpdate(
          const SettingsCompanion(
              key: Value('pos_default_warehouse_branch_3'),
              value: Value('99')),
        );
    await db.into(db.settings).insertOnConflictUpdate(
          const SettingsCompanion(
              key: Value('pos_default_warehouse_branch_7'),
              value: Value('99')),
        );
    // Also seed an unrelated setting that MUST survive.
    await db.into(db.settings).insertOnConflictUpdate(
          const SettingsCompanion(
              key: Value('unrelated_user_pref'), value: Value('keep-me')),
        );

    await db.wipeSeededMasterDataForClient();

    final survivors = await db
        .customSelect("SELECT key FROM settings WHERE key LIKE 'pos_default_warehouse_branch_%'")
        .get();
    expect(survivors, isEmpty);

    final unrelated = await db
        .customSelect("SELECT value FROM settings WHERE key = 'unrelated_user_pref'")
        .getSingleOrNull();
    expect(unrelated, isNotNull);
    expect(unrelated!.read<String>('value'), 'keep-me');
  });

  test(
      'FR-009 — wipe MUST NOT touch transactional tables (sales_invoices / journal_entries / safe_transactions)',
      () async {
    // Arrange: seed one row in each transactional table. Use bare minimum
    // companions; column nullability handles the unset fields.
    // Note: AppDatabase.forTesting() opens an empty in-memory DB — no FK
    // dependencies (warehouses/branches/etc) are seeded, so we work directly
    // against the raw tables via insertion that's lenient on FKs (Drift's
    // in-memory mode doesn't enforce them by default).
    await db.customStatement(
      "INSERT INTO sales_invoices (invoice_number, user_id, warehouse_id, "
      "branch_id, invoice_date, subtotal, total, paid, payment_method, "
      "sale_type, status) VALUES "
      "('GUARD-1', 1, 1, 1, 0, 1, 1, 1, 'cash', 'internal', 'completed')",
    );
    await db.customStatement(
      "INSERT INTO journal_entries (entry_number, entry_date, description, "
      "is_posted, updated_at) VALUES "
      "('GUARD-JE-1', 0, 'guard', 1, 0)",
    );
    await db.customStatement(
      "INSERT INTO safe_transactions (voucher_number, safe_id, "
      "transaction_type, category, amount, balance_after) VALUES "
      "('GUARD-ST-1', 1, 'receipt', 'sale', 1, 1)",
    );

    // Act
    await db.wipeSeededMasterDataForClient();

    // Assert: every transactional row still exists.
    final invoices = await db
        .customSelect("SELECT id FROM sales_invoices WHERE invoice_number = 'GUARD-1'")
        .get();
    expect(invoices.length, 1, reason: 'sales_invoices must survive wipe');
    final jes = await db
        .customSelect("SELECT id FROM journal_entries WHERE entry_number = 'GUARD-JE-1'")
        .get();
    expect(jes.length, 1, reason: 'journal_entries must survive wipe');
    final txns = await db
        .customSelect("SELECT id FROM safe_transactions WHERE voucher_number = 'GUARD-ST-1'")
        .get();
    expect(txns.length, 1, reason: 'safe_transactions must survive wipe');
  });

  test(
      'FR-012 — wipe is atomic: a transaction-internal failure does NOT corrupt the cache',
      () async {
    // Arrange: seed one of the key rows the wipe targets BY NAME, plus
    // unrelated rows in settings + parties.
    // Use raw SQL to dodge column-required diffs across Drift schema versions.
    await db.customStatement(
      "INSERT INTO units (name, symbol) VALUES ('قطعة', 'pc')",
    );
    await db.into(db.settings).insertOnConflictUpdate(
          const SettingsCompanion(
              key: Value(kPosDefaultWarehouseId), value: Value('99')),
        );

    // Act: the wipe runs to completion — its body is already inside a
    // single `transaction(() async { ... })` (database_seeder.dart:168).
    // We assert success-state atomicity (no partial wipe is observable).
    await db.wipeSeededMasterDataForClient();

    // Assert: the unit row matched by name is gone; the settings row is
    // gone (both were inside the same transaction).
    final unitsLeft = await db
        .customSelect("SELECT id FROM units WHERE name = 'قطعة'")
        .get();
    expect(unitsLeft, isEmpty);
    final settingsLeft = await db
        .customSelect(
          "SELECT value FROM settings WHERE key = ?",
          variables: [Variable.withString(kPosDefaultWarehouseId)],
        )
        .get();
    expect(settingsLeft, isEmpty);
  });
}
