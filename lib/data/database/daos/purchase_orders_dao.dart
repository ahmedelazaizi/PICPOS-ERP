// ═══════════════════════════════════════════════════════════════════════════
// Purchase Orders DAO Extension
// ═══════════════════════════════════════════════════════════════════════════
// Provides CRUD and workflow methods for purchase order management.
//
// Status flow: draft → sent → confirmed → received → (converted to invoice)
//            ↘ cancelled

part of '../database.dart';

/// A purchase order that may not be invoiced through the legacy full-quantity
/// paths (convertPOToInvoice, link-a-PO). [code] is a stable token the API
/// answers as 409 {error: code}, so an outbox replay is parked, not retried.
class PurchaseOrderNotConsumable implements Exception {
  PurchaseOrderNotConsumable(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

extension PurchaseOrdersDao on AppDatabase {
  // -----------------------------------------------------------------------
  // WATCH / READ
  // -----------------------------------------------------------------------

  /// Watch all purchase orders, sorted by newest first
  Stream<List<PurchaseOrderData>> watchPurchaseOrders() {
    return (select(purchaseOrders)
          ..orderBy([(po) => OrderingTerm.desc(po.createdAt)]))
        .watch();
  }

  /// Watch purchase orders filtered by status
  Stream<List<PurchaseOrderData>> watchPurchaseOrdersByStatus(String status) {
    return (select(purchaseOrders)
          ..where((po) => po.status.equals(status))
          ..orderBy([(po) => OrderingTerm.desc(po.createdAt)]))
        .watch();
  }

  /// Get single PO by ID
  /// Global id of a purchase order by local id (null when absent).
  Future<String?> purchaseOrderGlobalIdOf(int? id) async => id == null ? null : (await getPurchaseOrderById(id))?.globalId;

  Future<PurchaseOrderData?> getPurchaseOrderByGlobalId(String gid) {
    return (select(purchaseOrders)..where((po) => po.globalId.equals(gid)))
        .getSingleOrNull();
  }

  Future<PurchaseOrderData?> getPurchaseOrderById(int id) {
    return (select(purchaseOrders)..where((po) => po.id.equals(id)))
        .getSingleOrNull();
  }

  /// Get items for a purchase order
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) {
    return (select(purchaseOrderItems)
          ..where((i) => i.orderId.equals(orderId)))
        .get();
  }

  /// Watch items for a purchase order
  Stream<List<PurchaseOrderItem>> watchPurchaseOrderItems(int orderId) {
    return (select(purchaseOrderItems)
          ..where((i) => i.orderId.equals(orderId)))
        .watch();
  }

  /// Generate next PO number
  Future<String> _nextPONumber() async {
    final count = await (selectOnly(purchaseOrders)
          ..addColumns([purchaseOrders.id.count()]))
        .getSingle();
    final next = (count.read(purchaseOrders.id.count()) ?? 0) + 1;
    return 'PO-${next.toString().padLeft(5, '0')}';
  }

  // -----------------------------------------------------------------------
  // CREATE / UPDATE / DELETE
  // -----------------------------------------------------------------------

  /// Create a new purchase order with items
  Future<int> createPurchaseOrder({
    required int supplierId,
    required int warehouseId,
    required DateTime orderDate,
    DateTime? expectedDate,
    String? notes,
    int? costCenterId,
    required List<PurchaseOrderItemsCompanion> items,
  }) async {
    final poNumber = await _nextPONumber();
    double subtotal = 0;
    for (final item in items) {
      subtotal += item.total.value;
    }
    final orderGid = UuidV7.generate();

    if (SyncInterceptor.isClientMode) {
      final orderData = {
        'globalId': orderGid,
        'orderNumber': poNumber,
        'supplierId': supplierId,
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
          'unitCost': item.unitCost.value,
          'total': item.total.value,
          if (item.notes.present) 'notes': item.notes.value,
        };
      }).toList();
      final serverId = await SyncInterceptor.instance?.createPurchaseOrder(orderData, itemMaps);
      if (serverId != null) return serverId;
    }

    return transaction(() async {
      final orderId = await into(purchaseOrders).insert(
        PurchaseOrdersCompanion.insert(
          orderNumber: poNumber,
          supplierId: supplierId,
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
        await into(purchaseOrderItems).insert(itemWithGid);
      }
      return orderId;
    });
  }

