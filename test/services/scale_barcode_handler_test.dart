import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/presentation/pos/services/scale_barcode_handler.dart';

/// Mock data source for testing — returns predefined products.
class MockBarcodeDataSource implements ScaleBarcodeDataSource {
  final Map<String, String> settings;
  final Map<int, ProductEntity> productsByPlu;
  final Map<String, ProductEntity> productsByCode;
  final Map<String, ProductEntity> productsByBarcode;

  MockBarcodeDataSource({
    this.settings = const {},
    this.productsByPlu = const {},
    this.productsByCode = const {},
    this.productsByBarcode = const {},
  });

  @override
  Future<String?> getSettingValue(String key) async => settings[key];

  @override
  Future<ProductEntity?> getProductByScalePlu(int pluNumber) async =>
      productsByPlu[pluNumber];

  @override
  Future<ProductEntity?> getProductByCode(String code) async =>
      productsByCode[code];

  @override
  Future<ProductEntity?> getProductByBarcode(String barcode) async =>
      productsByBarcode[barcode];
}

/// Helper to create a simple ProductEntity for testing.
ProductEntity _makeProduct({
  int id = 1,
  String name = 'Test Product',
  String code = '00001',
  double salePrice = 10.0,
}) {
  return ProductEntity(
    id: id,
    name: name,
    code: code,
    salePrice: salePrice,
    costPrice: salePrice * 0.7,
    currentStock: 100,
    minStock: 5,
    isActive: true,
  );
}

/// Calculate a valid EAN-13 check digit for the first 12 digits.
String _calcCheckDigit(String barcode12) {
  assert(barcode12.length == 12);
  int sum = 0;
  for (int i = 0; i < 12; i++) {
    sum += int.parse(barcode12[i]) * (i.isEven ? 1 : 3);
  }
  final check = (10 - (sum % 10)) % 10;
  return '$barcode12$check';
}

