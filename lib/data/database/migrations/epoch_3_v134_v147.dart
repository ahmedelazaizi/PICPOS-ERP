part of '../database.dart';

/// Epoch 3 migration steps v134–v147 (pure move out of `epoch_3.dart`;
/// no behaviour change). Called in order by `_migrateEpoch3`.
///
extension Epoch3MigrationsV134ToV147 on AppDatabase {
  Future<void> _migrateEpoch3V134ToV147(Migrator m, int from) async {

    // v134 (2026-04-28): branch code for invoice number prefixing.
    // Auto-derive from name (first 3 chars uppercased, spaces stripped) when
    // not set, so existing branches get a sensible default like "FAR" for
    // "فرع رئيسي". Admin can later override via the branch management UI.
    if (from < 134) {
      await _safeMigrate('v134 branches.code',
          () => m.database.customStatement(
              'ALTER TABLE branches ADD COLUMN code TEXT'));
      await _safeMigrate('v134 branches.code backfill',
          () => m.database.customStatement(
              "UPDATE branches SET code = UPPER(SUBSTR(REPLACE(name,' ',''), 1, 3)) "
              "WHERE code IS NULL OR code = ''"));
      debugPrint('[Migration] v134: branches.code added + backfilled');
    }
    // v135: M8 — add branch_id to op_expenses for branch-scoped expense reporting
    if (from < 135) {
      await _safeMigrate('v135 op_expenses.branch_id',
          () => m.database.customStatement(
              'ALTER TABLE op_expenses ADD COLUMN branch_id INTEGER REFERENCES branches(id)'));
      debugPrint('[Migration] v135: op_expenses.branch_id added');
    }
    // v136: M4 — add cost_center_id to parties for branch+cost-center assignment
    if (from < 136) {
      await _safeMigrate('v136 parties.cost_center_id',
          () => m.database.customStatement(
              'ALTER TABLE parties ADD COLUMN cost_center_id INTEGER REFERENCES cost_centers(id)'));
      debugPrint('[Migration] v136: parties.cost_center_id added');
    }
    // v137: M6 — add branch_ids + is_global to offers for branch-targeted promotions
    if (from < 137) {
      await _safeMigrate('v137 offers.branch_ids',
          () => m.database.customStatement(
              'ALTER TABLE offers ADD COLUMN branch_ids TEXT'));
      await _safeMigrate('v137 offers.is_global',
          () => m.database.customStatement(
              "ALTER TABLE offers ADD COLUMN is_global INTEGER NOT NULL DEFAULT 1"));
      debugPrint('[Migration] v137: offers.branch_ids + is_global added');
    }
    // v138: Issue 2 — products.created_on_server (server-canonical lock flag)
    //       Issue 18 cleanup — activity_logs.branch_id (SQL-level filter)
    //
    // Default 1 ("server-canonical") for existing product rows is the safe
    // backfill: every product on a client DB at migration time arrived via
    // a server pull, so treating it as server-canonical preserves prior
    // behaviour. Going forward, postProduct on the server stamps 0 when
    // the request comes from a client API call.
    //
    // activity_logs.branch_id is nullable so historical rows (no branch
    // recorded) keep working; ActivityLogger stamps it on new writes.
    if (from < 138) {
      await _safeMigrate('v138 products.created_on_server',
          () => m.database.customStatement(
              'ALTER TABLE products ADD COLUMN created_on_server INTEGER NOT NULL DEFAULT 1'));
      await _safeMigrate('v138 activity_logs.branch_id',
          () => m.database.customStatement(
              'ALTER TABLE activity_logs ADD COLUMN branch_id INTEGER REFERENCES branches(id)'));
      debugPrint('[Migration] v138: products.created_on_server + activity_logs.branch_id added');
    }

    // v139 — Phase 5A.9 (Issue 5). Additive only: seed two settings rows
    // used by the new server-side branch scope work shipped in this phase.
    //   * `client_branch_scope_v5_migrated` — false until the user runs the
    //     "تنظيف بيانات الفروع الأخرى" action from settings (5A.4). Lets us
    //     show the dry-run prompt only on the first launch after upgrade
    //     and never again once the cleanup has happened.
    //   * `server_branch_filter_enabled` — feature flag (G7). True after
    //     upgrade. Setting it to false at runtime makes /api/sync/pull
    //     ignore the `branch_id` parameter and revert to the pre-Phase-5
    //     behaviour without redeploy.
    // Both use INSERT OR IGNORE so a second run of the migration is a
    // no-op, and existing user-set values (e.g. someone manually flipped
    // the flag) survive the upgrade.
    if (from < 139) {
      await _safeMigrate('v139 client_branch_scope_v5_migrated seed',
          () => m.database.customStatement(
              "INSERT OR IGNORE INTO settings(key, value) VALUES('client_branch_scope_v5_migrated', 'false')"));
      await _safeMigrate('v139 server_branch_filter_enabled seed',
          () => m.database.customStatement(
              "INSERT OR IGNORE INTO settings(key, value) VALUES('server_branch_filter_enabled', 'true')"));
      debugPrint('[Migration] v139: Phase 5A branch-scope settings seeded');
    }

    // v140 — Phase 6 (T1). Branch-isolation feature flag.
    //   `client_pulls_transactional_enabled` — when 'false' (the default),
    //   a client device skips Tier 3 of fullSync (sales, purchases, journals,
    //   safe_transactions, shifts, …) and treats itself as a self-contained
    //   branch ledger. Pushes via outbox are unaffected; the server still
    //   gets every write tagged with branch_id. Set to 'true' to revert to
    //   pre-Phase-6 behaviour without redeploy. Server mode reads but does
    //   not act on this flag (the gate in SyncService checks `isClient`
    //   first), so the seeded value is fine for both modes.
    if (from < 140) {
      await _safeMigrate('v140 client_pulls_transactional_enabled seed',
          () => m.database.customStatement(
              "INSERT OR IGNORE INTO settings(key, value) VALUES('client_pulls_transactional_enabled', 'false')"));
      debugPrint('[Migration] v140: client_pulls_transactional_enabled seeded (false)');
    }

    // v142 (Feature 004 — Multi-Branch Governance, US1). FixedAssets gains
    // `global_id` (UUIDv7 sync identity) and `linked_account_id` (per-asset
    // Chart-of-Accounts sub-account FK). Both are nullable for legacy rows;
    // the DAO populates them atomically on every new fixed asset going
    // forward. Note v141 is reserved for the in-flight Phase 7 T1 stash
    // (safe_transactions.branch_id) — leaving the gap is intentional.
    if (from < 142) {
      await _safeMigrate('v142 fixed_assets.linked_account_id',
          () => m.database.customStatement(
              'ALTER TABLE fixed_assets ADD COLUMN linked_account_id INTEGER REFERENCES accounts(id)'));
      await _safeMigrate('v142 fixed_assets.linked_account_id index',
          () => m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_fixed_assets_linked_account ON fixed_assets(linked_account_id)'));
      await _safeMigrate('v142 fixed_assets.global_id',
          () => m.database.customStatement(
              'ALTER TABLE fixed_assets ADD COLUMN global_id TEXT'));
      await _safeMigrate('v142 fixed_assets.global_id unique index',
          () => m.database.customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_fixed_assets_global_id ON fixed_assets(global_id) WHERE global_id IS NOT NULL'));
      debugPrint('[Migration] v142: fixed_assets.linked_account_id + global_id added');
    }
    // v143 (Feature 005, 2026-05-03): Re-align party sub-account parents
    // to the seeded codes `1121` / `2111`. Pre-005 the constants in
    // PartyDao referenced `1201` / `2101`, codes that were never added to
    // seedChartOfAccounts(). On installs that exercised the party-creation
    // flow before this migration, those phantom parents were created at
    // runtime as orphan roots holding a parallel set of sub-accounts.
    //
    // Migration steps:
    //   1. If the seeded `1121` exists AND a runtime `1201` exists, re-
    //      parent every child of `1201` onto `1121` then delete `1201`.
    //   2. Same flip for `2101` → `2111`.
    //   3. Best-effort: rows that can't be migrated (FK conflicts) are
    //      logged and left in place. The chart will then show both parents
    //      side by side until the user resolves the leftover manually.
    //
    // Idempotent: running twice on a clean install is a no-op because the
    // SELECT for the orphan parent returns null.
    if (from < 143) {
      Future<void> realignParent(String oldCode, String newCode) async {
        await _safeMigrate('v143 realign $oldCode → $newCode', () async {
          // Boolean literal pinned to SQLite syntax. The migration runs on
          // the client (SQLite). Postgres deployments pick up the seeded
          // chart fresh, so the orphan-cleanup branch never triggers.
          const boolTrue = '1';

          // Lookup both accounts. If either is missing, skip.
          final oldRow = await m.database.customSelect(
            'SELECT id FROM accounts WHERE code = ? LIMIT 1',
            variables: [Variable<String>(oldCode)],
          ).getSingleOrNull();
          if (oldRow == null) return;
          final newRow = await m.database.customSelect(
            'SELECT id FROM accounts WHERE code = ? LIMIT 1',
            variables: [Variable<String>(newCode)],
          ).getSingleOrNull();
          if (newRow == null) {
            debugPrint('[Migration] v143 skip $oldCode → $newCode: '
                'seeded $newCode missing (chart not seeded yet)');
            return;
          }

          final oldId = oldRow.data['id'] as int;
          final newId = newRow.data['id'] as int;
          if (oldId == newId) return;

          // Re-parent every child of the orphan onto the seeded parent.
          await m.database.customStatement(
            'UPDATE accounts SET parent_id = ? WHERE parent_id = ?',
            [newId, oldId],
          );

          // Delete the orphan IF it now has no children AND no JE lines
          // reference it directly. Anything else is a developer-only
          // edge case; leave it in place + log.
          final residualChildren = await m.database.customSelect(
            'SELECT COUNT(*) AS c FROM accounts WHERE parent_id = ?',
            variables: [Variable<int>(oldId)],
          ).getSingle();
          final residualLines = await m.database.customSelect(
            'SELECT COUNT(*) AS c FROM journal_entry_lines WHERE account_id = ?',
            variables: [Variable<int>(oldId)],
          ).getSingle();
          final children = (residualChildren.data['c'] as num).toInt();
          final lines = (residualLines.data['c'] as num).toInt();
          if (children == 0 && lines == 0) {
            await m.database.customStatement(
              'DELETE FROM accounts WHERE id = ?',
              [oldId],
            );
            debugPrint(
                '[Migration] v143: dropped orphan account $oldCode (id=$oldId)');
          } else {
            // Mark the orphan inactive + system-protected so the user
            // sees it greyed out in the COA UI but can't delete it
            // accidentally — it still anchors any historical JE lines.
            await m.database.customStatement(
              'UPDATE accounts SET is_active = $boolTrue, is_system = $boolTrue '
              'WHERE id = ?',
              [oldId],
            );
            debugPrint('[Migration] v143: kept orphan $oldCode (id=$oldId) — '
                'residualChildren=$children residualLines=$lines');
          }
        });
      }

      await realignParent('1201', '1121');
      await realignParent('2101', '2111');
      debugPrint('[Migration] v143: party sub-account parent realignment complete');
    }
    // v144 (Feature 005 Phase 8, 2026-05-03): cleanup duplicate safe-linked
    // accounts that some users created via the manual COA dialog before
    // realising the modern atomic createSafeWithLinkedAccount() helper
    // already produces them with a canonical `111-XXXXX` (dashed, 5-digit)
    // code. The legacy duplicates show up as same-name siblings under
    // either parent `111` or `1110` with a no-dash compact format like
    // `11101`, `11102`, `111001`, etc. Symptom in production:
    //   111-00001  صندوق نقد الادارة   ← canonical, linked from safes.linked_account_id
    //   11101      صندوق نقد الادارة   ← orphan duplicate, never referenced by FKs
    //
    // Migration steps:
    //   1. For every safe with a non-null `linked_account_id`, look up the
    //      canonical account.
    //   2. Find any OTHER account under the same parent that shares the
    //      safe's name AND has no rows in `journal_entry_lines`.
    //   3. Soft-delete (mark inactive + system) the orphan rather than
    //      hard-deleting; keeps a paper trail and preserves any sync
    //      history. The COA UI hides inactive system accounts by default.
    //
    // No-op on fresh installs (no duplicates exist).
    if (from < 144) {
      await _safeMigrate('v144 dedupe orphan safe accounts', () async {
        final dialect = m.database.executor.dialect;
        final isPg = dialect == SqlDialect.postgres;
        final boolFalse = isPg ? 'FALSE' : '0';
        final boolTrue = isPg ? 'TRUE' : '1';

        // Pull every safe + its canonical linked account in one round-trip.
        final pairs = await m.database.customSelect(
          'SELECT s.id AS safe_id, s.name AS safe_name, '
          's.linked_account_id AS linked_id, '
          'a.parent_id AS parent_id '
          'FROM safes s '
          'JOIN accounts a ON a.id = s.linked_account_id '
          'WHERE s.linked_account_id IS NOT NULL',
        ).get();

        var dropped = 0;
        for (final row in pairs) {
          final safeName = row.data['safe_name'] as String?;
          final linkedId = row.data['linked_id'] as int?;
          final parentId = row.data['parent_id'] as int?;
          if (safeName == null || linkedId == null || parentId == null) {
            continue;
          }

          // Find sibling accounts (same parent) that share the safe's
          // name but are NOT the canonical linked one.
          final siblings = await m.database.customSelect(
            'SELECT id, code FROM accounts '
            'WHERE parent_id = ? AND name = ? AND id <> ? AND is_active = $boolTrue',
            variables: [
              Variable<int>(parentId),
              Variable<String>(safeName),
              Variable<int>(linkedId),
            ],
          ).get();

          for (final sib in siblings) {
            final orphanId = sib.data['id'] as int;
            // Don't touch orphans that have JE lines — those carry
            // historical data and silently hiding them would break audit.
            final lineCount = await m.database.customSelect(
              'SELECT COUNT(*) AS c FROM journal_entry_lines '
              'WHERE account_id = ?',
              variables: [Variable<int>(orphanId)],
            ).getSingle();
            final hasLines = (lineCount.data['c'] as num).toInt() > 0;
            if (hasLines) {
              debugPrint(
                  '[Migration] v144 keep orphan #$orphanId (${sib.data['code']}) — has JE lines');
              continue;
            }

            await m.database.customStatement(
              'UPDATE accounts SET is_active = $boolFalse, '
              "name = name || ' [مكرر — مُؤرشف v144]' "
              'WHERE id = ?',
              [orphanId],
            );
            dropped++;
            debugPrint(
                '[Migration] v144 archived orphan #$orphanId code=${sib.data['code']} name="$safeName"');
          }
        }
        debugPrint(
            '[Migration] v144 complete — archived $dropped duplicate safe accounts');
      });
    }

    // ── v145: Spec 008 / FR-001 — add `branch_id` to `shifts` table ──
    //
    // Multi-branch users (admin / financial manager with user_branch_access
    // rows for >1 branch) had no way to record WHICH branch a shift was
    // opened on. The close-time logic fell back to `getUserBranchId(userId)`
    // which returns the FIRST user_branch_access row — closing a shift on
    // Branch B incorrectly zeroed Branch A's safes.
    //
    // The new column is nullable so legacy `shifts` rows (created before
    // this migration) keep working: `closeShiftWithAudit` reads
    // `shift.branchId` first and only falls back to `getUserBranchId` when
    // the column is null.
    if (from < 145) {
      await _safeMigrate('v145 shifts.branch_id (Spec 008)', () async {
        await m.addColumn(shifts, shifts.branchId);
        debugPrint('[Migration] v145 added shifts.branch_id (NULLABLE)');
      });
    }

    // ── v146: Feature 009 — Auto-Deplete BOM on Sale + POS Terminals ──
    //
    // Phase 2 (foundational) of Feature 009. Four additive changes, all
    // safe with default values that preserve legacy behavior:
    //
    //   1. bill_of_materials.auto_deplete_on_sale (BOOL, default 0)
    //      Enables the new at-sale deduction path. Existing BOMs keep the
    //      manual-production behavior because default = false (FR-002,
    //      FR-031, FR-032).
    //
    //   2. bill_of_materials.depletion_policy (TEXT, default
    //      'prefer_finished_stock')
    //      Per RD-1 — when on-hand finished stock exists, deduct it first
    //      and only auto-deplete the residual. Settable to
    //      'always_auto_deplete' per BOM.
    //
    //   3. sale_bom_consumptions (NEW append-only table, FR-028)
    //      Logs every raw-material deduction caused by an auto-deplete sale,
    //      freezing unit_cost_at_sale at deduction time so returns reverse
    //      at original cost (FR-021). Sync = appendOnly (Constitution III).
    //
    //   4. pos_terminals (NEW master-data table, FR-034) +
    //      shifts.pos_terminal_id (NULLABLE column, FR-035)
    //      Foundation for per-terminal stock-shortage policy override
    //      (FR-017). Each device gets a stable device_id (UUIDv7 in
    //      flutter_secure_storage); shifts opened from the device populate
    //      pos_terminal_id automatically. Pre-migration shifts keep NULL
    //      (Constitution I — Behavior Preservation).
    if (from < 146) {
      await _safeMigrate(
        'v146 BOM auto-deplete + POS terminals (Feature 009)',
        () async {
          // 1+2: BOM columns
          await m.addColumn(billOfMaterials, billOfMaterials.autoDepleteOnSale);
          await m.addColumn(billOfMaterials, billOfMaterials.depletionPolicy);
          // 3: consumption log (append-only)
          await m.createTable(saleBomConsumptions);
          // 4a: POS terminal registry
          await m.createTable(posTerminals);
          // 4b: shift -> terminal link
          await m.addColumn(shifts, shifts.posTerminalId);
          debugPrint(
              '[Migration] v146 BOM auto-deplete + POS terminals OK');
        },
      );
    }

    // ═════════════════════════════════════════════════════════════════════
    // v147 — Quality hardening pass (2026-05-12)
    //
    // Adds the **performance indexes** that were declared via @TableIndex
    // annotations on fresh installs but never backfilled into upgraded
    // databases. Audit (May 12) flagged these as missing for installs that
    // shipped before the corresponding feature work landed:
    //
    //   - journal_entries.fiscal_year_id  → period-close report scans
    //   - cost_centers.parent_id          → hierarchical roll-up reports
    //   - activity_logs.branch_id         → per-branch audit filter
    //   - parties (is_active, deleted_at) → list screens with soft-delete
    //
    // (idx_journal_entry_lines_cost_center, idx_journal_entries_branch,
    // idx_journal_entries_ref were already backfilled in v111/v115 so we
    // don't re-add them here.)
    //
    // Why no ALTER TABLE ADD FK: SQLite can't add FK constraints to an
    // existing table without a full rebuild — too risky on production
    // 100MB+ databases. The Drift schema already declares the constraints
    // for new installs; the application layer (orchestrators + dual-write
    // pattern in ENGINEERING_GUIDELINES.md R4) enforces referential integrity on legacy
    // rows going forward.
    //
    // Wrapped in a single transaction for atomicity (lesson from v143/v144
    // audit feedback — partial index creation could leave query planner
    // confused mid-migration). `IF NOT EXISTS` keeps it idempotent.
    // ═════════════════════════════════════════════════════════════════════
    if (from < 147) {
      await _safeMigrate(
        'v147 quality hardening: missing FK indexes',
        () async {
          await m.database.transaction(() async {
            await m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_journal_entries_fiscal '
              'ON journal_entries(fiscal_year_id) '
              'WHERE fiscal_year_id IS NOT NULL;',
            );
            await m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_cost_centers_parent '
              'ON cost_centers(parent_id) '
              'WHERE parent_id IS NOT NULL;',
            );
            await m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_activity_logs_branch '
              'ON activity_logs(branch_id) '
              'WHERE branch_id IS NOT NULL;',
            );
            await m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_parties_active '
              'ON parties(is_active, deleted_at) '
              'WHERE deleted_at IS NULL;',
            );
          });
          debugPrint('[Migration] v147 quality-hardening indexes OK');
        },
      );
    }
  }
}
