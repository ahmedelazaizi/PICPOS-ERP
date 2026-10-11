// ApiDataHandler - purchase orders, sales orders, quotations and price lists endpoints.
part of '../api_data_handler.dart';

/// Trade-document endpoints of [ApiDataHandler].
extension ApiDataDocumentsRoutes on ApiDataHandler {
  // ═══════════════════════════════════════════════════════════════
  // S4.2: Purchase Orders
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postPurchaseOrder(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.purchasesCreate);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incomingGid = data['globalId'] as String?;

      if (incomingGid != null && incomingGid.isNotEmpty) {
        final existing = await (db.select(db.purchaseOrders)
              ..where((o) => o.globalId.equals(incomingGid))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          broadcast('purchase_orders');
          return jsonResponse({'success': true, 'id': existing.id, 'global_id': incomingGid});
        }
      }

      final gid = (incomingGid != null && incomingGid.isNotEmpty) ? incomingGid : UuidV7.generate();
      final supplierId = await _resolveWarehouseId(parseInt(data['supplierId']));
      final warehouseId = await _resolveWarehouseId(
        parseInt(data['warehouseId']),
        branchId: parseIntNullable(data['branchId']),
      );
      final orderDate = DateTime.tryParse(data['orderDate'] as String? ?? '') ?? DateTime.now();

      final orderId = await db.transaction(() async {
        final id = await db.into(db.purchaseOrders).insert(
          PurchaseOrdersCompanion.insert(
            orderNumber: data['orderNumber'] as String? ?? 'PO-SYNC',
            supplierId: supplierId,
            warehouseId: warehouseId,
            orderDate: orderDate,
            expectedDate: Value(DateTime.tryParse(data['expectedDate'] as String? ?? '')),
            subtotal: Value(parseDouble(data['subtotal'])),
            total: Value(parseDouble(data['total'])),
            notes: Value(data['notes'] as String?),
            costCenterId: Value(parseIntNullable(data['costCenterId'])),
            globalId: Value(gid),
          ),
        );
        final items = data['items'] as List? ?? [];
        for (final item in items) {
          final itemMap = item as Map<String, dynamic>;
          final itemGid = itemMap['globalId'] as String?;
          final resolvedPid = await resolveProductId(
            clientProductId: parseIntNullable(itemMap['productId']),
            productGlobalId: itemMap['productGlobalId'] as String?,
            fallbackCode: itemMap['productCode'] as String?,
            fallbackName: itemMap['productName'] as String?,
          );
          if (resolvedPid == null) {
            throw Exception('Validation Error: purchase order item missing productId/productGlobalId');
          }
          await db.into(db.purchaseOrderItems).insert(
            PurchaseOrderItemsCompanion.insert(
              orderId: id,
              productId: resolvedPid,
              quantity: parseDouble(itemMap['quantity']),
              unitCost: parseDouble(itemMap['unitCost']),
              total: parseDouble(itemMap['total']),
              notes: Value(itemMap['notes'] as String?),
              globalId: Value(itemGid != null && itemGid.isNotEmpty ? itemGid : UuidV7.generate()),
            ),
            onConflict: DoNothing(target: []),
          );
        }
        return id;
      });

