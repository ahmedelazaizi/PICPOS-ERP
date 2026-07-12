// ═══════════════════════════════════════════════════════════════════════════
// Sales Orders DAO Extension
// ═══════════════════════════════════════════════════════════════════════════
// Provides CRUD and workflow methods for sales order management.
//
// Status flow: draft → sent → confirmed → delivered → (converted to invoice)
//            ↘ cancelled

part of '../database.dart';

extension SalesOrdersDao on AppDatabase {
  // -----------------------------------------------------------------------
  // WATCH / READ
  // -----------------------------------------------------------------------

  /// Watch all sales orders, sorted by newest first
  Stream<List<SalesOrderData>> watchSalesOrders() {
    return (select(salesOrders)
          ..orderBy([(so) => OrderingTerm.desc(so.createdAt)]))
        .watch();
  }

  /// Watch sales orders filtered by status
  Stream<List<SalesOrderData>> watchSalesOrdersByStatus(String status) {
    return (select(salesOrders)
          ..where((so) => so.status.equals(status))
          ..orderBy([(so) => OrderingTerm.desc(so.createdAt)]))
        .watch();
  }

  /// Get single SO by ID
  Future<SalesOrderData?> getSalesOrderById(int id) {
    return (select(salesOrders)..where((so) => so.id.equals(id)))
        .getSingleOrNull();
  }

  /// Get items for a sales order
  Future<List<SalesOrderItem>> getSalesOrderItems(int orderId) {
    return (select(salesOrderItems)
          ..where((i) => i.orderId.equals(orderId)))
        .get();
  }

  /// Watch items for a sales order
  Stream<List<SalesOrderItem>> watchSalesOrderItems(int orderId) {
    return (select(salesOrderItems)
          ..where((i) => i.orderId.equals(orderId)))
        .watch();
  }

  /// Generate next SO number
  Future<String> _nextSONumber() async {
    final count = await (selectOnly(salesOrders)
          ..addColumns([salesOrders.id.count()]))
        .getSingle();
    final next = (count.read(salesOrders.id.count()) ?? 0) + 1;
    return 'SO-${next.toString().padLeft(5, '0')}';
  }

  // -----------------------------------------------------------------------
  // CREATE / UPDATE / DELETE
  // -----------------------------------------------------------------------

  /// Create a new sales order with items
  Future<int> createSalesOrder({
    int? customerId,
    required int warehouseId,
    required DateTime orderDate,
    DateTime? expectedDate,
    String? notes,
    int? costCenterId,
    required List<SalesOrderItemsCompanion> items,
    // 062 (D1-004): caller's userId for the overrideCreditLimit gate.
    int? userId,
  }) async {
    final soNumber = await _nextSONumber();
    double subtotal = 0;
    for (final item in items) {
      subtotal += item.total.value;
    }

    // Credit limit check (always, regardless of mode)
    // 062 (D1-004): allow override for users with overrideCreditLimit.
    if (customerId != null && subtotal > 0.01) {
      final customer = await getPartyById(customerId);
      if (customer != null && customer.creditLimit > 0) {
        final projectedBalance = customer.balance + subtotal;
        if (projectedBalance > customer.creditLimit) {
          final hasOverride = await permissionEnforcer.hasCriticalOp(
            userId, PermissionCodes.overrideCreditLimit);
          if (!hasOverride) {
            throw Exception(
              'تجاوز العميل الحد الائتماني المسموح به\n'
              'الرصيد الحالي: ${customer.balance.toStringAsFixed(2)}\n'
              'قيمة الطلب: ${subtotal.toStringAsFixed(2)}\n'
              'الحد المسموح: ${customer.creditLimit.toStringAsFixed(2)}',
            );
          }
          unawaited(DiagnosticLogger.log('CREDIT-OVERRIDE',
              'sales-order user=$userId customer=${customer.id} '
              'projected=$projectedBalance limit=${customer.creditLimit}'));
        }
      }
    }

    final orderGid = UuidV7.generate();

    if (SyncInterceptor.isClientMode) {
      final orderData = {
        'globalId': orderGid,
        'orderNumber': soNumber,
        'customerId': customerId,
        'warehouseId': warehouseId,
        'orderDate': orderDate.toIso8601String(),
        'expectedDate': expectedDate?.toIso8601String(),
        'subtotal': subtotal,
        'total': subtotal,
        'notes': notes,
        'costCenterId': costCenterId,
      };
      final itemMaps = items.map((item) {
        final hasGid = item.globalId.present && (item.globalId.value?.isNotEmpty ?? false);
        return {
          'globalId': hasGid ? item.globalId.value : UuidV7.generate(),
          'productId': item.productId.value,
          'quantity': item.quantity.value,
          'unitPrice': item.unitPrice.value,
          'total': item.total.value,
        };
      }).toList();
      final serverId = await SyncInterceptor.instance?.createSalesOrder(orderData, itemMaps);
      if (serverId != null) return serverId;
    }

    return transaction(() async {
      final orderId = await into(salesOrders).insert(
        SalesOrdersCompanion.insert(
          orderNumber: soNumber,
          customerId: Value(customerId),
          warehouseId: warehouseId,
          orderDate: orderDate,
          expectedDate: Value(expectedDate),
          subtotal: Value(subtotal),
          total: Value(subtotal),
          notes: Value(notes),
          costCenterId: Value(costCenterId),
          globalId: Value(orderGid),
        ),
      );
      for (final item in items) {
        final hasGid = item.globalId.present && (item.globalId.value?.isNotEmpty ?? false);
        final itemWithGid = hasGid
            ? item.copyWith(orderId: Value(orderId))
            : item.copyWith(orderId: Value(orderId), globalId: Value(UuidV7.generate()));
        await into(salesOrderItems).insert(itemWithGid);
      }
      return orderId;
    });
  }

