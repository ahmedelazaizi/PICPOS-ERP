/// Barcode normalization shared by the device (scanner input) and the cloud
/// (product barcodes pushed by the desktop), so a scanned code and a stored
/// code compare equal.
library;

final _control = RegExp(r'[\x00-\x1F\x7F]');
final _aimPrefix = RegExp(r'^\][A-Za-z][0-9A-Za-z]');

/// Cleans what a scanner delivered: keyboard-wedge (HID) scanners may add a
/// CR/LF/TAB suffix or an AIM/GS1 symbology prefix (`]C1`, `]E0`, …) and
/// group separators; camera reads may carry whitespace.
String normalizeBarcode(String raw) {
  var s = raw.replaceAll(_control, '').trim();
  if (_aimPrefix.hasMatch(s)) s = s.substring(3);
  return s;
}
