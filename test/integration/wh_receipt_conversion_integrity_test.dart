// WH-001 / WH-003 (review 2026-10-25): converting a phone receipt into a
// purchase invoice must (a) consume the PO so no quantity can be invoiced
// twice by the legacy desktop paths and (b) carry the PO line's discount, tax
// and cost centre. Every assertion is on DB state (stock, AP, journal).
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice;

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE');
  });
  tearDown(() => h.dispose());

  Map<String, Object?> line(String gid, int pid, String qty, {String cond = 'ok'}) =>
      {'lineGlobalId': gid, 'productId': pid, 'quantity': qty, 'condition': cond};

  Future<void> receive(int po, String doc, String qty, {bool convert = true}) async {
    final d = await h.call('POST', '/api/m1/wh/po/$po/receipts',
        user: h.clerk, body: {'globalId': doc, 'lines': [line('line-$doc', rice, qty)]});
    expect(d.status, 200, reason: d.text);
    final s = await h.call('POST', '/api/m1/wh/receipts/$doc/submit', user: h.clerk);
    expect(s.status, 200, reason: s.text);
    if (convert) {
      final c = await h.call('POST', '/api/m1/wh/receipts/$doc/convert', user: h.admin);
      expect(c.status, 200, reason: c.text);
    }
  }

  Future<double> supplierBalance(int po) async {
    final order = (await h.db.getPurchaseOrderById(po))!;
    return (await (h.db.select(h.db.parties)..where((p) => p.id.equals(order.supplierId))).getSingle()).balance;
  }

  group('WH-001 a partially received PO is never invoiced in full again', () {
    test('the exact double-invoicing sequence: phone 6 of 12, then desktop convertPOToInvoice', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 12}, status: 'confirmed');
      await receive(po, 'doc-00000001', '6');
      expect(await h.stock(rice, h.a1), 6);
      final apAfterPhone = await supplierBalance(po);
      expect(apAfterPhone, 240, reason: '6 x 40 owed to the supplier');

      await expectLater(h.db.convertPOToInvoice(po), throwsException);

      expect(await h.stock(rice, h.a1), 6, reason: 'no second entry of the same goods');
      expect(await supplierBalance(po), apAfterPhone, reason: 'no second payable');
      expect(await h.db.select(h.db.purchaseInvoices).get(), hasLength(1));
    });

    test('"pull PO" into a purchase invoice (sourceOrderId) is refused the same way', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 12}, status: 'confirmed');
      await receive(po, 'doc-00000001', '6');
      final order = (await h.db.getPurchaseOrderById(po))!;
      await expectLater(
        h.db.createPurchaseInvoice(
          supplierId: order.supplierId,
          warehouseId: order.warehouseId,
          paid: 0,
          paymentMethod: 'credit',
          items: [PurchaseInvoiceItemsCompanion.insert(invoiceId: 0, productId: rice, quantity: 12, unitCost: 40, total: 480)],
          sourceOrderId: po,
        ),
        throwsException,
      );
      expect(await h.stock(rice, h.a1), 6);
      expect(await h.db.select(h.db.purchaseInvoices).get(), hasLength(1));
    });

    test('a submitted-but-not-converted receipt also blocks the legacy full conversion', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 12}, status: 'confirmed');
      await receive(po, 'doc-00000001', '6', convert: false);
      await expectLater(h.db.convertPOToInvoice(po), throwsException);
      expect(await h.db.select(h.db.purchaseInvoices).get(), isEmpty);
    });

    test('the receipt route still finishes the order: 6 + 6 = 12 stock, PO stamped once', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 12}, status: 'confirmed');
      await receive(po, 'doc-00000001', '6');
      await receive(po, 'doc-00000002', '6');
      expect(await h.stock(rice, h.a1), 12);
      final order = (await h.db.getPurchaseOrderById(po))!;
      expect(order.convertedToInvoiceId, isNotNull);
      expect(order.status, 'received');
      expect(await supplierBalance(po), 480);
    });

    test('an untouched PO still converts through the legacy path (no regression)', () async {
      final po = await h.purchaseOrder(h.a1, {rice: 12}, status: 'confirmed');
      final inv = await h.db.convertPOToInvoice(po);
      expect(inv, isPositive);
      expect(await h.stock(rice, h.a1), 12);
    });
  });

  group('WH-003 the invoice carries the PO line discount, tax and cost centre', () {
    test('half of a discounted+taxed line -> half the discount and half the tax, journal balanced', () async {
      final cc = await h.db.into(h.db.costCenters).insert(CostCentersCompanion.insert(code: 'CC1', name: 'Project'));
      final supplier = await h.db.into(h.db.parties).insert(PartiesCompanion.insert(name: 'S2', isSupplier: const Value(true)));
      final po = await h.db.createPurchaseOrder(
        supplierId: supplier,
        warehouseId: h.a1,
        orderDate: DateTime(2026, 9, 1),
        costCenterId: cc,
        items: [
          // 10 x 40 = 400 gross, 20 discount, 60 tax (15%).
          PurchaseOrderItemsCompanion.insert(
            orderId: 0, productId: rice, quantity: 10, unitCost: 40, total: 400,
            discount: const Value(20), taxRate: const Value(15), taxAmount: const Value(60),
          ),
        ],
      );
      await h.db.updatePurchaseOrderStatus(po, 'confirmed');

      await receive(po, 'doc-00000001', '5');

      final inv = (await h.db.select(h.db.purchaseInvoices).get()).single;
      expect(inv.tax, closeTo(30, 0.01), reason: 'half of the 60 tax');
      expect(inv.discount, closeTo(10, 0.01), reason: 'half of the 20 discount');
      expect(inv.total, closeTo(200 + 30 - 10, 0.01));
      expect(inv.costCenterId, cc);
      final items = await h.db.select(h.db.purchaseInvoiceItems).get();
      expect(items.single.taxRate, 15);
      expect(items.single.taxAmount, closeTo(30, 0.01));

      final lines = await h.db.select(h.db.journalEntryLines).get();
      final debit = lines.fold<double>(0, (s, l) => s + l.debit);
      final credit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(debit, closeTo(credit, 0.01), reason: 'the entries balance');
      expect(await supplierBalance(po), closeTo(220, 0.01), reason: 'AP = net of discount incl. tax');
    });
  });
}