  // PIR P1-03: Reserve stock for a confirmed sales order.
  // Delegates to inventory_dao.reserveStock() with the order's warehouseId.
  Future<void> reserveStockForOrder(int orderId) async {
    final so = await getSalesOrderById(orderId);
    if (so == null) return;
    final items = await getSalesOrderItems(orderId);
    for (final item in items) {
      await reserveStock(
        productId: item.productId,
        warehouseId: so.warehouseId,
        quantity: item.quantity,
        salesOrderId: orderId,
      );
    }
  }

  /// Update SO status
  Future<void> updateSalesOrderStatus(int orderId, String newStatus) async {
    return transaction(() async {
      final so = await getSalesOrderById(orderId);
      if (so == null) throw Exception('طلب بيع غير موجود');
      final currentStatus = so.status;

      if (currentStatus == newStatus) return;

      final items = await getSalesOrderItems(orderId);

      // 1. Handle Reservation Logic (PIR P1-03: Activated)
      // Transition TO confirmed: Reserve stock
      if (newStatus == 'confirmed') {
        for (final item in items) {
          try {
            await reserveStock(
              productId: item.productId,
              warehouseId: so.warehouseId,
              quantity: item.quantity,
              salesOrderId: orderId,
            );
          } catch (e) {
            debugPrint('[SO-RESERVE] Failed to reserve for product #${item.productId}: $e');
            // Re-throw so caller knows reservation failed
            rethrow;
          }
        }
      }
      // Transition AWAY FROM confirmed (to cancelled/draft): Release stock
      else if (currentStatus == 'confirmed' &&
          (newStatus == 'cancelled' || newStatus == 'draft')) {
        for (final item in items) {
          try {
            await releaseStock(
              productId: item.productId,
              warehouseId: so.warehouseId,
              quantity: item.quantity,
            );
          } catch (e) {
            debugPrint('[SO-RELEASE] Failed to release for product #${item.productId}: $e');
          }
        }
      }

      if (SyncInterceptor.isClientMode) {
        await SyncInterceptor.instance?.updateSalesOrderStatus(orderId, newStatus);
      }
      await (update(salesOrders)..where((so) => so.id.equals(orderId)))
          .write(SalesOrdersCompanion(status: Value(newStatus)));
    });
  }

  /// Delete a draft SO (only drafts can be deleted)
  Future<void> deleteSalesOrder(int orderId) async {
    final so = await getSalesOrderById(orderId);
    if (so == null) throw Exception('طلب بيع غير موجود');
    if (so.status != 'draft') throw Exception('لا يمكن حذف طلب بيع غير مسودة');

    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.deleteSalesOrder(orderId);
    }
    await transaction(() async {
      await (delete(salesOrderItems)..where((i) => i.orderId.equals(orderId))).go();
      await (delete(salesOrders)..where((so) => so.id.equals(orderId))).go();
    });
  }

  /// Convert SO to Sales Invoice
  Future<int> convertSOToInvoice(int orderId) async {
    return transaction(() async {
      final so = await getSalesOrderById(orderId);
      if (so == null) throw Exception('طلب بيع غير موجود');
      if (so.status == 'cancelled') throw Exception('لا يمكن تحويل طلب بيع ملغي');

      final items = await getSalesOrderItems(orderId);

      // Get user or fallback to first user (auditors prefer explicit user, but for conversion we might need a system/default user)
      final defaultUser = await (select(users)..limit(1)).getSingleOrNull();
      if (defaultUser == null) throw Exception('لا يوجد مستخدمين في النظام لإجراء التحويل');

      // Resolve branchId from warehouse to maintain branch isolation
      final warehouse = await (select(warehouses)..where((w) => w.id.equals(so.warehouseId))).getSingleOrNull();
      final branchId = warehouse?.branchId;

      // Map SO items to Invoice items companions
      final invoiceItems = items.map((item) {
        return SalesInvoiceItemsCompanion.insert(
          invoiceId: 0, // Placeholder — overwritten by createSalesInvoice
          productId: item.productId,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          total: item.total,
          discount: Value(item.discount),
          // costPrice will be auto-resolved from WAC in createSalesInvoice
        );
      }).toList();

      // CREATION VIA HARDENED DAO (SalesMutationsDao)
      // This ensures accounting (Autopost), Inventory (Stock adjust), and Treasury (Safe) are handled.
      // Note: we pass paid=0 as it's typically a credit invoice upon conversion unless specified.
      final invoiceId = await createSalesInvoice(
        customerId: so.customerId,
        warehouseId: so.warehouseId,
        userId: defaultUser.id,
        subtotal: so.subtotal,
        discount: so.discount,
        tax: so.tax,
        total: so.total,
        paid: 0, 
        paymentMethod: 'credit',
        notes: 'تم التحويل من طلب بيع ${so.orderNumber}',
        items: invoiceItems,
      );

      // RELEASE RESERVATION (PIR P1-03: Activated)
      // If the SO was confirmed, it holds reserved stock.
      // We release it now because createSalesInvoice just deducted physical stock.
      if (so.status == 'confirmed') {
        for (final item in items) {
          try {
            await releaseStock(
              productId: item.productId,
              warehouseId: so.warehouseId,
              quantity: item.quantity,
            );
          } catch (e) {
            debugPrint('[SO-RELEASE] Failed to release stock on convert for product #${item.productId}: $e');
          }
        }
      }

      // Update SO status and link
      await (update(salesOrders)..where((so) => so.id.equals(orderId)))
          .write(SalesOrdersCompanion(
        status: const Value('delivered'),
        convertedToInvoiceId: Value(invoiceId),
      ));

      return invoiceId;
    });
  }
}
