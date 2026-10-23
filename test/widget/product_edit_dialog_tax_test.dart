// Owner item 5 — the Edit Item dialog (opened by the PicPos products table)
// maps an item's stored tax onto «معفى من الضريبة» / «تفعيل الضريبة» +
// «نسبة الضريبة %»: exempt (tax_rate 0 + tax_exempt 1), a specific rate,
// and the company default (tax_rate 0, no flag).
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/tax/product_tax_choice.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/presentation/screens/products/widgets/product_edit_dialog.dart';
import 'package:picpos_erp/presentation/widgets/dialogs/product_tax_fields.dart';

import 'product_tax_test_support.dart';

Future<void> _openEdit(
  WidgetTester tester,
  AppDatabase db,
  ProductEntity product,
) async {
  // Unmount first: a fresh State must run initState + the DB refresh.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(taxTestHost(
    ProductEditDialog(key: UniqueKey(), product: product),
    db: db,
  ));
  // Let `_refreshFromDatabase` (real drift I/O) finish.
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  await tester.tap(find.text('الأسعار'));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('Edit Item dialog maps stored tax: exempt / 16% / default',
      (tester) async {
    useLargeTestView(tester);
    tolerateDialogOverflow();
    final db = await bootTaxTestDb(tester);

    final ids = <String, int>{};
    await tester.runAsync(() async {
      for (final (code, rate, exempt) in const [
        ('EX', 0.0, true),
        ('RT', 16.0, false),
        ('DF', 0.0, false),
      ]) {
        final id = await db.into(db.products).insert(ProductsCompanion.insert(
              code: code,
              name: 'P-$code',
              taxRate: Value(rate),
            ));
        await db.setProductTaxExempt(id, exempt);
        ids[code] = id;
      }
    });

    // The entity carries tax_rate only (as the products table passes it); the
    // exempt flag must come from the dialog's own database refresh.
    ProductEntity entity(String code, double rate) => ProductEntity(
          id: ids[code]!,
          code: code,
          name: 'P-$code',
          salePrice: 10,
          costPrice: 4,
          currentStock: 0,
          minStock: 0,
          taxRate: rate,
        );

    await _openEdit(tester, db, entity('EX', 0));
    expect(taxBoxChecked(tester, ProductTaxFields.exemptKey), isTrue);
    expect(taxBoxChecked(tester, ProductTaxFields.enableKey), isFalse);
    expect(dialogTaxController(tester).choice,
        const ProductTaxChoice.exempt());

    await _openEdit(tester, db, entity('RT', 16));
    expect(taxBoxChecked(tester, ProductTaxFields.exemptKey), isFalse);
    expect(taxBoxChecked(tester, ProductTaxFields.enableKey), isTrue);
    expect(dialogTaxController(tester).rateController.text, '16');
    expect(dialogTaxController(tester).choice,
        const ProductTaxChoice.custom(16));

    await _openEdit(tester, db, entity('DF', 0));
    expect(taxBoxChecked(tester, ProductTaxFields.exemptKey), isFalse);
    expect(taxBoxChecked(tester, ProductTaxFields.enableKey), isFalse);
    expect(dialogTaxController(tester).choice,
        const ProductTaxChoice.companyDefault());

    // 16% → exempt is mutually exclusive inside the dialog; the values the
    // save writes are tax_rate 0 + tax_exempt 1.
    await _openEdit(tester, db, entity('RT', 16));
    await tester.tap(find.byKey(ProductTaxFields.exemptKey));
    await tester.pump();
    expect(taxBoxChecked(tester, ProductTaxFields.enableKey), isFalse);
    expect(dialogTaxController(tester).choice!.storedTaxRate, 0);
    expect(dialogTaxController(tester).choice!.storedTaxExempt, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
