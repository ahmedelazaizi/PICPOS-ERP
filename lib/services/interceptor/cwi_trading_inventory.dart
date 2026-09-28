part of '../client_write_interceptor.dart';


// ═══════════════════════════════════════════════════════════════════════════
// Trading module — Sales · Inventory · Commercial Papers · Safe Operations
//                  Stock Transfers · Purchase Auto-Push
//
// Part of the ClientWriteInterceptor library.
// ═══════════════════════════════════════════════════════════════════════════

class _CwiTradingInventory {
  _CwiTradingInventory._();

  // ── Sales ─────────────────────────────────────────────────────────────────


  // ── Inventory ─────────────────────────────────────────────────────────────

  static Future<bool> adjustStock({
    required int productId,
    required int warehouseId,
    required double quantity,
    String? type,
    String? notes,
    String? adjustmentEventGid, // Spec 135 BUG-A: per-event gid (caller-minted)
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing stock adjustment to server');

    final db = ClientWriteInterceptor._db;
    String? productGlobalId;
    if (db != null) {
      try {
        final p = await (db.select(db.products)
              ..where((c) => c.id.equals(productId))
              ..limit(1))
            .getSingleOrNull();
        if (p != null) {
          productGlobalId = p.globalId;
          if (productGlobalId == null || productGlobalId.isEmpty) {
            productGlobalId = const Uuid().v7();
            try {
              await (db.update(db.products)
                    ..where((c) => c.id.equals(productId)))
                  .write(ProductsCompanion(globalId: Value(productGlobalId)));
            } catch (error, stack) {
                unawaited(DiagnosticLogger.logError(
                  'SYNC-INTERCEPTOR',
                  'stock adjustment product identity persistence failed',
                  error,
                  stack,
                ));
              }
          }
        }
      } catch (e) {
        debugPrint(
            '[ClientInterceptor] product lookup for adjustStock failed (non-fatal): $e');
      }
    }

    // Spec 136 ISS-26 (#2 hardening / Spec 132) — thread the warehouse globalId
    // so the server resolves to its OWN warehouse id even when the mirror/client
    // local warehouse ids diverge. Without it, the raw warehouseId could miss on
    // the server ("Strict Mapping Violation") or land the stock movement in the
    // wrong warehouse — so opening-stock/adjustments wouldn't show on the branch.
    String? warehouseGlobalId;
    if (db != null) {
      try {
        final w = await (db.select(db.warehouses)
              ..where((c) => c.id.equals(warehouseId))
              ..limit(1))
            .getSingleOrNull();
        warehouseGlobalId = w?.globalId;
      } catch (e) {
        debugPrint(
            '[ClientInterceptor] warehouse lookup for adjustStock failed (non-fatal): $e');
      }
    }

    final payload = {
      'productId': productId,
      'productGlobalId': productGlobalId,
      'warehouseId': warehouseId,
      'warehouseGlobalId': warehouseGlobalId,
      'quantity': quantity,
      'type': type,
      'notes': notes,
      // Spec 135 BUG-A: carry the event gid in the outbox payload too, so an
      // offline replay re-sends the SAME id (idempotent on the server).
      'adjustmentEventGid': adjustmentEventGid,
    };
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'inventory',
      operation: 'adjust',
      payload: payload,
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy.adjustStock(
          productId: productId,
          warehouseId: warehouseId,
          quantity: quantity,
          type: type,
          notes: notes,
          productGlobalId: productGlobalId,
          warehouseGlobalId: warehouseGlobalId,
          adjustmentEventGid: adjustmentEventGid,
          idempotencyKey: reqIdemKey,
        );
      },
    );
  }

  /// One-shot reconciliation of local `inventory_balances` → server.
  /// Runs on client startup. Fails soft — never throws, never blocks startup.
  static Future<int> reconcileOpeningStocks() async {
    if (!SyncInterceptor.isClientMode) return 0;
    final db = ClientWriteInterceptor._db;
    if (db == null) return 0;

    try {
      final allBalances = await db.select(db.inventoryBalances).get();
      final balances = allBalances.where((b) => b.quantity > 0).toList();
      if (balances.isEmpty) return 0;

      debugPrint('[Reconcile] pushing ${balances.length} local inventory '
          'balance(s) to server as opening_stock (server will skip duplicates)');

      int pushed = 0;
      for (final bal in balances) {
        try {
          await adjustStock(
            productId: bal.productId,
            warehouseId: bal.warehouseId,
            quantity: bal.quantity,
            type: 'opening_stock',
            notes: 'Startup reconcile — materialise missing server balance',
          );
          pushed++;
        } catch (e) {
          debugPrint('[Reconcile] balance push failed for product=${bal.productId} '
              'warehouse=${bal.warehouseId}: $e');
        }
      }
      debugPrint('[Reconcile] pushed $pushed / ${balances.length} balance(s)');
      return pushed;
    } catch (e) {
      debugPrint('[Reconcile] reconcileOpeningStocks failed (non-fatal): $e');
      return 0;
    }
  }
}
