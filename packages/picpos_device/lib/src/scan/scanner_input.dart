/// Scanner input: keyboard-wedge (HID) scanners "type" the code quickly and
/// end it with Enter/Tab; this buffer tells a scan from human typing by the
/// gap between characters and normalizes the result with `picpos_rules`
/// (the same normalization the cloud applies to stored barcodes).
library;

import 'package:picpos_rules/picpos_rules.dart';

/// Normalizes a camera or wedge read (CR/LF/TAB, AIM prefixes, spaces).
String normalizeScan(String raw) => normalizeBarcode(raw);

class KeyboardWedgeBuffer {
  KeyboardWedgeBuffer({this.maxGap = const Duration(milliseconds: 60), this.minLength = 3});

  /// Larger gaps between characters mean a human is typing: the buffer
  /// restarts from that character.
  final Duration maxGap;
  final int minLength;

  final StringBuffer _buf = StringBuffer();
  DateTime? _last;

  /// Feeds one key; returns the normalized code when a terminator (Enter,
  /// Tab) ends a fast burst of at least [minLength] characters.
  String? add(String char, DateTime at) {
    final last = _last;
    _last = at;
    if (char == '\n' || char == '\r' || char == '\t') {
      final code = normalizeScan(_buf.toString());
      _buf.clear();
      final burst = last != null && at.difference(last) <= maxGap;
      return burst && code.length >= minLength ? code : null;
    }
    if (last != null && at.difference(last) > maxGap) _buf.clear();
    _buf.write(char);
    return null;
  }

  void reset() {
    _buf.clear();
    _last = null;
  }
}
