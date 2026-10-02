import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_van/app.dart';
import 'package:picpos_van/data/db_key.dart';
import 'package:picpos_van/data/local_store.dart';
import 'package:picpos_van/domain/sale_math.dart';
import 'package:picpos_van/screens/barcode_scanner.dart';
import 'package:picpos_van/screens/sale_screen.dart';
import 'package:picpos_van/state/app_controller.dart';

import 'support/fakes.dart';

class MapSecrets implements SecretStore {
  final m = <String, String>{};
  @override
  Future<String?> read(String key) async => m[key];
  @override
  Future<void> write(String key, String value) async => m[key] = value;
  @override
  Future<void> delete(String key) async => m.remove(key);
}

Future<void> openSale(WidgetTester tester, CameraScan camera) async {
  final (c, _) = await readyController();
  await tester.pumpWidget(PicposVanApp(controller: c));
  await tester.pumpAndSettle();
  tester.state<NavigatorState>(find.byType(Navigator)).push(MaterialPageRoute<void>(
        builder: (_) => SaleScreen(customerGlobalId: 'c2', cameraScan: camera),
      ));
  await tester.pumpAndSettle();
}

void main() {
  group('scanner input', () {
    test('normalizeBarcode strips wedge suffixes, control chars and AIM prefixes', () {
      expect(normalizeBarcode('6251234567890\n'), '6251234567890');
      expect(normalizeBarcode(' 6251234567890\r\n'), '6251234567890');
      expect(normalizeBarcode('6251234567890\t'), '6251234567890');
      expect(normalizeBarcode(']E06251234567890'), '6251234567890');
      expect(normalizeBarcode(']C1\x1d0106251234567890'), '0106251234567890');
      expect(normalizeBarcode('\n'), '');
    });

    testWidgets('keyboard-wedge scan (with CR suffix) adds the product', (tester) async {
      await openSale(tester, (_) async => null);
      await tester.enterText(find.byKey(const Key('barcode')), '6251234567890\r');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('مياه ٦ لتر'), findsOneWidget);
      expect(find.text('2.90'), findsWidgets);
    });

    testWidgets('camera scan result goes through the same lookup; unknown code warns', (tester) async {
      var next = '6250000000017';
      await openSale(tester, (_) async => next);
      await tester.tap(find.byKey(const Key('cameraScan')));
      await tester.pumpAndSettle();
      expect(find.text('خبز'), findsOneWidget);
      next = '999';
      await tester.tap(find.byKey(const Key('cameraScan')));
      await tester.pumpAndSettle();
      expect(find.text('لا يوجد صنف بهذا الباركود'), findsOneWidget);
    });
  });

  group('pricing on the device (same rules as the server gate)', () {
    test('price-list quantity tier, wholesale level, override permission', () async {
      final (c, _) = await readyController();
      final bread = (await c.product('p2'))!;
      final water = (await c.product('p1'))!;
      expect((await c.unitPriceFor(bread, 'c2', 9)).price, 1.0);
      final tier = await c.unitPriceFor(bread, 'c2', 10);
      expect((tier.price, tier.source, tier.listGlobalId), (0.9, 'price_list', 'pl1'));
      CartLine line(String p, double price, double q) =>
          CartLine(productGlobalId: p, name: p, unitPrice: price, taxRate: 0, quantity: q);
      await expectLater(() => c.createSale(customerGlobalId: 'c2', lines: [line('p2', 1, 10)], paid: 10),
          throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'priceNotAllowed')));
      final ok = await c.createSale(customerGlobalId: 'c2', lines: [line('p2', 0.9, 10)], paid: 9);
      expect(ok.payload['total'], 9.0);

      await c.store.upsert(Kinds.customers, [
        {...(await c.store.get(Kinds.customers, 'c2'))!, 'priceLevel': 'wholesale'},
      ]);
      expect((await c.unitPriceFor(water, 'c2', 1)).price, 2.2);

      await c.applyServerPayload({'employee': {'name': 'x', 'canOverridePrice': true}});
      await c.createSale(customerGlobalId: 'c2', lines: [line('p1', 2.0, 1)], paid: 0);
    });

    test('tax-inclusive company: tax extracted, total = price × qty (server example)', () async {
      final (c, _) = await readyController();
      await c.applyServerPayload({
        'company': {'defaultTaxRate': 16.0, 'pricesIncludeTax': true, 'decimalPlaces': 2},
      });
      final lines = [
        CartLine(productGlobalId: 'p1', name: 'w', unitPrice: 2.5, taxRate: 16, quantity: 2),
        CartLine(productGlobalId: 'p2', name: 'b', unitPrice: 1, taxRate: 0),
      ];
      final t = c.totalsOf(lines);
      expect((t.net, t.tax, t.total), (5.31, 0.69, 6.0));
      final e = await c.createSale(customerGlobalId: 'c2', lines: lines, paid: 6);
      expect(e.payload['total'], 6.0);
    });
  });

  group('database key (Android Keystore via flutter_secure_storage)', () {
    test('256-bit key created once, then reused; malformed value replaced', () async {
      final secrets = MapSecrets();
      final k1 = await DatabaseKey(secrets, random: Random(1)).obtain();
      expect(k1, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(await DatabaseKey(secrets, random: Random(2)).obtain(), k1);
      secrets.m[DatabaseKey.storageKey] = 'short';
      expect(await DatabaseKey(secrets, random: Random(3)).obtain(), isNot(anyOf('short', k1)));
    });
  });
}
