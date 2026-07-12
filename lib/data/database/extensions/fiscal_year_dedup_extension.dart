import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Variable;
import '../database.dart';

/// Feature 014 / Issue 2 — collapse duplicate fiscal year rows that
/// piled up on mirror / client devices. The user reported the same
/// fiscal year (e.g., "2026") appearing twice on mirror UI and the
/// "open" year appearing twice on client devices, which corrupts every
/// "current fiscal year" lookup downstream (period close, financial
/// statements, accounting period scoping).
///
/// Two operations, both gated by an explicit caller (NEVER auto-run on
/// startup unsupervised — destructive, mirrors the
/// [BranchDedupExtension] pattern):
///
///   * [dryRunDuplicateFiscalYears] — read-only. Returns groups of
///     `[id, name, startDate, endDate]` for fiscal years sharing the
///     same `(name, startDate, endDate)` triple. Empty list = clean
///     state, exits in O(1) on a single GROUP BY scan.
///
///   * [mergeDuplicateFiscalYears] — for each group, picks a survivor
///     (preference: row with non-null `globalId`; tie-break: smallest
///     id), repoints `accounting_periods.fiscal_year_id` from each
///     duplicate to the survivor, then deletes the duplicates.
///     Wrapped in a single transaction; idempotent.
extension FiscalYearDedupExtension on AppDatabase {
  /// Read-only — returns groups of duplicate fiscal years.
  Future<List<Map<String, dynamic>>> dryRunDuplicateFiscalYears() async {
    // Cluster 030 / Bug A: PostgreSQL doesn't permit referencing a
    // SELECT alias (`c`) in the HAVING clause — only SQLite does.
    // Use the aggregate directly (`HAVING COUNT(*) > 1`) so the same
    // SQL works on both engines. The PG compat layer translates
    // `GROUP_CONCAT(...)` → `STRING_AGG(...)` already.
    final rows = await customSelect(
      'SELECT name, start_date, end_date, '
      "       GROUP_CONCAT(id, ',') AS ids, "
      '       COUNT(*) AS c '
      'FROM fiscal_years '
      'WHERE deleted_at IS NULL '
      'GROUP BY name, start_date, end_date '
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
        'name': r.data['name'] as String? ?? '',
        'ids': ids,
        'count': r.data['c'] as int? ?? ids.length,
      });
    }
    if (groups.isEmpty) {
      debugPrint('[FY-DEDUP-DRYRUN] no duplicate fiscal-year groups');
    } else {
      debugPrint('[FY-DEDUP-DRYRUN] ${groups.length} duplicate group(s)');
    }
    return groups;
  }

  /// Destructive — collapses duplicate fiscal-year groups. Returns the
  /// total count of rows deleted (not the group count). Idempotent.
  Future<int> mergeDuplicateFiscalYears() async {
    final groups = await dryRunDuplicateFiscalYears();
    if (groups.isEmpty) return 0;

    var totalDeleted = 0;
    await transaction(() async {
      for (final g in groups) {
        final ids = (g['ids'] as List).cast<int>().toList();
        if (ids.length < 2) continue;

        // Survivor preference: prefer a row with a non-null globalId
        // (server-blessed identity); fall back to smallest id.
        final rows = await customSelect(
          'SELECT id, global_id FROM fiscal_years WHERE id IN '
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
          final dupVar = Variable.withInt(dup).value;
          final survivorVar = Variable.withInt(survivor).value;
          // Repoint accounting_periods FK so the survivor inherits
          // every period the duplicate previously owned.
          await customStatement(
            'UPDATE accounting_periods SET fiscal_year_id = ? '
            'WHERE fiscal_year_id = ?',
            [survivorVar, dupVar],
          );
          await customStatement(
            'DELETE FROM fiscal_years WHERE id = ?',
            [dupVar],
          );
          totalDeleted++;
          debugPrint('[FY-DEDUP] merged $dup → $survivor '
              '(name="${g['name']}")');
        }
      }
    });
    debugPrint('[FY-DEDUP] deleted $totalDeleted duplicate fiscal-year row(s) total');
    return totalDeleted;
  }
}
