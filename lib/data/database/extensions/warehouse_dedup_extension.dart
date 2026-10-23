import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import '../database.dart';

/// Spec 150 / BUG 5b — merge duplicate warehouse rows that piled up on
/// client/mirror devices before `WarehouseSyncStrategy`'s dedup tiers
/// closed the sync-time gap that let a server-origin "المخزن الرئيسي"
/// duplicate the locally-seeded default. Mirrors [BranchDedupExtension]
/// exactly — same survivor rule, same "never hard-delete without
/// repointing FKs first" discipline.
///
/// Two operations, both gated by an explicit caller (NEVER auto-run on
/// startup unsupervised — destructive, mirrors the [BranchDedupExtension]
/// pattern):
///
///   * [dryRunDuplicateWarehouseGroups] — read-only. Returns groups of
///     `[id, name]` for warehouses sharing the same trimmed name. Empty
///     list = clean state. Idempotent and cheap.
///
///   * [mergeDuplicateWarehouses] — for each group, picks the survivor
///     (preference: row with non-null `globalId`, then smallest `id`),
///     repoints every dependent table's `warehouse_id` from each
///     duplicate to the survivor, then deletes the duplicates. Wrapped
///     in a single transaction. Returns the count of rows deleted (not
///     group count).
extension WarehouseDedupExtension on AppDatabase {
  // ── Schema map ────────────────────────────────────────────────────
  // Tables with a single `warehouse_id` column and no other constraint
  // riding on it. Updated with a plain `UPDATE ... SET warehouse_id =
  // survivor WHERE warehouse_id = dup`.
  static const _singleFkTables = <String>[
    'cycle_count_plans',
    'purchase_invoices',
    'sales_invoices',
    'purchase_orders',
    'sales_orders',
    'sale_bom_consumptions',
    'product_batches',
    'products',
    'quotations',
    'manufacturing_orders',
    'stock_movements',
    'stock_audits',
  ];

  // inventory_bonds carries both the source warehouse and, for transfer
  // bonds, the destination warehouse. Both columns get the same survivor
  // mapping so a transfer that pointed at "duplicate-of-main → some-
  // other-warehouse" survives as "main → some-other-warehouse".
  static const _twoFkTable = 'inventory_bonds';
  static const _twoFkColumns = <String>['warehouse_id', 'to_warehouse_id'];

  // Table where `(user_id, warehouse_id)` is the composite PK. Naive
  // UPDATE would conflict if `(user_id, survivor)` already exists — use
  // `INSERT OR IGNORE` to copy missing links to the survivor first, then
  // DELETE the duplicate's rows.
  static const _compositePkTables = <Map<String, String>>[
    {'table': 'user_warehouse_access', 'otherCol': 'user_id'},
  ];

  // Tables where `(product_id, warehouse_id)` is UNIQUE but `id` (not
  // that pair) is the primary key. A plain UPDATE risks the same
  // conflict as the composite-PK tables above whenever the survivor
  // warehouse already carries a balance/price row for the same product —
  // a real case here, since a duplicate "المخزن الرئيسي" and its
  // survivor are, by definition, the same warehouse from the business's
  // point of view and are likely to stock the same products. Same
  // INSERT-OR-IGNORE-then-DELETE technique as the composite-PK tables,
  // extended to carry the data columns across so a non-colliding
  // duplicate keeps its quantity/price instead of resetting to defaults.
  static const _uniqueKeyTables = <Map<String, Object>>[
    {
      'table': 'inventory_balances',
      'dataColumns': <String>[
        'quantity',
        'reserved_quantity',
        'average_cost',
        'last_updated',
      ],
      // Columns surfaced in the SYNC-WARN audit line when a colliding row
      // is discarded (product already stocked on the survivor).
      'logColumns': <String>['product_id', 'quantity', 'average_cost'],
    },
    {
      'table': 'warehouse_prices',
      'dataColumns': <String>[
        'sale_price',
        'cost_price',
        'wholesale_price',
        'notes',
      ],
      'logColumns': <String>['product_id', 'sale_price'],
    },
  ];

