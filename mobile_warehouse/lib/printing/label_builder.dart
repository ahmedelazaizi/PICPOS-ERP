import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';

/// Transport-independent label: a [Receipt] of blocks (name, code, Code128,
/// and a QR for bins so a phone camera can read it too). The same document
/// is rasterised to ESC/POS for 58 / 80 mm thermal printers; no ZPL/TSPL in
/// release 1 (plan E-10). [copies] repeats the label on one job.
Receipt buildLabelReceipt(WhLabelData label, {int copies = 1, String locale = 'ar'}) {
  final n = copies.clamp(1, 50);
  final blocks = <ReceiptBlock>[
    for (var i = 0; i < n; i++) ...[
      ReceiptText(label.title, size: ReceiptTextSize.large, bold: true),
      if (label.subtitle.isNotEmpty) ReceiptText(label.subtitle, size: ReceiptTextSize.small),
      ReceiptBarcode(label.barcode),
      if (label.kind == 'location') ReceiptQrCode(label.barcode),
      if (i < n - 1) const ReceiptDivider() else const ReceiptFeed(2),
    ],
  ];
  return Receipt(kind: 'label_${label.kind}', number: label.barcode, blocks: blocks, locale: locale);
}
