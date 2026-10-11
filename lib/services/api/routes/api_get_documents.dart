// ApiHandler - sales, purchases, orders, stock movements and balances (GET).
part of '../api_handler.dart';

/// sales, purchases, orders, stock movements and balances (GET) (see [ApiHandler]).
extension ApiHandlerDocumentGets on ApiHandler {
  // ═══════════════════════════════════════════════════════════════
  // Sales Invoices (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getSalesInvoices(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      final warehouseIds = branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;
      final query = _db.select(_db.salesInvoices)
        ..orderBy([(s) => OrderingTerm.desc(s.id)]);
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        query.where((s) => s.warehouseId.isIn(warehouseIds));
      }
      final invoices = await query.get();

      final jsonList = <Map<String, dynamic>>[];
      for (final inv in invoices) {
        final items = await (_db.select(
          _db.salesInvoiceItems,
        )..where((i) => i.invoiceId.equals(inv.id))).get();
        final itemsJson = items
            .map(
              (item) => <String, dynamic>{
                'id': item.id,
                'invoiceId': item.invoiceId,
                'productId': item.productId,
                'quantity': item.quantity,
                'unitPrice': item.unitPrice,
                'discount': item.discount,
                'total': item.total,
                'costPrice': item.costPrice,
                // SAL-2 (pull): thread the UOM factor so a carton sale
                // replicates with the correct base-unit conversion — else the
                // mirror/client stores quantity_in_base=1.0 and its now-UOM-aware
                // local COGS reports diverge from the authoritative GL.
                'quantityInBase': item.quantityInBase,
                'taxRate': item.taxRate,
                'taxAmount': item.taxAmount,
              },
            )
            .toList();

        jsonList.add({
          'id': inv.id,
          'invoiceNumber': inv.invoiceNumber,
          'customerId': inv.customerId,
          'warehouseId': inv.warehouseId,
          'userId': inv.userId,
          'invoiceDate': inv.invoiceDate.toIso8601String(),
          'subtotal': inv.subtotal,
          'discount': inv.discount,
          'tax': inv.tax,
          'total': inv.total,
          'paid': inv.paid,
           'currencyId': inv.currencyId,
           'exchangeRate': inv.exchangeRate,
          // فرقُ التقريب يسافر مع الفاتورة، وإلّا قرأه العميلُ صفراً بعد
          // السحب فرأى `total > paid` ⇒ فاتورةٌ مكتملةٌ تعود `pending`.
          'roundingAdjustment': inv.roundingAdjustment,
          'cashPaid': inv.cashPaid,
          'bankPaid': inv.bankPaid,
          'paymentMethod': inv.paymentMethod,
          'saleType': inv.saleType,
          'status': inv.status,
          'orderNumber': inv.orderNumber,
          'deliveryFee': inv.deliveryFee,
          'notes': inv.notes,
          'costCenterId': inv.costCenterId,
          // C2 (v183) — raw column; the client's JE/return must use the same.
          'revenueAccountId':
              await _db.getSalesInvoiceRevenueAccountId(inv.id),
          ...(await _db.repStampJson('sales_invoices', inv.id)), // v185
          'items': itemsJson,
        });
      }
      return _json({'sales': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getSalesInvoices error: $e');
      return ApiErrors.fail(e, 'Failed to fetch sales');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Held Orders (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getHeldOrders(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      // Spec 151 P1-8b: the query below is NOT branch-scoped, so short-circuit
      // the no-identity sentinel to zero rows — otherwise a tokenless caller
      // reads every branch's parked carts. (Branch-scoping held orders for a
      // logged-in restricted user is a separate pre-existing gap; this only
      // closes the omission vector the P1-8b flag promises.)
      if (branchId == _kNoBranchAccess) {
        return _json({'held_orders': const [], 'count': 0});
      }
      final query = _db.select(_db.heldOrders)
        ..orderBy([(h) => OrderingTerm.desc(h.id)]);
      final orders = await query.get();

      final jsonList = orders.map((o) => {
        'id': o.id,
        'holdNumber': o.holdNumber,
        'subtotal': o.subtotal,
        'discount': o.discount,
        'discountIsPercent': o.discountIsPercent,
        'note': o.note,
        'userId': o.userId,
        'customerId': o.customerId,
        'customerName': o.customerName,
        'createdAt': o.createdAt.toIso8601String(),
      }).toList();

      return _json({'held_orders': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getHeldOrders error: $e');
      return ApiErrors.fail(e, 'Failed to fetch held orders');
    }
  }

  Future<Response> _getHeldOrderItems(Request request) async {
    try {
      // Spec 151 residual #1 — held_order_items' parent (held_orders) has no
      // branch/warehouse/safe linkage, so per-branch scoping isn't feasible.
      // Mirror _getHeldOrders: close the OMISSION (no identity → zero rows) so a
      // tokenless caller can't read every branch's parked cart items. An
      // identified caller still sees all (documented gap, same as held_orders).
      final branchId =
          await _extractBranchId(request, failClosedOnNoIdentity: true);
      if (branchId == _kNoBranchAccess) {
        return _json({'held_order_items': const [], 'count': 0});
      }
      final items = await _db.select(_db.heldOrderItems).get();

      final jsonList = items.map((i) => {
        'id': i.id,
        'heldOrderId': i.heldOrderId,
        'productId': i.productId,
        'quantity': i.quantity,
        'unitPrice': i.unitPrice,
        'customPrice': i.customPrice,
        'note': i.note,
      }).toList();

      return _json({'held_order_items': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getHeldOrderItems error: $e');
      return ApiErrors.fail(e, 'Failed to fetch held order items');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Purchase Invoices (GET — for client pull sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getPurchaseInvoices(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      final warehouseIds = branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;
      final query = _db.select(_db.purchaseInvoices);
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        query.where((i) => i.warehouseId.isIn(warehouseIds));
      }
      final invoices = await query.get();
      final jsonList = <Map<String, dynamic>>[];

      for (final inv in invoices) {
        final items = await (_db.select(_db.purchaseInvoiceItems)
              ..where((i) => i.invoiceId.equals(inv.id)))
            .get();

        jsonList.add({
          'id': inv.id,
          'invoiceNumber': inv.invoiceNumber,
          'supplierId': inv.supplierId,
          'warehouseId': inv.warehouseId,
          'invoiceDate': inv.invoiceDate.toIso8601String(),
          'subtotal': inv.subtotal,
          'discount': inv.discount,
          'tax': inv.tax,
          'total': inv.total,
          'paid': inv.paid,
           'currencyId': inv.currencyId,
           'exchangeRate': inv.exchangeRate,
          'status': inv.status,
          'notes': inv.notes,
          'costCenterId': inv.costCenterId,
          // J1b (v188) — raw column; the client's JE/return must use the same.
          'purchaseAccountId':
              await _db.getPurchaseInvoicePurchaseAccountId(inv.id),
          'createdAt': inv.createdAt.toIso8601String(),
          'items': items
              .map((i) => {
                    'id': i.id,
                    'productId': i.productId,
                    'quantity': i.quantity,
                    'unitCost': i.unitCost,
                    'total': i.total,
                  })
              .toList(),
        });
      }

      return _json({'purchases': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getPurchaseInvoices error: $e');
      return ApiErrors.fail(e, 'Failed to fetch purchase invoices');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Stock Movements (GET — for client pull sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getStockMovements(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      final warehouseIds = branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;
      final query = _db.select(_db.stockMovements);
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        query.where((m) => m.warehouseId.isIn(warehouseIds));
      }
      final movements = await query.get();
      final jsonList = movements.map((m) => {
        'id': m.id,
        'productId': m.productId,
        'warehouseId': m.warehouseId,
        'movementType': m.movementType,
        'quantity': m.quantity,
        'unitCost': m.unitCost,
        'balanceAfter': m.balanceAfter,
        'referenceType': m.referenceType,
        'referenceId': m.referenceId,
        'userId': m.userId,
        'branchId': m.branchId,
        'notes': m.notes,
        'createdAt': m.createdAt.toIso8601String(),
      }).toList();

      return _json({'stock_movements': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getStockMovements error: $e');
      return ApiErrors.fail(e, 'Failed to fetch stock movements');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Inventory Balances (GET — for client pull sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getInventoryBalances(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      final warehouseIds = branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;
      final query = _db.select(_db.inventoryBalances);
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        query.where((b) => b.warehouseId.isIn(warehouseIds));
      }
      final balances = await query.get();
      final jsonList = balances.map((b) => {
        'id': b.id,
        'productId': b.productId,
        'warehouseId': b.warehouseId,
        'quantity': b.quantity,
        'reservedQuantity': b.reservedQuantity,
        'averageCost': b.averageCost,
        'lastUpdated': b.lastUpdated.toIso8601String(),
      }).toList();

      return _json({'inventory_balances': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getInventoryBalances error: $e');
      return ApiErrors.fail(e, 'Failed to fetch inventory balances');
    }
  }



  // ═══════════════════════════════════════════════════════════════
  // Sales Orders
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getSalesOrders(Request request) async {
    try {
      // Spec 151 residual #1 — scope by warehouse→branch (sales_orders has no
      // branch column). Items are scoped implicitly by only iterating the
      // in-scope orders. No identity → sentinel → warehouseId IN (-1) → zero.
      final branchId =
          await _extractBranchId(request, failClosedOnNoIdentity: true);
      final warehouseIds =
          branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;
      final ordersQuery = _db.select(_db.salesOrders);
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        ordersQuery.where((o) => o.warehouseId.isIn(warehouseIds));
      }
      final orders = await ordersQuery.get();
      final jsonList = <Map<String, dynamic>>[];
      for (final o in orders) {
        final items = await (_db.select(_db.salesOrderItems)
          ..where((i) => i.orderId.equals(o.id))).get();
        final itemsJson = items.map((i) => <String, dynamic>{
          'id': i.id,
          'orderId': i.orderId,
          'productId': i.productId,
          'quantity': i.quantity,
          'unitPrice': i.unitPrice,
          'discount': i.discount,
          'total': i.total,
          'deliveredQuantity': i.deliveredQuantity,
          'taxRate': i.taxRate,
          'taxAmount': i.taxAmount,
          'notes': i.notes,
        }).toList();
        jsonList.add({
          'id': o.id,
          'orderNumber': o.orderNumber,
          'customerId': o.customerId,
          'warehouseId': o.warehouseId,
          'orderDate': o.orderDate.toIso8601String(),
          'expectedDate': o.expectedDate?.toIso8601String(),
          'subtotal': o.subtotal,
          'discount': o.discount,
          'tax': o.tax,
          'total': o.total,
          'status': o.status,
          'notes': o.notes,
          'costCenterId': o.costCenterId,
          'convertedToInvoiceId': o.convertedToInvoiceId,
          'createdAt': o.createdAt.toIso8601String(),
          'items': itemsJson,
        });
      }
      return _json({'sales_orders': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch sales orders');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Purchase Orders
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getPurchaseOrders(Request request) async {
    try {
      // Spec 151 residual #1 — scope by warehouse→branch (purchase_orders has
      // no branch column). Items scoped implicitly by iterating in-scope orders.
      final branchId =
          await _extractBranchId(request, failClosedOnNoIdentity: true);
      final warehouseIds =
          branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;
      final ordersQuery = _db.select(_db.purchaseOrders);
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        ordersQuery.where((o) => o.warehouseId.isIn(warehouseIds));
      }
      final orders = await ordersQuery.get();
      final jsonList = <Map<String, dynamic>>[];
      for (final o in orders) {
        final items = await (_db.select(_db.purchaseOrderItems)
          ..where((i) => i.orderId.equals(o.id))).get();
        final itemsJson = items.map((i) => <String, dynamic>{
          'id': i.id,
          'orderId': i.orderId,
          'productId': i.productId,
          'quantity': i.quantity,
          'unitCost': i.unitCost,
          'discount': i.discount,
          'total': i.total,
          'receivedQuantity': i.receivedQuantity,
          'taxRate': i.taxRate,
          'taxAmount': i.taxAmount,
          'notes': i.notes,
        }).toList();
        jsonList.add({
          'id': o.id,
          'orderNumber': o.orderNumber,
          'supplierId': o.supplierId,
          'warehouseId': o.warehouseId,
          'orderDate': o.orderDate.toIso8601String(),
          'expectedDate': o.expectedDate?.toIso8601String(),
          'subtotal': o.subtotal,
          'discount': o.discount,
          'tax': o.tax,
          'total': o.total,
          'status': o.status,
          'notes': o.notes,
          'costCenterId': o.costCenterId,
          'convertedToInvoiceId': o.convertedToInvoiceId,
          'createdAt': o.createdAt.toIso8601String(),
          'items': itemsJson,
        });
      }
      return _json({'purchase_orders': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch purchase orders');
    }
  }

}