  /// Read-only dry-run. Returns one entry per duplicate group:
  /// `{normalizedName, ids: [...], names: [...]}`. The `names` list keeps
  /// the original (un-normalized) names so a settings UI could surface
  /// "المخزن الرئيسي" vs "المخزن الرئيسي " (trailing-space) to the operator.
  Future<List<Map<String, dynamic>>> dryRunDuplicateWarehouseGroups() async {
    // Cluster 030 / Bug A: PG rejects alias references in HAVING.
    // Use the aggregate directly so the same SQL works on both
    // SQLite and PostgreSQL (the PG compat layer maps GROUP_CONCAT
    // → STRING_AGG transparently).
    final rows = await customSelect(
      'SELECT TRIM(name) AS norm, '
      "       GROUP_CONCAT(id, ',') AS ids, "
      "       GROUP_CONCAT(name, '|') AS names, "
      '       COUNT(*) AS c '
      'FROM warehouses '
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
      debugPrint('[WAREHOUSE-DEDUP-DRYRUN] no duplicate groups');
    } else {
      debugPrint('[WAREHOUSE-DEDUP-DRYRUN] ${groups.length} duplicate groups');
    }
    return groups;
  }

  /// Destructive — merges every duplicate group surfaced by
  /// [dryRunDuplicateWarehouseGroups]. Survivor preference: row whose
  /// `global_id` is NOT NULL (server-blessed identity), then smallest id.
  /// All dependent FKs are repointed to the survivor before the
  /// duplicates are deleted, so no orphan rows are left behind.
  ///
  /// Returns the total count of warehouse rows deleted (not the group
  /// count). Idempotent: a second call returns 0.
  Future<int> mergeDuplicateWarehouses() async {
    final groups = await dryRunDuplicateWarehouseGroups();
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
          'SELECT id, global_id FROM warehouses WHERE id IN '
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
          await remapWarehouseFks(dup, survivor);
          await customStatement(
            'DELETE FROM warehouses WHERE id = ?',
            [Variable.withInt(dup).value],
          );
          totalDeleted++;
          debugPrint('[WAREHOUSE-DEDUP] merged $dup → $survivor '
              '(name="${g['normalizedName']}")');
        }
      }
    });
    debugPrint('[WAREHOUSE-DEDUP] deleted $totalDeleted duplicate warehouse rows total');
    return totalDeleted;
  }

  /// Repoint every dependent FK from [fromId] to [toId] across the
  /// canonical dependent-table list (12 single-FK tables + `inventory_bonds`
  /// two-FK + the `user_warehouse_access` composite-PK table + the
  /// `inventory_balances`/`warehouse_prices` unique-key tables). Package-
  /// private (no underscore) so `WarehouseSyncStrategy` can call it from
  /// its own straggler-cleanup pass without a top-level helper.
  ///
  /// [mergePrices] guards the `warehouse_prices` merge. The supervised
  /// [mergeDuplicateWarehouses] leaves it `true`. The unsupervised
  /// sync-time straggler pass passes `false`: unlike `inventory_balances`
  /// (re-applied later in the same pull by InventoryBalanceSyncStrategy),
  /// `warehouse_prices` has NO server→client re-sync, so discarding a
  /// colliding price row there would be permanent. With `false` the price
  /// rows follow the deactivated warehouse untouched instead.
  ///
  /// Caller is responsible for wrapping in `db.transaction()` if atomic
  /// behavior across multiple remap+delete sequences is needed; this
  /// method itself only issues the row writes.
  Future<void> remapWarehouseFks(int fromId, int toId,
      {bool mergePrices = true}) async {
    final fromVar = Variable.withInt(fromId).value;
    final toVar = Variable.withInt(toId).value;

    for (final table in _singleFkTables) {
      await customStatement(
        'UPDATE $table SET warehouse_id = ? WHERE warehouse_id = ?',
        [toVar, fromVar],
      );
    }

    // inventory_bonds has two warehouse columns.
    for (final col in _twoFkColumns) {
      await customStatement(
        'UPDATE $_twoFkTable SET $col = ? WHERE $col = ?',
        [toVar, fromVar],
      );
    }

    // Composite-PK table: copy missing links to survivor, then drop the
    // duplicate's rows. INSERT OR IGNORE handles the already-exists case
    // gracefully on SQLite; pg_compat_sql.dart translates to ON CONFLICT
    // DO NOTHING for PG (commit 8bfa2b8).
    for (final t in _compositePkTables) {
      final tbl = t['table']!;
      final otherCol = t['otherCol']!;
      await customStatement(
        'INSERT OR IGNORE INTO $tbl ($otherCol, warehouse_id) '
        'SELECT $otherCol, ? FROM $tbl WHERE warehouse_id = ?',
        [toVar, fromVar],
      );
      await customStatement(
        'DELETE FROM $tbl WHERE warehouse_id = ?',
        [fromVar],
      );
    }

    // Unique-key tables — same INSERT-OR-IGNORE-then-DELETE idiom, with
    // the data columns carried across so a duplicate that doesn't
    // collide with the survivor's existing row keeps its values instead
    // of being reset to column defaults.
    for (final t in _uniqueKeyTables) {
      final tbl = t['table'] as String;
      // Prices are never re-synced from the server — skip the destructive
      // merge unless the supervised path explicitly opted in (see
      // [mergePrices]).
      if (tbl == 'warehouse_prices' && !mergePrices) continue;
      final dataColumns = (t['dataColumns'] as List).cast<String>();
      final logColumns = (t['logColumns'] as List).cast<String>();

      // Audit-log the rows about to be discarded — those whose product is
      // ALREADY stocked on the survivor, so INSERT OR IGNORE keeps the
      // survivor's row and the dup's values are dropped. Under R4/R9 an
      // unsupervised balance mutation must leave a trace.
      final collisions = await customSelect(
        'SELECT ${logColumns.join(', ')} FROM $tbl '
        'WHERE warehouse_id = ? '
        'AND product_id IN (SELECT product_id FROM $tbl WHERE warehouse_id = ?)',
        variables: [Variable.withInt(fromId), Variable.withInt(toId)],
      ).get();
      if (collisions.isNotEmpty) {
        final sample = collisions
            .take(10)
            .map((r) =>
                '{${logColumns.map((c) => '$c=${r.data[c]}').join(', ')}}')
            .join(', ');
        await DiagnosticLogger.log(
          'SYNC-WARN',
          '$tbl merge dropped ${collisions.length} duplicate row(s) from '
          'warehouse $fromId (product already on survivor $toId) — survivor '
          'values kept. Discarded: $sample',
        );
      }

      final colList = (['product_id', ...dataColumns]).join(', ');
      await customStatement(
        'INSERT OR IGNORE INTO $tbl (warehouse_id, $colList) '
        'SELECT ?, $colList FROM $tbl WHERE warehouse_id = ?',
        [toVar, fromVar],
      );
      await customStatement(
        'DELETE FROM $tbl WHERE warehouse_id = ?',
        [fromVar],
      );
    }

    // F4 (spec 150) — repoint any POS default-warehouse setting off the
    // duplicate so the sale-flow FK pre-flight (Spec 131 FR-005) doesn't
    // reject a dangling id once the dup is deactivated/deleted. The
    // settings.value column is TEXT, so bind the ids as strings.
    await customStatement(
      "UPDATE settings SET value = ? "
      "WHERE key LIKE 'pos_default_warehouse%' AND value = ?",
      [toId.toString(), fromId.toString()],
    );
  }
}
