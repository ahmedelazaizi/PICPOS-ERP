part of 'returns_repository_impl.dart';

extension _ReturnsRepositoryCap on ReturnsRepositoryImpl {
  Future<T> _withInvoiceReturnLock<T>(
    int invoiceId,
    Future<T> Function() action,
  ) async {
    final lockTails = ReturnsRepositoryImpl._returnLockTails;
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

  Future<void> _lockReturnInvoiceRow(int invoiceId) async {
    final lockClause = _db.isPostgres ? ' FOR UPDATE' : '';
    await _db
        .customSelect(
          'SELECT id FROM sales_invoices WHERE id = ?$lockClause',
          variables: [Variable<int>(invoiceId)],
        )
        .getSingleOrNull();
  }

  Future<void> _assertReturnQuantityAvailable(
    int invoiceId,
    int productId,
    double soldBaseQuantity,
    double requestedBaseQuantity,
  ) async {
    final returnedBaseQuantity = await _db.getAlreadyReturnedQty(
      invoiceId,
      productId,
    );
    final availableBaseQuantity = soldBaseQuantity - returnedBaseQuantity;
    if (requestedBaseQuantity > availableBaseQuantity + 0.001) {
      throw Exception(
        'كمية الإرجاع بوحدة الأساس '
        '(${requestedBaseQuantity.toStringAsFixed(AppConstants.decimalPlaces)}) '
        'تتجاوز المتاح للإرجاع بوحدة الأساس '
        '(${(availableBaseQuantity < 0 ? 0 : availableBaseQuantity).toStringAsFixed(AppConstants.decimalPlaces)}) '
        'للصنف رقم $productId',
      );
    }
  }

  Future<void> _validateReturnQuantities(
    int invoiceId,
    List<SalesInvoiceItem> items,
    Map<int, double> quantities,
  ) async {
    final soldByProduct = <int, double>{};
    final requestedByProduct = <int, double>{};
    for (final line in items) {
      final factor = line.quantityInBase > 0 ? line.quantityInBase : 1.0;
      final soldBaseQuantity = line.quantity * factor;
      soldByProduct.update(
        line.productId,
        (sum) => sum + soldBaseQuantity,
        ifAbsent: () => soldBaseQuantity,
      );
      final requestedSaleQuantity = quantities[line.id] ?? 0;
      if (requestedSaleQuantity > 0) {
        final requestedBaseQuantity = requestedSaleQuantity * factor;
        requestedByProduct.update(
          line.productId,
          (sum) => sum + requestedBaseQuantity,
          ifAbsent: () => requestedBaseQuantity,
        );
      }
    }
    for (final entry in requestedByProduct.entries) {
      await _assertReturnQuantityAvailable(
        invoiceId,
        entry.key,
        soldByProduct[entry.key] ?? 0,
        entry.value,
      );
    }
  }
}
