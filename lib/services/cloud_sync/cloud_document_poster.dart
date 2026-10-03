import 'package:drift/drift.dart';

import '../../core/constants/app_constants.dart';
import '../../data/database/database.dart';
import '../../data/database/extensions/distribution_dao.dart';
import '../../data/mappers/product_mapper.dart';
import '../../data/repositories/returns_repository_impl.dart';
import '../../data/repositories/sales_transaction_orchestrator.dart';
import '../../domain/entities/cart_item_entity.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/models/return_refund_calculator.dart';
import '../../domain/models/voucher_book.dart';
import '../../domain/repositories/sales_repository.dart';
import '../accounting_service.dart';
import 'cloud_customer_poster.dart';

/// A cloud field document the desktop refused; [code] is stable (shown and
/// sent to the cloud as the failure reason), [detail] is for the operator.
class CloudPostingException implements Exception {
  CloudPostingException(this.code, [this.detail]);
  final String code;
  final String? detail;

  String get reason => detail == null ? code : '$code: $detail';

  @override
  String toString() => 'CloudPostingException($reason)';
}

/// The desktop document a cloud field document became.
class CloudPostedRef {
  const CloudPostedRef(this.desktopRef, this.desktopNumber);
  final String desktopRef;
  final String? desktopNumber;
}

/// Posts one accepted cloud field document (I-3, ARCHITECTURE-I §8) through
/// the **existing** desktop paths, so stock, journal entries, safe
/// movements, voucher books, rep/route stamps, integrity and numbering are
/// what the same document entered on the desktop produces:
/// * `sales_invoice` → [SalesTransactionOrchestrator.completeSalesTransaction]
///   (van warehouse, payment into the rep's custody safe, field date, rep and
///   route stamp, cloud `globalId` kept on the invoice);
/// * `sales_return` → [ReturnsRepositoryImpl.processSalesReturn] against the
///   desktop invoice the original cloud invoice was posted as (cash refund
///   from the custody safe);
/// * `collection` → `createReceiptVoucher` + `assignVoucherBookLeaf`
///   (the paper leaf of the rep's voucher book);
/// * `visit` → `route_visits`.
///
/// Every reference travels as a cloud/desktop `global_id`; an unknown one,
/// a total that does not match what the desktop computes, or any desktop
/// validation error raises [CloudPostingException] and nothing is written.
class CloudDocumentPoster {
  CloudDocumentPoster(this.db, AccountingService accounting,
      {required this.postingUserId, this.postingUserName = 'Cloud sync'})
      : _orchestrator = SalesTransactionOrchestrator(db, accounting),
        _returns = ReturnsRepositoryImpl(db, accounting);

  final AppDatabase db;
  final int postingUserId;
  final String postingUserName;
  final SalesTransactionOrchestrator _orchestrator;
  final ReturnsRepositoryImpl _returns;

  /// Totals may differ by at most this (same 2-dp rounding on both sides).
  static const tolerance = 0.01;

  Future<CloudPostedRef> post(Map<String, dynamic> doc) {
    final kind = doc['kind'];
    return switch (kind) {
      'sales_invoice' => _postInvoice(doc),
      'sales_return' => _postReturn(doc),
      'collection' => _postCollection(doc),
      'visit' => _postVisit(doc),
      'customer' => postCloudCustomer(db, doc),
      _ => throw CloudPostingException('unsupported_kind', '$kind'),
    };
  }

  // ───────────────────────────── lookups ─────────────────────────────

  Future<int?> _idByGlobalId(String table, Object? gid) async {
    if (gid is! String || gid.isEmpty) return null;
    final row = await db.customSelect(
      'SELECT id FROM $table WHERE global_id = ? LIMIT 1',
      variables: [Variable<String>(gid)],
    ).getSingleOrNull();
    return (row?.data['id'] as num?)?.toInt();
  }

  Future<int> _require(String table, Object? gid, String code) async {
    final id = await _idByGlobalId(table, gid);
    if (id == null) throw CloudPostingException(code, '$gid');
    return id;
  }

  static double _num(Object? v) => v is num ? v.toDouble() : 0.0;

