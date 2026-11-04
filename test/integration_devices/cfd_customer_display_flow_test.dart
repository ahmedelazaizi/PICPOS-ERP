// Integration review 2026-11-04: the customer-facing display (CFD) chain.
//
//   cart (CartState) -> CfdService.broadcastCart -> CfdNetworkTransport (SSE
//   events) -> GET /api/cfd/stream -> the page served at GET /cfd.
//
// The first two tests pin the in-process half (what the display receives).
// The HTTP half is exercised against the REAL LAN pipeline; the two skipped
// tests are the defects found by this review (run with --run-skipped).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';
import 'package:picpos_erp/services/cfd/cfd_transport.dart';
import 'package:picpos_erp/services/cfd_service.dart';

import '../helpers/lan_host_harness.dart';

Map<String, dynamic> _decodeEvent(String event) {
  expect(event, startsWith('data: '));
  expect(event, endsWith('\n\n'));
  return jsonDecode(event.substring(6).trim()) as Map<String, dynamic>;
}

void main() {
  final cfd = CfdService.instance;

  const cart = CartState(
    items: [
      CartItemEntity(
        productId: 1,
        productName: 'قهوة',
        productCode: 'C1',
        quantity: 2,
        unitPrice: 15,
      ),
    ],
    selectedCustomerName: 'أحمد',
  );

  test('every connected display receives the cart as one SSE event, then the '
      'idle screen when the cart empties', () async {
    final screenA = StreamIterator(cfd.connect());
    final screenB = StreamIterator(cfd.connect());
    addTearDown(() async {
      await screenA.cancel();
      await screenB.cancel();
    });

    cfd.broadcastCart(cart);
    for (final screen in [screenA, screenB]) {
      expect(await screen.moveNext(), isTrue);
      final json = _decodeEvent(screen.current);
      final items = (json['items'] as List).cast<Map<String, dynamic>>();
      expect(items.single['name'], 'قهوة');
      expect(items.single['qty'], 2);
      expect(json['total'], 30);
      expect(json['customer'], 'أحمد');
    }

    cfd.broadcastIdle();
    expect(await screenA.moveNext(), isTrue);
    final idle = _decodeEvent(screenA.current);
    expect(idle['type'], 'idle');
    expect(idle['welcomeMessage'], cfd.displayConfig.welcomeMessage);
  });

  test('fields hidden in the display settings never leave the till', () async {
    final transport = cfd.networkTransport;
    final screen = StreamIterator(transport.connectClient());
    addTearDown(screen.cancel);

    transport.sendCartUpdate(
      const CfdCartData(
        items: [CfdCartItem(name: 'شاي', quantity: 1, price: 5, total: 5)],
        subtotal: 5,
        discountPercent: 0,
        taxAmount: 0.8,
        total: 5.8,
        customerName: 'سري',
      ),
      const CfdDisplayConfig(
        showItemPrice: false,
        showTax: false,
        showCustomerName: false,
      ),
    );
    expect(await screen.moveNext(), isTrue);
    final json = _decodeEvent(screen.current);
    expect((json['items'] as List).single, {
      'name': 'شاي',
      'qty': 1,
      'total': 5,
    });
    expect(json.containsKey('tax'), isFalse);
    expect(json.containsKey('customer'), isFalse);
    expect(json['total'], 5.8);
  });

  // INT-08 was reported from reading only. Measured: a single-subscription
  // StreamController completes `done` when its listener cancels, so the
  // transport already drops the client — this pins that behaviour.
  test('INT-08: a display that disconnects (cancels its stream) is dropped '
      'from the transport client list', () async {
    final transport = cfd.networkTransport;
    final before = transport.clientCount;
    final sub = transport.connectClient().listen((_) {});
    expect(transport.clientCount, before + 1);
    await sub.cancel();
    await pumpEventQueue();
    expect(transport.clientCount, before);
  });

  group('over the LAN server', () {
    late LanHost host;

    setUp(() async {
      host = await LanHost.start();
    });
    tearDown(() => host.close());

    test(
      'GET /cfd serves the display page without any credential, and the page '
      'subscribes to /api/cfd/stream',
      () async {
        final r = await host.direct('GET', '/cfd', const {}, null);
        expect(r.status, 200);
        expect(r.body, contains("new EventSource('/api/cfd/stream')"));
      },
    );

    test(
      'the display page can open its event stream without a device bearer '
      '(a browser EventSource cannot send one)',
      () async {
        // Fixed INT-01 (was 401): the exact GET feed of the public display page.
        // `host.direct` reads the body to its end, and a working SSE stream
        // never ends — so the status is read from the shelf response and the
        // stream is then cancelled, as a closing browser tab does.
        final res = await host.handler(
          shelf.Request('GET', Uri.parse('http://lan.test/api/cfd/stream')),
        );
        expect(res.statusCode, 200);
        await res.read().listen((_) {}).cancel();
      },
    );

    test(
      'INT-01 boundary: only the two exact GET feeds are public; their '
      'neighbours, other methods and a wrong bearer stay protected',
      () async {
        final menu = await host.direct('GET', '/api/menu', const {}, null);
        expect(menu.status, 200, reason: '$menu');
        expect(menu.json.containsKey('products'), isTrue);
        for (final (method, path) in const [
          ('POST', '/api/menu'),
          ('POST', '/api/cfd/stream'),
          ('GET', '/api/menu/admin'),
          ('GET', '/api/cfd/data'),
          ('GET', '/api/cfd/stream/x'),
          ('GET', '/api/menus'),
          ('GET', '/api/products'),
        ]) {
          final r = await host.direct(method, path, const {}, null);
          expect(r.status, 401, reason: '$method $path -> $r');
        }
        // A request that DOES carry a bearer is authenticated as before.
        final forged = await host.direct('GET', '/api/menu', const {
          'authorization': 'Bearer not-a-device-token',
          'x-device-id': 'nobody',
        }, null);
        expect(forged.status, 403, reason: '$forged');
      },
    );

    test(
      'a client that holds the stream receives the cart event as bytes',
      () async {
        final offer = await host.issue(kind: 'client', branchId: 1);
        final dev = LanDevice(host.direct, 'cfd-tablet');
        expect((await dev.pair(offer.code)).status, 200);
        final res = await host.handler(
          shelf.Request(
            'GET',
            Uri.parse('http://lan.test/api/cfd/stream'),
            headers: dev.headers(),
          ),
        );
        expect(res.statusCode, 200);
        final first = res.read().first;
        cfd.broadcastCart(cart);
        final bytes = await first.timeout(const Duration(seconds: 5));
        // Fixed INT-02 (was a String/List<int> TypeError): UTF-8 SSE bytes.
        expect(utf8.decode(bytes), startsWith('data: '));
        expect(res.headers['content-type'], startsWith('text/event-stream'));
        expect(res.headers['cache-control'], 'no-cache');
      },
    );

    test(
      'INT-02 over a real socket: a browser-like client with no credential '
      'receives the cart event while the stream stays open (not buffered)',
      () async {
        final base = await host.serve();
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final displays = cfd.networkTransport.clientCount;
        // The response head leaves with the first event (the stream has no
        // body before it), so the sale happens while the request is open.
        final pending = client
            .getUrl(Uri.parse('$base/api/cfd/stream'))
            .then((req) => req.close());
        while (cfd.networkTransport.clientCount == displays) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        cfd.broadcastCart(cart);
        final res = await pending.timeout(const Duration(seconds: 5));
        expect(res.statusCode, 200);
        expect(res.headers.contentType?.mimeType, 'text/event-stream');
        final event = await res
            .transform(utf8.decoder)
            .first
            .timeout(const Duration(seconds: 5));
        expect(_decodeEvent(event)['customer'], 'أحمد');
      },
    );
  });
}
