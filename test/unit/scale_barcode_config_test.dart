import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/presentation/pos/services/ean13_modules.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_config.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_encoder.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_handler.dart';

class _Source implements ScaleBarcodeDataSource {
  _Source(this.settings, this.product);
  final Map<String, String> settings;
  final ProductEntity product;

  @override
  Future<String?> getSettingValue(String key) async => settings[key];
  @override
  Future<ProductEntity?> getProductByScalePlu(int pluNumber) async =>
      pluNumber == product.scalePluNumber ? product : null;
  @override
  Future<ProductEntity?> getProductByCode(String code) async => null;
  @override
  Future<ProductEntity?> getProductByBarcode(String barcode) async => null;
}

void main() {
  test(
    'defaults match ScaleBarcodeHandler (price 20, weight 21, fallback 22)',
    () {
      const c = ScaleBarcodeConfig();
      expect(c.pricePrefix, '20');
      expect(c.weightPrefix, '21');
      expect(c.fallbackPrefix, '22');
      expect(c.validate(), isEmpty);
      expect(c.valueDigitsOf(ScaleBarcodeValueKind.weight), 5);
      expect(c.decimalsOf(ScaleBarcodeValueKind.weight), 3);
      expect(c.decimalsOf(ScaleBarcodeValueKind.price), 2);
    },
  );

  test(
    'fromSettings reads canonical keys, then legacy keys, then defaults',
    () {
      final c = ScaleBarcodeConfig.fromSettings({
        'scale_weight_enabled': 'true',
        'scale_barcode_prefix': '24', // legacy weight prefix
        'scale_qty_code_length': '4', // legacy price code length
        'scale_price_prefix': '27',
        'scale_qty_prefix': '29', // ignored: canonical key wins
      });
      expect(c.weightEnabled, isTrue);
      expect(
        c.priceEnabled,
        isTrue,
      ); // Saved prefix preserves pre-toggle behavior.
      expect(c.weightPrefix, '24');
      expect(c.pricePrefix, '27');
      expect(c.priceCodeLen, '4');
      expect(c.weightDivider, '1000');
      expect(
        c.toSettings().keys,
        containsAll(ScaleBarcodeConfig.canonicalKeys),
      );
      expect(c.toSettings().keys, isNot(contains('scale_barcode_prefix')));
    },
  );

  test('missing toggle follows saved prefixes; explicit false wins', () {
    final untouched = ScaleBarcodeConfig.fromSettings({});
    expect(untouched.weightEnabled, isFalse);
    expect(untouched.priceEnabled, isFalse);

    final legacy = ScaleBarcodeConfig.fromSettings({
      'scale_barcode_prefix': '21',
      'scale_qty_prefix': '20',
    });
    expect(legacy.weightEnabled, isTrue);
    expect(legacy.priceEnabled, isTrue);

    final explicitlyOff = ScaleBarcodeConfig.fromSettings({
      'scale_weight_enabled': 'false',
      'scale_price_enabled': 'false',
      'scale_barcode_prefix': '21',
      'scale_qty_prefix': '20',
    });
    expect(explicitlyOff.weightEnabled, isFalse);
    expect(explicitlyOff.priceEnabled, isFalse);
    expect(explicitlyOff.isEnabledScaleBarcode('2112345001234'), isFalse);
    expect(explicitlyOff.isDisabledScaleBarcode('2112345001234'), isTrue);
    expect(untouched.isEnabledScaleBarcode('2112345001234'), isFalse);
    expect(untouched.isDisabledScaleBarcode('2112345001234'), isTrue);
  });

  test('rejects non-digit prefixes, layouts that overflow 13 digits, bad '
      'dividers and overlapping prefixes', () {
    ScaleBarcodeConfig c0() => const ScaleBarcodeConfig();
    expect(
      c0().copyWith(weightPrefix: '2a').validate(),
      contains(ScaleBarcodeIssue.weightPrefixInvalid),
    );
    expect(
      c0().copyWith(weightPrefix: '31').validate(),
      contains(ScaleBarcodeIssue.weightPrefixInvalid),
    );
    // 2 + 10 = 12 ⇒ لا خانة للقيمة.
    expect(
      c0().copyWith(weightCodeLen: '10').validate(),
      contains(ScaleBarcodeIssue.weightCodeLenInvalid),
    );
    expect(c0().copyWith(weightCodeLen: '9').validate(), isEmpty);
    expect(
      c0().copyWith(priceCodeLen: '0').validate(),
      contains(ScaleBarcodeIssue.priceCodeLenInvalid),
    );
    expect(
      c0().copyWith(weightDivider: '250').validate(),
      contains(ScaleBarcodeIssue.weightDividerInvalid),
    );
    expect(c0().copyWith(weightDivider: '1000.0').validate(), isEmpty);
    expect(
      c0().copyWith(pricePrefix: '21').validate(),
      contains(ScaleBarcodeIssue.prefixConflict),
    );
    expect(
      c0().copyWith(pricePrefix: '2').validate(),
      contains(ScaleBarcodeIssue.prefixConflict),
    );
    // السعر 22 = البادئة البديلة للوزن (الافتراض القديم للشاشة).
    expect(
      c0().copyWith(pricePrefix: '22').validate(),
      contains(ScaleBarcodeIssue.fallbackConflict),
    );
  });

  test('sample barcode (PLU 12345, 1.234 kg) round-trips through the POS '
      'parser with the configured profile', () async {
    final settings = {
      'scale_weight_enabled': 'true',
      'scale_weight_prefix': '23',
      'scale_weight_item_code_len': '5',
      'scale_weight_divider': '1000',
    };
    final config = ScaleBarcodeConfig.fromSettings(settings);
    final sample = config.sample(ScaleBarcodeValueKind.weight);
    expect(
      sample.barcode,
      ScaleBarcodeEncoder.encode(
        plu: '12345',
        value: 1.234,
        kind: ScaleBarcodeValueKind.weight,
        prefix: '23',
      ),
    );
    expect(sample.barcode, startsWith('231234501234'));
    const product = ProductEntity(
      id: 9,
      code: 'X',
      name: 'منتج تجريبي',
      salePrice: 10,
      costPrice: 1,
      currentStock: 10,
      minStock: 0,
      scalePluNumber: 12345,
    );
    final parsed = await ScaleBarcodeHandler.tryParse(
      _Source(settings, product),
      sample.barcode!,
    );
    expect(parsed?.product.id, 9);
    expect(parsed!.quantity, closeTo(1.234, 1e-9));
  });

  test('enabled, explicit false, missing toggle with saved prefix, and no '
      'saved prefix round-trip through the handler', () async {
    const product = ProductEntity(
      id: 9,
      code: 'X',
      name: 'منتج تجريبي',
      salePrice: 10,
      costPrice: 1,
      currentStock: 10,
      minStock: 0,
      scalePluNumber: 12345,
    );
    final barcode = const ScaleBarcodeConfig(
      weightEnabled: true,
    ).encode(kind: ScaleBarcodeValueKind.weight, plu: '12345', value: 1.234);

    final enabled = {
      'scale_weight_enabled': 'true',
      'scale_weight_prefix': '21',
    };
    expect(
      (await ScaleBarcodeHandler.tryParse(
        _Source(enabled, product),
        barcode,
      ))?.quantity,
      closeTo(1.234, 1e-9),
    );

    final disabled = {
      'scale_weight_enabled': 'false',
      'scale_weight_prefix': '21',
    };
    expect(
      await ScaleBarcodeHandler.tryParse(_Source(disabled, product), barcode),
      isNull,
    );

    final missingToggle = {'scale_weight_prefix': '21'};
    expect(
      (await ScaleBarcodeHandler.tryParse(
        _Source(missingToggle, product),
        barcode,
      ))?.quantity,
      closeTo(1.234, 1e-9),
    );

    expect(
      await ScaleBarcodeHandler.tryParse(_Source({}, product), barcode),
      isNull,
    );
  });

  test('sample trims PLU / rounds value instead of failing, and reports '
      'overflow', () {
    final short = const ScaleBarcodeConfig(
      weightCodeLen: '4',
    ).sample(ScaleBarcodeValueKind.weight);
    expect(short.plu, '1234');
    expect(short.barcode, hasLength(13));
    final coarse = const ScaleBarcodeConfig(
      weightDivider: '100',
    ).sample(ScaleBarcodeValueKind.weight);
    expect(coarse.value, 1.23);
    // 2 + 8 ⇒ خانتا قيمة؛ 1234 لا تتسع.
    final overflow = const ScaleBarcodeConfig(
      weightCodeLen: '8',
    ).sample(ScaleBarcodeValueKind.weight);
    expect(overflow.barcode, isNull);
    expect(overflow.error, ScaleSampleError.valueOverflow);
    expect(
      const ScaleBarcodeConfig(
        pricePrefix: '21',
      ).sample(ScaleBarcodeValueKind.weight).error,
      ScaleSampleError.profileInvalid,
    );
  });

  test('ean13Modules produces the 95-module GS1 pattern', () {
    // 4006381333931 مثالٌ معياريٌّ شائع لـ EAN-13.
    final m = ean13Modules('4006381333931')!;
    expect(m, hasLength(95));
    String bits(int from, int to) =>
        m.sublist(from, to).map((b) => b ? '1' : '0').join();
    expect(bits(0, 3), '101');
    expect(bits(45, 50), '01010');
    expect(bits(92, 95), '101');
    // الرقم الثاني 0 بتماثل L (البادئة 4 ⇒ LGLLGG).
    expect(bits(3, 10), '0001101');
    // الرقم الثالث 0 بتماثل G.
    expect(bits(10, 17), '0100111');
    // أوّل رقم يميني 3 ⇒ R = 1000010.
    expect(bits(50, 57), '1000010');
    expect(ean13Modules('12'), isNull);
  });
}
