// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';

/// Pulls sale_bom_consumptions rows from the server (where the auto-deplete
/// logic actually executes in client/mirror modes) into the local DB.
///
/// Feature 009 / T012b — without this strategy the consumption log written by
/// the server is invisible to clients/mirrors, breaking exact-cost returns
/// (FR-021) and sale-mode reports (US5). Constitution III + R5 mandate
/// `appendOnly` for the table type.
///
/// FK dependencies: sales_invoices, sales_invoice_items, bill_of_materials,
/// products, warehouses, branches. All are synced in earlier tiers
/// (BillOfMaterials sync arrives with the broader BOM master-data sync;
/// orphan rows on the receiving side are skipped with a debug warning so a
/// single mismatch never aborts the whole pull batch).
class SaleBomConsumptionSyncStrategy extends SyncStrategy {
  SaleBomConsumptionSyncStrategy(super.db);

  @override
  String get tableName => 'sale_bom_consumptions';

  @override
  String get apiEndpoint => '/api/sale-bom-consumptions';

  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.appendOnly;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final list = (json['sale_bom_consumptions'] as List?) ??
        (json['saleBomConsumptions'] as List?) ??
        const [];
    int written = 0;
    for (final item in list) {
      if (await _syncSingle(item as Map<String, dynamic>)) {
        written++;
      }
    }
    if (written > 0) {
      db.markTablesUpdated({db.saleBomConsumptions});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  Future<bool> _syncSingle(Map<String, dynamic> m) async {
    try {
      final serverGlobalId = m['globalId'] as String?;

      // appendOnly + deterministic globalId — if the row already exists by
      // globalId, skip silently. This is the idempotency contract that
      // applyAutoDepleteForSale (T015) honors when minting consumption ids.
      if (serverGlobalId != null && serverGlobalId.isNotEmpty) {
        final existing = await (db.select(db.saleBomConsumptions)
              ..where((t) => t.globalId.equals(serverGlobalId)))
            .getSingleOrNull();
        if (existing != null) return false;
      }

      // Insert. We let Drift's FK-on-insert raise if any parent row
      // (sales_invoices, products, ...) is missing locally — that signals
      // an upstream sync ordering issue worth surfacing in logs rather
      // than swallowing.
      await db.into(db.saleBomConsumptions).insert(
            SaleBomConsumptionsCompanion(
              saleInvoiceId: Value(parseInt(m['saleInvoiceId'])),
              saleInvoiceItemId: Value(parseInt(m['saleInvoiceItemId'])),
              bomId: Value(parseInt(m['bomId'])),
              rawMaterialId: Value(parseInt(m['rawMaterialId'])),
              consumedQty: Value(parseDouble(m['consumedQty'])),
              unitCostAtSale: Value(parseDouble(m['unitCostAtSale'])),
              wastageApplied: Value(parseDouble(m['wastageApplied'])),
              warehouseId: Value(parseInt(m['warehouseId'])),
              branchId: Value(parseIntNullable(m['branchId'])),
              reversedByReturnId:
                  Value(parseIntNullable(m['reversedByReturnId'])),
              createdAt: Value(
                DateTime.tryParse(m['createdAt'] as String? ?? '') ??
                    DateTime.now(),
              ),
              globalId: Value(serverGlobalId ?? ''),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      return true;
    } catch (e) {
      debugPrint(
          '[Sync] Skipped sale_bom_consumptions row (likely missing FK parent): $e');
      return false;
    }
  }

  @override
  Future<void> upsert(Insertable record) async {
    if (record is SaleBomConsumptionsCompanion) {
      await db.into(db.saleBomConsumptions).insert(
            record,
            mode: InsertMode.insertOrIgnore,
          );
    }
  }
}