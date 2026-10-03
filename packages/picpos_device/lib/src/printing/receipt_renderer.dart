/// Rasterizes a [Receipt] with Flutter's text engine (full Arabic shaping
/// and bidi, Noto Naskh Arabic — the desktop print font) onto a canvas of
/// exactly the paper's dot width, then encodes it for ESC/POS (`GS v 0`).
/// Copied from mobile/lib/printing/receipt_renderer.dart; the font family is
/// a parameter (default: the copy bundled by `picpos_ui`).
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/painting.dart';

import 'escpos.dart';
import 'receipt.dart';

/// `PicPosFonts.print` of picpos_ui (kept as a string so this package does
/// not depend on the UI kit).
const kReceiptFontFamily = 'packages/picpos_ui/NotoNaskhArabic';

/// Receipt → printer bytes. Injected into print services (tests use fakes).
typedef ReceiptRasterizer = Future<Uint8List> Function(Receipt receipt, PaperWidth width);

Future<Uint8List> rasterizeReceipt(Receipt receipt, PaperWidth width,
    {bool kickDrawer = false, String fontFamily = kReceiptFontFamily}) async {
  final image = await renderReceipt(receipt, width, fontFamily: fontFamily);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bmp = monochrome(bytes!.buffer.asUint8List(), image.width, image.height);
    return EscPos.job(bmp, kickDrawer: kickDrawer);
  } finally {
    image.dispose();
  }
}

class _Metrics {
  _Metrics(PaperWidth w)
      : margin = w == PaperWidth.mm58 ? 6 : 10,
        small = w == PaperWidth.mm58 ? 17 : 21,
        normal = w == PaperWidth.mm58 ? 21 : 25,
        large = w == PaperWidth.mm58 ? 28 : 34,
        qr = w == PaperWidth.mm58 ? 200 : 260,
        barcodeHeight = w == PaperWidth.mm58 ? 56 : 72;
  final double margin, small, normal, large, qr, barcodeHeight;
}

Future<ui.Image> renderReceipt(Receipt receipt, PaperWidth width, {String fontFamily = kReceiptFontFamily}) async {
  final w = width.dots.toDouble();
  final m = _Metrics(width);
  final dir = receipt.rtl ? TextDirection.rtl : TextDirection.ltr;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final black = Paint()..color = const Color(0xFF000000);
  canvas.drawRect(Rect.fromLTWH(0, 0, w, 100000), Paint()..color = const Color(0xFFFFFFFF)); // paper
  final inner = w - 2 * m.margin;
  var y = 4.0;

  TextPainter tp(String text, double size, {bool bold = false, TextAlign align = TextAlign.start, double? maxW}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          height: 1.25,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: const Color(0xFF000000),
        ),
      ),
      textAlign: align,
      textDirection: dir,
    )..layout(maxWidth: maxW ?? inner);
  }

  double startX(double textWidth) => receipt.rtl ? w - m.margin - textWidth : m.margin;
  double endX(double textWidth) => receipt.rtl ? m.margin : w - m.margin - textWidth;

  void paintBars(Iterable<BarcodeElement> els, double ox, double oy) {
    for (final e in els) {
      if (e is BarcodeBar && e.black) {
        canvas.drawRect(
            Rect.fromLTWH(ox + e.left.roundToDouble(), oy + e.top.roundToDouble(), e.width.roundToDouble(),
                e.height.roundToDouble()),
            black);
      }
    }
  }

  for (final b in receipt.blocks) {
    switch (b) {
      case ReceiptText(:final text, :final align, :final size, :final bold):
        final s = switch (size) {
          ReceiptTextSize.small => m.small,
          ReceiptTextSize.normal => m.normal,
          ReceiptTextSize.large => m.large,
        };
        final ta = switch (align) {
          ReceiptAlign.start => TextAlign.start,
          ReceiptAlign.center => TextAlign.center,
          ReceiptAlign.end => TextAlign.end,
        };
        final box = tp(text, s, bold: bold, align: ta)..layout(minWidth: inner, maxWidth: inner);
        box.paint(canvas, Offset(m.margin, y));
        y += box.height;
      case ReceiptRow(:final label, :final value, :final bold, :final large):
        final s = large ? m.large : m.normal;
        final lp = tp(label, s, bold: bold, maxW: inner * 0.55);
        final vp = tp(value, s, bold: bold || large, maxW: inner);
        if (lp.width + vp.width + 12 <= inner) {
          final h = math.max(lp.height, vp.height);
          lp.paint(canvas, Offset(startX(lp.width), y));
          vp.paint(canvas, Offset(endX(vp.width), y + (h - vp.height)));
          y += h;
        } else {
          lp.paint(canvas, Offset(startX(lp.width), y));
          y += lp.height;
          vp.paint(canvas, Offset(endX(vp.width), y));
          y += vp.height;
        }
      case ReceiptItem(:final name, :final detail, :final total):
        final np = tp(name, m.normal, bold: true);
        np.paint(canvas, Offset(startX(np.width), y));
        y += np.height;
        final dp = tp(detail, m.small);
        final totp = tp(total, m.normal);
        final h = math.max(dp.height, totp.height);
        dp.paint(canvas, Offset(startX(dp.width), y + (h - dp.height)));
        totp.paint(canvas, Offset(endX(totp.width), y));
        y += h + 2;
      case ReceiptDivider(:final thick):
        y += 6;
        if (thick) {
          canvas.drawRect(Rect.fromLTWH(m.margin, y, inner, 3), black);
        } else {
          for (var x = m.margin; x < w - m.margin; x += 10) {
            canvas.drawRect(Rect.fromLTWH(x, y, 6, 2), black);
          }
        }
        y += 8;
      case ReceiptBarcode(:final data):
        final bc = Barcode.code128();
        if (!bc.isValid(data)) break;
        // Snap to whole dots per module so bars stay crisp on 203 dpi.
        const probe = 10000.0;
        final probeEls = bc.make(data, width: probe, height: 1).whereType<BarcodeBar>();
        final minBar = probeEls.map((e) => e.width).reduce(math.min);
        final modules = (probe / minBar).round();
        final dots = math.max(1, (inner / modules).floor());
        final bw = (modules * dots).toDouble();
        y += 6;
        paintBars(bc.make(data, width: bw, height: m.barcodeHeight), (w - bw) / 2, y);
        y += m.barcodeHeight + 2;
        final tpn = tp(data, m.small, align: TextAlign.center)..layout(minWidth: inner, maxWidth: inner);
        tpn.paint(canvas, Offset(m.margin, y));
        y += tpn.height;
      case ReceiptQrCode(:final payload, :final caption):
        final qr = Barcode.qrCode(errorCorrectLevel: BarcodeQRCorrectionLevel.medium);
        const probe = 1000.0;
        final els = qr.make(payload, width: probe, height: probe).whereType<BarcodeBar>().toList();
        final minBar = els.map((e) => e.width).reduce(math.min);
        final modules = (probe / minBar).round();
        final dots = math.max(2, (m.qr / modules).floor());
        final size = (modules * dots).toDouble();
        y += 8;
        paintBars(qr.make(payload, width: size, height: size), (w - size) / 2, y);
        y += size + 4;
        if (caption.isNotEmpty) {
          final cp = tp(caption, m.small, align: TextAlign.center)..layout(minWidth: inner, maxWidth: inner);
          cp.paint(canvas, Offset(m.margin, y));
          y += cp.height;
        }
      case ReceiptFeed(:final lines):
        y += lines * m.normal * 0.6;
    }
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width.dots, y.ceil() + 4);
  } finally {
    picture.dispose();
  }
}
