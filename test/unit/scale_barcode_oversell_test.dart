// ═══════════════════════════════════════════════════════════════════════════
// Scanning a SCALE label for an out-of-stock weighed item.
//
// The PicPos till detects a silently-refused scan and offers «اسمح بالبيع
// بالسالب». To do that it must name the product the scan meant — but a scale
// label (EAN-13 starting with `2`, PLU and weight embedded) never matches a
// product's barcode or code raw: the digits change with every weighing.
//
// So `_blockedProductForBarcode` composes two pieces:
//     ScaleBarcodeHandler.tryParse(...)  →  the product
//     CartState.blocksAdd(product, ...)  →  was it the stock guard?
//
// These tests pin that composition. They are what stops a weighed item from
// falling back into the old silent behaviour, and — just as important — stop a
// FALSE prompt on a scan that was refused for some other reason.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_handler.dart';

class _MockDataSource implements ScaleBarcodeDataSource {
  final Map<String, String> settings;
  final Map<int, ProductEntity> byPlu;

  _MockDataSource({this.settings = const {}, this.byPlu = const {}});

  @override
  Future<String?> getSettingValue(String key) async => settings[key];

  @override
  Future<ProductEntity?> getProductByScalePlu(int plu) async => byPlu[plu];

  @override
  Future<ProductEntity?> getProductByCode(String code) async => null;

  @override
  Future<ProductEntity?> getProductByBarcode(String barcode) async => null;
}

ProductEntity _weighedProduct({required double currentStock}) => ProductEntity(
      id: 7,
      code: '00001',
      name: 'جبنة بيضاء',
      salePrice: 120,
      costPrice: 90,
      currentStock: currentStock,
      minStock: 0,
      isSoldByWeight: true,
      scaleType: 'weight',
      scalePluNumber: 1,
    );

/// EAN-13 check digit over the first 12 digits.
String _ean13(String barcode12) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(barcode12[i]) * (i.isEven ? 1 : 3);
  }
  return '$barcode12${(10 - (sum % 10)) % 10}';
}

/// prefix `21` · PLU `00001` · weight `01234` → 1.234 kg
String _weightLabel() => _ean13('210000101234');

void main() {
  const weightSettings = {'scale_weight_prefix': '21'};

  test('a scale label resolves to its product even at zero stock', () async {
    // The contract `_blockedProductForBarcode` leans on. `getProductByCode` and
    // `getProductByBarcode` both return null in the mock ON PURPOSE — proving
    // the resolution came from the PLU path, which is the only one that can
    // work for a scale label.
    final ds = _MockDataSource(
      settings: weightSettings,
      byPlu: {1: _weighedProduct(currentStock: 0)},
    );

    final result = await ScaleBarcodeHandler.tryParse(ds, _weightLabel());

    expect(result, isNotNull,
        reason: 'without this the till cannot name the item and falls back to '
            'refusing the scan in silence');
    expect(result!.product.id, 7);
    expect(result.quantity, closeTo(1.234, 0.001),
        reason: 'the embedded weight must survive so the retry re-adds the '
            'same quantity the cashier weighed');
  });

  test('the resolved product is correctly seen as stock-blocked', () async {
    final ds = _MockDataSource(
      settings: weightSettings,
      byPlu: {1: _weighedProduct(currentStock: 0)},
    );
    final product =
        (await ScaleBarcodeHandler.tryParse(ds, _weightLabel()))!.product;

    expect(
      const CartState().blocksAdd(product, globalNegativeSales: false),
      isTrue,
      reason: 'this is what turns the silent refusal into the prompt',
    );
  });

  test('after allowing oversell the retry is no longer blocked', () async {
    final ds = _MockDataSource(
      settings: weightSettings,
      byPlu: {1: _weighedProduct(currentStock: 0)},
    );
    final product =
        (await ScaleBarcodeHandler.tryParse(ds, _weightLabel()))!.product;

    expect(
      const CartState(allowOversell: true)
          .blocksAdd(product, globalNegativeSales: false),
      isFalse,
      reason: 're-running searchBarcode after approval must succeed, otherwise '
          'the cashier approves and nothing happens',
    );
  });

  test('an in-stock weighed item is never prompted about', () async {
    final ds = _MockDataSource(
      settings: weightSettings,
      byPlu: {1: _weighedProduct(currentStock: 5)},
    );
    final product =
        (await ScaleBarcodeHandler.tryParse(ds, _weightLabel()))!.product;

    expect(
      const CartState().blocksAdd(product, globalNegativeSales: false),
      isFalse,
    );
  });

  test('an unknown PLU resolves to nothing — no false prompt', () async {
    // The label parses as a scale barcode but matches no product. The till must
    // stay silent here: the shared search controller already reported its own
    // error, and a second «الصنف غير متوفر» would be wrong AND confusing.
    final ds = _MockDataSource(settings: weightSettings, byPlu: const {});

    expect(await ScaleBarcodeHandler.tryParse(ds, _weightLabel()), isNull);
  });

  test('a non-scale barcode is not treated as one', () async {
    // Plain product barcodes must fall through to the code/barcode lookup
    // rather than being mis-parsed as a PLU + weight.
    final ds = _MockDataSource(
      settings: weightSettings,
      byPlu: {1: _weighedProduct(currentStock: 0)},
    );

    expect(await ScaleBarcodeHandler.tryParse(ds, '6221031492015'), isNull,
        reason: 'a normal EAN-13 starting with 6 is not a scale label');
  });
}
