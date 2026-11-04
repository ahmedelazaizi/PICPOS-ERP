/// وحداتُ قضبان EAN-13 (95 وحدة: `true` = قضيب أسود) لمعاينة الشاشة.
///
/// الورقُ يرسمه `pw.BarcodeWidget` (حزمة pdf)؛ الشاشةُ لا تملك رسّام باركود
/// (‏`label_template_preview.dart` يرسم عنصراً نائباً). هذه الجداول هي
/// المعيار GS1 نفسه، فما يُرى على الشاشة يُقرأ بالماسح كما يُقرأ المطبوع.
/// نقيّ: لا Flutter.
library;

const _l = [
  '0001101', '0011001', '0010011', '0111101', '0100011',
  '0110001', '0101111', '0111011', '0110111', '0001011',
];
const _g = [
  '0100111', '0110011', '0011011', '0100001', '0011101',
  '0111001', '0000101', '0010001', '0001001', '0010111',
];
const _parity = [
  'LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG',
  'LGGLLG', 'LGGGLL', 'LGLGLG', 'LGLGGL', 'LGGLGL',
];

String _invert(String bits) =>
    bits.split('').map((b) => b == '0' ? '1' : '0').join();

/// `null` لنصٍّ ليس 13 رقماً.
List<bool>? ean13Modules(String code) {
  if (!RegExp(r'^\d{13}$').hasMatch(code)) return null;
  final d = [for (final c in code.split('')) int.parse(c)];
  final buf = StringBuffer('101');
  final parity = _parity[d[0]];
  for (var i = 0; i < 6; i++) {
    buf.write(parity[i] == 'L' ? _l[d[i + 1]] : _g[d[i + 1]]);
  }
  buf.write('01010');
  for (var i = 7; i < 13; i++) {
    buf.write(_invert(_l[d[i]]));
  }
  buf.write('101');
  return [for (final c in buf.toString().split('')) c == '1'];
}
