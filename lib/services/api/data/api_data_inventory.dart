// ApiDataHandler - stock adjust, categories, stock transfers and inventory bonds endpoints.
part of '../api_data_handler.dart';

/// Inventory and category endpoints of [ApiDataHandler].
extension ApiDataInventoryRoutes on ApiDataHandler {
  // ═══════════════════════════════════════════════════════════════
  // Inventory
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postStockAdjust(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.inventoryEdit);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postStockAdjust',
        // adjustStock writes a stock_movement, updates inventory_balances +
        // products.currentStock, and autoposts a JE for cycle_count /
        // adjustment / write_off / loss types.
        tables: const {
          'products', 'inventory', 'stock_movements',
          'accounting', 'journal_entries',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // Resolve productId — prefer globalId when the client sends one so a
      // client↔server id drift (different auto-increment sequences, outbox
      // replay after the row was created under a different server id) heals
      // transparently instead of failing silently and leaving `inventory_balances`
      // unpopulated. Mirrors the `categoryGlobalId` reconciliation already used
      // in postProduct.
      int productIdResolved = parseInt(data['productId']);
      final productGlobalId = data['productGlobalId'] as String?;
      if (productGlobalId != null && productGlobalId.isNotEmpty) {
        final existingByUuid = await (db.select(db.products)
              ..where((p) => p.globalId.equals(productGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existingByUuid != null) {
          productIdResolved = existingByUuid.id;
        }
      }
      if (productIdResolved <= 0) {
        throw Exception(
          'Validation Error: productId or productGlobalId is required.',
        );
      }

      final clientWhIdAdj = parseInt(data['warehouseId']);
      if (clientWhIdAdj == 0) throw Exception('Validation Error: warehouseId is required.');
      final resolvedWhIdAdj = await _resolveWarehouseId(
        clientWhIdAdj,
        branchId: parseIntNullable(data['branchId']),
        warehouseGlobalId: data['warehouseGlobalId'] as String?,
      );

      final type = data['type'] as String?;

      // Idempotency for opening_stock: if this (product, warehouse) already
      // has an opening_stock movement recorded, a repeat call (from outbox
      // retry OR the client startup reconcile) must NOT stack a second
      // opening balance on top — that would silently double the stock.
      // Treated as success so the caller / outbox stops retrying.
      if (type == 'opening_stock') {
        final existingMv = await (db.select(db.stockMovements)
              ..where((m) =>
                  m.productId.equals(productIdResolved) &
                  m.warehouseId.equals(resolvedWhIdAdj) &
                  m.movementType.equals('opening_stock'))
              ..limit(1))
            .getSingleOrNull();
        if (existingMv != null) {
          debugPrint('[API] postStockAdjust: opening_stock already recorded '
              'for product=$productIdResolved warehouse=$resolvedWhIdAdj '
              '— skipping (idempotent).');
          return jsonResponse({
            'success': true,
            'skipped': 'opening_stock_already_applied',
          });
        }
      }

      await db.adjustStock(
        productId: productIdResolved,
        warehouseId: resolvedWhIdAdj,
        quantity: parseDouble(data['quantity']),
        type: type,
        notes: data['notes'] as String?,
        // Spec 135 BUG-A: honour the client-minted event gid so the server's
        // autoposted JE converges on the SAME deterministic globalId as the
        // client's, and the UNIQUE constraint dedups a replay instead of the
        // server re-deriving a colliding ...ref0... id.
        adjustmentEventGid: data['adjustmentEventGid'] as String?,
      );
      return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postStockAdjust error: $e');
      return ApiErrors.fail(e, 'Failed to adjust stock');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Categories
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postCategory(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.categoriesAdd);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final isGlobal = parseBool(data['isGlobal'], true);
      final clientGlobalId = (data['globalId'] as String?)?.trim();
      final name = data['name'] as String;

      // Issue 1 — dedup-by-globalId so a retried create from the client outbox
      // (or a duplicate POST from a different device that already received the
      // record via WebSocket pull) doesn't end up as a second row on the
      // server. The strategy already dedups by globalId on the read side; we
      // need the same guarantee on the write side because not all clients
      // pull before posting.
      if (clientGlobalId != null && clientGlobalId.isNotEmpty) {
        final existing = await (db.select(db.categories)
              ..where((c) => c.globalId.equals(clientGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postCategory dedup: globalId=$clientGlobalId '
              'already exists as id=${existing.id}; returning that id.');
          return jsonResponse({'success': true, 'id': existing.id, 'deduped': true});
        }
      }

      final id = await db.insertCategoryWithPrinter(
        name: name,
        color: data['color'] as String? ?? '#2563EB',
        printerId: parseIntNullable(data['printerId']),
        iconName: data['iconName'] as String?,
      );

      // Now update the global flag, branch links, and globalId stamp using
      // raw updates since insertCategoryWithPrinter doesn't expose them.
      await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          isGlobal: Value(isGlobal),
          isLocked: Value(parseBool(data['isLocked'], false)),
          isExcluded: Value(parseBool(data['isExcluded'], false)),
          showInPos: Value(parseBool(data['showInPos'], true)),
          globalId: (clientGlobalId != null && clientGlobalId.isNotEmpty)
              ? Value(clientGlobalId)
              : const Value.absent(),
        )
      );

      final branchIdsList = data['branchIds'] as List?;
      if (branchIdsList != null) {
        final intBranchIds = branchIdsList.map((e) => parseInt(e)).toList();
        await db.setCategoryBranches(id, intBranchIds);
      }

      broadcast('categories');
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      debugPrint('[API] postCategory error: $e');
      return ApiErrors.fail(e, 'Failed to create category');
    }
  }

