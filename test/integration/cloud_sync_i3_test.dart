// I-3 — desktop ↔ cloud sync.
//
// Proves, against a fake cloud speaking the `/desktop/*` contract
// (server/lib/src/service/desktop_service.dart):
//  * a field sale / return / collection posted from the cloud produces the
//    same journal entries, stock, safe movements, invoice (number, totals,
//    integrity hash, rep/route stamp) and voucher-book leaf as the same
//    documents entered on the desktop (golden comparison, two databases);
//  * re-pull is idempotent (a lost ack is re-acknowledged, never re-posted);
//  * refused documents become visible conflicts with a reason and retry;
//  * the master-data push carries what the van needs (route customers with
//    balances, products/tax, routes, rep resources, books, van stock).
//
// With CLOUD_URL set (docker test stack, `docker compose up` in docker/), the
// `live cloud` group runs the same flow against the real API: desktop push →
// mobile bootstrap sees it → mobile pushes → desktop posts.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/mappers/product_mapper.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/data/repositories/returns_repository_impl.dart';
import 'package:picpos_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';
import 'package:picpos_erp/services/cloud_sync/cloud_document_poster.dart';
import 'package:picpos_erp/services/cloud_sync/cloud_link_api.dart';
import 'package:picpos_erp/services/cloud_sync/cloud_sync_service.dart';
import 'package:picpos_erp/services/invoice_integrity_service.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