  /// Update PO status
  Future<void> updatePurchaseOrderStatus(int orderId, String newStatus) async {
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.updatePurchaseOrderStatus(orderId, newStatus);
    }
    await (update(purchaseOrders)..where((po) => po.id.equals(orderId)))
        .write(PurchaseOrdersCompanion(status: Value(newStatus)));
  }

  /// Delete a draft PO (only drafts can be deleted)
  Future<void> deletePurchaseOrder(int orderId) async {
    final po = await getPurchaseOrderById(orderId);
    if (po == null) throw Exception('أمر شراء غير موجود');
    if (po.status != 'draft') throw Exception('لا يمكن حذف أمر شراء غير مسودة');

    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.deletePurchaseOrder(orderId);
    }
    await transaction(() async {
      await (delete(purchaseOrderItems)..where((i) => i.orderId.equals(orderId))).go();
      await (delete(purchaseOrders)..where((po) => po.id.equals(orderId))).go();
    });
  }

  /// يتحقّق أنّ الأمرَ **صالحٌ للاستهلاك** — ويرمي إن لم يكن.
  ///
  /// ═══ ولماذا قاعدةٌ لا رسم ═══
  ///
  /// للأمر **مدخلان** إلى نفس الحدث منذ قرارِ المالك 2026-09-18: زرُّ
  /// «استلام وتحويل لفاتورة» على شاشة الأوامر، و«ربط أمر شراء» من داخل
  /// الفاتورة. وأيُّ واحدٍ منهما يُدخل البضاعةَ ويقيّد ذمّةَ المورّد.
  ///
  /// 🔴 **وكان المنعُ رسماً لا قاعدة**: `convertPOToInvoice` يرفض الملغى
  /// وحدَه، وشاشةُ الأوامر تخفي الزرَّ بعد التحويل لأنّ الحالةَ تصير
  /// `received`. فالمنعُ يعيش في الودجت، ويمرّ منه كلُّ منادٍ آخر — حالةُ
  /// الاستعمال العامّة، والمدخلُ الجديد. وثمنُه فاتورتان بنفس البضاعة:
  /// مخزونٌ يدخل مرّتَين، ومتوسّطُ تكلفةٍ على كمّيّةٍ ضِعفَ الحقيقة، وذمّةٌ
  /// تُقيَّد مرّتَين.
  ///
  /// ⚠️ **والفاصلُ `convertedToInvoiceId` لا `status`**: الرابطُ هو **واقعةُ**
  /// الاستهلاك، والحالةُ وسمٌ يُبدَّل بـ`updatePurchaseOrderStatus` بلا أن
  /// يقع شيء.
  Future<PurchaseOrderData> _requireConsumablePurchaseOrder(int orderId) async {
    final po = await getPurchaseOrderById(orderId);
    if (po == null) throw PurchaseOrderNotConsumable('po_not_found', 'أمر شراء غير موجود');
    if (po.status == 'cancelled') {
      throw PurchaseOrderNotConsumable('po_cancelled', 'لا يمكن تحويل أمر شراء ملغي');
    }
    if (po.convertedToInvoiceId != null) {
      throw PurchaseOrderNotConsumable('po_already_converted',
          'أمر الشراء ${po.orderNumber} مرتبطٌ بالفاتورة رقم '
          '${po.convertedToInvoiceId} — لا يُحوَّل مرّتين');
    }
    // WH-001: a phone receipt (submitted or already converted) moves
    // `received_quantity`. The legacy full-quantity paths invoice the whole
    // order, so they would enter the received part a second time (stock and
    // supplier AP doubled). Such an order is invoiced ONLY through the receipt
    // conversion (`WhReceiptPosting`), which stamps it via
    // [markPurchaseOrderConvertedByReceipts].
    final received = await (select(purchaseOrderItems)
          ..where((i) => i.orderId.equals(orderId) & i.receivedQuantity.isBiggerThanValue(0))
          ..limit(1))
        .get();
    if (received.isNotEmpty) {
      throw PurchaseOrderNotConsumable('po_has_receipts',
          'أمر الشراء ${po.orderNumber} له استلام من تطبيق المخازن — '
          'يُفوتَر من شاشة «استلامات المخازن» بالكميات المستلمة فقط');
    }
    return po;
  }

  /// Stamps the order consumed by the LAST warehouse-receipt invoice (the
  /// receipts conversion calls this inside its transaction).
  Future<void> markPurchaseOrderConvertedByReceipts(int orderId, int invoiceId) =>
      _markPurchaseOrderConverted(orderId, invoiceId);

  /// WH-001: an invoice may not carry more of a product than the order asked for
  /// (the order is the ceiling). Checked on the invoice's STORED lines, inside the
  /// invoice's own transaction, so a refusal rolls the stock and the journal back.
  Future<void> _requireInvoiceWithinOrder(int orderId, int invoiceId) async {
    final ordered = <int, double>{};
    for (final i in await getPurchaseOrderItems(orderId)) {
      ordered[i.productId] = (ordered[i.productId] ?? 0) + i.quantity;
    }
    final invoiced = <int, double>{};
    final lines = await (select(purchaseInvoiceItems)..where((l) => l.invoiceId.equals(invoiceId))).get();
    for (final l in lines) {
      if (!ordered.containsKey(l.productId)) continue;
      invoiced[l.productId] = (invoiced[l.productId] ?? 0) + l.quantity;
    }
    for (final e in invoiced.entries) {
      if (e.value > ordered[e.key]! + 1e-9) {
        throw PurchaseOrderNotConsumable('po_over_invoiced',
            'كمية الفاتورة للصنف ${e.key} (${e.value}) تتجاوز المطلوب في أمر الشراء (${ordered[e.key]})');
      }
    }
  }

  /// يختم الأمرَ مستهلَكاً بالفاتورة — **داخلَ معاملةِ إنشائها**.
  ///
  /// فلو أخفق شيءٌ بعده رجع الختمُ مع الفاتورة، ولا يبقى أمرٌ مستهلَكٌ بلا
  /// فاتورة.
  Future<void> _markPurchaseOrderConverted(int orderId, int invoiceId) async {
    await _requireInvoiceWithinOrder(orderId, invoiceId);
    // The invoice brings the goods in: the lines count as received, so a late
    // phone receipt of the same order is an over_receipt (WH-001).
    for (final i in await getPurchaseOrderItems(orderId)) {
      if (i.receivedQuantity + 1e-9 >= i.quantity) continue;
      await (update(purchaseOrderItems)..where((x) => x.id.equals(i.id))).write(
          PurchaseOrderItemsCompanion(receivedQuantity: Value(i.quantity)));
    }
    await (update(purchaseOrders)..where((po) => po.id.equals(orderId)))
        .write(PurchaseOrdersCompanion(
      status: const Value('received'),
      convertedToInvoiceId: Value(invoiceId),
      receivedAt: Value(DateTime.now()),
    ));
  }

  /// Convert PO to Purchase Invoice
  Future<int> convertPOToInvoice(int orderId) async {
    return transaction(() async {
      final po = await _requireConsumablePurchaseOrder(orderId);

      final items = await getPurchaseOrderItems(orderId);

      // Get user or fallback
      final defaultUser = await (select(users)..limit(1)).getSingleOrNull();
      if (defaultUser == null) throw Exception('لا يوجد مستخدمين في النظام لإجراء التحويل');

      // Map PO items to Purchase Invoice items companions
      final invoiceItems = items.map((item) {
        return PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0, // Placeholder — overwritten by createPurchaseInvoice
          productId: item.productId,
          quantity: item.quantity,
          unitCost: item.unitCost,
          total: item.total,
          discount: Value(item.discount),
          // NEW-04: tax and cost centre travel like the receipt conversion does.
          taxRate: Value(item.taxRate),
          taxAmount: Value(item.taxAmount),
        );
      }).toList();
      final lineDiscounts = items.fold<double>(0, (s, i) => s + i.discount);

      // CREATION VIA HARDENED DAO (PurchaseDao)
      // This ensures accounting (Autopost), Inventory (Stock adjust + WAC), and Treasury are handled.
      // We pass paid=0 for credit invoice.
      final invoiceId = await createPurchaseInvoice(
        supplierId: po.supplierId,
        warehouseId: po.warehouseId,
        paid: 0,
        paymentMethod: 'credit',
        notes: 'تم التحويل من أمر شراء ${po.orderNumber}',
        items: invoiceItems,
        costCenterId: po.costCenterId,
        // The document discount is the TOTAL (header + the lines' own).
        discount: FinancialUtils.round(po.discount + lineDiscounts),
      );

      await _markPurchaseOrderConverted(orderId, invoiceId);

      return invoiceId;
    });
  }
}
