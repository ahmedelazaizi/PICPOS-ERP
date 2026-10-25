import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';

import 'label_builder.dart';

/// Why a label did not reach paper, in the app's own terms.
enum LabelPrintStatus { printed, noPrinter, queued }

class LabelPrintResult {
  const LabelPrintResult(this.status, [this.error]);
  final LabelPrintStatus status;

  /// `PrinterException.code` when [status] is queued (bluetoothOff, ...).
  final String? error;
}

/// Printing port of the app. The label is rendered by [buildLabelReceipt]
/// (transport independent); a port only decides where the bytes go.
/// A failed print NEVER touches stock or documents.
abstract class LabelPrinter {
  /// True once a printer (Bluetooth or network) is chosen in Settings.
  bool get hasPrinter;
  String? get printerName;
  Future<LabelPrintResult> printLabel(WhLabelData label, {int copies = 1, String locale = 'ar'});
}

/// Honest default: nothing is connected, and it says so.
class NoPrinter implements LabelPrinter {
  const NoPrinter();
  @override
  bool get hasPrinter => false;
  @override
  String? get printerName => null;
  @override
  Future<LabelPrintResult> printLabel(WhLabelData label, {int copies = 1, String locale = 'ar'}) async =>
      const LabelPrintResult(LabelPrintStatus.noPrinter);
}

/// ESC/POS over `PrintService` (Bluetooth SPP or network raw TCP, 58/80 mm).
class ServiceLabelPrinter implements LabelPrinter {
  ServiceLabelPrinter(this.service, {ReceiptRasterizer? rasterizer}) : _raster = rasterizer ?? rasterizeReceipt;
  final PrintService service;
  final ReceiptRasterizer _raster;

  @override
  bool get hasPrinter => service.settings.hasPrinter;
  @override
  String? get printerName => service.settings.name ?? service.settings.address;

  @override
  Future<LabelPrintResult> printLabel(WhLabelData label, {int copies = 1, String locale = 'ar'}) async {
    if (!hasPrinter) return const LabelPrintResult(LabelPrintStatus.noPrinter);
    final receipt = buildLabelReceipt(label, copies: copies, locale: locale);
    final out = await service.print(
      'label-${label.kind}-${label.barcode}',
      label.title,
      (paper) => _raster(receipt, paper),
    );
    return out.status == PrintStatus.printed
        ? const LabelPrintResult(LabelPrintStatus.printed)
        : LabelPrintResult(LabelPrintStatus.queued, out.error);
  }
}