void main() {
  setUp(() => SyncInterceptor.instance = null);
  tearDown(() => SyncInterceptor.instance = null);

  group('fake cloud', () {
    test(
        'field docs post like desktop docs, re-pull is idempotent, conflicts '
        'are kept with a reason, master push carries the van scope', () async {
      final a = await _Fx.seed();
      final cloud = _FakeCloud();
      final sync = a.service(cloud.client);

      // 1. First run: nothing pending, full master push.
      final first = await sync.runOnce();
      expect(first.ok, isTrue, reason: first.error);
      final m = cloud.lastMaster!;
      // J3 — the system cash customer rides every push (every route).
      final cash = (m['parties'] as List).cast<Map>().where((p) => p['systemRole'] != null);
      expect(cash.single['systemRole'], 'cash_customer');
      final party =
          (m['parties'] as List).cast<Map>().where((p) => p['systemRole'] == null).single;
      expect(party['name'], 'Cust A');
      expect(party['balance'], 0.0);
      expect(party['creditLimit'], 500.0);
      final products = {
        for (final p in (m['products'] as List).cast<Map>()) p['name']: p,
      };
      expect(products['Water']!['taxRate'], 16.0);
      expect(products['Bread']!['taxExempt'], isTrue);
      final rep = (m['employees'] as List).single as Map;
      final route = (m['salesRoutes'] as List).single as Map;
      expect(route['salesRepGlobalId'], rep['globalId']);
      expect(route['visitDays'], 'mon,wed');
      final rc = (m['routeCustomers'] as List).single as Map;
      expect(rc['customerGlobalId'], party['globalId']);
      final rr = (m['repResources'] as List).single as Map;
      final van = (m['warehouses'] as List).single as Map;
      final safe = (m['safes'] as List).single as Map;
      expect(rr['vanWarehouseGlobalId'], van['globalId']);
      expect(rr['custodySafeGlobalId'], safe['globalId']);
      final book = (m['voucherBooks'] as List).single as Map;
      expect(book['holderEmployeeGlobalId'], rep['globalId']);
      expect(_stock(m, products['Water']!['globalId']), 50.0);
      expect(_stock(m, products['Bread']!['globalId']), 20.0);

      // 2. Field documents accepted by the cloud.
      final ids = _Ids(party['globalId'], rep['globalId'], route['globalId'],
          van['globalId'], safe['globalId'], book['globalId'],
          products['Water']!['globalId'], products['Bread']!['globalId']);
      final sale = ids.sale('VS-100000', paid: 5);
      final collection = ids.collection(3, leaf: 7);
      final visit = ids.visit();
      final ret = ids.ret('VR-100000', sale['globalId'] as String);
      final unknownProduct = ids.sale('VS-100001')
        ..['lines'] = [
          {'productGlobalId': _uuid.v4(), 'quantity': 1, 'unitPrice': 1},
        ];
      final mismatch = ids.sale('VS-100002')..['total'] = 99.0;
      final orphanReturn = ids.ret('VR-100001', mismatch['globalId'] as String);
      cloud.pending.addAll([
        sale, collection, visit, ret, unknownProduct, mismatch, orphanReturn,
      ]);

      cloud.dropAcks = true; // the ack response is lost
      final r1 = await sync.runOnce();
      expect(r1.ok, isTrue, reason: r1.error);
      expect(r1.posted, 4);
      expect(r1.conflicts, 3);

      // 3. Re-pull: nothing is posted twice, posted docs are re-acked.
      cloud.dropAcks = false;
      final invoicesBefore = await a.db.select(a.db.salesInvoices).get();
      final jeBefore = await a.db.select(a.db.journalEntries).get();
      final r2 = await sync.runOnce();
      expect(r2.posted, 0);
      expect(r2.reAcked, 4);
      expect(r2.skippedConflicts, 3);
      expect(await a.db.select(a.db.salesInvoices).get(), hasLength(invoicesBefore.length));
      expect(await a.db.select(a.db.journalEntries).get(), hasLength(jeBefore.length));
      expect(cloud.postedAcks.keys,
          containsAll([sale['globalId'], collection['globalId'], visit['globalId'], ret['globalId']]));
      final r3 = await sync.runOnce();
      expect(r3.reAcked, 0, reason: 'the cloud no longer lists posted docs');

      // 4. Conflicts: visible, with reason, acknowledged as failed, retryable.
      final conflicts = {
        for (final c in await a.db.listCloudSyncConflicts()) c.globalId: c,
      };
      expect(conflicts.keys.toSet(),
          {unknownProduct['globalId'], mismatch['globalId'], orphanReturn['globalId']});
      expect(conflicts[unknownProduct['globalId']]!.reason, startsWith('product_not_found'));
      expect(conflicts[mismatch['globalId']]!.reason, startsWith('totals_mismatch'));
      expect(conflicts[orphanReturn['globalId']]!.reason,
          startsWith('original_invoice_not_posted'));
      expect(cloud.failedAcks[mismatch['globalId']], startsWith('totals_mismatch'));
      expect(invoicesBefore.where((i) => i.platformOrderNumber == 'VS-100002'), isEmpty,
          reason: 'a refused document writes nothing');
      await a.db.requestCloudSyncRetry(unknownProduct['globalId'] as String);
      final r4 = await sync.runOnce();
      expect(r4.conflicts, 1);
      expect((await a.db.cloudSyncDocument(unknownProduct['globalId'] as String))!.attempts, 2);
      expect((await a.db.cloudSyncCounts()), (posted: 4, conflicts: 3));

      // 5. Posted invoice: cloud identity, field rep/route stamp, integrity.
      final inv = await (a.db.select(a.db.salesInvoices)
            ..where((s) => s.globalId.equals(sale['globalId'] as String)))
          .getSingle();
      expect(inv.platformOrderNumber, 'VS-100000');
      expect(inv.warehouseId, a.vanId);
      final stamp = await a.db.getDocumentRepStamp('sales_invoices', inv.id);
      expect(stamp.repEmployeeId, a.repId);
      expect(stamp.routeId, isNotNull);
      expect(
          inv.integrityHash,
          InvoiceIntegrityService.computeSalesInvoiceHash(
            invoiceNumber: inv.invoiceNumber,
            invoiceDate: inv.invoiceDate,
            total: inv.total,
            subtotal: inv.subtotal,
            discount: inv.discount,
            tax: inv.tax,
            paid: inv.paid,
            customerId: inv.customerId,
            userId: inv.userId,
            paymentMethod: inv.paymentMethod,
          ));
      final visits = await a.db.select(a.db.routeVisits).get();
      expect(visits.single.status, 'skipped');
      expect(visits.single.notes, contains('no_sale: closed'));

      // 6. Balances and van stock flow back up after posting.
      final m2 = cloud.lastMaster!;
      final p2 =
          (m2['parties'] as List).cast<Map>().where((p) => p['systemRole'] == null).single;
      expect(p2['balance'], closeTo(12.6 - 5 - 2.9 - 3, 1e-9));
      expect(_stock(m2, ids.water), 47.0);
      expect(_stock(m2, ids.bread), 19.0);

      // 7. Golden: the same documents entered on the desktop, same order.
      final b = await _Fx.seed();
      await b.db.openShift(b.userId, 0);
      final bInvoice = await b.enterSale(paid: 5);
      await b.enterCollection(3, leaf: 7);
      await b.enterReturn(bInvoice);
      await _expectSameBooks(a, b);
    });
  });

  group('tax-inclusive van sale regression', () {
    setUp(() => AppConstants.setCurrency('EGP'));
    tearDown(() => AppConstants.setCurrency('JOD'));

    for (final paid in [40.0, 0.0]) {
      test('inclusive ${paid == 0 ? 'credit' : 'cash'} sale keeps tax inside 40', () async {
        final fixture = await _Fx.seed();
        addTearDown(fixture.db.close);
        await fixture.db.setSetting('prices_include_tax', 'true');
        if (paid > 0) await fixture.db.openShift(fixture.userId, 0);
        final invoice = await _postTaxSale(fixture, paid: paid, inclusive: true);
        await _expectTaxSale(fixture, invoice, total: 40, tax: 5.52,
            revenue: 34.48, paid: paid);
      });
    }

    test('inclusive line and invoice discounts with delivery reconcile', () async {
      final fixture = await _Fx.seed();
      addTearDown(fixture.db.close);
      await fixture.db.setSetting('prices_include_tax', 'true');
      final invoice = await _postTaxSale(fixture, paid: 0, inclusive: true,
          lineDiscountPercent: 10, invoiceDiscountPercent: 10, deliveryFee: 2);
      await _expectTaxSale(fixture, invoice, total: 34.40, tax: 4.47,
          revenue: 27.93, paid: 0, deliveryFee: 2, discount: 7.60);
    });

    test('exclusive prices retain tax-on-top total', () async {
      final fixture = await _Fx.seed();
      addTearDown(fixture.db.close);
      final invoice = await _postTaxSale(fixture, paid: 0, inclusive: false);
      await _expectTaxSale(fixture, invoice, total: 46.40, tax: 6.40,
          revenue: 40, paid: 0);
    });

    test('cloud van tax-inclusive invoice posts without totals_mismatch', () async {
      final fixture = await _Fx.seed();
      addTearDown(fixture.db.close);
      await fixture.db.setSetting('prices_include_tax', 'true');
      final master = _FakeCloud();
      final sync = fixture.service(master.client);
      expect((await sync.runOnce()).ok, isTrue);
      final scope = master.lastMaster!;
      Object? gid(String table, [String? name]) =>
          (scope[table] as List).cast<Map>().firstWhere(
              (row) => name == null || row['name'] == name)['globalId'];
      final ids = _Ids(gid('parties', 'Cust A'), gid('employees'),
          gid('salesRoutes'), gid('warehouses', 'Van A'), gid('safes', 'Custody A'),
          gid('voucherBooks'), gid('products', 'Water'), gid('products', 'Bread'));
      final doc = ids.sale('VS-100003')
        ..['subtotal'] = 40.0
        ..['tax'] = 5.52
        ..['total'] = 40.0
        ..['lines'] = [
          {'productGlobalId': ids.water, 'quantity': 8, 'unitPrice': 5.0,
            'discount': 0, 'taxRate': 16, 'taxAmount': 5.52, 'total': 40.0},
        ];
      final posted = await CloudDocumentPoster(fixture.db, fixture.accounting,
          postingUserId: fixture.userId).post(doc);
      final invoice = await (fixture.db.select(fixture.db.salesInvoices)
            ..where((s) => s.id.equals(int.parse(posted.desktopRef)))).getSingle();
      await _expectTaxSale(fixture, invoice, total: 40, tax: 5.52,
          revenue: 34.48, paid: 0);
    });
  });

  group('live cloud (CLOUD_URL)', () {
    final url = Platform.environment['CLOUD_URL'];
    test('desktop push → mobile bootstrap → mobile push → desktop posts', () async {
      final adminKey = Platform.environment['CLOUD_ADMIN_KEY'] ?? 'test-admin-key';
      final company = Platform.environment['CLOUD_COMPANY_GID'] ??
          '00000000-0000-4000-8000-000000000001';
      final client = http.Client();
      addTearDown(client.close);
      Future<Map<String, dynamic>> call(String method, String path,
          {Map<String, String> headers = const {}, Object? body}) async {
        final req = http.Request(method, Uri.parse('$url$path'))
          ..headers.addAll({'content-type': 'application/json', ...headers});
        if (body != null) req.body = jsonEncode(body);
        final res = await http.Response.fromStream(await client.send(req));
        final json = (jsonDecode(res.body) as Map).cast<String, dynamic>();
        expect(res.statusCode, inInclusiveRange(200, 201), reason: '$path → $json');
        return json;
      }

      final link = await call('POST', '/admin/desktop-links',
          headers: {'x-admin-key': adminKey}, body: {'companyGlobalId': company, 'name': 'I-3 test'});
      final a = await _Fx.seed();
      final api = CloudLinkApi(
          CloudLinkCredentials(baseUrl: url!, linkId: link['linkId'], secret: link['linkSecret']),
          client: client);
      final sync = CloudSyncService(
          db: a.db, api: api, accounting: a.accounting, postingUserId: a.userId);
      final first = await sync.runOnce(fullPush: true);
      expect(first.ok, isTrue, reason: first.error);
      expect(first.masterSkipped, isEmpty);

      // Mobile: pair via the desktop link, bootstrap sees the desktop data.
      final repGid = (await (a.db.select(a.db.employees)).getSingle()).globalId!;
      final pairing = await api.pairingCode(repGid, pin: '2468');
      final deviceId = _uuid.v4();
      final pair = await call('POST', '/mobile/pair',
          body: {'code': pairing['code'], 'deviceId': deviceId, 'deviceName': 'i3'});
      final dh = {'authorization': 'Bearer ${pair['deviceToken']}', 'x-device-id': deviceId};
      final login = await call('POST', '/mobile/login', headers: dh, body: {'pin': '2468'});
      final sh = {...dh, 'x-session-token': login['sessionToken'] as String};
      final boot = await call('GET', '/mobile/bootstrap', headers: sh);
      final cust = (boot['customers'] as List).single as Map;
      expect(cust['name'], 'Cust A');
      expect(cust['creditLimit'], 500.0);
      Future<String> gid(int productId) async => (await a.db.getProductById(productId))!.globalId!;
      final prods = {
        for (final p in _list(boot['products']))
          if (p['globalId'] == await gid(a.waterId)) 'Water': p
          else if (p['globalId'] == await gid(a.breadId)) 'Bread': p,
      };
      expect(prods.keys, containsAll(['Water', 'Bread']));
      expect(prods['Bread']!['taxExempt'], isTrue);
      final ids = _Ids(
          cust['globalId'],
          repGid,
          _list(boot['routes']).single['globalId'],
          _map(boot['vanWarehouse'])['globalId'],
          _map(boot['custodySafe'])['globalId'],
          _list(boot['voucherBooks']).single['globalId'],
          prods['Water']!['globalId'],
          prods['Bread']!['globalId']);
      expect(boot['vanStock'], containsAll([
        {'productGlobalId': ids.water, 'quantity': 50.0},
        {'productGlobalId': ids.bread, 'quantity': 20.0},
      ]));
      String lease(Map b, String t) {
        final l = _list(b['leases']).firstWhere((l) => l['docType'] == t);
        return '${l['prefix']}${l['nextNumber']}';
      }

      final sale = ids.sale(lease(boot, 'sales_invoice'), paid: 5)..remove('total');
      final saleRes = await call('POST', '/mobile/sync/push', headers: sh, body: {
        'documents': [
          {...sale, 'kind': 'sales_invoice'},
          ids.collection(3, leaf: 7),
        ],
      });
      final saleResults = _list(saleRes['results']);
      expect(saleResults.map((r) => r['status']), ['accepted', 'accepted'], reason: '$saleRes');
      final retRes = await call('POST', '/mobile/sync/push', headers: sh, body: {
        'documents': [ids.ret(lease(boot, 'sales_return'), sale['globalId'] as String)..remove('total')],
      });
      final retResult = _list(retRes['results']).single;
      expect(retResult['status'], 'accepted', reason: '$retRes');

      final run = await sync.runOnce();
      expect(run.ok, isTrue, reason: run.error);
      for (final gid in [saleResults[0]['globalId'], saleResults[1]['globalId'], retResult['globalId']]) {
        expect((await a.db.cloudSyncDocument(gid as String))?.status, 'posted');
      }

      // Balances flow back to the van.
      final pull = await call('GET', '/mobile/bootstrap', headers: sh);
      final c2 = (pull['customers'] as List).single as Map;
      expect(c2['balance'], closeTo(12.6 - 5 - 2.9 - 3, 1e-9));

      final b = await _Fx.seed();
      await b.db.openShift(b.userId, 0);
      final bInvoice = await b.enterSale(paid: 5);
      await b.enterCollection(3, leaf: 7);
      await b.enterReturn(bInvoice);
      await _expectSameBooks(a, b);
    }, skip: url == null ? 'set CLOUD_URL (docker test stack) to run' : false);
  });
}

