// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

class PurchaseSyncStrategy extends SyncStrategy {
  PurchaseSyncStrategy(super.db);

  @override
  String get tableName => 'purchases';

  @override
  String get apiEndpoint => '/api/purchases';

  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.appendOnly;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final purchases = json['purchases'] as List? ?? [];
    for (final purchase in purchases) {
      await _syncSinglePurchase(purchase as Map<String, dynamic>);
    }
    // Force UI refresh after sync
    if (purchases.isNotEmpty) {
      db.markTablesUpdated({db.purchaseInvoices, db.purchaseInvoiceItems});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0; // Full sync only for now
  }

  Future<void> _syncSinglePurchase(Map<String, dynamic> purchaseMap) async {
    try {
      final serverId = parseInt(purchaseMap['id']);

      // Spec 136 (field 2026-06-14): resolve server supplierId → LOCAL party id
      // via FK mappings — the SAME remap sales_sync_strategy does for customerId.
      // PartySyncStrategy keeps a locally-created party's own auto-increment id
      // (matched by globalId), so on a mirror the supplier may live under a
      // different id than the server stored. Storing the raw server supplierId
      // in the purchase FK made the supplier's account statement come up EMPTY
      // on the mirror (getPartyStatement filters purchase_invoices.supplierId by
      // the local party id). Resolve it so purchases attach to the local party.
      final serverSupplierId = parseInt(purchaseMap['supplierId']);
      final resolvedSupplierId =
          await resolveLocalPartyId(serverSupplierId, label: 'supplierId') ??
              serverSupplierId;

      // Check if already exists (by server ID) for update handling
      final existing = await (db.select(db.purchaseInvoices)
            ..where((p) => p.id.equals(serverId))
            ..limit(1))
          .getSingleOrNull();

      if (existing != null) {
        // Update mutable fields on existing records
        await (db.update(db.purchaseInvoices)
              ..where((p) => p.id.equals(serverId)))
            .write(PurchaseInvoicesCompanion(
              isDeleted: Value(parseBool(purchaseMap['isDeleted'])),
              deletedAt: Value(purchaseMap['deletedAt'] != null
                  ? DateTime.tryParse(purchaseMap['deletedAt'].toString())
                  : null),
              status: Value(purchaseMap['status'] as String? ?? existing.status),
              isLocked: Value(parseBool(purchaseMap['isLocked'], existing.isLocked)),
              paymentMethod: Value(purchaseMap['paymentMethod'] as String? ?? existing.paymentMethod),
              paid: Value(parseDouble(purchaseMap['paid'])),
              supplierId: Value(resolvedSupplierId), // heal stale server id
              updatedAt: Value(DateTime.tryParse(purchaseMap['updatedAt']?.toString() ?? '') ?? DateTime.now()),
            ));
        debugPrint('[Sync] Updated existing purchase #$serverId');
        return;
      }

      // Also skip if a local purchase with the same invoice number already exists
      // (prevents duplicates when client creates locally then syncs server copy)
      final invoiceNumber = purchaseMap['invoiceNumber'] as String?;
      if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
        final byNumber = await (db.select(db.purchaseInvoices)
              ..where((p) => p.invoiceNumber.equals(invoiceNumber))
              ..limit(1))
            .getSingleOrNull();
        if (byNumber != null) {
          debugPrint('[Sync] Skipping purchase #$serverId — invoice $invoiceNumber already exists locally as id=${byNumber.id}');
          return;
        }
      }

      final warehouseId = parseInt(purchaseMap['warehouseId'], 1);

      await db.into(db.purchaseInvoices).insertOnConflictUpdate(
            PurchaseInvoicesCompanion(
              id: Value(serverId),
              invoiceNumber: Value(purchaseMap['invoiceNumber'] as String? ?? 'SYNC-$serverId'),
              supplierId: Value(resolvedSupplierId),
              warehouseId: Value(warehouseId),
              branchId: Value(parseIntNullable(purchaseMap['branchId'])),
              invoiceDate: Value(DateTime.tryParse(purchaseMap['invoiceDate']?.toString() ?? '') ?? DateTime.now()),
              subtotal: Value(parseDouble(purchaseMap['subtotal'])),
              discount: Value(parseDouble(purchaseMap['discount'])),
              tax: Value(parseDouble(purchaseMap['tax'])),
              total: Value(parseDouble(purchaseMap['total'])),
              paid: Value(parseDouble(purchaseMap['paid'])),
              paymentMethod: Value(purchaseMap['paymentMethod'] as String? ?? 'cash'),
              status: Value(purchaseMap['status'] as String? ?? 'completed'),
              isLocked: Value(parseBool(purchaseMap['isLocked'])),
              isDeleted: Value(parseBool(purchaseMap['isDeleted'])),
              deletedAt: Value(purchaseMap['deletedAt'] != null
                  ? DateTime.tryParse(purchaseMap['deletedAt'].toString())
                  : null),
              updatedAt: Value(DateTime.tryParse(purchaseMap['updatedAt']?.toString() ?? '') ?? DateTime.now()),
              notes: Value(purchaseMap['notes'] as String?),
              costCenterId: Value(parseIntNullable(purchaseMap['costCenterId'])),
              supplierInvoiceNumber: Value(purchaseMap['supplierInvoiceNumber'] as String?),
              createdAt: Value(DateTime.tryParse(purchaseMap['createdAt']?.toString() ?? '') ?? DateTime.now()),
            ),
          );

      // Insert purchase items AND materialize stock
      final items = purchaseMap['items'] as List? ?? [];
      for (final item in items) {
        final itemMap = item as Map<String, dynamic>;
        // Issue 11 (Feature 018): remap server productId → local id (see
        // sales_sync_strategy for the full reasoning).
        final remoteProductId = parseInt(itemMap['productId']);
        final productId = await db.resolveItemFk(
          'products',
          remoteProductId,
          context: 'purchase_invoice_items invoice=$serverId',
        );
        final quantity = parseDouble(itemMap['quantity']);
        final unitCost = parseDouble(itemMap['unitCost']);

        // Issue 3 (Feature 022): dedup by globalId first, then by
        // (invoiceId, productId). Field evidence showed mirror operators
        // seeing duplicate item rows on a re-opened purchase invoice. The
        // legacy `insertOnConflictUpdate` keyed only on `id` — but client
        // and server item ids commonly diverge after sync, so the
        // strategy inserted a second row instead of updating the first.
        final remoteGlobalId = itemMap['globalId'] as String?;
        PurchaseInvoiceItem? existingItem;
        if (remoteGlobalId != null && remoteGlobalId.isNotEmpty) {
          existingItem = await (db.select(db.purchaseInvoiceItems)
                ..where((i) => i.globalId.equals(remoteGlobalId))
                ..limit(1))
              .getSingleOrNull();
        }
        existingItem ??= await (db.select(db.purchaseInvoiceItems)
              ..where((i) =>
                  i.invoiceId.equals(serverId) &
                  i.productId.equals(productId))
              ..limit(1))
            .getSingleOrNull();

        if (existingItem != null) {
          // Server is source of truth — UPDATE the existing row's data
          // but KEEP its local id (and globalId) so any FK from
          // stock_movements stays valid.
          await (db.update(db.purchaseInvoiceItems)
                ..where((i) => i.id.equals(existingItem!.id)))
              .write(PurchaseInvoiceItemsCompanion(
            invoiceId: Value(serverId),
            productId: Value(productId),
            quantity: Value(quantity),
            unitCost: Value(unitCost),
            total: Value(parseDouble(itemMap['total'])),
            taxRate: Value(parseDouble(itemMap['taxRate'])),
            taxAmount: Value(parseDouble(itemMap['taxAmount'])),
            batchNumber: Value(itemMap['batchNumber'] as String?),
            expiryDate: Value(itemMap['expiryDate'] != null
                ? DateTime.tryParse(itemMap['expiryDate'].toString())
                : null),
          ));
        } else {
          await db.into(db.purchaseInvoiceItems).insert(
                PurchaseInvoiceItemsCompanion(
                  id: Value(parseInt(itemMap['id'])),
                  invoiceId: Value(serverId),
                  productId: Value(productId),
                  quantity: Value(quantity),
                  unitCost: Value(unitCost),
                  total: Value(parseDouble(itemMap['total'])),
                  taxRate: Value(parseDouble(itemMap['taxRate'])),
                  taxAmount: Value(parseDouble(itemMap['taxAmount'])),
                  batchNumber: Value(itemMap['batchNumber'] as String?),
                  expiryDate: Value(itemMap['expiryDate'] != null
                      ? DateTime.tryParse(itemMap['expiryDate'].toString())
                      : null),
                  globalId: remoteGlobalId != null && remoteGlobalId.isNotEmpty
                      ? Value(remoteGlobalId)
                      : const Value.absent(),
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }

        // PHASE-7 FIX: Materialize stock into the correct warehouse
        // Idempotency: check if stock_movements already has this reference
        final existingMovement = await (db.select(db.stockMovements)
              ..where((m) =>
                  m.referenceType.equals('purchase') &
                  m.referenceId.equals(serverId) &
                  m.productId.equals(productId))
              ..limit(1))
            .getSingleOrNull();

        if (existingMovement == null && quantity > 0) {
          await db.adjustStock(
            productId: productId,
            warehouseId: warehouseId,
            quantity: quantity,
            type: 'purchase',
            referenceType: 'purchase',
            referenceId: serverId,
            unitCost: unitCost,
            notes: 'Sync from server - Purchase #$serverId',
          );
          debugPrint('[Sync] Materialized stock: product=$productId, qty=$quantity, warehouse=$warehouseId');
        }
      }
    } catch (e) {
      debugPrint('[Sync] Error in PurchaseSyncStrategy: $e');
    }
  }

  @override
  Future<void> upsert(Insertable record) async {
    if (record is PurchaseInvoicesCompanion) {
      await db.into(db.purchaseInvoices).insertOnConflictUpdate(record);
    }
  }
}