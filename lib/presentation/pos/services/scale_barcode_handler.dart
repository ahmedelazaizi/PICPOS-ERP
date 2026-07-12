// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/foundation.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../data/providers/repository_providers.dart';

class ScaleBarcodeResult {
  final ProductEntity product;
  final double quantity;
  final String displayText;

  ScaleBarcodeResult({
    required this.product,
    required this.quantity,
    required this.displayText,
  });
}

/// Default scale barcode profile configuration
class ScaleBarcodeProfile {
  final String pricePrefix;
  final String weightPrefix;
  final String fallbackPrefix;
  final int pluLength;
  final double weightDivider;
  final double priceDivider;

  const ScaleBarcodeProfile({
    this.pricePrefix = '20',
    this.weightPrefix = '21',
    this.fallbackPrefix = '22',
    this.pluLength = 5,
    this.weightDivider = 1000.0,
    this.priceDivider = 100.0,
  });

  /// Common profiles for popular scales
  static const ean13Standard = ScaleBarcodeProfile();

  static const ean13Price2x = ScaleBarcodeProfile(
    pricePrefix: '20',
    weightPrefix: '21',
    fallbackPrefix: '22',
  );

  @override
  String toString() =>
      'ScaleBarcodeProfile('
      'price=$pricePrefix, weight=$weightPrefix, '
      'pluLen=$pluLength, wDiv=$weightDivider, pDiv=$priceDivider)';
}

/// Abstraction for scale barcode data access.
///
/// Replaces direct AppDatabase dependency for better testability
/// and separation of concerns.
abstract class ScaleBarcodeDataSource {
  Future<String?> getSettingValue(String key);
  Future<ProductEntity?> getProductByScalePlu(int pluNumber);
  Future<ProductEntity?> getProductByCode(String code);
  Future<ProductEntity?> getProductByBarcode(String barcode);
}

/// Adapts repositories to ScaleBarcodeDataSource interface.
class RepositoryBarcodeAdapter implements ScaleBarcodeDataSource {
  final dynamic _ref; 
  RepositoryBarcodeAdapter(this._ref);

  @override
  Future<String?> getSettingValue(String key) => 
    _ref.read(settingsRepositoryProvider).getSetting(key);
  
  @override
  Future<ProductEntity?> getProductByScalePlu(int pluNumber) => 
    _ref.read(productRepositoryProvider).getProductByScalePlu(pluNumber);
  
  @override
  Future<ProductEntity?> getProductByCode(String code) => 
    _ref.read(productRepositoryProvider).getProductByCode(code);
    
  @override
  Future<ProductEntity?> getProductByBarcode(String barcode) => 
    _ref.read(productRepositoryProvider).getProductByBarcode(barcode);
}