Future<SalesInvoiceData> _postTaxSale(_Fx fixture, {
  required double paid,
  required bool inclusive,
  double lineDiscountPercent = 0,
  double invoiceDiscountPercent = 0,
  double deliveryFee = 0,
}) async {
  final sale = await SalesTransactionOrchestrator(fixture.db, fixture.accounting)
      .completeSalesTransaction(SaleRequest(
    items: [CartItemEntity(productId: fixture.waterId, productName: 'Water',
        productCode: 'W-1', quantity: 8, unitPrice: 5, taxRate: 16,
        discountPercent: lineDiscountPercent)],
    customerId: fixture.customerId,
    warehouseId: fixture.vanId,
    userId: fixture.userId,
    paymentMethod: paid > 0 ? 'cash' : 'credit',
    paidAmount: paid,
    cashAmount: paid > 0 ? paid : null,
    cashSafeId: paid > 0 ? fixture.safeId : null,
    discountPercent: invoiceDiscountPercent,
    deliveryFee: deliveryFee,
    taxPercent: 16,
    pricesIncludeTax: inclusive,
  ));
  expect(sale.isSuccess, isTrue, reason: sale.errorMessage);
  return (fixture.db.select(fixture.db.salesInvoices)
        ..where((s) => s.id.equals(sale.invoiceId!))).getSingle();
}

