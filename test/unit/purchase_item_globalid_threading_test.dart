// Feature 043 — Per-item globalId threading (Route B.1).
//
// Pins the contract at the data layer: when a caller passes per-item
// `globalId` values on the items companions, the DAO MUST store them
// verbatim. Mirrors the threading contract already proven for shifts
// (Feature 035) and shift-closing safe-txns (Feature 041).
//
// Pre-fix the client minted item gids locally and the server minted its
// own gids — same logical line, two different UUIDs — so DeltaPull's
// Tier-1 dedup missed and the mirror surfaced duplicate item rows after
// the next pull (worst on invoices with two cartons of the same SKU,
// where the Tier-2 `(invoiceId, productId)` fallback also collapsed).

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int supplierId;
  late int warehouseId;
  late int productAId;
  late int productBId;

  setUp(() async {
    db = AppDatabase.forTesting();

    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'WH-043',
            isDefault: const Value(true),
            globalId: const Value('gid-wh-043'),
          ),
        );
    await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'Safe-043',
            safeType: const Value('cash'),
            isDefault: const Value(true),
            globalId: const Value('gid-safe-043'),
          ),
        );
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'Supplier-043',
            isSupplier: const Value(true),
            globalId: const Value('gid-supplier-043'),
          ),
        );
    productAId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            code: 'PRD-A-043',
            name: 'Product A 043',
            trackInventory: const Value(true),
            globalId: const Value('gid-prod-a-043'),
          ),
        );
    productBId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            code: 'PRD-B-043',
            name: 'Product B 043',
            trackInventory: const Value(true),
            globalId: const Value('gid-prod-b-043'),
          ),
        );
  });

  tearDown(() => db.close());

  test('createPurchaseInvoice honours caller-provided per-item globalId',
      () async {
    // Caller (e.g. mirror's submitPurchase replay or the local cache
    // insert path) pre-mints stable UUIDs and passes them on the items
    // Companions. The DAO must preserve them verbatim so the server-side
    // row and the client-side row share identity.
    const gidA = '019e2000-aaaa-0000-0000-00000000000a';
    const gidB = '019e2000-bbbb-0000-0000-00000000000b';

    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productAId,
          quantity: 3,
          unitCost: 10,
          total: 30,
          taxRate: const Value(0),
          globalId: const Value(gidA),
        ),
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productBId,
          quantity: 2,
          unitCost: 12.5,
          total: 25,
          taxRate: const Value(0),
          globalId: const Value(gidB),
        ),
      ],
      paid: 55,
      paymentMethod: 'cash',
    );

    final rows = await (db.select(db.purchaseInvoiceItems)
          ..where((i) => i.invoiceId.equals(invoiceId))
          ..orderBy([(i) => OrderingTerm.asc(i.id)]))
        .get();

    expect(rows.length, 2);
    expect(rows[0].globalId, gidA,
        reason: 'caller-provided line globalId must be stored verbatim');
    expect(rows[1].globalId, gidB);
  });

  test('insertPurchaseInvoiceWithoutStock honours caller-provided per-item '
      'globalId (the mirror client-cache path)', () async {
    // This is the path the client mirror uses for the local cache row
    // (the server processes stock/accounting/treasury). Threading the
    // gid here keeps the mirror's row aligned with the server's row
    // pulled later via DeltaPull.
    const gid1 = '019e2000-1111-0000-0000-000000000001';
    const gid2 = '019e2000-2222-0000-0000-000000000002';

    final invoiceId = await db.insertPurchaseInvoiceWithoutStock(
      supplierId: supplierId,
      warehouseId: warehouseId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productAId,
          quantity: 5,
          unitCost: 4,
          total: 20,
          globalId: const Value(gid1),
        ),
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productAId, // SAME SKU as line 1 — two cartons case
          quantity: 5,
          unitCost: 4,
          total: 20,
          globalId: const Value(gid2),
        ),
      ],
      paid: 40,
      paymentMethod: 'cash',
    );

    final rows = await (db.select(db.purchaseInvoiceItems)
          ..where((i) => i.invoiceId.equals(invoiceId))
          ..orderBy([(i) => OrderingTerm.asc(i.id)]))
        .get();

    expect(rows.length, 2,
        reason: 'two distinct lines for the same SKU must coexist — they '
            'are different physical receipts; collapsing them is the bug');
    expect(rows[0].globalId, gid1);
    expect(rows[1].globalId, gid2);
    expect(rows[0].globalId, isNot(rows[1].globalId),
        reason: 'distinct gids per line is exactly what makes Tier-1 '
            'globalId dedup work on the mirror after DeltaPull');
  });

  test('legacy callers without per-item globalId still get fresh UUIDs '
      '(non-regression for standalone + pre-043 mirror caches)', () async {
    final invoiceId = await db.insertPurchaseInvoiceWithoutStock(
      supplierId: supplierId,
      warehouseId: warehouseId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productAId,
          quantity: 1,
          unitCost: 7,
          total: 7,
          // intentionally no globalId
        ),
      ],
      paid: 7,
      paymentMethod: 'cash',
    );

    final row = await (db.select(db.purchaseInvoiceItems)
          ..where((i) => i.invoiceId.equals(invoiceId)))
        .getSingle();

    expect(row.globalId, isNotNull,
        reason: 'DAO must mint a fresh UUID when the caller did not provide one');
    expect(row.globalId!.length, greaterThan(20));
  });
}
