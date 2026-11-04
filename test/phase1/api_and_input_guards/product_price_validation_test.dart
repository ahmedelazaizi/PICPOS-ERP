import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/presentation/widgets/dialogs/product_form_helpers.dart';

void main() {
  test('negative prices fail validation while zero remains allowed', () {
    expect(ProductFormHelpers.validateNonNegativePrice('-0.01'), isNotNull);
    expect(ProductFormHelpers.validateNonNegativePrice('0'), isNull);
    expect(ProductFormHelpers.validateNonNegativePrice('12.5'), isNull);
    expect(ProductFormHelpers.validateNonNegativePrice('--1'), isNotNull);
  });

  testWidgets('negative price is shown as a field-level error', (tester) async {
    final controller = TextEditingController(text: '-0.01');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductFormHelpers.buildCompactTextField(
          controller,
          'سعر البيع',
          nonNegativePrice: true,
        ),
      ),
    ));
    final error = ProductFormHelpers.validateNonNegativePrice(controller.text)!;
    expect(find.text(error), findsOneWidget);
  });

  test('product DAO rejects negative prices and accepts zero', () async {
    final db = AppDatabase.forTesting();
    try {
      await expectLater(
        db.insertProduct(ProductsCompanion.insert(
          code: 'NEG',
          name: 'Negative price',
          salePrice: const Value(-1),
        )),
        throwsA(isA<ArgumentError>().having(
            (error) => error.message.toString(), 'message', contains('سالباً'))),
      );
      await expectLater(
        db.insertProduct(ProductsCompanion.insert(
          code: 'NEG-COST',
          name: 'Negative cost',
          costPrice: const Value(-1),
        )),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        db.insertProduct(ProductsCompanion.insert(
          code: 'NEG-SPECIAL',
          name: 'Negative special price',
          priceTalabat: const Value(-1),
        )),
        throwsA(isA<ArgumentError>()),
      );
      final id = await db.insertProduct(ProductsCompanion.insert(
        code: 'ZERO',
        name: 'Zero price',
        salePrice: const Value(0),
        costPrice: const Value(0),
      ));
      expect(id, greaterThan(0));
      final product = await db.getProductById(id);
      await expectLater(
        db.updateProduct(product!.copyWith(wholesalePrice: -0.5)),
        throwsA(isA<ArgumentError>()),
      );
    } finally {
      await db.close();
    }
  });
}