Future<void> _expectTaxSale(_Fx fixture, SalesInvoiceData invoice, {
  required double total,
  required double tax,
  required double revenue,
  required double paid,
  double deliveryFee = 0,
  double discount = 0,
}) async {
  expect(invoice.total, total);
  expect(invoice.tax, tax);
  expect(invoice.discount, closeTo(discount, 0.001));
  expect(invoice.subtotal - invoice.discount + invoice.tax + deliveryFee,
      closeTo(total, 0.001));
  expect(invoice.paid, paid);
  expect(invoice.status, paid == total ? 'completed' : 'pending');
  final lines = await fixture.db.getSalesInvoiceItems(invoice.id);
  expect(lines, hasLength(1));
  expect(lines.single.total + deliveryFee, closeTo(total, 0.001));
  expect(lines.single.taxAmount, tax);
  expect((await fixture.db.getPartyById(fixture.customerId))!.balance,
      closeTo(total - paid, 0.001));
  final receipts = await (fixture.db.select(fixture.db.safeTransactions)
        ..where((t) => t.referenceType.equals('sales_invoice') &
            t.referenceId.equals(invoice.id))).get();
  expect(receipts.fold<double>(0, (sum, receipt) => sum + receipt.amount), paid);
  final entry = await (fixture.db.select(fixture.db.journalEntries)
        ..where((j) => j.referenceType.equals('sales_invoice') &
            j.referenceId.equals(invoice.id))).getSingle();
  final journalLines = await (fixture.db.select(fixture.db.journalEntryLines)
        ..where((line) => line.entryId.equals(entry.id))).get();
  final accounts = {for (final account in await fixture.db.select(fixture.db.accounts).get())
    account.id: account.code};
  double debit(String code) => journalLines.where((line) => accounts[line.accountId] == code)
      .fold<double>(0, (sum, line) => sum + line.debit);
  double credit(String code) => journalLines.where((line) => accounts[line.accountId] == code)
      .fold<double>(0, (sum, line) => sum + line.credit);
  expect(journalLines.fold<double>(0, (sum, line) => sum + line.debit),
      closeTo(journalLines.fold<double>(0, (sum, line) => sum + line.credit), 0.001));
  expect(credit('4121'), revenue);
  expect(credit('2121'), tax);
  expect(paid > 0 ? debit('1111') : debit('1121'), total);
}

