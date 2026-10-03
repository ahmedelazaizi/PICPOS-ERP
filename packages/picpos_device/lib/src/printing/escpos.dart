/// ESC/POS byte encoding for raster receipts (pure Dart), copied from
/// mobile/lib/printing/escpos.dart and extended with the cash-drawer kick.
/// Arabic is never sent as text — receipts are rasterized and sent with
/// `GS v 0` (most thermal printers lack a shaping Arabic code page).
library;

import 'dart:typed_data';

/// 1-bit image, rows packed MSB-first, 1 = black dot.
class MonoBitmap {
  MonoBitmap(this.width, this.height, this.data) : assert(data.length == ((width + 7) >> 3) * height);
  final int width;
  final int height;
  final Uint8List data;
  int get widthBytes => (width + 7) >> 3;

  bool isBlack(int x, int y) => (data[y * widthBytes + (x >> 3)] & (0x80 >> (x & 7))) != 0;
}

/// RGBA8888 → 1-bit. A pixel is black when its luminance, composited over
/// white, is below [threshold].
MonoBitmap monochrome(Uint8List rgba, int width, int height, {int threshold = 160}) {
  if (rgba.length < width * height * 4) throw ArgumentError('rgba buffer too small');
  final wb = (width + 7) >> 3;
  final out = Uint8List(wb * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final a = rgba[i + 3];
      final luma = (299 * rgba[i] + 587 * rgba[i + 1] + 114 * rgba[i + 2]) ~/ 1000;
      final lum = (luma * a + 255 * (255 - a)) ~/ 255;
      if (lum < threshold) out[y * wb + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  return MonoBitmap(width, height, out);
}

/// Cash-drawer connector pin of `ESC p`.
enum DrawerPin {
  /// Connector pin 2 (`m = 0`), the usual drawer port.
  pin2,

  /// Connector pin 5 (`m = 1`), second drawer on some printers.
  pin5,
}

abstract final class EscPos {
  /// ESC @ — initialize printer.
  static const List<int> init = [0x1B, 0x40];

  /// ESC d n — print and feed n lines.
  static List<int> feed(int lines) => [0x1B, 0x64, lines.clamp(0, 255)];

  /// GS V 66 0 — feed to cutter and partial cut.
  static const List<int> cut = [0x1D, 0x56, 0x42, 0x00];

  /// `ESC p m t1 t2` — drawer kick pulse: on for t1×2 ms, off for t2×2 ms.
  /// Default `ESC p 0 25 250` = `1B 70 00 19 FA` (ARCHITECTURE-M ADR-M5).
  static List<int> drawerKick({DrawerPin pin = DrawerPin.pin2, int onTime = 25, int offTime = 250}) {
    if (onTime < 0 || onTime > 255 || offTime < 0 || offTime > 255) {
      throw RangeError('drawer pulse times must be 0..255');
    }
    return [0x1B, 0x70, pin == DrawerPin.pin2 ? 0x00 : 0x01, onTime, offTime];
  }

  /// `GS v 0 m xL xH yL yH d1…dk` (m = 0), split in bands of at most
  /// [maxBandRows] rows for printers with small buffers.
  static List<int> raster(MonoBitmap bmp, {int maxBandRows = 256}) {
    final out = <int>[];
    final wb = bmp.widthBytes;
    for (var y0 = 0; y0 < bmp.height; y0 += maxBandRows) {
      final rows = (bmp.height - y0) < maxBandRows ? bmp.height - y0 : maxBandRows;
      out.addAll([0x1D, 0x76, 0x30, 0x00, wb & 0xFF, (wb >> 8) & 0xFF, rows & 0xFF, (rows >> 8) & 0xFF]);
      out.addAll(bmp.data.sublist(y0 * wb, (y0 + rows) * wb));
    }
    return out;
  }

  /// Full job: init, raster bands, feed, cut, then an optional drawer kick
  /// (after a cash payment when the desktop's drawer policy is on).
  static Uint8List job(MonoBitmap bmp, {int feedLines = 4, bool cut = true, int maxBandRows = 256, bool kickDrawer = false}) =>
      Uint8List.fromList([
        ...init,
        ...raster(bmp, maxBandRows: maxBandRows),
        ...feed(feedLines),
        if (cut) ...EscPos.cut,
        if (kickDrawer) ...drawerKick(),
      ]);

  /// Drawer only (manual open, `pos_open_drawer`).
  static Uint8List drawerJob() => Uint8List.fromList([...init, ...drawerKick()]);
}
