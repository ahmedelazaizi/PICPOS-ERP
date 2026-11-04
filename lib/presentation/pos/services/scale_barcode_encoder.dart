/// Encodes the same fixed-width scale payload consumed by ScaleBarcodeHandler.
/// EAN-13 payload layout: prefix + PLU + scaled integer value + check digit.
enum ScaleBarcodeValueKind { weight, price }

class ScaleBarcodeEncoder {
  const ScaleBarcodeEncoder._();

  static String encode({
    required String plu,
    required double value,
    required ScaleBarcodeValueKind kind,
    String? prefix,
    int codeLength = 5,
    double? divider,
  }) {
    final resolvedPrefix =
        prefix ?? (kind == ScaleBarcodeValueKind.weight ? '21' : '20');
    final resolvedDivider =
        divider ?? (kind == ScaleBarcodeValueKind.weight ? 1000.0 : 100.0);
    if (resolvedPrefix.isEmpty ||
        !resolvedPrefix.startsWith('2') ||
        !RegExp(r'^\d+$').hasMatch(resolvedPrefix) ||
        resolvedPrefix.length > 12) {
      throw ArgumentError.value(resolvedPrefix, 'prefix', 'Must be numeric');
    }
    if (codeLength < 1 || codeLength > 12 - resolvedPrefix.length) {
      throw ArgumentError.value(
        codeLength,
        'codeLength',
        'Invalid EAN-13 layout',
      );
    }
    if (!RegExp(r'^\d+$').hasMatch(plu) || plu.length > codeLength) {
      throw ArgumentError.value(plu, 'plu', 'PLU exceeds configured digits');
    }
    if (!value.isFinite ||
        value <= 0 ||
        !resolvedDivider.isFinite ||
        resolvedDivider <= 0) {
      throw ArgumentError.value(
        value,
        'value',
        'Value and divider must be positive and finite',
      );
    }

    final valueLength = 12 - resolvedPrefix.length - codeLength;
    if (valueLength < 1) {
      throw ArgumentError('Scale profile leaves no digits for its value');
    }
    final scaledValue = value * resolvedDivider;
    final scaled = scaledValue.round();
    if ((scaledValue - scaled).abs() > 0.000001) {
      throw ArgumentError.value(
        value,
        'value',
        'Value precision exceeds the scale profile',
      );
    }
    final maxValue = _pow10(valueLength);
    if (scaled < 1 || scaled >= maxValue) {
      throw RangeError('Scaled value $scaled does not fit $valueLength digits');
    }
    final data =
        '$resolvedPrefix${plu.padLeft(codeLength, '0')}${scaled.toString().padLeft(valueLength, '0')}';
    final check = _checkDigit(data);
    return '$data$check';
  }

  static int _pow10(int n) {
    var result = 1;
    for (var i = 0; i < n; i++) {
      result *= 10;
    }
    return result;
  }

  static int _checkDigit(String data12) {
    if (data12.length != 12 || !RegExp(r'^\d{12}$').hasMatch(data12)) {
      throw ArgumentError.value(data12, 'data12', 'Expected 12 digits');
    }
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(data12[i]) * (i.isEven ? 1 : 3);
    }
    return (10 - sum % 10) % 10;
  }
}
