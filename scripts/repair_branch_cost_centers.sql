-- ============================================================================
-- repair_branch_cost_centers.sql
-- ----------------------------------------------------------------------------
-- One-off DATA REPAIR (review before running — NOT auto-executed).
--
-- Re-attributes historical AUTO-POSTED journal entries that landed on the
-- global «عام» (GEN) cost center back to their branch's OWN cost center,
-- falling back to the branch's region cost center — matching the fixed
-- resolution priority in createJournalEntry:  explicit -> branch -> region -> GEN.
--
-- WHY THIS IS NEEDED
--   Before the fix, the GEN «عام» fallback ran BEFORE the branch/region
--   resolution, so every branch sale/purchase/receipt/payment was attributed
--   to «عام». New entries are now posted correctly; this script repairs the
--   pre-fix history so cost-center / branch reports are accurate.
--
-- SCOPE / SAFETY
--   * Touches ONLY is_auto_posted = TRUE entries currently on a «عام» (GEN)
--     centre whose branch has its OWN (non-GEN) centre. Manual journal entries
--     the user deliberately placed on «عام» are left untouched.
--   * Cost-center reassignment does NOT change any debit/credit amount, the
--     trial balance, or the P&L totals — it only reclassifies the analytical
--     (cost-center) dimension. It is balance-neutral.
--   * 1) BACK UP THE DATABASE FIRST.
--     2) Run STEP 0 (preview) and eyeball the per-branch counts + target centre.
--     3) Run STEP 1 inside the transaction; review the row counts; COMMIT
--        (or ROLLBACK if anything looks wrong).
--     4) Run STEP 2 (verify) — expect 0 remaining.
--   * Optional: to leave CLOSED fiscal periods untouched, add a date guard to
--     every WHERE below, e.g.  AND je.entry_date >= '2026-01-01'.
--
-- DIALECT — is_auto_posted is a boolean; replace <BOOL_TRUE> before running:
--     PostgreSQL / Supabase  ->  TRUE
--     SQLite (SQLCipher)     ->  1
--
-- NOTE for a SQLCipher (encrypted SQLite) SERVER DB: a raw .sql file cannot open
-- the encrypted file without the key. In that case ask me to wire the identical
-- logic as an in-app maintenance action (dry-run first) that runs through the
-- app — that is the practical path for encrypted local server DBs.
-- ============================================================================


-- ─── STEP 0 · PREVIEW (read-only) ───────────────────────────────────────────
-- Per-branch: how many auto-posted entries would move, and to which centre.
SELECT je.branch_id,
       COALESCE(b.cost_center_id, r.cost_center_id) AS target_cost_center_id,
       COUNT(*)                                     AS entries_to_move
FROM journal_entries je
JOIN branches b        ON b.id = je.branch_id
LEFT JOIN regions r    ON r.id = b.region_id
WHERE je.is_auto_posted = <BOOL_TRUE>
  AND je.cost_center_id IN (SELECT id FROM cost_centers WHERE code = 'GEN')
  AND COALESCE(b.cost_center_id, r.cost_center_id) IS NOT NULL
  AND COALESCE(b.cost_center_id, r.cost_center_id)
        NOT IN (SELECT id FROM cost_centers WHERE code = 'GEN')
GROUP BY je.branch_id, COALESCE(b.cost_center_id, r.cost_center_id)
ORDER BY je.branch_id;


-- ─── STEP 1 · APPLY (transactional) ─────────────────────────────────────────
BEGIN;

-- 1a) Move the LINES first — while the headers still point at GEN, so the
--     target entries are still identifiable. Only lines currently on a GEN
--     centre are moved; lines already carrying a specific centre are left.
UPDATE journal_entry_lines
SET cost_center_id = (
      SELECT COALESCE(b.cost_center_id, r.cost_center_id)
      FROM journal_entries je
      JOIN branches b     ON b.id = je.branch_id
      LEFT JOIN regions r ON r.id = b.region_id
      WHERE je.id = journal_entry_lines.entry_id
    )
WHERE journal_entry_lines.cost_center_id IN (SELECT id FROM cost_centers WHERE code = 'GEN')
  AND EXISTS (
      SELECT 1
      FROM journal_entries je
      JOIN branches b     ON b.id = je.branch_id
      LEFT JOIN regions r ON r.id = b.region_id
      WHERE je.id = journal_entry_lines.entry_id
        AND je.is_auto_posted = <BOOL_TRUE>
        AND je.cost_center_id IN (SELECT id FROM cost_centers WHERE code = 'GEN')
        AND COALESCE(b.cost_center_id, r.cost_center_id) IS NOT NULL
        AND COALESCE(b.cost_center_id, r.cost_center_id)
              NOT IN (SELECT id FROM cost_centers WHERE code = 'GEN')
    );

-- 1b) Then move the HEADERS.
UPDATE journal_entries
SET cost_center_id = (
      SELECT COALESCE(b.cost_center_id, r.cost_center_id)
      FROM branches b
      LEFT JOIN regions r ON r.id = b.region_id
      WHERE b.id = journal_entries.branch_id
    )
WHERE journal_entries.is_auto_posted = <BOOL_TRUE>
  AND journal_entries.cost_center_id IN (SELECT id FROM cost_centers WHERE code = 'GEN')
  AND journal_entries.branch_id IS NOT NULL
  AND (SELECT COALESCE(b.cost_center_id, r.cost_center_id)
       FROM branches b LEFT JOIN regions r ON r.id = b.region_id
       WHERE b.id = journal_entries.branch_id) IS NOT NULL
  AND (SELECT COALESCE(b.cost_center_id, r.cost_center_id)
       FROM branches b LEFT JOIN regions r ON r.id = b.region_id
       WHERE b.id = journal_entries.branch_id)
        NOT IN (SELECT id FROM cost_centers WHERE code = 'GEN');

-- Review the two UPDATE row counts, then choose ONE:
--   COMMIT;    -- keep the changes
--   ROLLBACK;  -- undo everything in this transaction
COMMIT;


-- ─── STEP 2 · VERIFY (read-only) ────────────────────────────────────────────
-- Expect 0 — no auto-posted entry should remain on «عام» for a branch that has
-- its own (non-GEN) cost center.
SELECT COUNT(*) AS remaining_on_gen
FROM journal_entries je
JOIN branches b        ON b.id = je.branch_id
LEFT JOIN regions r    ON r.id = b.region_id
WHERE je.is_auto_posted = <BOOL_TRUE>
  AND je.cost_center_id IN (SELECT id FROM cost_centers WHERE code = 'GEN')
  AND COALESCE(b.cost_center_id, r.cost_center_id) IS NOT NULL
  AND COALESCE(b.cost_center_id, r.cost_center_id)
        NOT IN (SELECT id FROM cost_centers WHERE code = 'GEN');
