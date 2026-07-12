import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Variable;
import '../database.dart';

/// Feature 012 / Issue M-DUP-BRANCH — merge duplicate branch rows that
/// piled up on mirror devices before Feature 011's server-side `postBranch`
/// dedup landed. The mirror's `BranchSyncStrategy` already collapses
/// server duplicates into a single local row going forward, but legacy
/// rows already in the local `branches` table (e.g., one from the seeded
/// "الفرع الرئيسي" defaults plus one or more pulled from an HQ that
/// accumulated duplicates) survive untouched and show up in
/// إدارة الفروع + every branch filter dropdown.
///
/// Two operations, both gated by an explicit caller (NEVER auto-run on
/// startup unsupervised — destructive, mirrors the
/// [CategoryDedupExtension] pattern):
///
///   * [dryRunDuplicateBranchGroups] — read-only. Returns groups of
///     `[id, name]` for branches sharing the same trimmed name. Empty
///     list = clean state. Idempotent and cheap.
///
///   * [mergeDuplicateBranches] — for each group, picks the survivor
///     (preference: row with non-null `globalId`, then smallest `id`),
///     repoints every dependent table's `branch_id` (and the two-FK
///     `stock_requisitions` columns) from each duplicate to the survivor,
///     then deletes the duplicates. Wrapped in a single transaction.
///     Returns the count of rows deleted (not group count).
extension BranchDedupExtension on AppDatabase {
  // ── Schema map ────────────────────────────────────────────────────
  // Tables with a single `branch_id` column. Updated with a plain
  // `UPDATE ... SET branch_id = survivor WHERE branch_id = dup`.
  static const _singleFkTables = <String>[
    'employees',
    'shifts',
    'journal_entries',
    'warehouses',
    'stock_movements',
    'op_expenses',
    'activity_logs',
    'entity_mappings',
    'sales_invoices',
    'purchase_invoices',
    'sale_bom_consumptions',
    'safes',
    'pos_terminals',
  ];

  // Tables with two branch FKs (from / to). Both columns get the same
  // survivor mapping so a transfer that pointed at "duplicate-of-main →
  // some-other-branch" survives as "main → some-other-branch".
  static const _twoFkTable = 'stock_requisitions';
  static const _twoFkColumns = <String>['from_branch_id', 'to_branch_id'];

  // Tables where `(other_id, branch_id)` is the composite PK. Naive
  // UPDATE would conflict if `(other_id, survivor)` already exists — use
  // `INSERT OR IGNORE` to copy missing links to the survivor first, then
  // DELETE the duplicate's rows.
  static const _compositePkTables = <Map<String, String>>[
    {'table': 'user_branch_access', 'otherCol': 'user_id'},
    {'table': 'category_branches', 'otherCol': 'category_id'},
  ];

  /// Read-only dry-run. Returns one entry per duplicate group:
  /// `{normalizedName, ids: [...], names: [...]}`. The `names` list keeps
  /// the original (un-normalized) names so a settings UI could surface
  /// "الفرع الرئيسي" vs "الفرع الرئيسي " (trailing-space) to the operator.
  Future<List<Map<String, dynamic>>> dryRunDuplicateBranchGroups() async {
    // Cluster 030 / Bug A: PG rejects alias references in HAVING.
    // Use the aggregate directly so the same SQL works on both
    // SQLite and PostgreSQL (the PG compat layer maps GROUP_CONCAT
    // → STRING_AGG transparently).
    final rows = await customSelect(
      'SELECT TRIM(name) AS norm, '
      "       GROUP_CONCAT(id, ',') AS ids, "
      "       GROUP_CONCAT(name, '|') AS names, "
      '       COUNT(*) AS c '
      'FROM branches '
      'GROUP BY TRIM(name) '
      'HAVING COUNT(*) > 1',
    ).get();
    final groups = <Map<String, dynamic>>[];
    for (final r in rows) {
      final ids = (r.data['ids'] as String? ?? '')
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();
      groups.add({
        'normalizedName': r.data['norm'] as String? ?? '',
        'ids': ids,
        'names': (r.data['names'] as String? ?? '').split('|'),
        'count': r.data['c'] as int? ?? ids.length,
      });
    }
    if (groups.isEmpty) {
      debugPrint('[BRANCH-DEDUP-DRYRUN] no duplicate groups');
    } else {
      debugPrint('[BRANCH-DEDUP-DRYRUN] ${groups.length} duplicate groups');
    }
    return groups;
  }

