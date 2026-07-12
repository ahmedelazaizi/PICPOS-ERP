import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show UpdateKind, Variable;
import '../database.dart';

/// Feature 016 — backfill `sales_invoice_items.cost_price` for legacy rows
/// where it was never stamped.
///
/// Mirror devices sold for months with the local-cache invoice insert path
/// not setting `cost_price` (the bug Feature 016's main change fixes). All
/// those legacy rows have `cost_price IS NULL` or `cost_price = 0`, which
/// makes the analytics COGS query at
/// [SalesAnalyticsDao.getProfitAndLoss] return 0 and inflates net profit.
///
/// This pass is a one-shot historical fix-up: for every zero/null
/// `cost_price` row, copy `products.cost_price` (the current WAC) onto the
/// item. This is "good enough" — exact at-sale-time WAC is unrecoverable
/// client-side (the server doesn't keep an audit trail either if WAC has
/// drifted since). Documented as approximate in the spec.
///
/// Idempotent: a clean DB exits the dry-run in O(1) and the destructive
/// pass returns 0. Skips rows whose product was deleted in the meantime.
extension SalesCogsBackfillExtension on AppDatabase {
  /// Read-only — returns the number of rows that
  /// [backfillSalesItemCostPrice] would update on a real run.
  Future<int> dryRunSalesCogsBackfill() async {
    // Use COALESCE so the count covers BOTH null and 0 in one scan.
    final rows = await customSelect(
      'SELECT COUNT(*) AS missing '
      'FROM sales_invoice_items si '
      'JOIN products p ON p.id = si.product_id '
      'WHERE COALESCE(si.cost_price, 0) = 0 '
      "AND COALESCE(p.cost_price, 0) > 0",
    ).get();
    if (rows.isEmpty) return 0;
    return (rows.first.data['missing'] as int?) ?? 0;
  }

  /// Destructive — UPDATE every `sales_invoice_items` row whose
  /// `cost_price` is null or 0 to match the current `products.cost_price`.
  /// Skips items whose product is missing (deleted) — those stay at 0
  /// and are logged for visibility.
  ///
  /// Wrapped in a transaction so a partial failure rolls back. Returns
  /// the count of rows updated.
  Future<int> backfillSalesItemCostPrice() async {
    final candidates = await dryRunSalesCogsBackfill();
    if (candidates == 0) {
      debugPrint('[COGS-BACKFILL] no legacy zero-cost rows found — skipping');
      return 0;
    }

    // Single SQL UPDATE…FROM-style fix in a portable form: per-row update
    // gated on the JOIN. Keeps drift_postgres compatibility (no UPDATE…FROM
    // in SQLite legacy mode either).
    final updated = await transaction(() async {
      final affected = await customUpdate(
        'UPDATE sales_invoice_items '
        'SET cost_price = ('
        '  SELECT cost_price FROM products WHERE products.id = sales_invoice_items.product_id'
        ') '
        'WHERE COALESCE(cost_price, 0) = 0 '
        'AND EXISTS ('
        '  SELECT 1 FROM products WHERE products.id = sales_invoice_items.product_id '
        '  AND COALESCE(products.cost_price, 0) > 0'
        ')',
        updates: {salesInvoiceItems},
        updateKind: UpdateKind.update,
      );
      return affected;
    });

    debugPrint('[COGS-BACKFILL] updated $updated row(s) from product WAC');

    // Visibility: orphan rows (product missing OR product WAC=0) are not
    // patched — log the count so the field can flag investigation.
    final orphans = await customSelect(
      'SELECT COUNT(*) AS orphans '
      'FROM sales_invoice_items si '
      'WHERE COALESCE(si.cost_price, 0) = 0 '
      'AND NOT EXISTS ('
      '  SELECT 1 FROM products p WHERE p.id = si.product_id '
      '  AND COALESCE(p.cost_price, 0) > 0'
      ')',
      variables: const <Variable>[],
    ).get();
    final orphanCount = (orphans.first.data['orphans'] as int?) ?? 0;
    if (orphanCount > 0) {
      debugPrint('[COGS-BACKFILL] $orphanCount row(s) still at 0 — '
          'product missing or WAC=0; skipped');
    }

    return updated;
  }

  /// C-PERF-3: one-shot wrapper for boot. The dry-run + UPDATE is a full JOIN
  /// scan (NOT O(1) despite the legacy comment), so it ran on every boot. Once
  /// a pass patches nothing (clean), the `cogs_backfill_done` flag is set and
  /// later boots skip the scan. Returns rows updated, or -1 when skipped.
  Future<int> backfillSalesItemCostPriceOnce() async {
    const flag = 'cogs_backfill_done';
    if (await getSettingValue(flag) == 'true') return -1;
    final updated = await backfillSalesItemCostPrice();
    // F-ACCT-1: only arm the one-shot flag once NO zero-cost sales item remains
    // whose product still EXISTS. `updated == 0` also happens when the only
    // remaining zero-cost rows belong to products that are currently uncosted
    // (cost_price = 0) — those gain a WAC on a later purchase and MUST still be
    // backfilled, or getProfitAndLoss understates COGS forever. Orphan rows
    // (product deleted) are never patchable, so they must not pin the scan on.
    // The cheap COUNT keeps re-running each boot; the expensive UPDATE only
    // fires when candidates > 0 (unchanged), preserving the C-PERF-3 win.
    final pending = await customSelect(
      'SELECT COUNT(*) AS c FROM sales_invoice_items si '
      'WHERE COALESCE(si.cost_price, 0) = 0 '
      'AND EXISTS (SELECT 1 FROM products p WHERE p.id = si.product_id)',
    ).get();
    final remaining = (pending.first.data['c'] as int?) ?? 0;
    if (remaining == 0) await setSetting(flag, 'true');
    return updated;
  }
}
