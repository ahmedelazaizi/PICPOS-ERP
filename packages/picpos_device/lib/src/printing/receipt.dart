/// Receipt layout model (pure Dart): what is printed, in order, independent
/// of how it is rasterized. Block types copied from
/// mobile/lib/printing/receipt_model.dart; the document builders (sale,
/// return, Z report) are written per app in M-5.
library;

/// Thermal paper: printable width in dots at 203 dpi and characters per
/// line of font A (reference only; text is rasterized).
enum PaperWidth {
  mm58(384, 32),
  mm80(576, 48);

  const PaperWidth(this.dots, this.chars);
  final int dots;
  final int chars;

  /// Raster bytes per row (`xL`/`xH` of `GS v 0`): 48 for 58 mm, 72 for 80 mm.
  int get widthBytes => (dots + 7) >> 3;

  static PaperWidth byName(String? n) => n == 'mm58' ? mm58 : mm80;
}

enum ReceiptAlign { start, center, end }

enum ReceiptTextSize { small, normal, large }

sealed class ReceiptBlock {
  const ReceiptBlock();
}

class ReceiptText extends ReceiptBlock {
  const ReceiptText(this.text, {this.align = ReceiptAlign.center, this.size = ReceiptTextSize.normal, this.bold = false});
  final String text;
  final ReceiptAlign align;
  final ReceiptTextSize size;
  final bool bold;
}

/// Label at the reading start, value at the other end.
class ReceiptRow extends ReceiptBlock {
  const ReceiptRow(this.label, this.value, {this.bold = false, this.large = false});
  final String label;
  final String value;
  final bool bold;
  final bool large;
}

/// One line: name, then `qty × price` and the line total.
class ReceiptItem extends ReceiptBlock {
  const ReceiptItem(this.name, this.detail, this.total);
  final String name;
  final String detail;
  final String total;
}

class ReceiptDivider extends ReceiptBlock {
  const ReceiptDivider({this.thick = false});
  final bool thick;
}

class ReceiptQrCode extends ReceiptBlock {
  const ReceiptQrCode(this.payload, {this.caption = ''});
  final String payload;
  final String caption;
}

/// CODE128 of [data] with the human-readable value under it.
class ReceiptBarcode extends ReceiptBlock {
  const ReceiptBarcode(this.data);
  final String data;
}

class ReceiptFeed extends ReceiptBlock {
  const ReceiptFeed([this.lines = 1]);
  final int lines;
}

class Receipt {
  Receipt({required this.kind, required this.number, required this.blocks, this.locale = 'ar'});

  /// e.g. `sales_invoice` | `sales_return` | `z_report` | `test`.
  final String kind;
  final String number;
  final List<ReceiptBlock> blocks;
  final String locale;
  bool get rtl => locale != 'en';

  /// Printer test page (setup screen).
  factory Receipt.testPage(PaperWidth width, {String locale = 'ar', String? title}) {
    final ar = locale != 'en';
    final mm = width == PaperWidth.mm58 ? 58 : 80;
    return Receipt(kind: 'test', number: 'TEST', locale: locale, blocks: [
      ReceiptText(title ?? 'PicPos', size: ReceiptTextSize.large, bold: true),
      ReceiptText(ar ? 'صفحة اختبار الطابعة' : 'Printer test page'),
      ReceiptText(ar ? 'عرض الورق $mm مم' : 'Paper $mm mm'),
      const ReceiptDivider(),
      ReceiptRow(ar ? 'الإجمالي' : 'Total', '1,250.500', bold: true),
      const ReceiptDivider(thick: true),
      const ReceiptFeed(),
    ]);
  }
}