Map<dynamic, dynamic> _map(Object? o) => o as Map;
List<Map<dynamic, dynamic>> _list(Object? o) => (o as List).cast<Map<dynamic, dynamic>>();

Future<String> _stamp(AppDatabase db, int invoiceId) async {
  final s = await db.getDocumentRepStamp('sales_invoices', invoiceId);
  return 'rep=${s.repEmployeeId},route=${s.routeId}';
}

double? _stock(Map<String, Object?> master, Object? productGid) {
  for (final s in (master['vanStock'] as List).cast<Map>()) {
    if (s['productGlobalId'] == productGid) return (s['quantity'] as num).toDouble();
  }
  return null;
}

/// Cloud-side global ids of the fixture, and builders of cloud documents in
/// the `/desktop/documents/pending` (and mobile push) shape.
class _Ids {
  _Ids(this.customer, this.rep, this.route, this.van, this.safe, this.book, this.water,
      this.bread);
  final Object? customer, rep, route, van, safe, book, water, bread;

  /// 4 × water @2.5 (16 %) + 1 × bread @1 (exempt) = 11.6 + 1 = 12.6.
  Map<String, Object?> sale(String number, {double paid = 0}) => {
        'kind': 'sales_invoice',
        'globalId': _uuid.v4(),
        'number': number,
        'date': DateTime.now().toUtc().toIso8601String(),
        'customerGlobalId': customer,
        'repEmployeeGlobalId': rep,
        'routeGlobalId': route,
        'warehouseGlobalId': van,
        'safeGlobalId': safe,
        'subtotal': 11.0,
        'discount': 0.0,
        'tax': 1.6,
        'total': 12.6,
        'paid': paid,
        'lines': [
          {'productGlobalId': water, 'quantity': 4, 'unitPrice': 2.5, 'discount': 0, 'taxRate': 16,
            'taxAmount': 1.6, 'total': 11.6},
          {'productGlobalId': bread, 'quantity': 1, 'unitPrice': 1, 'discount': 0, 'taxRate': 0,
            'taxAmount': 0, 'total': 1.0},
        ],
      };

