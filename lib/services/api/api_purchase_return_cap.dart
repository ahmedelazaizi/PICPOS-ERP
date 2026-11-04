part of 'api_purchase_handler.dart';

extension _ApiPurchaseReturnCap on ApiPurchaseHandler {
  Future<void> _lockPurchaseInvoiceRow(int invoiceId) async {
    final lockClause = db.isPostgres ? ' FOR UPDATE' : '';
    await db
        .customSelect(
          'SELECT id FROM purchase_invoices WHERE id = ?$lockClause',
          variables: [Variable<int>(invoiceId)],
        )
        .getSingleOrNull();
  }

  Future<Map<int, double>> _requestedPurchaseReturnQtyByProduct(
    List<Map<String, dynamic>> items,
  ) async {
    final requestedByProduct = <int, double>{};
    for (final returnItem in items) {
      final productId = await resolveProductId(
        clientProductId: parseIntNullable(returnItem['productId']),
        productGlobalId: returnItem['productGlobalId'] as String?,
        fallbackCode: returnItem['productCode'] as String?,
        fallbackName: returnItem['productName'] as String?,
      );
      final quantity = parseDouble(returnItem['returnQuantity']);
      if (productId != null && quantity > 0) {
        requestedByProduct.update(
          productId,
          (sum) => sum + quantity,
          ifAbsent: () => quantity,
        );
      }
    }
    return requestedByProduct;
  }

  Future<double> _returnedPurchaseQty(int invoiceId, int productId) async {
    final returned = await db
        .customSelect(
          'SELECT COALESCE(SUM(-quantity), 0) AS returned_qty '
          'FROM stock_movements WHERE reference_id = ? AND product_id = ? AND '
          'deleted_at IS NULL AND '
          "((reference_type = 'purchase_return' AND "
          "movement_type = 'purchase_return') OR "
          "(reference_type = 'purchase_return_reverse' AND "
          "movement_type = 'purchase_return_reverse'))",
          variables: [Variable<int>(invoiceId), Variable<int>(productId)],
          readsFrom: {db.stockMovements},
        )
        .getSingle();
    return (returned.data['returned_qty'] as num).toDouble();
  }

  Future<void> _assertPurchaseReturnFits(
    int invoiceId,
    int productId,
    double soldQuantity,
    double requestedQuantity,
  ) async {
    final previous = await _returnedPurchaseQty(invoiceId, productId);
    final available = soldQuantity - (previous < 0 ? 0 : previous);
    if (requestedQuantity > available + 0.001) {
      throw Exception(
        'كمية الإرجاع ($requestedQuantity) تتجاوز الكمية المتاحة للإرجاع '
        '(${available < 0 ? 0 : available}) للصنف رقم $productId',
      );
    }
  }

  Future<void> _validateCumulativePurchaseReturn(
    int invoiceId,
    List<Map<String, dynamic>> returnItems,
  ) async {
    await _lockPurchaseInvoiceRow(invoiceId);
    final originals = await (db.select(
      db.purchaseInvoiceItems,
    )..where((line) => line.invoiceId.equals(invoiceId))).get();
    final soldByProduct = <int, double>{};
    for (final line in originals) {
      soldByProduct.update(
        line.productId,
        (sum) => sum + line.quantity,
        ifAbsent: () => line.quantity,
      );
    }
    final requestedByProduct = await _requestedPurchaseReturnQtyByProduct(
      returnItems,
    );
    for (final entry in requestedByProduct.entries) {
      final soldQuantity = soldByProduct[entry.key];
      if (soldQuantity == null) continue;
      await _assertPurchaseReturnFits(
        invoiceId,
        entry.key,
        soldQuantity,
        entry.value,
      );
    }
  }
}