void main() {
  // ═══════════════════════════════════════════════════════════════
  // EAN-13 Check Digit Validation
  // ═══════════════════════════════════════════════════════════════

  group('EAN-13 Check Digit', () {
    test('rejects barcode with wrong check digit', () async {
      final ds = MockBarcodeDataSource(
        productsByPlu: {1: _makeProduct()},
      );
      // Valid would be "2100001012345" → manually set wrong check
      final result = await ScaleBarcodeHandler.tryParse(ds, '2100001012340');
      expect(result, isNull, reason: 'Wrong check digit should be rejected');
    });

    test('rejects non-13-digit barcode', () async {
      final ds = MockBarcodeDataSource();
      final result = await ScaleBarcodeHandler.tryParse(ds, '210000101234');
      expect(result, isNull, reason: '12 digits should be rejected');
    });

    test('rejects barcode not starting with 2', () async {
      final ds = MockBarcodeDataSource();
      // Valid EAN-13 starting with 5
      final barcode = _calcCheckDigit('500000012345');
      final result = await ScaleBarcodeHandler.tryParse(ds, barcode);
      expect(result, isNull, reason: 'Non-2 prefix should be rejected');
    });

    test('accepts valid EAN-13 with correct check digit', () async {
      // Build barcode: prefix=21, PLU=00001, value=01234, checkDigit=?
      final barcode = _calcCheckDigit('210000101234');
      final product = _makeProduct(code: '00001');
      final ds = MockBarcodeDataSource(
        productsByPlu: {1: product},
        settings: {'scale_weight_prefix': '21'},
      );
      final result = await ScaleBarcodeHandler.tryParse(ds, barcode);
      expect(result, isNotNull);
      expect(result!.product.name, 'Test Product');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Weight Mode (prefix 21)
  // ═══════════════════════════════════════════════════════════════

  group('Weight Mode', () {
    test('parses weight from barcode value field', () async {
      final barcode = _calcCheckDigit('210000101234');
      final product = _makeProduct(code: '00001');
      final ds = MockBarcodeDataSource(
        productsByPlu: {1: product},
        settings: {'scale_weight_prefix': '21'},
      );
      final result = await ScaleBarcodeHandler.tryParse(ds, barcode);
      expect(result, isNotNull);
      // Value = 01234, divider = 1000 → weight = 1.234 kg
      expect(result!.quantity, closeTo(1.234, 0.001));
    });

    test('displays weight in kg', () async {
      final barcode = _calcCheckDigit('210000101234');
      final product = _makeProduct();
      final ds = MockBarcodeDataSource(
        productsByPlu: {1: product},
        settings: {'scale_weight_prefix': '21'},
      );
      final result = await ScaleBarcodeHandler.tryParse(ds, barcode);
      expect(result, isNotNull);
      expect(result!.displayText, contains('kg'));
    });

    test('uses custom divider from settings', () async {
      final barcode = _calcCheckDigit('210000101234');
      final product = _makeProduct();
      final ds = MockBarcodeDataSource(
        productsByPlu: {1: product},
        settings: {
          'scale_weight_prefix': '21',
          'scale_weight_divider': '100',
        },
      );
      final result = await ScaleBarcodeHandler.tryParse(ds, barcode);
      expect(result, isNotNull);
      // Value = 01234, divider = 100 → weight = 12.34
      expect(result!.quantity, closeTo(12.34, 0.01));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Price Mode (prefix 20)
  // ═══════════════════════════════════════════════════════════════

  group('Price Mode', () {
    test('calculates quantity from total price', () async {
      // prefix=20, PLU=00001, value=02500
      final barcode = _calcCheckDigit('200000102500');
      final product = _makeProduct(salePrice: 10.0);
      final ds = MockBarcodeDataSource(
        productsByPlu: {1: product},
        settings: {'scale_price_prefix': '20'},
      );
      final result = await ScaleBarcodeHandler.tryParse(ds, barcode);
      expect(result, isNotNull);
      // totalPrice = 02500 / 100 = 25.00, qty = 25.00 / 10.0 = 2.5
      expect(result!.quantity, closeTo(2.5, 0.01));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Product Lookup Fallbacks
  // ═══════════════════════════════════════════════════════════════

  group('Product Lookup', () {
    test('finds product by PLU number first', () async {
      final barcode = _calcCheckDigit('210000501234');
      final product = _makeProduct(name: 'PLU Match');
      final ds = MockBarcodeDataSource(
        productsByPlu: {5: product},
        settings: {'scale_weight_prefix': '21'},
      );
      final result = await ScaleBarcodeHandler.tryParse(ds, barcode);
      expect(result, isNotNull);
      expect(result!.product.name, 'PLU Match');
    });

    test('falls back to code lookup', () async {
      final barcode = _calcCheckDigit('210000301234');
      final product = _makeProduct(name: 'Code Match');
      final ds = MockBarcodeDataSource(
        productsByCode: {'00003': product},
        settings: {'scale_weight_prefix': '21'},
      );
      final result = await ScaleBarcodeHandler.tryParse(ds, barcode);
      expect(result, isNotNull);
      expect(result!.product.name, 'Code Match');
    });

    test('falls back to barcode lookup', () async {
      final barcode = _calcCheckDigit('210000701234');
      final product = _makeProduct(name: 'Barcode Match');
      final ds = MockBarcodeDataSource(
        productsByBarcode: {'00007': product},
        settings: {'scale_weight_prefix': '21'},
      );
      final result = await ScaleBarcodeHandler.tryParse(ds, barcode);
      expect(result, isNotNull);
      expect(result!.product.name, 'Barcode Match');
    });

    test('returns null when no product found', () async {
      final barcode = _calcCheckDigit('210009901234');
      final ds = MockBarcodeDataSource(
        settings: {'scale_weight_prefix': '21'},
      );
      final result = await ScaleBarcodeHandler.tryParse(ds, barcode);
      expect(result, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Input Cleaning
  // ═══════════════════════════════════════════════════════════════

  group('Input Cleaning', () {
    test('strips CR/LF/null chars', () async {
      final barcode = _calcCheckDigit('210000101234');
      final dirty = '$barcode\r\n\x00';
      final product = _makeProduct();
      final ds = MockBarcodeDataSource(
        productsByPlu: {1: product},
        settings: {'scale_weight_prefix': '21'},
      );
      final result = await ScaleBarcodeHandler.tryParse(ds, dirty);
      expect(result, isNotNull);
    });

    test('trims whitespace', () async {
      final barcode = _calcCheckDigit('210000101234');
      final padded = '  $barcode  ';
      final product = _makeProduct();
      final ds = MockBarcodeDataSource(
        productsByPlu: {1: product},
        settings: {'scale_weight_prefix': '21'},
      );
      final result = await ScaleBarcodeHandler.tryParse(ds, padded);
      expect(result, isNotNull);
    });
  });
}