  /// One water back: 11.6 / 4 = 2.9 (offsets the unpaid part).
  Map<String, Object?> ret(String number, String invoiceGid) => {
        'kind': 'sales_return',
        'globalId': _uuid.v4(),
        'number': number,
        'date': DateTime.now().toUtc().toIso8601String(),
        'originalInvoiceGlobalId': invoiceGid,
        'customerGlobalId': customer,
        'repEmployeeGlobalId': rep,
        'routeGlobalId': route,
        'warehouseGlobalId': van,
        'safeGlobalId': safe,
        'total': 2.9,
        'arOffset': 2.9,
        'cashRefund': 0.0,
        'lines': [
          {'productGlobalId': water, 'quantity': 1},
        ],
      };

  Map<String, Object?> collection(double amount, {required int leaf}) => {
        'kind': 'collection',
        'globalId': _uuid.v4(),
        'number': 'Q-$leaf',
        'customerGlobalId': customer,
        'repEmployeeGlobalId': rep,
        'routeGlobalId': route,
        'safeGlobalId': safe,
        'amount': amount,
        'bookGlobalId': book,
        'bookNumber': leaf,
      };

  Map<String, Object?> visit() => {
        'kind': 'visit',
        'globalId': _uuid.v4(),
        'date': DateTime.now().toUtc().toIso8601String(),
        'customerGlobalId': customer,
        'repEmployeeGlobalId': rep,
        'routeGlobalId': route,
        'outcome': 'no_sale',
        'noSaleReason': 'closed',
      };
}

/// A fresh desktop with one rep, van, custody safe, route customer, receipt
/// book and two products — identical in every database it is seeded into.
class _Fx {
  _Fx(this.db, this.accounting, this.userId, this.repId, this.vanId, this.safeId,
      this.customerId, this.waterId, this.breadId, this.bookId);
  final AppDatabase db;
  final AccountingService accounting;
  final int userId, repId, vanId, safeId, customerId, waterId, breadId, bookId;

