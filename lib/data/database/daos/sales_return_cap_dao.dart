part of '../database.dart';

extension SalesReturnCapDao on AppDatabase {
  /// Returns the net active sales-return quantity in base units.
  ///
  /// Prefer [getReturnedQuantitiesForInvoice] when loading every product.
  Future<double> getReturnedQuantityForInvoiceItem({
    required int invoiceId,
    required int productId,
  }) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(quantity), 0) AS total_returned '
      'FROM stock_movements WHERE reference_id = ? AND product_id = ? AND '
      'deleted_at IS NULL AND '
      "((reference_type IN ('sales_return', 'sales_invoice') "
      "AND movement_type = 'return') OR "
      "(reference_type = 'return_cancel' AND movement_type = 'return_cancel'))",
      variables: [Variable<int>(invoiceId), Variable<int>(productId)],
      readsFrom: {stockMovements},
    ).getSingle();
    final returned = (result.data['total_returned'] as num).toDouble();
    return returned > 0 ? returned : 0.0;
  }

  /// Returns net base-unit quantities by product in one query.
  Future<Map<int, double>> getReturnedQuantitiesForInvoice(
    int invoiceId,
  ) async {
    final rows = await customSelect(
      'SELECT product_id, COALESCE(SUM(quantity), 0) AS total_returned '
      'FROM stock_movements WHERE reference_id = ? AND '
      "((reference_type IN ('sales_return', 'sales_invoice') "
      "AND movement_type = 'return') OR "
      "(reference_type = 'return_cancel' AND movement_type = 'return_cancel')) "
      'AND deleted_at IS NULL '
      'GROUP BY product_id',
      variables: [Variable<int>(invoiceId)],
      readsFrom: {stockMovements},
    ).get();
    return {
      for (final row in rows)
        if ((row.data['total_returned'] as num).toDouble() > 0)
          row.data['product_id'] as int: (row.data['total_returned'] as num)
              .toDouble(),
    };
  }
}
