import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Variable;
import '../database.dart';

/// Phase 6 (T7) — merge duplicate category rows that piled up before the
/// Phase 5A.1 globalId/name dedup landed. Issue 2 of the post-Phase-5
/// round: the user reported "categories duplicated on both client and
/// server when created from a client". The current sync strategy is
/// correct (globalId match → name fallback → insert); duplicates only
/// appear when historical rows have NULL globalId AND their names diverge
/// by whitespace/casing. This helper closes those out.
///
/// Two operations, both gated by an explicit caller (NEVER auto-run on
/// startup — destructive):
///
///   * [dryRunDuplicateCategoryGroups] — read-only. Returns groups of
///     `[id, name]` for categories that share the same trimmed lowercase
///     name. Empty list = clean state.
///
///   * [mergeDuplicateCategories] — for each group, picks the survivor
///     (smallest id; oldest = first seen), repoints `products.category_id`,
///     `category_branches.category_id`, and `categories.parent_id` from
///     the duplicates to the survivor, then deletes the duplicates.
///     Wrapped in a single transaction so partial failure rolls back.
///     Returns the count of merged-away rows.
extension CategoryDedupExtension on AppDatabase {
  /// Read-only dry-run. Returns one entry per duplicate group:
  /// `{normalizedName, ids: [...], names: [...]}`. The `names` list keeps
  /// the original (un-normalized) names so the UI can show "Test1" vs
  /// "test1 " vs "Test1‎" to the operator.
  Future<List<Map<String, dynamic>>> dryRunDuplicateCategoryGroups() async {
    final rows = await customSelect(
      'SELECT LOWER(TRIM(name)) AS norm, '
      '       GROUP_CONCAT(id) AS ids, '
      '       GROUP_CONCAT(name, \'|\') AS names, '
      '       COUNT(*) AS c '
      'FROM categories '
      'GROUP BY LOWER(TRIM(name)) '
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
      debugPrint('[CATEGORY-DEDUP-DRYRUN] no duplicate groups');
    } else {
      debugPrint('[CATEGORY-DEDUP-DRYRUN] ${groups.length} duplicate groups');
    }
    return groups;
  }

  /// Destructive — merges every duplicate group surfaced by
  /// [dryRunDuplicateCategoryGroups]. The lowest id in each group is the
  /// survivor; the rest are repointed and deleted.
  ///
  /// Returns the total count of rows merged away (not the group count).
  /// Idempotent: a second call returns 0.
  Future<int> mergeDuplicateCategories() async {
    final groups = await dryRunDuplicateCategoryGroups();
    if (groups.isEmpty) return 0;

    var totalMerged = 0;
    await transaction(() async {
      for (final g in groups) {
        final ids = (g['ids'] as List).cast<int>().toList()..sort();
        if (ids.length < 2) continue;
        final survivor = ids.first;
        final dups = ids.sublist(1);

        for (final dup in dups) {
          // products.category_id → survivor
          await customStatement(
            'UPDATE products SET category_id = ? WHERE category_id = ?',
            [Variable.withInt(survivor).value, Variable.withInt(dup).value],
          );

          // category_branches: a (categoryId,branchId) row may already exist
          // for the survivor. Insert any missing links first, then drop the
          // duplicate's rows (so we don't try to overwrite the PK).
          await customStatement(
            'INSERT OR IGNORE INTO category_branches (category_id, branch_id) '
            'SELECT ?, branch_id FROM category_branches WHERE category_id = ?',
            [Variable.withInt(survivor).value, Variable.withInt(dup).value],
          );
          await customStatement(
            'DELETE FROM category_branches WHERE category_id = ?',
            [Variable.withInt(dup).value],
          );

          // categories.parent_id (self-FK) → survivor
          await customStatement(
            'UPDATE categories SET parent_id = ? WHERE parent_id = ?',
            [Variable.withInt(survivor).value, Variable.withInt(dup).value],
          );

          // Finally drop the duplicate row itself.
          await customStatement(
            'DELETE FROM categories WHERE id = ?',
            [Variable.withInt(dup).value],
          );
          totalMerged++;
          debugPrint('[CATEGORY-DEDUP] merged $dup → $survivor');
        }
      }
    });
    debugPrint('[CATEGORY-DEDUP] merged $totalMerged duplicate rows total');
    return totalMerged;
  }
}