  static Future<_Fx> seed() async {
    final db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    if ((await db.select(db.fiscalYears).get()).isEmpty) {
      final now = DateTime.now();
      await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
            name: '${now.year}',
            startDate: DateTime(now.year, 1, 1),
            endDate: DateTime(now.year, 12, 31),
            isClosed: const Value(false),
          ));
    }
    await db.setSetting('tax_rate', '16');
    final accounting = AccountingService(DriftAccountingRepository(db), _StubParties(),
        _RealisticTreasury(db), _StubProducts(), _StubInventory(), _StubSettings(),
        _StubAudit());
    final roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'i3_poster', isSystemRole: const Value(false)));
    final userId = await db.createUser(
        username: 'i3_poster', password: 'pw123456', displayName: 'I3 poster', roleId: roleId);
    final repId = await db.into(db.employees).insert(EmployeesCompanion.insert(name: 'Rep A'));
    final vanId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'Van A'));
    final safeId = await db.into(db.safes).insert(SafesCompanion.insert(name: 'Custody A'));
    final customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'Cust A', isCustomer: const Value(true), creditLimit: const Value(500)));
    final routeId = await db.saveDistributionRoute(
        name: 'Route A', repEmployeeId: repId, visitDays: const [1, 3]);
    await db.assignCustomerToRoute(
        customerId: customerId, routeId: routeId, at: DateTime(2020));
    await db.saveRepResources(employeeId: repId, vanWarehouseId: vanId, custodySafeId: safeId);
    final bookId = await db.createVoucherBook(
        type: 'receipt', rangeFrom: 1, rangeTo: 50, prefix: 'Q-', holderEmployeeId: repId);
    final waterId = await db.insertProduct(ProductsCompanion.insert(
      code: 'W-1',
      name: 'Water',
      salePrice: const Value(2.5),
      costPrice: const Value(1.0),
      taxRate: const Value(16),
      trackInventory: const Value(true),
    ));
    final breadId = await db.insertProduct(ProductsCompanion.insert(
      code: 'B-1',
      name: 'Bread',
      salePrice: const Value(1.0),
      costPrice: const Value(0.4),
      trackInventory: const Value(true),
    ));
    await db.setProductTaxExempt(breadId, true);
    await db.adjustStock(
        productId: waterId, warehouseId: vanId, quantity: 50, type: 'purchase', unitCost: 1);
    await db.adjustStock(
        productId: breadId, warehouseId: vanId, quantity: 20, type: 'purchase', unitCost: 0.4);
    return _Fx(db, accounting, userId, repId, vanId, safeId, customerId, waterId, breadId, bookId);
  }

  CloudSyncService service(http.Client client) => CloudSyncService(
        db: db,
        api: CloudLinkApi(
            const CloudLinkCredentials(baseUrl: 'http://fake', linkId: 'l', secret: 's'),
            client: client),
        accounting: accounting,
        postingUserId: userId,
      );

  /// The same sale typed into the desktop sales screen.
  Future<int> enterSale({required double paid}) async {
    final r = await SalesTransactionOrchestrator(db, accounting).completeSalesTransaction(
      SaleRequest(
        items: [
          CartItemEntity(
              productId: waterId, productName: 'Water', productCode: 'W-1',
              quantity: 4, unitPrice: 2.5, taxRate: 16),
          CartItemEntity(
              productId: breadId, productName: 'Bread', productCode: 'B-1',
              quantity: 1, unitPrice: 1, taxRate: 0),
        ],
        customerId: customerId,
        warehouseId: vanId,
        userId: userId,
        paymentMethod: 'cash',
        paidAmount: paid,
        cashAmount: paid,
        cashSafeId: safeId,
        taxPercent: 16,
      ),
    );
    expect(r.isSuccess, isTrue, reason: r.errorMessage);
    return r.invoiceId!;
  }

  Future<void> enterReturn(int invoiceId) async {
    final inv =
        await (db.select(db.salesInvoices)..where((s) => s.id.equals(invoiceId))).getSingle();
    final items = await db.getSalesInvoiceItems(invoiceId);
    final water = items.firstWhere((i) => i.productId == waterId);
    final ok = await ReturnsRepositoryImpl(db, accounting).processSalesReturn(
      invoice: inv,
      returnQuantities: {water.id: 1},
      productCache: <int, ProductEntity>{
        for (final i in items) i.productId: (await db.getProductById(i.productId))!.toEntity(),
      },
      userId: userId,
      userName: 'I3 poster',
    );
    expect(ok, isTrue);
  }

  Future<void> enterCollection(double amount, {required int leaf}) async {
    await db.validateVoucherBookLeaf(bookId, leaf);
    final id = await db.createReceiptVoucher(
        amount: amount, category: 'customer_payment', partyId: customerId, safeId: safeId,
        userId: userId);
    await db.assignVoucherBookLeaf(txnId: id, bookId: bookId, number: leaf);
  }
}

/// Golden comparison: everything a posting touches is equal in [a] (cloud
/// path) and [b] (desktop entry).
Future<void> _expectSameBooks(_Fx a, _Fx b) async {
  Future<Map<String, double>> trialBalance(AppDatabase db) async {
    final codes = {for (final x in await db.select(db.accounts).get()) x.id: x.code};
    final out = <String, double>{};
    for (final l in await db.select(db.journalEntryLines).get()) {
      final k = codes[l.accountId]!;
      out[k] = double.parse(((out[k] ?? 0) + l.debit - l.credit).toStringAsFixed(4));
    }
    out.removeWhere((_, v) => v.abs() < 1e-9);
    return out;
  }

  Future<List<String>> invoices(_Fx f) async => [
        for (final i in await (f.db.select(f.db.salesInvoices)..orderBy([(s) => OrderingTerm(expression: s.id)])).get())
          [i.invoiceNumber, i.subtotal, i.discount, i.tax, i.total, i.paid, i.paymentMethod,
            i.status, i.warehouseId, i.customerId,
            await _stamp(f.db, i.id)].join('|'),
      ];

  Future<List<String>> items(AppDatabase db) async => [
        for (final i in await db.select(db.salesInvoiceItems).get())
          [i.productId, i.quantity, i.unitPrice, i.taxRate, i.taxAmount, i.total, i.costPrice]
              .join('|'),
      ];

  Future<List<String>> safeTx(AppDatabase db) async => [
        for (final t in await db.select(db.safeTransactions).get())
          [t.safeId, t.transactionType, t.category, t.amount, t.partyId, t.voucherNumber].join('|'),
      ]..sort();

  Future<List<String>> stock(AppDatabase db) async => [
        for (final s in await db.select(db.inventoryBalances).get())
          [s.productId, s.warehouseId, s.quantity].join('|'),
      ]..sort();

  Future<Map<String, Object?>> scalars(_Fx f) async => {
        'customerBalance': (await f.db.getPartyById(f.customerId))!.balance,
        'safeBalance': (await f.db.getSafeById(f.safeId))!.balance,
        'waterStock': (await f.db.getProductById(f.waterId))!.currentStock,
        'breadStock': (await f.db.getProductById(f.breadId))!.currentStock,
        'bookNext': (await f.db.getVoucherBook(f.bookId))!.nextNumber,
        'leaves': (await f.db.customSelect(
                'SELECT book_number FROM safe_transactions WHERE book_id IS NOT NULL')
            .get())
            .map((r) => r.data['book_number'])
            .toList(),
      };

  expect(await trialBalance(a.db), await trialBalance(b.db), reason: 'journal entries');
  expect(await invoices(a), await invoices(b), reason: 'invoices');
  expect(await items(a.db), await items(b.db), reason: 'invoice lines');
  expect(await safeTx(a.db), await safeTx(b.db), reason: 'safe movements');
  expect(await stock(a.db), await stock(b.db), reason: 'warehouse stock');
  expect(await scalars(a), await scalars(b));
}