class ScaleBarcodeHandler {
  /// Try to parse a scale barcode (EAN-13 starting with '2')
  /// Returns ScaleBarcodeResult or null if not a scale barcode
  ///
  /// Accepts [ScaleBarcodeDataSource] instead of raw AppDatabase for
  /// proper architecture separation. AppDatabase already implements
  /// the required methods, so pass it directly.
  static Future<ScaleBarcodeResult?> tryParse(
    ScaleBarcodeDataSource dataSource,
    String rawBarcode,
  ) async {
    // Step 1: Clean raw input (remove CR, LF, spaces, null chars)
    final barcode = rawBarcode
        .replaceAll('\r', '')
        .replaceAll('\n', '')
        .replaceAll('\x00', '')
        .trim();

    // Step 2: Debug logging — ALWAYS log raw barcode data
    debugPrint('[ScaleBarcode] ════════════════════════════════════');
    debugPrint('[ScaleBarcode] Raw input: "${_safeHex(rawBarcode)}"');
    debugPrint('[ScaleBarcode] Cleaned:   "$barcode"');
    debugPrint(
      '[ScaleBarcode] Length:     ${barcode.length} (raw: ${rawBarcode.length})',
    );
    debugPrint(
      '[ScaleBarcode] Chars:      ${barcode.codeUnits.map((c) => '0x${c.toRadixString(16)}').join(' ')}',
    );

    // Step 3: Validate — must be EAN-13 starting with '2'
    if (barcode.length != 13) {
      debugPrint(
        '[ScaleBarcode] ✗ Not 13 digits (length=${barcode.length}), skipping scale parse',
      );
      return null;
    }
    if (!barcode.startsWith('2')) {
      debugPrint(
        '[ScaleBarcode] ✗ Does not start with "2", skipping scale parse',
      );
      return null;
    }

    // Step 3b: Validate EAN-13 check digit
    if (!_verifyEan13CheckDigit(barcode)) {
      debugPrint(
        '[ScaleBarcode] ✗ EAN-13 check digit invalid, skipping scale parse',
      );
      return null;
    }

    // Step 4: Load profile from settings (or use defaults)
    final pricePfx = await dataSource.getSettingValue('scale_price_prefix') ?? '20';
    final weightPfx = await dataSource.getSettingValue('scale_weight_prefix') ?? '21';
    final fallbackPfx =
        await dataSource.getSettingValue('scale_fallback_prefix') ?? '22';

    debugPrint(
      '[ScaleBarcode] Profile: pricePrefix=$pricePfx, weightPrefix=$weightPfx, fallback=$fallbackPfx',
    );

    // Step 5: Detect mode by prefix
    if (barcode.startsWith(pricePfx)) {
      debugPrint('[ScaleBarcode] Mode: PRICE (prefix=$pricePfx)');
      return _extractScaleProduct(
        dataSource,
        barcode,
        pricePfx,
        'scale_price_item_code_len',
        'scale_price_divider',
        5,
        100.0,
        isPriceMode: true,
      );
    } else if (barcode.startsWith(weightPfx) ||
        barcode.startsWith(fallbackPfx)) {
      final prefix = barcode.startsWith(weightPfx) ? weightPfx : fallbackPfx;
      debugPrint('[ScaleBarcode] Mode: WEIGHT (prefix=$prefix)');
      return _extractScaleProduct(
        dataSource,
        barcode,
        prefix,
        'scale_weight_item_code_len',
        'scale_weight_divider',
        5,
        1000.0,
      );
    }

    // Auto-detect: prefix "2X" not in configured list — try default weight parse
    final autoPrefix = barcode.substring(0, 2);
    debugPrint(
      '[ScaleBarcode] ⚠ Prefix "$autoPrefix" not configured '
      '[$pricePfx, $weightPfx, $fallbackPfx] — trying auto-detect...',
    );
    return _extractScaleProduct(
      dataSource,
      barcode,
      autoPrefix,
      'scale_weight_item_code_len',
      'scale_weight_divider',
      5,
      1000.0,
    );
  }

