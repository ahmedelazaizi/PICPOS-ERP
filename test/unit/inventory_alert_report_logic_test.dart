import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/presentation/reports_picpos/screens/inventory_alert_report_support.dart';

void main() {
  test('expiry rows expose remaining days and cost at risk', () {
    final products = [
      const ProductEntity(
        id: 7,
        code: 'P-7',
        name: 'حليب',
        salePrice: 4,
        costPrice: 2.5,
        currentStock: 10,
        minStock: 3,
      ),
    ];
    final batch = ProductBatchData(
      id: 2,
      productId: 7,
      batchNumber: 'B-2',
      expiryDate: DateTime.now().add(const Duration(days: 8)),
      quantity: 8,
      costPrice: 2.5,
      createdAt: DateTime.now(),
    );

    final rows = expiryAlertRows(
      batches: [batch],
      products: products,
      days: 30,
      expired: false,
    );

    expect(rows.single.detail, contains('7'));
    expect(rows.single.value, 20);
    expect(rows.single.severity, 1);
  });
}