/// In-memory cloud speaking the `/desktop/*` contract.
class _FakeCloud {
  final List<Map<String, Object?>> pending = [];
  final Map<String, String?> postedAcks = {};
  final Map<String, String> failedAcks = {};
  Map<String, Object?>? lastMaster;
  bool dropAcks = false;

  http.Client get client => MockClient((req) async {
        expect(req.headers['authorization'], 'Bearer s');
        expect(req.headers['x-desktop-link'], 'l');
        Map<String, Object?> body() =>
            (jsonDecode(req.body) as Map).cast<String, Object?>();
        http.Response json(Object o) => http.Response(jsonEncode(o), 200,
            headers: {'content-type': 'application/json'});
        switch ('${req.method} ${req.url.path}') {
          case 'GET /desktop/ping':
            return json({'company': {'globalId': 'c', 'name': 'Fake'}, 'pending': {}});
          case 'GET /desktop/documents/pending':
            return json({
              'documents': [
                for (final d in pending)
                  if (!postedAcks.containsKey(d['globalId'])) d,
              ],
            });
          case 'POST /desktop/documents/ack':
            final results = (body()['results'] as List).cast<Map>();
            if (!dropAcks) {
              for (final r in results) {
                if (r['status'] == 'posted') {
                  postedAcks[r['globalId'] as String] = r['desktopNumber'] as String?;
                } else {
                  failedAcks[r['globalId'] as String] = r['reason'] as String;
                }
              }
            }
            return json({'results': [for (final r in results) {'globalId': r['globalId'], 'status': 'ok'}]});
          case 'POST /desktop/master':
            lastMaster = body();
            return json({'applied': {'parties': 1}, 'skipped': []});
        }
        return http.Response('{"error":"not_found"}', 404);
      });
}

class _StubParties implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) {
    if (inv.memberName == #getPartyById) return Future<Null>.value(null);
    throw UnsupportedError('parties repo not used here');
  }
}

/// Behavioural copy of `TreasuryRepositoryImpl.getSafeAccountsForReference`
/// (same as `sales_revenue_account_c2_test.dart`).
class _RealisticTreasury implements ITreasuryRepository {
  _RealisticTreasury(this.db);
  final AppDatabase db;

  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
      String referenceType, int referenceId) async {
    final rows = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals(referenceType) &
              t.referenceId.equals(referenceId) &
              t.transactionType.equals('receipt')))
        .get();
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final safe = await (db.select(db.safes)..where((s) => s.id.equals(r.safeId))).getSingle();
      final accountId = safe.linkedAccountId ??
          (await db.getAccountByCode(safe.safeType == 'bank' ? '1112' : '1111'))?.id;
      if (accountId != null) {
        out.add({'accountId': accountId, 'amount': r.amount, 'safeName': safe.name});
      }
    }
    return out;
  }

  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('treasury repo: ${inv.memberName}');
}

class _StubProducts implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('products not used here');
}

class _StubInventory implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('inventory not used here');
}

class _StubSettings implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('settings not used here');
}

class _StubAudit implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('audit not used here');
}
