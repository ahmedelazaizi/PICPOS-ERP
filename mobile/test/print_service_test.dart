import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_van/domain/sale_math.dart' show CartLine;
import 'package:picpos_van/printing/print_service.dart';
import 'package:picpos_van/printing/printer_transport.dart';
import 'package:picpos_van/printing/receipt_model.dart';

import 'support/fakes.dart';

/// Printer fake: fails with [failWith], hangs when [hang], else records bytes.
class FakePrinter implements PrinterTransport {
  String? failWith;
  bool hang = false;
  final List<(String, List<int>)> sent = [];

  @override
  Future<List<PrinterDevice>> pairedDevices() async => const [PrinterDevice('MPT-II', '00:11:22:33:44:55')];

  @override
  Future<void> send(String address, List<int> bytes) async {
    if (hang) return Completer<void>().future;
    if (failWith != null) throw PrinterException(failWith!);
    sent.add((address, bytes));
  }
}

final rendered = <(String, PaperWidth)>[];
Future<Uint8List> fakeRaster(Receipt r, PaperWidth w) async {
  rendered.add((r.number, w));
  return Uint8List.fromList([0x1B, 0x40]);
}

CartLine water(double q) => CartLine(productGlobalId: 'p1', name: 'water', unitPrice: 2.5, taxRate: 16, quantity: q);

void main() {
  setUp(rendered.clear);

  Future<(PrintService, FakePrinter)> service({bool printer = true, Duration timeout = const Duration(seconds: 5)}) async {
    final (c, _) = await readyController();
    final fp = FakePrinter();
    final ps = PrintService(controller: c, transport: fp, rasterizer: fakeRaster, timeout: timeout);
    await ps.init();
    ps.attach();
    if (printer) {
      await ps.saveSettings(const PrinterSettings(address: '00:11:22:33:44:55', name: 'MPT-II', paper: PaperWidth.mm58));
    }
    return (ps, fp);
  }

  test('print on save prints with the remembered printer and paper width', () async {
    final (ps, fp) = await service();
    final outcomes = <PrintOutcome>[];
    ps.onOutcome = outcomes.add;
    await ps.controller.createSale(customerGlobalId: 'c2', lines: [water(1)], paid: 2.9);
    await pumpEventQueue();
    expect(fp.sent.single.$1, '00:11:22:33:44:55');
    expect(rendered.single, ('VS-100000', PaperWidth.mm58));
    expect(outcomes.single.status, PrintStatus.printed);
    expect(ps.queue, isEmpty);
  });

  test('offline printer: the sale is saved, the print is queued with the reason, retry prints it', () async {
    final (ps, fp) = await service();
    fp.failWith = 'connectFailed';
    final outcomes = <PrintOutcome>[];
    ps.onOutcome = outcomes.add;
    final sale = await ps.controller.createSale(customerGlobalId: 'c2', lines: [water(1)], paid: 2.9);
    await pumpEventQueue();
    expect((await ps.controller.pendingDocs()).single.globalId, sale.globalId, reason: 'sale never blocked');
    expect(outcomes.single.status, PrintStatus.queued);
    expect(outcomes.single.error, 'connectFailed');
    expect(ps.queue.single.number, 'VS-100000');

    // A second failed attempt raises the count instead of duplicating.
    expect((await ps.retryQueue()), 0);
    expect(ps.queue.single.attempts, 2);

    // The queue survives a restart (persisted in the device store).
    final again = PrintService(controller: ps.controller, transport: fp, rasterizer: fakeRaster);
    await again.init();
    expect(again.queue.single.globalId, sale.globalId);
    expect(again.settings.paper, PaperWidth.mm58);

    fp.failWith = null;
    expect(await again.retryQueue(), 1);
    expect(again.queue, isEmpty);
    expect(fp.sent, hasLength(1));
  });

  test('a hanging printer never blocks the sale; the job times out into the queue', () async {
    final (ps, fp) = await service(timeout: const Duration(milliseconds: 50));
    fp.hang = true;
    final sale = await ps.controller
        .createSale(customerGlobalId: 'c2', lines: [water(1)], paid: 2.9)
        .timeout(const Duration(seconds: 1));
    expect(sale.payload['number'], 'VS-100000');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(ps.queue.single.lastError, 'timeout');
  });

  test('no printer chosen → queued as noPrinter; print-on-save off → nothing; visits never print', () async {
    final (ps, fp) = await service(printer: false);
    await ps.controller.createSale(customerGlobalId: 'c2', lines: [water(1)], paid: 2.9);
    await pumpEventQueue();
    expect(ps.queue.single.lastError, 'noPrinter');

    await ps.saveSettings(ps.settings.copyWith(address: 'AA', printOnSave: false));
    await ps.controller.createSale(customerGlobalId: 'c2', lines: [water(1)], paid: 2.9);
    await ps.controller.createVisit(customerGlobalId: 'c1', outcome: 'visited');
    await pumpEventQueue();
    expect(ps.queue, hasLength(1));
    expect(fp.sent, isEmpty);
  });

  test('reprint from history; history lists printable documents newest first', () async {
    final (ps, fp) = await service();
    await ps.saveSettings(ps.settings.copyWith(printOnSave: false));
    final c = ps.controller;
    await c.createSale(customerGlobalId: 'c2', lines: [water(1)], paid: 2.9);
    await c.createCollection(customerGlobalId: 'c1', amount: 10, book: (await c.voucherBooks()).single, leaf: 1003);
    await c.createVisit(customerGlobalId: 'c1', outcome: 'visited');
    final h = await ps.history();
    expect(h.map(PrintService.numberOf), ['R-1003', 'VS-100000']);
    final out = await ps.printEntry(h.last, reprint: true);
    expect(out.status, PrintStatus.printed);
    expect(fp.sent, hasLength(1));
  });

  test('accepted push stores the cloud signature for reprints', () async {
    final (ps, _) = await service();
    final c = ps.controller;
    final sale = await c.createSale(customerGlobalId: 'c2', lines: [water(1)], paid: 2.9);
    await c.applyPushResults([sale], [
      {'globalId': sale.globalId, 'status': 'accepted', 'integrityHash': 'v2:abcdef0123456789'},
    ]);
    expect(sale.payload['_integrityHash'], 'v2:abcdef0123456789');
  });
}