  Future<Response> putCategory(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.categoriesEdit);
      if (perm != null) return perm;
      final categoryId = int.parse(id);
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      
      final isGlobal = parseBool(data['isGlobal'], true);

      await db.updateCategoryWithPrinter(
        id: categoryId,
        name: data['name'] as String,
        color: data['color'] as String? ?? '#2563EB',
        printerId: parseIntNullable(data['printerId']),
        iconName: data['iconName'] as String?,
      );

      // Same as above, update extra flags
      await (db.update(db.categories)..where((c) => c.id.equals(categoryId))).write(
        CategoriesCompanion(
          isGlobal: Value(isGlobal),
          isLocked: Value(parseBool(data['isLocked'], false)),
          isExcluded: Value(parseBool(data['isExcluded'], false)),
          showInPos: Value(parseBool(data['showInPos'], true)),
        )
      );

      final branchIdsList = data['branchIds'] as List?;
      if (branchIdsList != null) {
        final intBranchIds = branchIdsList.map((e) => parseInt(e)).toList();
        await db.setCategoryBranches(categoryId, intBranchIds);
      }

      broadcast('categories');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putCategory error: $e');
      return ApiErrors.fail(e, 'Failed to update category');
    }
  }

  Future<Response> deleteCategory(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.categoriesDelete);
      if (perm != null) return perm;
      final catId = int.parse(id);
      // Feature 045 — accept `moveToCategoryId` from either the query
      // string (the way server_proxy.deleteCategory ships it) or the
      // request body (defensive — older replays might use either).
      // A literal NULL value means "leave products uncategorized";
      // `Products.categoryId` is nullable so that's a valid resting
      // state. The DAO runs the move + soft-delete atomically.
      int? moveToCategoryId;
      final qpRaw = request.requestedUri.queryParameters['moveToCategoryId'];
      if (qpRaw != null && qpRaw.isNotEmpty) {
        moveToCategoryId = int.tryParse(qpRaw);
      }
      if (moveToCategoryId == null) {
        try {
          final body = await request.readAsString();
          if (body.isNotEmpty) {
            final data = json.decode(body);
            if (data is Map && data['moveToCategoryId'] != null) {
              moveToCategoryId = parseIntNullable(data['moveToCategoryId']);
            }
          }
        } catch (_) {/* DELETE bodies are optional; silent ignore */}
      }

      await db.deleteCategory(catId, moveToCategoryId: moveToCategoryId);
      broadcast('categories');
      // Soft-delete still broadcasts a delete event to clients so any
      // open UI refresh. The local row is now `isActive=false` rather
      // than physically gone; sync strategies UPDATE it on pull.
      broadcastRecordDeleted('categories', catId);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete category');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Stock Transfers (Client → Server sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postStockTransfer(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.inventoryTransfer);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final fromWarehouseId = await _resolveWarehouseId(parseInt(data['fromWarehouseId']));
      final toWarehouseId = await _resolveWarehouseId(parseInt(data['toWarehouseId']));
      final userId = await _resolveUserIdNullable(parseIntNullable(data['userId']),
          fallbackUsername: data['createdByUsername'] as String?);
      final notes = data['notes'] as String? ?? 'تحويل مخزني من عميل';
      // Spec 129 F4 — caller-minted globalId stamped on the inventory_bonds
      // row created below. Dedup against it before doing the stock moves so a
      // retried request can't double-deduct from the source warehouse.
      final incomingGlobalId = (data['globalId'] as String?)?.trim();
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.inventoryBonds)
              ..where((b) => b.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postStockTransfer: duplicate globalId=$incomingGlobalId — skipping (serverBondId=${existing.id})');
          return jsonResponse({'success': true, 'dedup': true});
        }
      }

  // ignore: unused_local_variable
      final transferBondId = await db.transaction(() async {
        // Record the header and every stock movement atomically.
        final transferBondId = await db.into(db.inventoryBonds).insert(
          InventoryBondsCompanion.insert(
            bondNumber: await db.generateInvoiceNumber('TRF'),
            type: const Value('transfer'),
            warehouseId: fromWarehouseId,
            toWarehouseId: Value(toWarehouseId),
            notes: Value(notes),
            createdBy: Value(userId),
            bondDate: Value(DateTime.now()),
            globalId: Value(incomingGlobalId),
          ),
        );

        final itemsList = (data['items'] as List? ?? []);
        for (final item in itemsList) {
        final m = item as Map<String, dynamic>;
        final resolvedPid = await resolveProductId(
          clientProductId: parseIntNullable(m['productId']),
          productGlobalId: m['productGlobalId'] as String?,
          fallbackCode: m['productCode'] as String?,
          fallbackName: m['productName'] as String?,
        );
        if (resolvedPid == null) {
          throw Exception('Validation Error: stock transfer item missing productId/productGlobalId');
        }
        final productId = resolvedPid;
        final quantity = parseDouble(m['quantity']);

        // Deduct from source warehouse
        await db.adjustStock(
          productId: productId,
          warehouseId: fromWarehouseId,
          quantity: -quantity,
          type: 'transfer_out',
          referenceType: 'stock_transfer',
          referenceId: transferBondId,
          notes: '$notes → مخزن $toWarehouseId',
        );

        // Add to destination warehouse
        await db.adjustStock(
          productId: productId,
          warehouseId: toWarehouseId,
          quantity: quantity,
          type: 'transfer_in',
          referenceType: 'stock_transfer',
          referenceId: transferBondId,
          notes: '$notes ← مخزن $fromWarehouseId',
        );
        }
        return transferBondId;
      });

      broadcast('products');
      broadcast('inventory');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] postStockTransfer error: $e');
      return ApiErrors.fail(e, 'Failed to process stock transfer');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Inventory Bonds — Spec 109
  // ═══════════════════════════════════════════════════════════════
  //
  // Server-side handler for inventory_bond inserts originating on client/
  // mirror. Mirrors the local-only `InventoryService.createAddingBond`
  // flow so the server stays the source of truth (Constitution R3):
  //   1. Insert bond header
  //   2. For each item: insert bond_item + adjustStock (creates a
  //      stock_movement row) + recompute weighted-average cost
  //   3. Post the inventory JE (Dr inventory / Cr capital|surplus|shrinkage)
  //
  // The whole flow runs inside a single transaction so a failed item
  // never leaves a half-applied bond.

  Future<Response> postInventoryBond(Request request) async {
    try {
      // Permission gate: bond creation is an inventory edit.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.inventoryEdit);
      if (perm != null) return perm;

      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      final type = (data['type'] as String?) ?? 'in';
      final warehouseId =
          await _resolveWarehouseId(parseInt(data['warehouseId']));
      final notes = data['notes'] as String?;
      final userId = await _resolveUserIdNullable(
          parseIntNullable(data['userId']),
          fallbackUsername: data['createdByUsername'] as String?);
      final dateStr = data['date'] as String?;
      final bondDate =
          dateStr != null ? DateTime.tryParse(dateStr) : DateTime.now();
      final itemsList = (data['items'] as List? ?? []);
      // Spec 129 F4 — caller-minted globalId. If present, dedup against
      // any existing inventory_bonds row before re-running the whole flow.
      final incomingGlobalId = (data['globalId'] as String?)?.trim();

      if (itemsList.isEmpty) {
        return errorResponse('Validation Error: bond items list is empty');
      }

      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.inventoryBonds)
              ..where((b) => b.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postInventoryBond: duplicate globalId=$incomingGlobalId — returning success (serverId=${existing.id})');
          return jsonResponse({'success': true, 'serverId': existing.id, 'dedup': true});
        }
      }

      final warehouse =
          await (db.select(db.warehouses)..where((w) => w.id.equals(warehouseId)))
              .getSingleOrNull();
      final branchId = warehouse?.branchId;

      final serverBondId = await db.transaction(() async {
        final bondNumber = 'BND-${DateTime.now().millisecondsSinceEpoch}';
        final bondId = await db.createInventoryBond(
          InventoryBondsCompanion.insert(
            bondNumber: bondNumber,
            type: Value(type),
            warehouseId: warehouseId,
            notes: Value(notes),
            createdBy: Value(userId),
            bondDate: Value(bondDate ?? DateTime.now()),
            globalId: Value(incomingGlobalId),
          ),
        );

        double totalValue = 0;

        for (final item in itemsList) {
          final m = item as Map<String, dynamic>;
          final resolvedPid = await resolveProductId(
            clientProductId: parseIntNullable(m['productId']),
            productGlobalId: m['productGlobalId'] as String?,
            fallbackCode: m['productCode'] as String?,
            fallbackName: m['productName'] as String?,
          );
          if (resolvedPid == null) {
            throw Exception(
                'Validation Error: inventory bond item missing productId/productGlobalId');
          }
          final productId = resolvedPid;
          final qty = parseDouble(m['quantity']);
          final unitCost = parseDouble(m['unitCost']);
          totalValue += qty * unitCost;

          await db.into(db.inventoryBondItems).insert(
                InventoryBondItemsCompanion.insert(
                  bondId: bondId,
                  productId: productId,
                  quantity: qty,
                  unitCost: Value(unitCost),
                ),
              );

          // Update stock and audit movement (same path used by every
          // other write so reports stay consistent).
          await db.adjustStock(
            productId: productId,
            warehouseId: warehouseId,
            quantity: qty,
            type: 'bond_${type == 'opening' ? 'opening' : 'in'}',
            notes: 'Bond #$bondId',
            branchId: branchId,
          );

          // Weighted-average cost update (mirrors the default path in
          // CostingMethodService).
          final product = await (db.select(db.products)
                ..where((p) => p.id.equals(productId)))
              .getSingleOrNull();
          if (product != null && qty > 0) {
            final stockBefore = product.currentStock - qty;
            final newCost = stockBefore + qty <= 0
                ? unitCost
                : ((stockBefore * product.costPrice) + (qty * unitCost)) /
                    (stockBefore + qty);
            if (newCost > 0 && (newCost - product.costPrice).abs() > 0.0001) {
              await db.updateProduct(
                product.copyWith(costPrice: newCost),
              );
            }
          }
        }

        // Generate the inventory JE — same pattern as InventoryService.
        if (totalValue > 0) {
          try {
            final String purpose = (type == 'opening')
                ? 'capital'
                : 'inventory_surplus';
            final invAccount = await db.getAccountByPurpose('inventory');
            final targetAccount = await db.getAccountByPurpose(purpose);
            if (invAccount != null && targetAccount != null) {
              await db.createJournalEntry(
                description: 'إثبات قيد سند مخزني #$bondId (${notes ?? ''})',
                date: bondDate ?? DateTime.now(),
                branchId: branchId,
                isAutoPosted: true,
                referenceType: 'inventory_bond',
                referenceId: bondId,
                lines: [
                  JournalLine(
                    accountId: invAccount.id,
                    debit: totalValue.abs(),
                    credit: 0,
                    description: 'تعديل قيمة المخزون',
                  ),
                  JournalLine(
                    accountId: targetAccount.id,
                    debit: 0,
                    credit: totalValue.abs(),
                    description: type == 'opening'
                        ? 'رصيد أول المدة'
                        : 'تسوية فروقات مخزنية',
                  ),
                ],
              );
            } else {
              debugPrint('[API] postInventoryBond: COA not configured — '
                  'JE skipped (bondId=$bondId)');
            }
          } catch (e) {
            debugPrint('[API] postInventoryBond JE failed (non-fatal): $e');
          }
        }

        return bondId;
      });

      broadcast('products');
      broadcast('inventory');
      return jsonResponse({'success': true, 'serverId': serverBondId});
    } catch (e) {
      debugPrint('[API] postInventoryBond error: $e');
      return ApiErrors.fail(e, 'Failed to create inventory bond');
    }
  }
}
