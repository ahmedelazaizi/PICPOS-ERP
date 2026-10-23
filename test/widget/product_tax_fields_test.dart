// Owner item 5 — the Add Item / Edit Item dialogs replace the tax dropdown
// with «معفى من الضريبة» + «تفعيل الضريبة» / «نسبة الضريبة %».
// The Edit Item dialog's load mapping is in product_edit_dialog_tax_test.dart
// (one database per test file — see bootTaxTestDb).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/tax/product_tax_choice.dart';
import 'package:picpos_erp/presentation/widgets/dialogs/add_product_dialog.dart';
import 'package:picpos_erp/presentation/widgets/dialogs/product_tax_fields.dart';

import 'product_tax_test_support.dart';

void main() {
  group('ProductTaxFields', () {
    testWidgets('exempt and custom rate are mutually exclusive',
        (tester) async {
      final c = ProductTaxController();
      addTearDown(c.dispose);
      await tester.pumpWidget(taxTestHost(ProductTaxFields(controller: c)));

      expect(taxBoxChecked(tester, ProductTaxFields.exemptKey), isFalse);
      expect(taxBoxChecked(tester, ProductTaxFields.enableKey), isFalse);
      expect(taxRateEnabled(tester), isFalse, reason: 'default: rate disabled');

      await tester.tap(find.byKey(ProductTaxFields.enableKey));
      await tester.pump();
      expect(taxBoxChecked(tester, ProductTaxFields.enableKey), isTrue);
      expect(taxRateEnabled(tester), isTrue);

      await tester.tap(find.byKey(ProductTaxFields.exemptKey));
      await tester.pump();
      expect(taxBoxChecked(tester, ProductTaxFields.exemptKey), isTrue);
      expect(taxBoxChecked(tester, ProductTaxFields.enableKey), isFalse,
          reason: 'ticking exempt turns the custom rate off');
      expect(taxRateEnabled(tester), isFalse);

      await tester.tap(find.byKey(ProductTaxFields.enableKey));
      await tester.pump();
      expect(taxBoxChecked(tester, ProductTaxFields.exemptKey), isFalse,
          reason: 'enabling the custom rate clears exempt');
      expect(taxBoxChecked(tester, ProductTaxFields.enableKey), isTrue);
    });

    testWidgets('load mapping: exempt / specific rate / default',
        (tester) async {
      final c = ProductTaxController();
      addTearDown(c.dispose);
      await tester.pumpWidget(taxTestHost(ProductTaxFields(controller: c)));

      c.loadStored(taxRate: 0, taxExempt: true);
      await tester.pump();
      expect(taxBoxChecked(tester, ProductTaxFields.exemptKey), isTrue);
      expect(taxBoxChecked(tester, ProductTaxFields.enableKey), isFalse);

      c.loadStored(taxRate: 16, taxExempt: false);
      await tester.pump();
      expect(taxBoxChecked(tester, ProductTaxFields.exemptKey), isFalse);
      expect(taxBoxChecked(tester, ProductTaxFields.enableKey), isTrue);
      expect(c.rateController.text, '16');
      expect(taxRateEnabled(tester), isTrue);

      c.loadStored(taxRate: 0, taxExempt: false);
      await tester.pump();
      expect(taxBoxChecked(tester, ProductTaxFields.exemptKey), isFalse);
      expect(taxBoxChecked(tester, ProductTaxFields.enableKey), isFalse);
      expect(c.rateController.text, isEmpty);
    });

    testWidgets('save values and validation', (tester) async {
      final c = ProductTaxController();
      addTearDown(c.dispose);
      await tester.pumpWidget(taxTestHost(ProductTaxFields(controller: c)));

      // default
      expect(c.choice, const ProductTaxChoice.companyDefault());
      expect(c.choice!.storedTaxRate, 0);
      expect(c.choice!.storedTaxExempt, isFalse);

      // custom 16
      await tester.tap(find.byKey(ProductTaxFields.enableKey));
      await tester.pump();
      await tester.enterText(find.byKey(ProductTaxFields.rateKey), '16');
      await tester.pump();
      expect(c.choice, const ProductTaxChoice.custom(16));
      expect(c.choice!.storedTaxRate, 16);

      // > 100, 3 decimals and an off-ladder rate block the save with an error
      for (final bad in ['150', '16.125', '7']) {
        await tester.enterText(find.byKey(ProductTaxFields.rateKey), bad);
        await tester.pump();
        expect(c.choice, isNull, reason: bad);
        expect(c.rateError, isNotNull, reason: bad);
        expect(find.text(c.rateError!), findsOneWidget, reason: bad);
      }

      // exempt
      await tester.tap(find.byKey(ProductTaxFields.exemptKey));
      await tester.pump();
      expect(c.choice, const ProductTaxChoice.exempt());
      expect(c.choice!.storedTaxRate, 0);
      expect(c.choice!.storedTaxExempt, isTrue);
    });

    testWidgets('LTR layout renders the same controls', (tester) async {
      final c = ProductTaxController();
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(body: ProductTaxFields(controller: c)),
        ),
      ));
      expect(find.byKey(ProductTaxFields.exemptKey), findsOneWidget);
      expect(find.byKey(ProductTaxFields.enableKey), findsOneWidget);
      expect(find.byKey(ProductTaxFields.rateKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Add Item dialog: controls replace the dropdown, default start',
      (tester) async {
    useLargeTestView(tester);
    tolerateDialogOverflow();
    final db = await bootTaxTestDb(tester);
    await tester.pumpWidget(taxTestHost(const AddProductDialog(), db: db));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(ProductTaxFields), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<double>), findsNothing,
        reason: 'the tax dropdown is gone');

    final c = dialogTaxController(tester);
    expect(c.choice, const ProductTaxChoice.companyDefault(),
        reason: 'a new item starts on the default — tax_rate 0 as before');

    await tester.tap(find.byKey(ProductTaxFields.enableKey));
    await tester.pump();
    await tester.enterText(find.byKey(ProductTaxFields.rateKey), '16');
    await tester.pump();
    expect(c.choice!.storedTaxRate, 16);
    expect(c.choice!.storedTaxExempt, isFalse);

    await tester.tap(find.byKey(ProductTaxFields.exemptKey));
    await tester.pump();
    expect(taxBoxChecked(tester, ProductTaxFields.enableKey), isFalse);
    expect(c.choice!.storedTaxRate, 0);
    expect(c.choice!.storedTaxExempt, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