  static String? _text(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  // ───────────────────────────── sales invoice ─────────────────────────────

  Future<CloudPostedRef> _postInvoice(Map<String, dynamic> doc) async {
    final gid = doc['globalId'] as String;
    final existing = await (db.select(db.salesInvoices)
          ..where((s) => s.globalId.equals(gid)))
        .getSingleOrNull();
    if (existing != null) {
      return CloudPostedRef('${existing.id}', existing.invoiceNumber);
    }
    final customerId =
        await _require('parties', doc['customerGlobalId'], 'customer_not_found');
    final warehouseId = await _require(
        'warehouses', doc['warehouseGlobalId'], 'van_warehouse_not_found');
    final repId = await _require(
        'employees', doc['repEmployeeGlobalId'], 'rep_not_found');
    final routeId = await _idByGlobalId('sales_routes', doc['routeGlobalId']);
    final safeId = await _idByGlobalId('safes', doc['safeGlobalId']);
    final paid = _num(doc['paid']);
    if (paid > 0 && safeId == null) {
      throw CloudPostingException('custody_safe_not_found', '${doc['safeGlobalId']}');
    }

    final items = <CartItemEntity>[];
    for (final raw in (doc['lines'] as List? ?? const [])) {
      final l = (raw as Map).cast<String, dynamic>();
      final productId =
          await _require('products', l['productGlobalId'], 'product_not_found');
      final product = await db.getProductById(productId);
      if (product == null) {
        throw CloudPostingException('product_not_found', '${l['productGlobalId']}');
      }
      final qty = _num(l['quantity']);
      final price = _num(l['unitPrice']);
      final discount = _num(l['discount']);
      final gross = qty * price;
      items.add(CartItemEntity(
        productId: productId,
        productName: product.name,
        productCode: product.code,
        barcode: product.barcode,
        quantity: qty,
        unitPrice: price,
        discountPercent: gross > 0 && discount > 0 ? discount / gross * 100 : 0,
        // The desktop product card is the tax authority (same as a desktop
        // sale); the cloud's own figure is only compared below.
        taxRate: product.taxRate,
      ));
    }
    if (items.isEmpty) throw CloudPostingException('no_lines');

    final total = _num(doc['total']);
    final systemTaxRate =
        double.tryParse(await db.getSettingValue('tax_rate') ?? '') ??
            SaleRequest.kDefaultTaxPercent;
    final pricesIncludeTax =
        await db.getSettingValue('prices_include_tax') == 'true';
    final number = doc['number'] as String?;

    return db.transaction(() async {
      final result = await _orchestrator.completeSalesTransaction(SaleRequest(
        items: items,
        customerId: customerId,
        warehouseId: warehouseId,
        userId: postingUserId,
        paymentMethod: paid > 0 ? 'cash' : 'credit',
        paidAmount: paid,
        cashAmount: paid > 0 ? paid : null,
        cashSafeId: safeId,
        taxPercent: systemTaxRate,
        pricesIncludeTax: pricesIncludeTax,
        notes: number == null ? null : 'Cloud $number',
        platformOrderNumber: number,
        globalId: gid,
        invoiceDate: _date(doc['date']),
        repEmployeeId: repId,
        routeId: routeId,
        cashOutsideDrawer: true,
        // J3 — the one-time name typed on a cash-customer van sale.
        adhocCustomerName: _text(doc['customerName']),
        adhocCustomerPhone: _text(doc['customerPhone']),
      ));
      if (result is! SaleSuccess) {
        throw CloudPostingException(
            'desktop_rejected', (result as SaleFailure).error);
      }
      final invoice = await (db.select(db.salesInvoices)
            ..where((s) => s.id.equals(result.invoiceId)))
          .getSingle();
      if ((invoice.total - total).abs() > tolerance) {
        throw CloudPostingException('totals_mismatch',
            'desktop ${invoice.total.toStringAsFixed(2)} ≠ cloud ${total.toStringAsFixed(2)}');
      }
      return CloudPostedRef('${invoice.id}', invoice.invoiceNumber);
    });
  }

  // ───────────────────────────── sales return ─────────────────────────────

  Future<CloudPostedRef> _postReturn(Map<String, dynamic> doc) async {
    final origGid = doc['originalInvoiceGlobalId'];
    final invoice = origGid is String
        ? await (db.select(db.salesInvoices)
              ..where((s) => s.globalId.equals(origGid)))
            .getSingleOrNull()
        : null;
    if (invoice == null) {
      throw CloudPostingException('original_invoice_not_posted', '$origGid');
    }
    final items = await db.getSalesInvoiceItems(invoice.id);
    final productIds = <String, int>{};
    final quantities = <int, double>{};
    for (final raw in (doc['lines'] as List? ?? const [])) {
      final l = (raw as Map).cast<String, dynamic>();
      final pg = l['productGlobalId'];
      final productId = productIds[pg] ??=
          await _require('products', pg, 'product_not_found');
      var remaining = _num(l['quantity']);
      for (final item in items.where((i) => i.productId == productId)) {
        if (remaining <= 0) break;
        final free = item.quantity - (quantities[item.id] ?? 0);
        if (free <= 0) continue;
        final take = remaining < free ? remaining : free;
        quantities[item.id] = (quantities[item.id] ?? 0) + take;
        remaining -= take;
      }
      if (remaining > 0.0001) {
        throw CloudPostingException('return_qty_exceeds_invoice', '$pg');
      }
    }
    if (quantities.isEmpty) throw CloudPostingException('no_lines');

    final desktopTotal = calculateReturnRefundTotal(
      lines: [
        for (final i in items) (id: i.id, quantity: i.quantity, lineTotal: i.total),
      ],
      invoiceTotal: invoice.total,
      invoiceDeliveryFee: invoice.deliveryFee,
      returnQuantities: quantities,
      decimalPlaces: AppConstants.decimalPlaces,
    );
    final cloudTotal = _num(doc['total']);
    if ((desktopTotal - cloudTotal).abs() > tolerance) {
      throw CloudPostingException('totals_mismatch',
          'desktop ${desktopTotal.toStringAsFixed(2)} ≠ cloud ${cloudTotal.toStringAsFixed(2)}');
    }
    final safeId = await _idByGlobalId('safes', doc['safeGlobalId']);
    if (_num(doc['cashRefund']) > 0 && safeId == null) {
      throw CloudPostingException('custody_safe_not_found', '${doc['safeGlobalId']}');
    }

    final productCache = <int, ProductEntity>{};
    for (final i in items) {
      final p = await db.getProductById(i.productId);
      if (p != null) productCache[i.productId] = p.toEntity();
    }
    final alreadyReturned = items.every((i) {
      final q = quantities[i.id] ?? 0;
      return (i.quantity - q).abs() < 0.0001;
    });

    return db.transaction(() async {
      String? voucher;
      final ok = await _returns.processSalesReturn(
        invoice: invoice,
        returnQuantities: quantities,
        productCache: productCache,
        reason: doc['reason'] as String?,
        userId: postingUserId,
        userName: postingUserName,
        isFullReturn: alreadyReturned,
        refundSafeId: safeId,
        onReturnVoucher: (v) => voucher = v,
      );
      if (!ok || voucher == null) {
        throw CloudPostingException('desktop_rejected', 'return not posted');
      }
      return CloudPostedRef(voucher!, voucher);
    });
  }

  // ───────────────────────────── collection ─────────────────────────────

  Future<CloudPostedRef> _postCollection(Map<String, dynamic> doc) async {
    final gid = doc['globalId'] as String;
    final existing = await (db.select(db.safeTransactions)
          ..where((t) => t.globalId.equals(gid)))
        .getSingleOrNull();
    if (existing != null) {
      return CloudPostedRef('${existing.id}', existing.voucherNumber);
    }
    final customerId =
        await _require('parties', doc['customerGlobalId'], 'customer_not_found');
    final safeId = await _require(
        'safes', doc['safeGlobalId'], 'custody_safe_not_found');
    final bookId = await _require(
        'voucher_books', doc['bookGlobalId'], 'voucher_book_not_found');
    final leaf = doc['bookNumber'];
    if (leaf is! int) throw CloudPostingException('book_number_required');
    final amount = _num(doc['amount']);
    if (amount <= 0) throw CloudPostingException('invalid_amount');

    return db.transaction(() async {
      try {
        await db.validateVoucherBookLeaf(bookId, leaf);
      } on VoucherBookException catch (e) {
        throw CloudPostingException('voucher_book_leaf_rejected', e.message);
      }
      final txnId = await db.createReceiptVoucher(
        amount: amount,
        category: 'customer_payment',
        partyId: customerId,
        safeId: safeId,
        userId: postingUserId,
        globalId: gid,
        description: 'Cloud ${doc['number'] ?? ''}'.trim(),
      );
      await db.assignVoucherBookLeaf(txnId: txnId, bookId: bookId, number: leaf);
      final row = await (db.select(db.safeTransactions)
            ..where((t) => t.id.equals(txnId)))
          .getSingle();
      return CloudPostedRef('$txnId', row.voucherNumber);
    });
  }

  // ───────────────────────────── visit ─────────────────────────────

  Future<CloudPostedRef> _postVisit(Map<String, dynamic> doc) async {
    final gid = doc['globalId'] as String;
    final existing = await (db.select(db.routeVisits)
          ..where((v) => v.globalId.equals(gid)))
        .getSingleOrNull();
    if (existing != null) return CloudPostedRef('${existing.id}', null);
    final customerId =
        await _require('parties', doc['customerGlobalId'], 'customer_not_found');
    final repId = await _require(
        'employees', doc['repEmployeeGlobalId'], 'rep_not_found');
    final routeId =
        await _require('sales_routes', doc['routeGlobalId'], 'route_not_found');
    final noSale = doc['outcome'] == 'no_sale';
    final notes = [
      if (noSale) 'no_sale: ${doc['noSaleReason'] ?? 'other'}',
      if (doc['note'] is String && (doc['note'] as String).isNotEmpty) doc['note'],
    ].join(' — ');
    final id = await db.createRouteVisit(RouteVisitsCompanion(
      routeId: Value(routeId),
      customerId: Value(customerId),
      salesRepId: Value(repId),
      visitDate: Value(_date(doc['date']) ?? DateTime.now()),
      status: Value(noSale ? 'skipped' : 'completed'),
      notes: Value(notes.isEmpty ? null : notes),
      globalId: Value(gid),
      lastModifiedAt: Value(DateTime.now()),
    ));
    return CloudPostedRef('$id', null);
  }
}
