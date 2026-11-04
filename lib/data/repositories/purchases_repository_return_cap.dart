part of 'purchases_repository_impl.dart';

extension _PurchaseReturnCap on PurchasesRepositoryImpl {
  Future<T> _withPurchaseReturnLock<T>(
    int invoiceId,
    Future<T> Function() action,
  ) async {
    final lockTails = PurchasesRepositoryImpl._returnLockTails;
    final previous = lockTails[invoiceId] ?? Future<void>.value();
    final gate = Completer<void>();
    final tail = previous.then((_) => gate.future);
    lockTails[invoiceId] = tail;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(lockTails[invoiceId], tail)) lockTails.remove(invoiceId);
    }
  }

  Future<void> _lockPurchaseInvoiceRow(int invoiceId) async {
    final lockClause = _db.isPostgres ? ' FOR UPDATE' : '';
    await _db
        .customSelect(
          'SELECT id FROM purchase_invoices WHERE id = ?$lockClause',
          variables: [Variable<int>(invoiceId)],
        )
        .getSingleOrNull();
  }

  Future<double> _returnedPurchaseQuantity(int invoiceId, int productId) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(-quantity), 0) AS returned_qty '
          'FROM stock_movements WHERE reference_id = ? AND product_id = ? AND '
          'deleted_at IS NULL AND '
          "((reference_type = 'purchase_return' AND "
          "movement_type = 'purchase_return') OR "
          "(reference_type = 'purchase_return_reverse' AND "
          "movement_type = 'purchase_return_reverse'))",
          variables: [Variable<int>(invoiceId), Variable<int>(productId)],
          readsFrom: {_db.stockMovements},
        )
        .getSingle();
    return (row.data['returned_qty'] as num).toDouble();
  }

  Future<void> _assertPurchaseReturnQuantityAvailable(
    int invoiceId,
    int productId,
    double soldQuantity,
    double requestedQuantity,
  ) async {
    final previouslyReturned = await _returnedPurchaseQuantity(
      invoiceId,
      productId,
    );
    final available =
        soldQuantity - (previouslyReturned < 0 ? 0 : previouslyReturned);
    if (requestedQuantity > available + 0.001) {
      throw Exception(
        'كمية الإرجاع ($requestedQuantity) تتجاوز الكمية المتاحة للإرجاع '
        '(${available < 0 ? 0 : available}) للصنف رقم $productId',
      );
    }
  }

  Future<void> _validatePurchaseReturnQuantities(
    int invoiceId,
    List<PurchaseReturnItem> items,
  ) async {
    final soldByProduct = <int, double>{};
    final requestedByProduct = <int, double>{};
    for (final line in items) {
      soldByProduct.update(
        line.productId,
        (quantity) => quantity + line.originalQuantity,
        ifAbsent: () => line.originalQuantity,
      );
      if (line.returnQuantity > 0) {
        requestedByProduct.update(
          line.productId,
          (quantity) => quantity + line.returnQuantity,
          ifAbsent: () => line.returnQuantity,
        );
      }
    }
    for (final entry in requestedByProduct.entries) {
      await _assertPurchaseReturnQuantityAvailable(
        invoiceId,
        entry.key,
        soldByProduct[entry.key] ?? 0,
        entry.value,
      );
    }
  }
}
