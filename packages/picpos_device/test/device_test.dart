import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/testing.dart';

class _FakePrinter implements PrinterTransport {
  _FakePrinter([this.kind = PrinterKind.bluetooth]);
  @override
  final PrinterKind kind;
  final List<(String, List<int>)> sent = [];
  PrinterException? failWith;

  @override
  Future<List<PrinterDevice>> pairedDevices() async => const [PrinterDevice('P58', 'AA:BB')];

  @override
  Future<void> send(String address, List<int> bytes) async {
    if (failWith != null) throw failWith!;
    sent.add((address, bytes));
  }
}

const _kick = [0x1B, 0x70, 0x00, 0x19, 0xFA];

void main() {
  group('ESC/POS', () {
    test('drawer kick is ESC p 0 25 250 = 1B 70 00 19 FA', () {
      expect(EscPos.drawerKick(), _kick);
      expect(EscPos.drawerKick(pin: DrawerPin.pin5, onTime: 50, offTime: 100), [0x1B, 0x70, 0x01, 0x32, 0x64]);
      expect(() => EscPos.drawerKick(onTime: 256), throwsRangeError);
      expect(EscPos.drawerJob(), [0x1B, 0x40, ..._kick]);
    });

    test('raster header: 58 mm = 384 dots = 48 bytes/row, 80 mm = 576 dots = 72 bytes/row', () {
      for (final (paper, xL) in [(PaperWidth.mm58, 48), (PaperWidth.mm80, 72)]) {
        expect(paper.widthBytes, xL);
        final bmp = MonoBitmap(paper.dots, 10, Uint8List(xL * 10));
        expect(EscPos.raster(bmp).sublist(0, 8), [0x1D, 0x76, 0x30, 0x00, xL, 0x00, 10, 0x00]);
      }
    });

    test('tall images are split in bands of ≤ 256 rows', () {
      final bmp = MonoBitmap(384, 300, Uint8List(48 * 300));
      final out = EscPos.raster(bmp);
      expect(out.length, 2 * 8 + 48 * 300);
      expect(out.sublist(0, 8), [0x1D, 0x76, 0x30, 0x00, 48, 0, 0x00, 0x01]); // 256 rows
      final second = 8 + 48 * 256;
      expect(out.sublist(second, second + 8), [0x1D, 0x76, 0x30, 0x00, 48, 0, 44, 0]);
    });

    test('job: init … feed, cut, optional drawer kick at the end', () {
      final bmp = MonoBitmap(8, 1, Uint8List(1));
      final plain = EscPos.job(bmp);
      expect(plain.sublist(0, 2), [0x1B, 0x40]);
      expect(plain.sublist(plain.length - 4), [0x1D, 0x56, 0x42, 0x00]);
      final kicked = EscPos.job(bmp, kickDrawer: true);
      expect(kicked.sublist(kicked.length - 5), _kick);
    });

    test('monochrome: dark → 1, light/transparent → 0, MSB first', () {
      final rgba = Uint8List.fromList([
        0, 0, 0, 255, // black
        255, 255, 255, 255, // white
        0, 0, 0, 0, // transparent = paper
      ]);
      final bmp = monochrome(rgba, 3, 1);
      expect(bmp.data, [0x80]);
      expect(bmp.isBlack(0, 0) && !bmp.isBlack(1, 0) && !bmp.isBlack(2, 0), isTrue);
    });
  });

  group('receipt rasterizer (Noto Naskh, real fonts)', () {
    setUpAll(loadPicPosFonts);

    testWidgets('58/80 mm receipts render at 384/576 dots', (tester) async {
      await tester.runAsync(() async {
        for (final (paper, xL) in [(PaperWidth.mm58, 48), (PaperWidth.mm80, 72)]) {
          final r = Receipt.testPage(paper);
          final img = await renderReceipt(r, paper);
          expect(img.width, paper.dots);
          img.dispose();
          final bytes = await rasterizeReceipt(r, paper, kickDrawer: true);
          expect(bytes.sublist(0, 6), [0x1B, 0x40, 0x1D, 0x76, 0x30, 0x00]);
          expect(bytes.sublist(6, 8), [xL, 0]);
          expect(bytes.sublist(bytes.length - 5), _kick);
          // The page is not blank: some dot is black.
          expect(bytes.sublist(12, bytes.length - 13).any((b) => b != 0), isTrue);
        }
      });
    });
  });

  group('outbox', () {
    late MemoryLocalStore store;
    late Outbox outbox;
    var t = DateTime.utc(2026, 2, 1, 10);
    setUp(() {
      store = MemoryLocalStore();
      t = DateTime.utc(2026, 2, 1, 10);
      outbox = Outbox(store, clock: () => t = t.add(const Duration(seconds: 1)));
    });

    test('enqueue is idempotent by globalId', () async {
      expect(await outbox.enqueue(globalId: 'g1', kind: 'sale', payload: {'n': 1}), isTrue);
      expect(await outbox.enqueue(globalId: 'g1', kind: 'sale', payload: {'n': 1}), isFalse);
      expect((await store.outbox()).length, 1);
    });

    test('drains in creation order; duplicate counts as accepted; rejected needs attention', () async {
      for (final id in ['a', 'b', 'c']) {
        await outbox.enqueue(globalId: id, kind: 'sale', payload: {});
      }
      final seen = <String>[];
      final r = await outbox.drain((e) async {
        seen.add(e.globalId);
        return switch (e.globalId) {
          'a' => const PushReply(PushOutcome.accepted),
          'b' => const PushReply(PushOutcome.duplicate),
          _ => const PushReply(PushOutcome.rejected, code: 'totals_mismatch'),
        };
      });
      expect(seen, ['a', 'b', 'c']);
      expect((r.accepted, r.rejected, r.complete), (2, 1, true));
      expect((await outbox.needsAttention()).single.error, 'totals_mismatch');
      expect(await outbox.pending(), isEmpty);
      expect(await outbox.isDrained(), isFalse); // a rejected doc blocks close-shift
    });

    test('lost response: transport failure stops the drain, retry uses the same key, server dedups', () async {
      await outbox.enqueue(globalId: 'a', kind: 'sale', payload: {});
      await outbox.enqueue(globalId: 'b', kind: 'sale', payload: {});
      // Fake server keyed by idempotency key; the first response for "a" is lost.
      final server = <String>{};
      var loseNext = true;
      Future<PushReply> send(OutboxEntry e) async {
        final dup = !server.add(e.globalId);
        if (loseNext) {
          loseNext = false;
          throw const SocketException('connection reset');
        }
        return PushReply(dup ? PushOutcome.duplicate : PushOutcome.accepted);
      }

      final first = await outbox.drain(send);
      expect(first.complete, isFalse);
      expect(server, {'a'}); // "b" was not sent out of order
      expect((await store.outboxEntry('a'))!.attempts, 1);

      final second = await outbox.drain(send);
      expect((second.accepted, second.complete), (2, true));
      expect(server, {'a', 'b'}); // each document exists once on the server
      expect((await store.outboxEntry('a'))!.attempts, 2);
      expect(await outbox.isDrained(), isTrue);
    });

    test('a concurrent drain does not send an entry twice', () async {
      await outbox.enqueue(globalId: 'a', kind: 'sale', payload: {});
      final gate = Completer<void>();
      var calls = 0;
      Future<PushReply> send(OutboxEntry e) async {
        calls++;
        await gate.future;
        return const PushReply(PushOutcome.accepted);
      }

      final f1 = outbox.drain(send);
      final r2 = await outbox.drain(send);
      gate.complete();
      await f1;
      expect((calls, r2.accepted), (1, 0));
    });

    test('backoff grows ×3 from 5 s with the LAN cap of 5 min', () {
      const b = Backoff.lan;
      expect(b.delay(1), const Duration(seconds: 5));
      expect(b.delay(2), const Duration(seconds: 15));
      expect(b.delay(5), const Duration(minutes: 5)); // 405 s capped
      expect(b.delay(1, 0).inMilliseconds, 4000);
      expect(b.delay(9, 0.999) <= const Duration(minutes: 5), isTrue);
    });
  });

  group('network printer (TCP 9100)', () {
    test('parses addresses', () {
      expect(NetworkPrinterTransport.parseAddress('192.168.1.50'), ('192.168.1.50', 9100));
      expect(NetworkPrinterTransport.parseAddress(' 10.0.0.9:9101 '), ('10.0.0.9', 9101));
      expect(NetworkPrinterTransport.parseAddress('[fe80::1]:9100'), ('fe80::1', 9100));
      for (final bad in ['', ':9100', 'h:0', 'h:70000', 'a:b:c']) {
        expect(() => NetworkPrinterTransport.parseAddress(bad), throwsA(isA<PrinterException>()), reason: bad);
      }
    });

    test('sends the bytes to a raw socket server', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final received = <int>[];
      final done = Completer<void>();
      server.listen((s) => s.listen(received.addAll, onDone: () {
            s.destroy();
            done.complete();
          }));
      final payload = [0x1B, 0x40, ...List.generate(10000, (i) => i & 0xFF), ..._kick];
      await NetworkPrinterTransport().send('127.0.0.1:${server.port}', payload);
      await done.future.timeout(const Duration(seconds: 5));
      await server.close();
      expect(received, payload);
    });

    test('closed port → connectFailed', () async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close();
      await expectLater(NetworkPrinterTransport().send('127.0.0.1:$port', [1]),
          throwsA(isA<PrinterException>().having((e) => e.code, 'code', 'connectFailed')));
    });
  });

  group('print service', () {
    late MemoryLocalStore store;
    late _FakePrinter bt;
    late _FakePrinter net;
    late PrintService svc;
    Future<Uint8List> build(PaperWidth p) async => Uint8List.fromList([p.widthBytes]);

    setUp(() async {
      store = MemoryLocalStore();
      bt = _FakePrinter();
      net = _FakePrinter(PrinterKind.network);
      svc = PrintService(store: store, transports: [bt, net]);
      await svc.init();
    });

    test('no printer → queued, never throws', () async {
      final o = await svc.print('inv-1', 'CAI-T01-000001', build);
      expect((o.status, o.error), (PrintStatus.queued, 'noPrinter'));
      expect(svc.queue.single.id, 'inv-1');
    });

    test('routes by printer kind, persists settings and queue, retries', () async {
      await svc.saveSettings(const PrinterSettings(kind: PrinterKind.network, address: '192.168.1.50', paper: PaperWidth.mm58));
      net.failWith = PrinterException('connectFailed');
      await svc.print('inv-1', 'N1', build);
      await svc.print('inv-1', 'N1', build);
      expect(svc.queue.single.attempts, 2);

      final reloaded = PrintService(store: store, transports: [bt, net]);
      await reloaded.init();
      expect(reloaded.settings.kind, PrinterKind.network);
      expect(reloaded.queue.single.lastError, 'connectFailed');

      net.failWith = null;
      expect(await reloaded.retryQueue((id) => build), 1);
      expect(reloaded.queue, isEmpty);
      expect(net.sent.single.$1, '192.168.1.50');
      expect(net.sent.single.$2, [48]);
      expect(bt.sent, isEmpty);
    });

    test('retry drops jobs whose document is gone', () async {
      await svc.print('gone', 'X', build);
      expect(await svc.retryQueue((id) => null), 0);
      expect(svc.queue, isEmpty);
    });

    test('open drawer sends ESC @ + ESC p 0 25 250', () async {
      await svc.saveSettings(const PrinterSettings(address: 'AA:BB'));
      await svc.openDrawer();
      expect(bt.sent.single.$2, [0x1B, 0x40, ..._kick]);
      bt.failWith = PrinterException('bluetoothOff');
      await expectLater(svc.openDrawer(), throwsA(isA<PrinterException>()));
    });
  });

  group('scanner input', () {
    test('normalizes wedge suffixes and AIM prefixes via picpos_rules', () {
      expect(normalizeScan(']E06291234567890\r\n'), '6291234567890');
      expect(normalizeScan('  ABC-1 \t'), 'ABC-1');
    });

    test('fast burst + Enter is a scan; slow typing is not', () {
      final w = KeyboardWedgeBuffer();
      var t = DateTime(2026);
      String? feed(String s, int gapMs) {
        String? out;
        for (final ch in s.split('')) {
          t = t.add(Duration(milliseconds: gapMs));
          out = w.add(ch, t);
        }
        return out;
      }

      expect(feed('6291234567890\n', 10), '6291234567890');
      expect(feed('123\n', 300), isNull);
      expect(feed('12\n', 10), isNull); // too short
    });
  });

  group('store and key', () {
    test('database key: 64 hex chars, created once', () async {
      final secrets = MemorySecretStore();
      final k = DatabaseKey(secrets, storageKey: 'picpos_pos.db_key.v1', random: Random(1));
      final a = await k.obtain();
      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(await DatabaseKey(secrets, storageKey: 'picpos_pos.db_key.v1').obtain(), a);
      expect(secrets.values.keys, ['picpos_pos.db_key.v1']);
    });

    test('memory store copies entries in and out; clear wipes', () async {
      final s = MemoryLocalStore();
      await s.addOutbox(OutboxEntry(globalId: 'g', kind: 'sale', payload: {}, createdAt: DateTime(2026)));
      final e = (await s.outbox()).single..attempts = 9;
      expect((await s.outboxEntry('g'))!.attempts, 0);
      await s.updateOutbox(e);
      expect((await s.outboxEntry('g'))!.attempts, 9);
      await s.upsert('products', [
        {'globalId': 'p1', 'name': 'شاي'},
        {'globalId': 'p2', 'name': 'سكر'},
      ]);
      await s.retainOnly('products', {'p2'});
      expect((await s.all('products')).single['name'], 'سكر');
      await s.setKv('k', 'v');
      await s.clear();
      expect(await s.getKv('k'), isNull);
      expect(await s.outbox(), isEmpty);
    });

    test('outbox row round-trip', () {
      final e = OutboxEntry(
          globalId: 'g', kind: 'sale', payload: {'total': '2.500'}, createdAt: DateTime.utc(2026), status: OutboxStatus.rejected, error: 'x');
      final back = OutboxEntry.fromRow(e.toRow());
      expect((back.globalId, back.status, back.error), ('g', OutboxStatus.rejected, 'x'));
      expect(back.payload, {'total': '2.500'});
    });
  });
}
