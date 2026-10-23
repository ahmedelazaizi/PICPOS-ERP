// Feature 043 — End-to-end guard against mirror purchase-item duplication.
//
// Field scenario (2026-05-12 on v124 mirror): saving a purchase invoice
// with line items on a CLIENT/mirror surfaced duplicate item rows in
// the rendered invoice after the next DeltaPull settled. Root cause:
// pre-043 the CLIENT and SERVER each minted their own item gids for
// the same logical line. Result on DeltaPull: Tier-1 (globalId) dedup
// missed because client-A != server-B, and Tier-2 (invoiceId, productId)
// could race when the same SKU appeared twice.
//
// Post-043 (Route B.1): the originator (client) pre-mints per-item
// gids and threads them into BOTH the local cache insert AND the
// payload sent to the server. The server honours those gids verbatim.
// DeltaPull's Tier-1 globalId-match catches the row, UPDATEs instead
// of duplicate-INSERTing, and the rendered invoice stays correct.

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int supplierId;
  late int warehouseId;
  late int productAId;

  setUp(() async {
    db = AppDatabase.forTesting();
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'WH-043-INT',
            isDefault: const Value(true),
            globalId: const Value('gid-wh-043-int'),
          ),
        );
    await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'Safe-043-INT',
            safeType: const Value('cash'),
            isDefault: const Value(true),
            globalId: const Value('gid-safe-043-int'),
          ),
        );
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'Supplier-043-INT',
            isSupplier: const Value(true),
            globalId: const Value('gid-supplier-043-int'),
          ),
        );
    productAId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            code: 'PRD-A-043-INT',
            name: 'Product A 043 INT',
            trackInventory: const Value(true),
            globalId: const Value('gid-prod-a-043-int'),
          ),
        );
  });

  tearDown(() => db.close());

  test('mirror cache + server-side INSERT under the SAME per-item gid leaves '
      'exactly one row per logical line on each side', () async {
    // Step 1 — mirror does the local-cache insert with its pre-minted gids
    // (mimicking purchases_repository_impl.dart's client-mode branch).
    const lineGid1 = '019e2042-aaaa-7000-0000-000000000001';
    const lineGid2 = '019e2042-bbbb-7000-0000-000000000002';
    const invoiceGid = '019e2042-cccc-7000-0000-000000000003';

    final clientInvoiceId = await db.insertPurchaseInvoiceWithoutStock(
      supplierId: supplierId,
      warehouseId: warehouseId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productAId,
          quantity: 5,
          unitCost: 4,
          total: 20,
          globalId: const Value(lineGid1),
        ),
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productAId, // same SKU, second carton — the worst-case
          quantity: 5,
          unitCost: 4,
          total: 20,
          globalId: const Value(lineGid2),
        ),
      ],
      paid: 40,
      paymentMethod: 'cash',
      globalId: invoiceGid,
    );

    // Sanity: two rows in the local cache, distinct gids.
    final clientRows = await (db.select(db.purchaseInvoiceItems)
          ..where((i) => i.invoiceId.equals(clientInvoiceId)))
        .get();
    expect(clientRows.length, 2);
    expect(clientRows.map((r) => r.globalId).toSet(),
        {lineGid1, lineGid2});

    // Step 2 — simulate what happens on the SERVER when postPurchase
    // processes the same payload. After Feature 043 the server reads
    // `m['globalId']` and stores the SAME UUIDs verbatim. Use a fresh
    // AppDatabase to model "the other side" without DeltaPull plumbing.
    final server = AppDatabase.forTesting();
    try {
      await server.into(server.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'WH-043-INT-SVR',
              isDefault: const Value(true),
              globalId: const Value('gid-wh-043-int-svr'),
            ),
          );
      final svrSupplierId = await server.into(server.parties).insert(
            PartiesCompanion.insert(
              name: 'Supplier-043-INT',
              isSupplier: const Value(true),
              globalId: const Value('gid-supplier-043-int'),
            ),
          );
      final svrProductId = await server.into(server.products).insert(
            ProductsCompanion.insert(
              code: 'PRD-A-043-INT',
              name: 'Product A 043 INT',
              trackInventory: const Value(true),
              globalId: const Value('gid-prod-a-043-int'),
            ),
          );
      final svrInvoiceId = await server.createPurchaseInvoice(
        supplierId: svrSupplierId,
        warehouseId: 1,
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: svrProductId,
            quantity: 5,
            unitCost: 4,
            total: 20,
            globalId: const Value(lineGid1),
          ),
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: svrProductId,
            quantity: 5,
            unitCost: 4,
            total: 20,
            globalId: const Value(lineGid2),
          ),
        ],
        paid: 40,
        paymentMethod: 'cash',
        globalId: invoiceGid,
      );

      final serverRows = await (server.select(server.purchaseInvoiceItems)
            ..where((i) => i.invoiceId.equals(svrInvoiceId)))
          .get();
      expect(serverRows.length, 2,
          reason: 'two-cartons-same-SKU invoice must produce two distinct '
              'rows on the server side too');
      expect(serverRows.map((r) => r.globalId).toSet(),
          {lineGid1, lineGid2},
          reason: 'AC-2 — server stores the per-line gids verbatim, '
              'matching the client. DeltaPull Tier-1 dedup will catch it.');
    } finally {
      await server.close();
    }
  });

  test('AC-3 — standalone callers without threaded gids still work', () async {
    // Same DAO call, no per-line gid. Must succeed and mint fresh UUIDs;
    // protects every existing non-mirror caller (the standalone path in
    // PurchasesRepositoryImpl, server-only deployments, legacy tests).
    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productAId,
          quantity: 1,
          unitCost: 9.5,
          total: 9.5,
          taxRate: const Value(0),
        ),
      ],
      paid: 9.5,
      paymentMethod: 'cash',
    );

    final rows = await (db.select(db.purchaseInvoiceItems)
          ..where((i) => i.invoiceId.equals(invoiceId)))
        .get();
    expect(rows.length, 1);
    expect(rows.first.globalId, isNotNull);
    expect(rows.first.globalId!.length, greaterThan(20));
  });
}
