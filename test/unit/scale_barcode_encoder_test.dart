import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_encoder.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_handler.dart';

class _Source implements ScaleBarcodeDataSource {
  final ProductEntity product;
  _Source(this.product);

  @override
  Future<String?> getSettingValue(String key) async => null;
  @override
  Future<ProductEntity?> getProductByScalePlu(int pluNumber) async =>
      pluNumber == product.scalePluNumber ? product : null;
  @override
  Future<ProductEntity?> getProductByCode(String code) async => null;
  @override
  Future<ProductEntity?> getProductByBarcode(String barcode) async => null;
}

void main() {
  test('round-trips scale payloads through the production parser', () async {
    final product = ProductEntity(
      id: 1,
      code: 'PEAR',
      name: 'Pear',
      salePrice: 2.5,
      costPrice: 1,
      currentStock: 100,
      minStock: 0,
      scalePluNumber: 123,
    );
    final source = _Source(product);
    for (final sample in [
      (ScaleBarcodeValueKind.weight, 0.001, 1000.0, 0.001),
      (ScaleBarcodeValueKind.weight, 99.999, 1000.0, 99.999),
      (ScaleBarcodeValueKind.price, 12.35, 100.0, 4.94),
    ]) {
      final code = ScaleBarcodeEncoder.encode(
        plu: '123',
        value: sample.$2,
        kind: sample.$1,
        divider: sample.$3,
      );
      final parsed = await ScaleBarcodeHandler.tryParse(source, code);
      expect(parsed?.product.id, product.id);
      expect(parsed!.quantity, closeTo(sample.$4, 0.000001));
    }
  });

  test('emits valid 13-digit EAN-13 weight and price payloads', () {
    for (final sample in [
      (ScaleBarcodeValueKind.weight, 0.001, 1000.0),
      (ScaleBarcodeValueKind.weight, 99.999, 1000.0),
      (ScaleBarcodeValueKind.price, 12.35, 100.0),
    ]) {
      final code = ScaleBarcodeEncoder.encode(
        plu: '123',
        value: sample.$2,
        kind: sample.$1,
        divider: sample.$3,
      );
      expect(code, matches(RegExp(r'^\d{13}$')));
      expect(
        code.startsWith(
          sample.$1 == ScaleBarcodeValueKind.weight ? '21' : '20',
        ),
        isTrue,
      );
      var sum = 0;
      for (var i = 0; i < 12; i++) {
        sum += int.parse(code[i]) * (i.isEven ? 1 : 3);
      }
      expect(int.parse(code[12]), (10 - sum % 10) % 10);
    }
  });

  test('rejects PLU/value overflow rather than emitting a bad barcode', () {
    expect(
      () => ScaleBarcodeEncoder.encode(
        plu: '123456',
        value: 1,
        kind: ScaleBarcodeValueKind.weight,
      ),
      throwsArgumentError,
    );
    expect(
      () => ScaleBarcodeEncoder.encode(
        plu: '12345',
        value: 1000,
        kind: ScaleBarcodeValueKind.weight,
      ),
      throwsRangeError,
    );
    expect(
      () => ScaleBarcodeEncoder.encode(
        plu: '12345',
        value: 1.2345,
        kind: ScaleBarcodeValueKind.weight,
      ),
      throwsArgumentError,
    );
  });
}
