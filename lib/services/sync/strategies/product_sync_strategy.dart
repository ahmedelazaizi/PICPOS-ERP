// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

class ProductSyncStrategy extends SyncStrategy {
  ProductSyncStrategy(super.db);

  @override
  String get tableName => 'products';

  @override
  String get apiEndpoint => '/api/products';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final products = json['products'] as List;
    for (final p in products) {
      final serverId = parseInt(p['id']);
      final productGlobalId = p['globalId'] as String?;
      final productCode = p['code'] as String? ?? '';

      // FIX 2026-04-28: Three-tier deduplication to prevent duplicate products
      // when a client creates a product locally (with a high local auto-increment
      // id like 1000000001) and the server later assigns its own id. Without
      // globalId/code-based matching, the same real-world product would appear
      // under two different ids (one local, one server), and after logout/login
      // both rows would show in the products list.
      Product? existing;
      // Tier 1: globalId match — strongest signal, survives id divergence
      if (productGlobalId != null && productGlobalId.isNotEmpty) {
        existing = await (db.select(db.products)
              ..where((t) => t.globalId.equals(productGlobalId)))
            .getSingleOrNull();
      }
      // Tier 2: code match — products have unique codes per business rule
      if (existing == null && productCode.isNotEmpty) {
        existing = await (db.select(db.products)
              ..where((t) => t.code.equals(productCode)))
            .getSingleOrNull();
      }
      // Tier 3: server id match — legacy path
      existing ??= await (db.select(db.products)
            ..where((t) => t.id.equals(serverId)))
          .getSingleOrNull();

      if (existing != null) {
        // Protect locally modified prices: if local price differs from server
        // AND the server data is older, log a conflict instead of overwriting
        final serverUpdated = DateTime.tryParse(p['updatedAt'] as String? ?? '');
        if (serverUpdated != null) {
          // If server data is older than local, skip price fields & log conflict
          // H-6 FIX: Compare against updatedAt (not createdAt) for accurate conflict detection
  // ignore: dead_code
          final localUpdated = existing.updatedAt ?? existing.createdAt;
          if (serverUpdated.isBefore(localUpdated)) {
            debugPrint('[Sync] ⚠️ Product #$serverId: server data is older than local — skipping price update');
            try {
              await db.into(db.syncConflictLog).insert(
                SyncConflictLogCompanion.insert(
                  conflictTable: 'products',
                  recordId: serverId.toString(),
                  resolution: 'skipped',
                  clientPayload: 'local_price=${existing.salePrice}, server_price=${p['salePrice']}',
                  reason: const Value('بيانات السيرفر أقدم من المحلية — تم الاحتفاظ بالبيانات المحلية'),
                ),
              );
            } catch (_) {}
            // Only update non-sensitive fields (name, category, etc.) — skip prices
            await (db.update(db.products)..where((t) => t.id.equals(existing!.id))).write(
              ProductsCompanion(
                name: Value(p['name'] as String),
                searchName: Value(p['searchName'] as String?),
                categoryId: Value(parseIntNullable(p['categoryId'])),
                isActive: Value(parseBool(p['isActive'], true)),
                isLocked: Value(parseBool(p['isLocked'], false)),
              ),
            );
            continue;
          }
        }
      }

      // Use existing local id if dedup matched, otherwise insert with server id.
      // Preserving the local id keeps any FKs (sales_invoice_items, stock_movements)
      // pointing at the same row instead of orphaning them when the server assigns
      // a different id.
      final useId = existing?.id ?? serverId;
      await db.into(db.products).insertOnConflictUpdate(
        ProductsCompanion(
          id: Value(useId),
          globalId: Value(productGlobalId),
          code: Value(p['code'] as String),
          barcode: Value(p['barcode'] as String?),
          name: Value(p['name'] as String),
          searchName: Value(p['searchName'] as String?),
          description: Value(p['description'] as String?),
          categoryId: Value(parseIntNullable(p['categoryId'])),
          unitId: Value(parseIntNullable(p['unitId'])),
          supplierId: Value(parseIntNullable(p['supplierId'])),
          warehouseId: Value(parseIntNullable(p['warehouseId'])),
          salePrice: Value(parseDouble(p['salePrice'])),
          wholesalePrice: Value(parseDouble(p['wholesalePrice'])),
          costPrice: Value(parseDouble(p['costPrice'])),
          minStock: Value(parseDouble(p['minStock'])),
          currentStock: Value(parseDouble(p['currentStock'])),
          isActive: Value(parseBool(p['isActive'], true)),
          isLocked: Value(parseBool(p['isLocked'], false)),
          trackInventory: Value(parseBool(p['trackInventory'], true)),
          isSoldByWeight: Value(parseBool(p['isSoldByWeight'], false)),
          pricePerUnit: Value(parseDoubleNullable(p['pricePerUnit'])),
          weightUnit: Value(p['weightUnit'] as String? ?? 'kg'),
          allowNegativeSale: Value(parseBool(p['allowNegativeSale'], false)),
          taxRate: Value(parseDouble(p['taxRate'])),
          scalePluNumber: Value(parseIntNullable(p['scalePluNumber'])),
          scaleType: Value(p['scaleType'] as String? ?? 'count'),
          sortOrder: Value(parseInt(p['sortOrder'])),
          updatedAt: Value(p['updatedAt'] != null ? DateTime.tryParse(p['updatedAt'].toString()) ?? DateTime.now() : DateTime.now()),
          // v138 (Issue 2): default true preserves the conservative
          // backfill semantics — if the server doesn't ship the column
          // (older server build), pulled rows are treated as
          // server-canonical and locked on the client edit dialog.
          createdOnServer: Value(parseBool(p['createdOnServer'], true)),
        ),
      );
      // B3: `tax_exempt` is a raw column (v182) outside the companion; it
      // changes money (0 % tax) so it is applied whenever the server sends
      // it. An older server omits the key → the local flag is left as is.
      if (p is Map && p.containsKey('taxExempt')) {
        await db.setProductTaxExempt(useId, parseBool(p['taxExempt'], false));
      }
    }
    // Force UI refresh after sync
    if (products.isNotEmpty) {
      // The upsert above rewrites currentStock, costPrice and salePrice from
      // the server. Without dropping the memoised rows, every reader keeps
      // serving the pre-sync figures until the process restarts — the same
      // failure `updateProductStock` had, reached from a different door.
      // This runs on every delta pull, so a stale entry here outlives any
      // number of syncs.
      db.invalidateProductCache();
      db.markTablesUpdated({db.products});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    // Logic from SyncService.incrementalSync moved here
    // Note: SyncService will handle the network call and pass JSON 
    // but the strategy should be able to trigger its own if needed.
    // However, to keep it simple and consistent with the current pattern:
    // SyncService will call a generic incremental endpoint or strategy-specific one.
    return 0; 
  }

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.products).insertOnConflictUpdate(record as ProductsCompanion);
  }
}
