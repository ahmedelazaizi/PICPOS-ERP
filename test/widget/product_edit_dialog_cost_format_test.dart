// QA: opening a product whose cost is 0.27999999999999997 showed the raw float
// in the edit dialog's cost field. It must read 0.28.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/presentation/screens/products/widgets/product_edit_dialog.dart';

import 'product_tax_test_support.dart';

void main() {
  testWidgets('cost/sale price fields show no float artifact', (tester) async {
    useLargeTestView(tester);
    tolerateDialogOverflow();
    final db = await bootTaxTestDb(tester);
    late int id;
    await tester.runAsync(() async {
      id = await db.into(db.products).insert(ProductsCompanion.insert(
            code: 'CF1',
            name: 'P-CF1',
            costPrice: const Value(0.27999999999999997),
            salePrice: const Value(0.35000000000000003),
          ));
    });
    final entity = ProductEntity(
      id: id,
      code: 'CF1',
      name: 'P-CF1',
      salePrice: 0.35000000000000003,
      costPrice: 0.27999999999999997,
      currentStock: 0,
      minStock: 0,
      taxRate: 0,
    );
    await tester.pumpWidget(taxTestHost(
      ProductEditDialog(key: UniqueKey(), product: entity),
      db: db,
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.tap(find.text('الأسعار'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final texts = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .map((e) => e.controller.text)
        .toList();
    expect(texts, contains('0.28'));
    expect(texts, contains('0.35'));
    expect(texts.where((t) => t.contains('99999') || t.contains('00000')),
        isEmpty);
  });
}
