// Contract test against the running docker TEST stack (docker/README.md).
// Skipped unless CLOUD_URL is set, e.g.  $env:CLOUD_URL='http://localhost:18080'; flutter test test/live_cloud_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:picpos_van/data/cloud_api.dart';
import 'package:picpos_van/data/local_store.dart';
import 'package:picpos_van/domain/sale_math.dart';
import 'package:picpos_van/state/app_controller.dart';

void main() {
  final base = Platform.environment['CLOUD_URL'];

  test('pair → login → bootstrap → offline sale + collection → sync accepted', () async {
    final codeRes = await http.post(Uri.parse('$base/admin/pairing-codes'),
        headers: {'x-admin-key': Platform.environment['CLOUD_ADMIN_KEY'] ?? 'test-admin-key'},
        body: jsonEncode({
          'companyGlobalId': '00000000-0000-4000-8000-000000000001',
          'employeeGlobalId': '00000000-0000-4000-8000-0000000000a1',
        }));
    expect(codeRes.statusCode, 201, reason: codeRes.body);
    final code = (jsonDecode(codeRes.body) as Map)['code'] as String;

    final c = AppController(store: MemoryLocalStore(), api: HttpCloudApi());
    await c.init();
    await c.pair(base!, code);
    await c.login('1234');
    expect(c.lastSyncError, isNull);
    final customers = await c.routeCustomers();
    expect(customers, isNotEmpty);
    final cust = customers.firstWhere((x) => x['globalId'] == '00000000-0000-4000-8000-0000000000c2');
    final water = (await c.products()).firstWhere((p) => p['barcode'] == '6251234567890');

    final sale = await c.createSale(
      customerGlobalId: cust['globalId'] as String,
      lines: [CartLine(productGlobalId: water['globalId'] as String, name: 'w', unitPrice: 2.5, taxRate: c.taxRateOf(water))],
      paid: 0,
    );
    final book = (await c.voucherBooks()).first;
    final col = await c.createCollection(
        customerGlobalId: cust['globalId'] as String, amount: 1, book: book, leaf: (await c.suggestLeaf(book))!);
    await c.syncNow();
    expect(c.lastSyncError, isNull);
    final ob = {for (final e in await c.store.outbox()) e.globalId: e};
    expect(ob[sale.globalId]!.status, OutboxStatus.accepted, reason: ob[sale.globalId]!.error);
    expect(ob[col.globalId]!.status, OutboxStatus.accepted, reason: ob[col.globalId]!.error);

    // I-2: the accepted invoice comes back as returnable; return it and record visits.
    expect((await c.returnableInvoices(cust['globalId'] as String)).map((i) => i['globalId']),
        contains(sale.globalId));
    final ret = await c.createReturn(
        invoiceGlobalId: sale.globalId, quantities: {water['globalId'] as String: 1}, reason: 'damaged');
    final v1 = await c.createVisit(customerGlobalId: cust['globalId'] as String, outcome: 'visited');
    final v2 = await c.createVisit(
        customerGlobalId: '00000000-0000-4000-8000-0000000000c1', outcome: 'no_sale', noSaleReason: 'closed');
    await c.syncNow();
    expect(c.lastSyncError, isNull);
    final ob2 = {for (final e in await c.store.outbox()) e.globalId: e};
    for (final e in [ret, v1, v2]) {
      expect(ob2[e.globalId]!.status, OutboxStatus.accepted, reason: '${e.kind}: ${ob2[e.globalId]!.error}');
    }
  }, skip: base == null ? 'CLOUD_URL not set' : false);
}
