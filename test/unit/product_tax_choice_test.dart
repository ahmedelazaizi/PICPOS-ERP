// Owner item 5 — product tax controls (exempt / enable-tax + rate).
//
// The new controls must store exactly what the old tax dropdown stored for
// the equivalent choice, so the invoice-line tax cannot change. The dropdown
// wrote only `products.tax_rate`: «معفي / صفر ٪» → 0, «16 ٪» → 16, and a new
// item left untouched → 0 (the add dialog's initial value, i.e. the company
// default on every PicPos sale path).
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/tax/product_tax_choice.dart';
import 'package:ural_erp/core/tax/tax_rate_policy.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/usecases/sales/calculate_invoice_totals_usecase.dart';

/// Invoice tax for one line of [taxRate] at a 14% company default — the
/// production totals engine (`item.taxRate > 0 ? item.taxRate : taxPercent`).
double _lineTax(double taxRate) {
  final totals = CalculateInvoiceTotalsUseCase().execute(
    items: [
      CartItemEntity(
        productId: 1,
        productName: 'P',
        productCode: 'P1',
        quantity: 2,
        unitPrice: 50,
        taxRate: taxRate,
      ),
    ],
    taxPercent: 14,
  );
  return totals.taxAmount;
}

void main() {
  tearDown(TaxRatePolicy.resetForTests);

  group('stored representation equals the old dropdown', () {
    // (new-control choice, value the dropdown stored for the same choice)
    const cases = <(String, ProductTaxChoice, double)>[
      ('exempt', ProductTaxChoice.exempt(), 0),
      ('16%', ProductTaxChoice.custom(16), 16),
      ('company default', ProductTaxChoice.companyDefault(), 0),
    ];

    for (final (label, choice, dropdownTaxRate) in cases) {
      test('$label → tax_rate $dropdownTaxRate and identical line tax', () {
        expect(choice.storedTaxRate, dropdownTaxRate);
        expect(_lineTax(choice.storedTaxRate), _lineTax(dropdownTaxRate));
      });
    }

    test('concrete line taxes (qty 2 × 50, company default 14%)', () {
      expect(_lineTax(const ProductTaxChoice.custom(16).storedTaxRate), 16);
      // tax_rate 0 falls back to the company default — as the dropdown's
      // «معفي» option always did (pre-existing semantics, documented).
      expect(_lineTax(const ProductTaxChoice.exempt().storedTaxRate), 14);
      expect(
          _lineTax(const ProductTaxChoice.companyDefault().storedTaxRate), 14);
    });

    test('only the exempt choice sets the tax_exempt flag', () {
      expect(const ProductTaxChoice.exempt().storedTaxExempt, isTrue);
      expect(const ProductTaxChoice.custom(16).storedTaxExempt, isFalse);
      expect(const ProductTaxChoice.companyDefault().storedTaxExempt, isFalse);
    });
  });

  group('fromStored — load mapping', () {
    test('rate > 0 → custom', () {
      expect(ProductTaxChoice.fromStored(taxRate: 16, taxExempt: false),
          const ProductTaxChoice.custom(16));
    });
    test('rate 0 + flag → exempt', () {
      expect(ProductTaxChoice.fromStored(taxRate: 0, taxExempt: true),
          const ProductTaxChoice.exempt());
    });
    test('rate 0, no flag → company default', () {
      expect(ProductTaxChoice.fromStored(taxRate: 0, taxExempt: false),
          const ProductTaxChoice.companyDefault());
    });
    test('a positive rate wins over a stale flag (it is what sales apply)', () {
      expect(ProductTaxChoice.fromStored(taxRate: 5, taxExempt: true),
          const ProductTaxChoice.custom(5));
    });
  });

  group('validateRate', () {
    test('accepts ladder rates incl. Arabic digits and comma', () {
      expect(ProductTaxChoice.validateRate('16'), isNull);
      expect(ProductTaxChoice.validateRate('١٦'), isNull);
      expect(ProductTaxChoice.validateRate('16.00'), isNull);
      expect(ProductTaxChoice.parseRate('16,0'), 16);
    });
    test('rejects empty, > 100, negative, text and > 2 decimals', () {
      for (final bad in ['', '101', '-5', 'abc', '16.001', '1e2']) {
        expect(ProductTaxChoice.validateRate(bad), isNotNull, reason: bad);
      }
    });
    test('rejects 0 — 0 is stored as the company default', () {
      expect(ProductTaxChoice.validateRate('0'), isNotNull);
    });
    test('rejects off-ladder rates, honours a configured ladder', () {
      expect(ProductTaxChoice.validateRate('7'), isNotNull);
      expect(ProductTaxChoice.validateRate('12.5'), isNotNull);
      TaxRatePolicy.configureFromSetting('0,12.5');
      expect(ProductTaxChoice.validateRate('12.5'), isNull);
    });
    test('an item\'s legacy off-ladder rate stays savable', () {
      expect(ProductTaxChoice.validateRate('14', legacyRate: 14), isNull);
      expect(ProductTaxChoice.validateRate('13', legacyRate: 14), isNotNull);
    });
    test('14 and 15 are on the default ladder (owner decision)', () {
      TaxRatePolicy.resetForTests();
      expect(ProductTaxChoice.validateRate('14'), isNull);
      expect(ProductTaxChoice.validateRate('15'), isNull);
    });
  });

  group('database round-trip (v182 products.tax_exempt)', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting());
    tearDown(() async => db.close());

    Future<ProductTaxChoice> roundTrip(String code, ProductTaxChoice c) async {
      final id = await db.into(db.products).insert(ProductsCompanion.insert(
            code: code,
            name: 'P-$code',
            taxRate: Value(c.storedTaxRate),
          ));
      await db.setProductTaxExempt(id, c.storedTaxExempt);
      final row = await (db.select(db.products)
            ..where((p) => p.id.equals(id)))
          .getSingle();
      return ProductTaxChoice.fromStored(
        taxRate: row.taxRate,
        taxExempt: await db.getProductTaxExempt(id),
      );
    }

    test('fresh install has the column, defaulting to 0', () async {
      final cols = await db.customSelect('PRAGMA table_info(products)').get();
      expect(cols.any((c) => c.data['name'] == 'tax_exempt'), isTrue);
      final id = await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'D', name: 'default'));
      expect(await db.getProductTaxExempt(id), isFalse);
    });

    test('ensureProductTaxExemptSchema is idempotent', () async {
      await db.ensureProductTaxExemptSchema();
      await db.ensureProductTaxExemptSchema();
    });

    test('exempt / 16% / default reload as themselves', () async {
      for (final (code, c) in const [
        ('E', ProductTaxChoice.exempt()),
        ('S', ProductTaxChoice.custom(16)),
        ('N', ProductTaxChoice.companyDefault()),
      ]) {
        expect(await roundTrip(code, c), c, reason: code);
      }
    });

    test('switching exempt → default clears the flag', () async {
      final id = await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'X', name: 'x'));
      await db.setProductTaxExempt(id, true);
      await db.setProductTaxExempt(id, false);
      expect(await db.getProductTaxExempt(id), isFalse);
    });
  });
}