  static Future<ScaleBarcodeResult?> _extractScaleProduct(
    ScaleBarcodeDataSource dataSource,
    String barcode,
    String prefix,
    String codeLenKey,
    String dividerKey,
    int defaultCodeLen,
    double defaultDivider, {
    bool isPriceMode = false,
  }) async {
    try {
      final codeLenStr = await dataSource.getSettingValue(codeLenKey);
      final dividerStr = await dataSource.getSettingValue(dividerKey);

      final codeLen = int.tryParse(codeLenStr ?? '') ?? defaultCodeLen;
      final divider = double.tryParse(dividerStr ?? '') ?? defaultDivider;

      final productCode = barcode.substring(
        prefix.length,
        prefix.length + codeLen,
      );
      final valueStr = barcode.substring(prefix.length + codeLen, 12);
      final value = double.tryParse(valueStr) ?? 0;
      final checkDigit = barcode[12];

      debugPrint(
        '[ScaleBarcode] Parsing: prefix=$prefix pluCode=$productCode '
        'rawValue=$valueStr checkDigit=$checkDigit',
      );
      debugPrint('[ScaleBarcode] Config:  codeLen=$codeLen divider=$divider');
      debugPrint('[ScaleBarcode] ═ Barcode breakdown ═');
      debugPrint(
        '[ScaleBarcode]   [$prefix][$productCode][$valueStr][$checkDigit]',
      );
      debugPrint('[ScaleBarcode]   prefix  PLU      value     check');

      // ═══ Product Lookup (prioritize scalePluNumber) ═══
      final pluInt = int.tryParse(productCode);
      final trimmedCode = productCode.replaceFirst(RegExp(r'^0+'), '');
      ProductEntity? product;

      // 1. Look up by scalePluNumber (exact PLU match)
      if (pluInt != null) {
        debugPrint('[ScaleBarcode] 1. Lookup by scalePluNumber: $pluInt');
        product = await dataSource.getProductByScalePlu(pluInt);
      }

      // 2. Fallback: try by internal code (exact)
      if (product == null) {
        debugPrint('[ScaleBarcode] 2. Lookup by code: "$productCode"');
        product = await dataSource.getProductByCode(productCode);
      }

      // 3. Fallback: try by code without leading zeros
      if (product == null && trimmedCode.isNotEmpty && trimmedCode != productCode) {
        debugPrint('[ScaleBarcode] 3. Lookup by trimmed code: "$trimmedCode"');
        product = await dataSource.getProductByCode(trimmedCode);
      }

      // 4. Fallback: try as barcode (exact PLU string)
      if (product == null) {
        debugPrint('[ScaleBarcode] 4. Lookup by barcode: "$productCode"');
        product = await dataSource.getProductByBarcode(productCode);
      }

      // 5. Fallback: try barcode without leading zeros
      if (product == null && trimmedCode.isNotEmpty && trimmedCode != productCode) {
        debugPrint('[ScaleBarcode] 5. Lookup by trimmed barcode: "$trimmedCode"');
        product = await dataSource.getProductByBarcode(trimmedCode);
      }

      if (product == null) {
        debugPrint(
          '[ScaleBarcode] ✗ NO PRODUCT FOUND for PLU "$productCode" (int: $pluInt)',
        );
        debugPrint('[ScaleBarcode] ✗ تأكد من إدخال رقم PLU ($pluInt) في إعدادات المنتج أو مطابقة كود الصنف');
        // P5 (Issue #1): Extra context to help diagnose codes starting with '2'.
        // If the PLU exceeds typical scale limits (e.g. 9999, 19999), the
        // upload likely was silently dropped on the device — see
        // label_scale_service.uploadToScaleRecord which now filters such
        // items and reports them in PLUUploadResult.errors.
        if (pluInt != null && pluInt > 9999) {
          debugPrint(
            '[ScaleBarcode] ⚠ PLU=$pluInt exceeds 9999 — many label scales '
            '(Aclas/Rongta/Digi older firmwares) cap PLU at 9999 and silently '
            'drop higher values during upload. Verify the scale\'s maxPlu in '
            'settings → label scales, and check the most-recent upload log '
            'for "تم تخطّى صنف" warnings.',
          );
        }
        return null;
      }

      double quantity;
      String displayText;

      if (isPriceMode) {
        final totalPrice = value / divider;
        quantity =
            totalPrice / (product.salePrice > 0 ? product.salePrice : 1.0);
        displayText = 'سعر ميزان: ${totalPrice.toStringAsFixed(AppConstants.decimalPlaces)}';
        debugPrint(
          '[ScaleBarcode] ✓ PRICE mode: totalPrice=$totalPrice qty=$quantity',
        );
      } else {
        quantity = value / divider;
        displayText = 'وزن ميزان: ${quantity.toStringAsFixed(3)} kg';
        debugPrint(
          '[ScaleBarcode] ✓ WEIGHT mode: weight=${quantity.toStringAsFixed(3)} kg',
        );
      }

      debugPrint(
        '[ScaleBarcode] ✓ Product: "${product.name}" (code=${product.code})',
      );
      debugPrint('[ScaleBarcode] ✓ Quantity: $quantity');
      debugPrint('[ScaleBarcode] ════════════════════════════════════');

      return ScaleBarcodeResult(
        product: product,
        quantity: quantity,
        displayText: displayText,
      );
    } catch (e, st) {
      debugPrint('[ScaleBarcode] ✗ Parse/lookup error: $e');
      debugPrint('[ScaleBarcode] ✗ Stack: $st');
      return null;
    }
  }

  /// Verify EAN-13 check digit (alternating weights 1/3, mod 10).
  static bool _verifyEan13CheckDigit(String barcode13) {
    if (barcode13.length != 13) return false;
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final d = barcode13.codeUnitAt(i) - 0x30; // '0'=0x30
      if (d < 0 || d > 9) return false;
      sum += d * (i.isEven ? 1 : 3);
    }
    final expected = (10 - (sum % 10)) % 10;
    final actual = barcode13.codeUnitAt(12) - 0x30;
    return expected == actual;
  }

  /// Convert raw string to hex representation for debugging
  static String _safeHex(String s) {
    final buf = StringBuffer();
    for (int i = 0; i < s.length && i < 30; i++) {
      final c = s.codeUnitAt(i);
      if (c >= 32 && c < 127) {
        buf.writeCharCode(c);
      } else {
        buf.write('\\x${c.toRadixString(16).padLeft(2, '0')}');
      }
    }
    if (s.length > 30) buf.write('...');
    return buf.toString();
  }
}