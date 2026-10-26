// NEW-04: the legacy full-quantity `convertPOToInvoice` (the PO screen's convert
// button on the host / standalone) used to drop the order's tax and cost centre.
// It now carries them like the receipt conversion does. Amounts are asserted on
// the stored invoice rows and the supplier balance.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice, supplier, costCenter, po;

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE');
    costCenter = await h.db.into(h.db.costCenters).insert(CostCentersCompanion.insert(code: 'CC1', name: 'Kitchen'));
    supplier = await h.db.into(h.db.parties).insert(PartiesCompanion.insert(name: 'Supp', isSupplier: const Value(true)));
    // 10 x 40 = 400 gross, line discount 20, 16 % tax on the net 380 = 60.80
    po = await h.db.createPurchaseOrder(
      supplierId: supplier,
      warehouseId: h.a1,
      orderDate: DateTime(2026, 9, 1),
      costCenterId: costCenter,
      items: [
        PurchaseOrderItemsCompanion.insert(
            orderId: 0, productId: rice, quantity: 10, unitCost: 40, total: 400,
            discount: const Value(20), taxRate: const Value(16), taxAmount: const Value(60.8)),
      ],
    );
    await h.db.updatePurchaseOrderStatus(po, 'confirmed');
  });
  tearDown(() => h.dispose());

  test('the invoice carries the order\'s tax and cost centre; stock and supplier balance are exact', () async {
    final invoiceId = await h.db.convertPOToInvoice(po);

    final inv = await (h.db.select(h.db.purchaseInvoices)..where((i) => i.id.equals(invoiceId))).getSingle();
    expect(inv.costCenterId, costCenter, reason: 'the cost centre of the order is dropped no more');
    expect(inv.tax, closeTo(60.8, 0.001), reason: 'the order\'s tax is dropped no more');
    final line = await (h.db.select(h.db.purchaseInvoiceItems)..where((l) => l.invoiceId.equals(invoiceId))).getSingle();
    expect(line.taxRate, 16);
    expect(line.taxAmount, closeTo(60.8, 0.001));
    expect(line.discount, 20);
    expect(line.quantity, 10);

    expect(await h.stock(rice, h.a1), 10);
    // payable = 400 - 20 discount + 60.80 tax
    final balance = (await (h.db.select(h.db.parties)..where((p) => p.id.equals(supplier))).getSingle()).balance;
    expect(balance, closeTo(440.8, 0.001));
    expect((await h.db.getPurchaseOrderById(po))!.convertedToInvoiceId, invoiceId);
  });
}
