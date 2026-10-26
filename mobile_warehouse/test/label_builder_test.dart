import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_warehouse/printing/label_builder.dart';
import 'package:picpos_warehouse/printing/label_printer.dart';

const _item = WhLabelData(kind: 'item', barcode: '6221234567890', title: 'Milk 1L', subtitle: 'P-1');
const _bin = WhLabelData(kind: 'location', barcode: 'BIN-1-A03', title: 'A-03-2', subtitle: '');

void main() {
  test('an item label carries name, code and a Code128 of the barcode; a bin label adds a QR', () {
    final item = buildLabelReceipt(_item);
    expect(item.blocks.whereType<ReceiptBarcode>().single.data, '6221234567890');
    expect(item.blocks.whereType<ReceiptQrCode>(), isEmpty);
    expect(item.blocks.whereType<ReceiptText>().map((b) => b.text), containsAll(['Milk 1L', 'P-1']));

    final bin = buildLabelReceipt(_bin);
    expect(bin.blocks.whereType<ReceiptBarcode>().single.data, 'BIN-1-A03');
    expect(bin.blocks.whereType<ReceiptQrCode>().single.payload, 'BIN-1-A03');
  });

  test('copies repeat the label inside one job and are bounded', () {
    expect(buildLabelReceipt(_item, copies: 3).blocks.whereType<ReceiptBarcode>(), hasLength(3));
    expect(buildLabelReceipt(_item, copies: 0).blocks.whereType<ReceiptBarcode>(), hasLength(1));
    expect(buildLabelReceipt(_item, copies: 999).blocks.whereType<ReceiptBarcode>(), hasLength(50));
  });

  test('the barcode string is valid Code128 (the rasteriser silently skips an invalid one)', () {
    // Digits and BIN- codes are plain ASCII; a quick structural check that nothing is dropped.
    for (final l in [_item, _bin]) {
      expect(l.barcode.codeUnits.every((c) => c >= 32 && c < 127), isTrue);
      // ...and the builder emits exactly that string (nothing dropped or altered)
      expect(buildLabelReceipt(l).blocks.whereType<ReceiptBarcode>().single.data, l.barcode);
    }
  });

  test('with no printer the port says noPrinter and never reaches a transport', () async {
    expect(await const NoPrinter().printLabel(_item), isA<LabelPrintResult>().having((r) => r.status, 'status', LabelPrintStatus.noPrinter));
  });

  test('ServiceLabelPrinter: no printer chosen -> noPrinter; a failing transport queues, never throws', () async {
    final svc = PrintService(store: MemoryLocalStore(), transports: [_FailingTransport()]);
    final port = ServiceLabelPrinter(svc, rasterizer: (r, w) async => Uint8List.fromList([1, 2, 3]));
    expect((await port.printLabel(_item)).status, LabelPrintStatus.noPrinter);

    await svc.saveSettings(const PrinterSettings(address: 'AA:BB', name: 'P1'));
    expect(port.hasPrinter, isTrue);
    final r = await port.printLabel(_item);
    expect(r.status, LabelPrintStatus.queued);
    expect(r.error, 'bluetoothOff');
    expect(svc.queue, hasLength(1), reason: 'kept for a later retry');
  });

  test('ServiceLabelPrinter sends the rasterised bytes to the chosen address', () async {
    final t = _RecordingTransport();
    final svc = PrintService(store: MemoryLocalStore(), transports: [t]);
    await svc.saveSettings(const PrinterSettings(address: 'AA:BB', name: 'P1'));
    final port = ServiceLabelPrinter(svc, rasterizer: (r, w) async => Uint8List.fromList([9, 9]));
    expect((await port.printLabel(_bin, copies: 2)).status, LabelPrintStatus.printed);
    expect(t.sent.single.$1, 'AA:BB');
    expect(t.sent.single.$2.toList(), [9, 9]);
  });
}

class _FailingTransport implements PrinterTransport {
  @override
  PrinterKind get kind => PrinterKind.bluetooth;
  @override
  Future<List<PrinterDevice>> pairedDevices() async => const [];
  @override
  Future<void> send(String address, List<int> bytes) async => throw PrinterException('bluetoothOff');
}

class _RecordingTransport implements PrinterTransport {
  final sent = <(String, List<int>)>[];
  @override
  PrinterKind get kind => PrinterKind.bluetooth;
  @override
  Future<List<PrinterDevice>> pairedDevices() async => const [PrinterDevice('P1', 'AA:BB')];
  @override
  Future<void> send(String address, List<int> bytes) async => sent.add((address, bytes));
}
