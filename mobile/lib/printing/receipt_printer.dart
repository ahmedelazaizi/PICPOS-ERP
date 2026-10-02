/// Printing contract — implementation is sub-phase I-4 (ARCHITECTURE-I §10):
/// Bluetooth SPP ESC/POS, 58 mm (384 dots) / 80 mm (576 dots), Arabic rendered
/// as a raster image (Noto Naskh Arabic), CODE128 invoice number, QR payload.
library;

enum PaperWidth { mm58, mm80 }

class ReceiptDocument {
  ReceiptDocument({required this.title, required this.number, required this.lines, required this.qrPayload});
  final String title;
  final String number;
  final List<(String label, String value)> lines;
  final String qrPayload;
}

abstract class ReceiptPrinter {
  Future<List<String>> discoverPrinters();
  Future<void> printReceipt(String printerAddress, ReceiptDocument doc, {PaperWidth width = PaperWidth.mm80});
}

/// Placeholder used until I-4; fails loudly so nothing silently "prints".
class UnimplementedReceiptPrinter implements ReceiptPrinter {
  @override
  Future<List<String>> discoverPrinters() async => const [];
  @override
  Future<void> printReceipt(String printerAddress, ReceiptDocument doc, {PaperWidth width = PaperWidth.mm80}) =>
      throw UnimplementedError('Bluetooth ESC/POS printing arrives in I-4');
}
