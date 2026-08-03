import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Variable;
import '../database.dart';

/// Phase 5A.4 (Issue 5) — clean up cross-branch rows that landed locally
/// before the server-side `/api/sync/pull` filter (5A.1) was active.
///
/// Two operations, both gated by an explicit caller (NEVER auto-run on
/// startup — destructive operations must be user-initiated per the
/// Stability Guarantee G2):
///
///   * [dryRunForeignBranchCounts] — returns a map of `table → row count`
///     for rows whose `branch_id` is NOT in [allowedBranchIds] and is NOT
///     NULL. Read-only, side-effect-free. Use this to populate a
///     "العميل يحتوي على X صفوف من فروع أخرى" summary in the settings UI
///     so the user knows what they're about to delete.
///
///   * [wipeForeignBranchData] — actually deletes those rows, inside a
///     single transaction so a partial failure rolls back. Returns the
///     same shape as [dryRunForeignBranchCounts] but counting deleted
///     rows. Safe to call repeatedly; subsequent runs are no-ops once
///     all foreign rows are gone.
///
/// Tables are taken from the same allowlist used server-side
/// (`api_handler._syncPullBranchColumn`) so the two ends stay aligned —
/// if the server filters a table, the cleanup helper will also remove
/// any pre-filter leaks for it.
extension BranchScopeCleanupExtension on AppDatabase {
  /// خريطة الجدول → عمود الفرع. **يجب أن تطابق
  /// `api_handler._syncPullBranchColumn` بالضبط** — أي جدول يقصّه الخادم
  /// يُنظَّف هنا أيضاً.
  ///
  /// كانت تحوي `sales_orders` · `purchase_orders` · `held_orders` ·
  /// `quotations` · `commercial_papers` بناءً على ترحيل مُخطَّط لم يحدث
  /// قط: هذه الجداول **بلا `branchId` في drift**
  /// (sales_purchase_tables.dart:286,329,380 · quotation_tables.dart:6 ·
  /// commercial_finance_tables.dart:11). الاستعلام عليها يرمي، و
  /// [wipeForeignBranchData] يعمل rethrow داخل `transaction` ⇒ **ارتداد
  /// دائم**؛ الزر في `branch_scope_admin_dialog.dart:346` لم يحذف صفاً قط.
  ///
  /// الجداول بلا عمود فرع (`sales_invoice_items`, `journal_lines`,
  /// `safe_transactions`) غائبة عمداً — تُحصَر عبر سجلّها الأب ويتتالى
  /// حذفها عبر سلسلة الـFK.
  ///
  /// الجداول الأساسية التي يقصّها الخادم (`warehouses`, `safes`) غائبة
  /// عمداً كذلك: حذف مخزن محلياً قد يكسر FK لصفوف تعاملية تشير إليه —
  /// قرار منفصل خارج نطاق المرحلة ١.
  static const _scopedTables = <String, String>{
    'sales_invoices': 'branch_id',
    'purchase_invoices': 'branch_id',
    'journal_entries': 'branch_id',
    'stock_movements': 'branch_id',
    'activity_logs': 'branch_id',
  };

  /// Read-only — returns the count per table of rows that would be
  /// deleted by [wipeForeignBranchData]. Empty map when no foreign rows
  /// exist anywhere (the common steady-state on a client that's been
  /// running with the server-side filter from day one).
  Future<Map<String, int>> dryRunForeignBranchCounts(
    Set<int> allowedBranchIds,
  ) async {
    if (allowedBranchIds.isEmpty) {
      // Empty allowed set means full access (admin) — there are no
      // foreign rows by definition. Mirrors BranchScope.fullAccess.
      return const {};
    }
    final result = <String, int>{};
    final placeholders = List.filled(allowedBranchIds.length, '?').join(',');
    final ids = allowedBranchIds.map((i) => Variable.withInt(i)).toList();
    for (final entry in _scopedTables.entries) {
      final table = entry.key;
      final col = entry.value;
      try {
        final rows = await customSelect(
          'SELECT COUNT(*) AS c FROM $table '
          'WHERE $col IS NOT NULL AND $col NOT IN ($placeholders)',
          variables: ids,
        ).get();
        final count = rows.isEmpty ? 0 : (rows.first.data['c'] as int? ?? 0);
        if (count > 0) result[table] = count;
      } catch (e) {
        // لا تبلع. عدّ ناقص هنا يسبق **حذفاً** يوافق عليه المستخدم بناءً
        // عليه، فالصمت أخطر من الفشل: الشاشة تقول «لا صفوف غريبة» بينما
        // الجدول لم يُستعلَم أصلاً.
        debugPrint('[BRANCH-CLEANUP-DRYRUN] $table failed: $e');
        rethrow;
      }
    }
    if (result.isEmpty) {
      debugPrint('[BRANCH-CLEANUP-DRYRUN] no foreign rows found');
    } else {
      debugPrint('[BRANCH-CLEANUP-DRYRUN] foreign-branch rows present: $result');
    }
    return result;
  }

  /// Destructive — deletes the rows surfaced by
  /// [dryRunForeignBranchCounts]. Wrapped in a transaction so a partial
  /// failure rolls back the whole cleanup. Returns the per-table count
  /// of rows actually deleted (zero entries omitted). Pre-existing
  /// `client_branch_scope_v5_migrated` setting is flipped to `'true'`
  /// on success so the settings UI hides the cleanup prompt afterwards.
  ///
  /// **The caller is responsible for confirming with the user before
  /// calling this method** — the dry-run + UI confirmation flow lives
  /// in the settings widget. This DAO method does NOT prompt; it just
  /// executes the delete.
  Future<Map<String, int>> wipeForeignBranchData(
    Set<int> allowedBranchIds,
  ) async {
    if (allowedBranchIds.isEmpty) return const {};
    final placeholders = List.filled(allowedBranchIds.length, '?').join(',');
    final ids = allowedBranchIds.map((i) => Variable.withInt(i)).toList();
    final deleted = <String, int>{};
    await transaction(() async {
      for (final entry in _scopedTables.entries) {
        final table = entry.key;
        final col = entry.value;
        try {
          final beforeRow = await customSelect(
            'SELECT COUNT(*) AS c FROM $table '
            'WHERE $col IS NOT NULL AND $col NOT IN ($placeholders)',
            variables: ids,
          ).get();
          final before =
              beforeRow.isEmpty ? 0 : (beforeRow.first.data['c'] as int? ?? 0);
          if (before == 0) continue;
          await customStatement(
            'DELETE FROM $table '
            'WHERE $col IS NOT NULL AND $col NOT IN ($placeholders)',
            ids.map((v) => v.value).toList(),
          );
          deleted[table] = before;
          debugPrint('[BRANCH-CLEANUP] deleted $before from $table');
        } catch (e) {
          debugPrint('[BRANCH-CLEANUP] $table failed inside transaction: $e');
          rethrow; // Roll back the entire cleanup on any failure.
        }
      }
      // Mark the migration as completed so the UI stops prompting. Done
      // INSIDE the transaction so a partial failure also un-marks it.
      await customStatement(
        "UPDATE settings SET value = 'true' "
        "WHERE key = 'client_branch_scope_v5_migrated'",
      );
    });
    return deleted;
  }
}