      broadcast('purchase_orders');
      return jsonResponse({'success': true, 'id': orderId, 'global_id': gid});
    } catch (e) {
      debugPrint('[API] postPurchaseOrder error: $e');
      return ApiErrors.fail(e, 'Failed to create purchase order');
    }
  }

  Future<Response> putPurchaseOrderStatus(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.purchasesEdit);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      await (db.update(db.purchaseOrders)..where((o) => o.id.equals(int.parse(id)))).write(
        PurchaseOrdersCompanion(status: Value(data['status'] as String)),
      );
      broadcast('purchase_orders');
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to update purchase order status');
    }
  }

  Future<Response> deletePurchaseOrder(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.purchasesDelete);
      if (perm != null) return perm;
      final oid = int.parse(id);
      await db.transaction(() async {
        await (db.delete(db.purchaseOrderItems)..where((i) => i.orderId.equals(oid))).go();
        await (db.delete(db.purchaseOrders)..where((o) => o.id.equals(oid))).go();
      });
      broadcast('purchase_orders');
      broadcastRecordDeleted('purchase_orders', oid);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete purchase order');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.2: Sales Orders
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postSalesOrder(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesCreate);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incomingGid = data['globalId'] as String?;

      if (incomingGid != null && incomingGid.isNotEmpty) {
        final existing = await (db.select(db.salesOrders)
              ..where((o) => o.globalId.equals(incomingGid))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          broadcast('sales_orders');
          return jsonResponse({'success': true, 'id': existing.id, 'global_id': incomingGid});
        }
      }

      final gid = (incomingGid != null && incomingGid.isNotEmpty) ? incomingGid : UuidV7.generate();
      final warehouseId = await _resolveWarehouseId(
        parseInt(data['warehouseId']),
        branchId: parseIntNullable(data['branchId']),
      );
      final orderDate = DateTime.tryParse(data['orderDate'] as String? ?? '') ?? DateTime.now();

      final orderId = await db.transaction(() async {
        final id = await db.into(db.salesOrders).insert(
          SalesOrdersCompanion.insert(
            orderNumber: data['orderNumber'] as String? ?? 'SO-SYNC',
            customerId: Value(parseIntNullable(data['customerId'])),
            warehouseId: warehouseId,
            orderDate: orderDate,
            expectedDate: Value(DateTime.tryParse(data['expectedDate'] as String? ?? '')),
            subtotal: Value(parseDouble(data['subtotal'])),
            total: Value(parseDouble(data['total'])),
            notes: Value(data['notes'] as String?),
            costCenterId: Value(parseIntNullable(data['costCenterId'])),
            globalId: Value(gid),
          ),
        );
        final items = data['items'] as List? ?? [];
        for (final item in items) {
          final itemMap = item as Map<String, dynamic>;
          final itemGid = itemMap['globalId'] as String?;
          final resolvedPid = await resolveProductId(
            clientProductId: parseIntNullable(itemMap['productId']),
            productGlobalId: itemMap['productGlobalId'] as String?,
            fallbackCode: itemMap['productCode'] as String?,
            fallbackName: itemMap['productName'] as String?,
          );
          if (resolvedPid == null) {
            throw Exception('Validation Error: sales order item missing productId/productGlobalId');
          }
          await db.into(db.salesOrderItems).insert(
            SalesOrderItemsCompanion.insert(
              orderId: id,
              productId: resolvedPid,
              quantity: parseDouble(itemMap['quantity']),
              unitPrice: parseDouble(itemMap['unitPrice']),
              total: parseDouble(itemMap['total']),
              notes: Value(itemMap['notes'] as String?),
              globalId: Value(itemGid != null && itemGid.isNotEmpty ? itemGid : UuidV7.generate()),
            ),
            onConflict: DoNothing(target: []),
          );
        }
        return id;
      });

      broadcast('sales_orders');
      return jsonResponse({'success': true, 'id': orderId, 'global_id': gid});
    } catch (e) {
      debugPrint('[API] postSalesOrder error: $e');
      return ApiErrors.fail(e, 'Failed to create sales order');
    }
  }

  Future<Response> putSalesOrderStatus(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesEdit);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      await (db.update(db.salesOrders)..where((o) => o.id.equals(int.parse(id)))).write(
        SalesOrdersCompanion(status: Value(data['status'] as String)),
      );
      broadcast('sales_orders');
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to update sales order status');
    }
  }

  Future<Response> deleteSalesOrder(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesDelete);
      if (perm != null) return perm;
      final oid = int.parse(id);
      await db.transaction(() async {
        await (db.delete(db.salesOrderItems)..where((i) => i.orderId.equals(oid))).go();
        await (db.delete(db.salesOrders)..where((o) => o.id.equals(oid))).go();
      });
      broadcast('sales_orders');
      broadcastRecordDeleted('sales_orders', oid);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete sales order');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.2: Quotations
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postQuotation(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesCreate);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incomingGid = data['globalId'] as String?;

      if (incomingGid != null && incomingGid.isNotEmpty) {
        final existing = await (db.select(db.quotations)
              ..where((q) => q.globalId.equals(incomingGid))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          broadcast('quotations');
          return jsonResponse({'success': true, 'id': existing.id, 'global_id': incomingGid});
        }
      }

      final gid = (incomingGid != null && incomingGid.isNotEmpty) ? incomingGid : UuidV7.generate();
      final userId = await _resolveUserId(parseInt(data['userId'], 1));
      final warehouseId = await _resolveWarehouseId(
        parseInt(data['warehouseId']),
        branchId: parseIntNullable(data['branchId']),
      );
      final quotationDate = DateTime.tryParse(data['quotationDate'] as String? ?? '') ?? DateTime.now();

      final resolvedQuotationCustomerId = await resolvePartyId(
        clientPartyId: parseIntNullable(data['customerId']),
        partyGlobalId: data['customerGlobalId'] as String?,
        isCustomer: true,
      );

      final quotationId = await db.transaction(() async {
        final id = await db.into(db.quotations).insert(
          QuotationsCompanion.insert(
            quotationNumber: data['quotationNumber'] as String? ?? 'QT-SYNC',
            customerId: Value(resolvedQuotationCustomerId),
            warehouseId: warehouseId,
            userId: userId,
            quotationDate: quotationDate,
            validityDate: Value(DateTime.tryParse(data['validityDate'] as String? ?? '')),
            subtotal: Value(parseDouble(data['subtotal'])),
            discount: Value(parseDouble(data['discount'])),
            tax: Value(parseDouble(data['tax'])),
            total: Value(parseDouble(data['total'])),
            notes: Value(data['notes'] as String?),
            status: Value(data['status'] as String? ?? 'draft'),
            globalId: Value(gid),
          ),
        );
        final items = data['items'] as List? ?? [];
        for (final item in items) {
          final itemMap = item as Map<String, dynamic>;
          final itemGid = itemMap['globalId'] as String?;
          final resolvedPid = await resolveProductId(
            clientProductId: parseIntNullable(itemMap['productId']),
            productGlobalId: itemMap['productGlobalId'] as String?,
            fallbackCode: itemMap['productCode'] as String?,
            fallbackName: itemMap['productName'] as String?,
          );
          if (resolvedPid == null) {
            throw Exception('Validation Error: quotation item missing productId/productGlobalId');
          }
          await db.into(db.quotationItems).insert(
            QuotationItemsCompanion.insert(
              quotationId: id,
              productId: resolvedPid,
              quantity: parseDouble(itemMap['quantity']),
              unitPrice: parseDouble(itemMap['unitPrice']),
              discount: Value(parseDouble(itemMap['discount'])),
              total: parseDouble(itemMap['total']),
              globalId: Value(itemGid != null && itemGid.isNotEmpty ? itemGid : UuidV7.generate()),
            ),
            onConflict: DoNothing(target: []),
          );
        }
        return id;
      });

      broadcast('quotations');
      return jsonResponse({'success': true, 'id': quotationId, 'global_id': gid});
    } catch (e) {
      debugPrint('[API] postQuotation error: $e');
      return ApiErrors.fail(e, 'Failed to create quotation');
    }
  }

  Future<Response> putQuotationStatus(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesEdit);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      await (db.update(db.quotations)..where((q) => q.id.equals(int.parse(id)))).write(
        QuotationsCompanion(
          status: Value(data['status'] as String),
          convertedToInvoiceId: data.containsKey('convertedToInvoiceId')
              ? Value(parseIntNullable(data['convertedToInvoiceId']))
              : const Value.absent(),
        ),
      );
      broadcast('quotations');
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to update quotation status');
    }
  }

  Future<Response> putQuotation(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesEdit);
      if (perm != null) return perm;
      final qid = int.parse(id);
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final quotationDate = DateTime.tryParse(data['quotationDate'] as String? ?? '');
      final validityDate = DateTime.tryParse(data['validityDate'] as String? ?? '');

      await db.transaction(() async {
        await (db.update(db.quotations)..where((q) => q.id.equals(qid))).write(
          QuotationsCompanion(
            customerId: data.containsKey('customerId')
                ? Value(parseIntNullable(data['customerId']))
                : const Value.absent(),
            warehouseId: data.containsKey('warehouseId')
                ? Value(parseInt(data['warehouseId']))
                : const Value.absent(),
            userId: data.containsKey('userId')
                ? Value(parseInt(data['userId']))
                : const Value.absent(),
            quotationDate: quotationDate != null
                ? Value(quotationDate)
                : const Value.absent(),
            validityDate: validityDate != null
                ? Value(validityDate)
                : const Value.absent(),
            subtotal: data.containsKey('subtotal')
                ? Value(parseDouble(data['subtotal']))
                : const Value.absent(),
            discount: data.containsKey('discount')
                ? Value(parseDouble(data['discount']))
                : const Value.absent(),
            tax: data.containsKey('tax')
                ? Value(parseDouble(data['tax']))
                : const Value.absent(),
            total: data.containsKey('total')
                ? Value(parseDouble(data['total']))
                : const Value.absent(),
            notes: data.containsKey('notes')
                ? Value(data['notes'] as String?)
                : const Value.absent(),
            status: data.containsKey('status')
                ? Value(data['status'] as String)
                : const Value.absent(),
          ),
        );

        final items = data['items'] as List?;
        if (items != null) {
          await (db.delete(db.quotationItems)..where((i) => i.quotationId.equals(qid))).go();
          for (final item in items) {
            final itemMap = item as Map<String, dynamic>;
            final itemGid = itemMap['globalId'] as String?;
            final resolvedPid = await resolveProductId(
              clientProductId: parseIntNullable(itemMap['productId']),
              productGlobalId: itemMap['productGlobalId'] as String?,
              fallbackCode: itemMap['productCode'] as String?,
              fallbackName: itemMap['productName'] as String?,
            );
            if (resolvedPid == null) {
              throw Exception('Validation Error: quotation item missing productId/productGlobalId');
            }
            await db.into(db.quotationItems).insert(
              QuotationItemsCompanion.insert(
                quotationId: qid,
                productId: resolvedPid,
                quantity: parseDouble(itemMap['quantity']),
                unitPrice: parseDouble(itemMap['unitPrice']),
                discount: Value(parseDouble(itemMap['discount'])),
                total: parseDouble(itemMap['total']),
                globalId: Value(itemGid != null && itemGid.isNotEmpty ? itemGid : UuidV7.generate()),
              ),
              onConflict: DoNothing(target: []),
            );
          }
        }
      });

      broadcast('quotations');
      return jsonResponse({'success': true, 'id': qid});
    } catch (e) {
      debugPrint('[API] putQuotation error: $e');
      return ApiErrors.fail(e, 'Failed to update quotation');
    }
  }

  Future<Response> deleteQuotation(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesDelete);
      if (perm != null) return perm;
      final qid = int.parse(id);
      await db.transaction(() async {
        await (db.delete(db.quotationItems)..where((i) => i.quotationId.equals(qid))).go();
        await (db.delete(db.quotations)..where((q) => q.id.equals(qid))).go();
      });
      broadcast('quotations');
      broadcastRecordDeleted('quotations', qid);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete quotation');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.2: Price Lists
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postPriceList(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.priceListsManage);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incomingGid = data['globalId'] as String?;

      if (incomingGid != null && incomingGid.isNotEmpty) {
        final existing = await (db.select(db.priceLists)
              ..where((p) => p.globalId.equals(incomingGid))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          broadcast('price_lists');
          return jsonResponse({'success': true, 'id': existing.id, 'global_id': incomingGid});
        }
      }

      final gid = (incomingGid != null && incomingGid.isNotEmpty) ? incomingGid : UuidV7.generate();
      final isDefault = parseBool(data['isDefault'], false);
      if (isDefault) {
        await db.update(db.priceLists).write(const PriceListsCompanion(isDefault: Value(false)));
      }
      final id = await db.into(db.priceLists).insert(
        PriceListsCompanion.insert(
          name: data['name'] as String,
          code: data['code'] as String? ?? gid.substring(0, 8),
          isDefault: Value(isDefault),
          currencyId: Value(parseIntNullable(data['currencyId'])),
          startDate: Value(DateTime.tryParse(data['startDate'] as String? ?? '')),
          endDate: Value(DateTime.tryParse(data['endDate'] as String? ?? '')),
          globalId: Value(gid),
        ),
      );
      broadcast('price_lists');
      return jsonResponse({'success': true, 'id': id, 'global_id': gid});
    } catch (e) {
      debugPrint('[API] postPriceList error: $e');
      return ApiErrors.fail(e, 'Failed to create price list');
    }
  }

  Future<Response> putPriceList(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.priceListsManage);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      await (db.update(db.priceLists)..where((p) => p.id.equals(int.parse(id)))).write(
        PriceListsCompanion(
          name: data.containsKey('name') ? Value(data['name'] as String) : const Value.absent(),
          isActive: data.containsKey('isActive') ? Value(parseBool(data['isActive'], true)) : const Value.absent(),
        ),
      );
      broadcast('price_lists');
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to update price list');
    }
  }

  Future<Response> postPriceListItem(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.priceListsManage);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incomingGid = data['globalId'] as String?;
      final priceListId = parseInt(data['priceListId']);
      final productId = parseInt(data['productId']);

      await (db.delete(db.priceListItems)
            ..where((i) => i.priceListId.equals(priceListId) & i.productId.equals(productId)))
          .go();
      await db.into(db.priceListItems).insert(
        PriceListItemsCompanion.insert(
          priceListId: priceListId,
          productId: productId,
          price: parseDouble(data['price']),
          minQuantity: Value(parseDouble(data['minQuantity'], 1.0)),
          maxDiscount: Value(parseDouble(data['maxDiscount'])),
          globalId: Value(incomingGid != null && incomingGid.isNotEmpty ? incomingGid : UuidV7.generate()),
        ),
      );
      broadcast('price_list_items');
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to set price list item');
    }
  }
}