  /// Destructive — merges every duplicate group surfaced by
  /// [dryRunDuplicateBranchGroups]. Survivor preference: row whose
  /// `global_id` is NOT NULL (server-blessed identity), then smallest id.
  /// All dependent FKs are repointed to the survivor before the
  /// duplicates are deleted, so no orphan rows are left behind.
  ///
  /// Returns the total count of branch rows deleted (not the group
  /// count). Idempotent: a second call returns 0.
  ///
  /// Note (Feature 035): there is no companion globalId-grouping pass
  /// because the schema enforces `global_id TEXT UNIQUE` since v119, so
  /// two local rows cannot share a non-null globalId. The "rename case"
  /// is instead handled at sync-time by `BranchSyncStrategy`'s Tier 4
  /// re-link (US4) — it re-attaches an inactive locally-seeded row to
  /// the server's identity instead of inserting a fresh row.
  Future<int> mergeDuplicateBranches() async {
    final groups = await dryRunDuplicateBranchGroups();
    if (groups.isEmpty) return 0;

    var totalDeleted = 0;
    await transaction(() async {
      for (final g in groups) {
        final ids = (g['ids'] as List).cast<int>().toList();
        if (ids.length < 2) continue;

        // Survivor preference: prefer a row with a non-null globalId
        // (this is the row that successfully matched the server's
        // identity at some point); fall back to smallest id.
        final rows = await customSelect(
          'SELECT id, global_id FROM branches WHERE id IN '
          '(${List.filled(ids.length, '?').join(',')})',
          variables: ids.map((i) => Variable.withInt(i)).toList(),
        ).get();
        int? survivor;
        for (final r in rows) {
          if (r.data['global_id'] != null) {
            survivor = r.data['id'] as int;
            break;
          }
        }
        survivor ??= (ids.toList()..sort()).first;
        final dups = ids.where((i) => i != survivor).toList();
        if (dups.isEmpty) continue;

        for (final dup in dups) {
          await remapBranchFks(dup, survivor);
          await customStatement(
            'DELETE FROM branches WHERE id = ?',
            [Variable.withInt(dup).value],
          );
          totalDeleted++;
          debugPrint('[BRANCH-DEDUP] merged $dup → $survivor '
              '(name="${g['normalizedName']}")');
        }
      }
    });
    debugPrint('[BRANCH-DEDUP] deleted $totalDeleted duplicate branch rows total');
    return totalDeleted;
  }

  /// Feature 035 / FR-008 — repoint every dependent FK from [fromId] to
  /// [toId] across the canonical 16-table dependent-table list (13 single-
  /// FK tables + `stock_requisitions` two-FK + 2 composite-PK tables).
  /// Package-private (no underscore) so `BranchSyncStrategy` can call it
  /// from the per-sync per-name dedup pass without a top-level helper.
  ///
  /// Caller is responsible for wrapping in `db.transaction()` if atomic
  /// behavior across multiple remap+delete sequences is needed; this
  /// method itself only issues the row writes.
  Future<void> remapBranchFks(int fromId, int toId) async {
    final fromVar = Variable.withInt(fromId).value;
    final toVar = Variable.withInt(toId).value;

    for (final table in _singleFkTables) {
      await customStatement(
        'UPDATE $table SET branch_id = ? WHERE branch_id = ?',
        [toVar, fromVar],
      );
    }

    // stock_requisitions has two branch columns.
    for (final col in _twoFkColumns) {
      await customStatement(
        'UPDATE $_twoFkTable SET $col = ? WHERE $col = ?',
        [toVar, fromVar],
      );
    }

    // Composite-PK tables: copy missing links to survivor, then drop the
    // duplicate's rows. INSERT OR IGNORE handles the already-exists case
    // gracefully on SQLite; pg_compat_sql.dart translates to ON CONFLICT
    // DO NOTHING for PG (commit 8bfa2b8).
    for (final t in _compositePkTables) {
      final tbl = t['table']!;
      final otherCol = t['otherCol']!;
      await customStatement(
        'INSERT OR IGNORE INTO $tbl ($otherCol, branch_id) '
        'SELECT $otherCol, ? FROM $tbl WHERE branch_id = ?',
        [toVar, fromVar],
      );
      await customStatement(
        'DELETE FROM $tbl WHERE branch_id = ?',
        [fromVar],
      );
    }
  }
}
