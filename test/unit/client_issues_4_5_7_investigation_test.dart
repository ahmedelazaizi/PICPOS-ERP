// ═══════════════════════════════════════════════════════════════════════════
// QA INVESTIGATION — client complaints 4 / 5 / 7 (2026-07-25)
// ═══════════════════════════════════════════════════════════════════════════
//
// These are CHARACTERISATION tests: they document the CURRENT (buggy)
// behaviour so the defect is reproducible and the eventual fix has a
// red/green marker. They intentionally assert the *broken* behaviour where
// noted — the comment on each expectation says what it must become once the
// fix lands.
//
//  ISSUE 4 — product tax rate accepts any number (must be one of
//            Exempt/0/1/2/4/5/10/16).
//  ISSUE 5 — duplicate supplier invoice number accepted on purchases.
//  ISSUE 7 — purchase-returns screen has no supplier / item / invoice-number
//            filter; this file also proves the item-across-all-returns query
//            IS feasible on the existing schema + indexes.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'Main Warehouse',
            isDefault: const Value(true),
          ),
        );
    await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'Main Safe',
            safeType: const Value('cash'),
            isDefault: const Value(true),
          ),
        );
  });

  tearDown(() async => db.close());

  // ═════════════════════════════════════════════════════════════════════════
  // ISSUE 4 — item/product tax rate is unvalidated
  // ═════════════════════════════════════════════════════════════════════════
  group('ISSUE 4 — product taxRate has no allowed-set constraint', () {
    const allowed = <double>[0, 1, 2, 4, 5, 10, 16];

    test('REPRO: arbitrary / illegal tax rates persist to products.tax_rate',
        () async {
      // Values an operator can literally type into "نسبة الضريبة %" today.
      const illegal = <double>[37.5, 123.45, 999, -5, 14.0, 0.16];

      for (var i = 0; i < illegal.length; i++) {
        final id = await db.into(db.products).insert(
              ProductsCompanion.insert(
                code: 'TAX$i',
                name: 'Illegal tax product $i',
                taxRate: Value(illegal[i]),
              ),
            );
        final p = await db.getProductById(id);
        expect(p, isNotNull);
        // CURRENT (buggy) behaviour: stored verbatim, no clamp, no reject.
        expect(p!.taxRate, illegal[i],
            reason: 'taxRate ${illegal[i]} was accepted unchanged — there is '
                'no DB CHECK, no DAO guard and no form validator.');
        expect(allowed.contains(p.taxRate), isFalse,
            reason: '${p.taxRate} is NOT in the legal set $allowed yet it '
                'persisted. After the fix this insert path must be rejected.');
      }
    });

    test('REPRO: negative tax rate is accepted (produces negative input VAT)',
        () async {
      final id = await db.into(db.products).insert(
            ProductsCompanion.insert(
              code: 'TAXNEG',
              name: 'Negative tax',
              taxRate: const Value(-16),
            ),
          );
      final p = await db.getProductById(id);
      expect(p!.taxRate, -16.0);
      expect(p.taxRate < 0, isTrue,
          reason: 'A negative rate flows straight into '
              'purchase/sales line tax = subtotal * (rate/100) → negative VAT.');
    });

    test('schema: products.tax_rate is a plain REAL with default 0 — '
        'no CHECK constraint, no FK to any tax lookup', () async {
      final rows = await db
          .customSelect(
            "SELECT sql FROM sqlite_master "
            "WHERE type='table' AND name='products'",
          )
          .get();
      final ddl = (rows.single.data['sql'] as String).toLowerCase();
      expect(ddl.contains('tax_rate'), isTrue);
      // Prove the absence of any constraint on the column.
      expect(RegExp(r'tax_rate[^,]*check').hasMatch(ddl), isFalse,
          reason: 'No CHECK constraint on products.tax_rate.');
      expect(RegExp(r'tax_rate[^,]*references').hasMatch(ddl), isFalse,
          reason: 'products.tax_rate is a bare number, not an FK into a '
              'tax-rate lookup table.');
    });

    test('an e-invoice tax lookup DOES already exist (tax_types/tax_subtypes) '
        'but is NOT wired to products.tax_rate', () async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name IN ('tax_types','tax_subtypes')",
          )
          .get();
      final names = tables.map((r) => r.data['name'] as String).toSet();
      expect(names, containsAll(<String>{'tax_types', 'tax_subtypes'}),
          reason: 'e-invoicing already ships a legal tax-category lookup — '
              'the product form ignores it entirely.');
    });

    // FIXED 2026-07-25 (البند 4) — this test originally asserted the BROKEN
    // state (bare TextField, no validator, no dropdown). It now guards the fix
    // so a future refactor can't quietly reintroduce a free-text tax field.
    test('REGRESSION: both product dialogs pick the tax rate from the legal '
        'ladder, not free text', () async {
      final helpers = File(
        'lib/presentation/widgets/dialogs/product_form_helpers.dart',
      ).readAsStringSync();
      expect(helpers.contains('buildTaxRateDropdown'), isTrue,
          reason: 'the shared helper exposes a ladder-backed dropdown');
      expect(helpers.contains('TaxRatePolicy'), isTrue,
          reason: 'the dropdown is driven by the same policy the server and '
              'the Excel importer enforce — one source of truth');

      for (final path in const [
        'lib/presentation/widgets/dialogs/add_product_dialog.dart',
        'lib/presentation/screens/products/widgets/product_edit_dialog.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src.contains('buildTaxRateDropdown'), isTrue,
            reason: '$path must use the ladder dropdown for the tax rate');
      }

      // The guard must exist at the write boundaries too — a UI-only fix is
      // bypassed by a mirror, an outbox replay or a spreadsheet import.
      expect(
        File('lib/services/api/api_product_handler.dart')
            .readAsStringSync()
            .contains('TaxRatePolicy'),
        isTrue,
        reason: 'server API enforces the ladder',
      );
      expect(
        File('lib/data/services/excel_service.dart')
            .readAsStringSync()
            .contains('TaxRatePolicy'),
        isTrue,
        reason: 'Excel importer enforces the ladder',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ISSUE 5 — duplicate purchase invoice number accepted
  // ═════════════════════════════════════════════════════════════════════════
  group('ISSUE 5 — duplicate supplier invoice number', () {
    Future<int> makeSupplier(String name) => db.into(db.parties).insert(
          PartiesCompanion.insert(name: name, isSupplier: const Value(true)),
        );

    Future<int> makeProduct(String code) => db.into(db.products).insert(
          ProductsCompanion.insert(
            code: code,
            name: 'P-$code',
            currentStock: const Value(0),
            trackInventory: const Value(true),
          ),
        );

    // FIXED 2026-07-25 (البند 5) — originally a REPRO asserting that the second
    // create succeeded (2 duplicate rows). It now guards the rejection.
    test('REGRESSION: the SAME supplierInvoiceNumber is REJECTED for the '
        'SAME supplier', () async {
      final supplierId = await makeSupplier('Supplier A');
      final productId = await makeProduct('DUP1');
      final wh = await (db.select(db.warehouses)..limit(1)).getSingle();

      List<PurchaseInvoiceItemsCompanion> items() => [
            PurchaseInvoiceItemsCompanion.insert(
              invoiceId: 0,
              productId: productId,
              quantity: 1,
              unitCost: 10,
              total: 10,
              taxRate: const Value(0),
            ),
          ];

      final id1 = await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: wh.id,
        items: items(),
        paid: 0,
        paymentMethod: 'credit',
        supplierInvoiceNumber: 'INV-2026-001',
      );

      expect(id1, greaterThan(0));

      // Second, IDENTICAL supplier invoice number → rejected.
      await expectLater(
        db.createPurchaseInvoice(
          supplierId: supplierId,
          warehouseId: wh.id,
          items: items(),
          paid: 0,
          paymentMethod: 'credit',
          supplierInvoiceNumber: 'INV-2026-001',
        ),
        throwsA(isA<StateError>()),
      );

      final dupes = await (db.select(db.purchaseInvoices)
            ..where((p) => p.supplierInvoiceNumber.equals('INV-2026-001')))
          .get();
      expect(dupes.length, 1,
          reason: 'the duplicate never persisted — the transaction rolled back');

      // createPurchaseInvoice copies supplierInvoiceNumber into invoiceNumber,
      // so blocking the duplicate protects the internal number too.
      final byInternal = await (db.select(db.purchaseInvoices)
            ..where((p) => p.invoiceNumber.equals('INV-2026-001')))
          .get();
      expect(byInternal.length, 1,
          reason: 'purchase_dao.dart createPurchaseInvoice sets '
              'invoiceNumber = supplierInvoiceNumber, so blocking the '
              'duplicate protects the internal document number as well.');
    });

    // STILL TRUE and intentionally so: the DB-level partial unique index is
    // DEFERRED until the customer's live database is confirmed free of
    // pre-existing duplicates, otherwise the migration fails on their data.
    // The application-level guard above is what ships now.
    test('schema: purchase_invoices has NO unique index on invoice_number '
        'or supplier_invoice_number (only global_id)', () async {
      final idx = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type='index' "
            "AND tbl_name='purchase_invoices'",
          )
          .get();
      final uniques = idx
          .where((r) =>
              (r.data['sql'] as String?)?.toLowerCase().contains('unique') ??
              false)
          .map((r) => (r.data['sql'] as String).toLowerCase())
          .toList();

      final onInvoiceNumber = uniques.where((s) =>
          s.contains('(invoice_number') || s.contains('supplier_invoice_number'));
      expect(onInvoiceNumber, isEmpty,
          reason: 'No UNIQUE index covers the (supplier) invoice number.');

      // Auto-generated UNIQUE indexes for `.unique()` columns are implicit in
      // SQLite, so also prove it behaviourally: a second row with the same
      // number inserts cleanly.
      final supplierId = await makeSupplier('Supplier B');
      final wh = await (db.select(db.warehouses)..limit(1)).getSingle();
      for (var i = 0; i < 2; i++) {
        await db.into(db.purchaseInvoices).insert(
              PurchaseInvoicesCompanion.insert(
                invoiceNumber: 'RAW-DUP',
                supplierId: supplierId,
                warehouseId: wh.id,
                invoiceDate: DateTime.now(),
                supplierInvoiceNumber: const Value('RAW-DUP'),
              ),
            );
      }
      final raw = await (db.select(db.purchaseInvoices)
            ..where((p) => p.invoiceNumber.equals('RAW-DUP')))
          .get();
      expect(raw.length, 2,
          reason: 'Raw inserts confirm there is no DB-level uniqueness.');
    });

    test('same number for DIFFERENT suppliers is legitimate — a global UNIQUE '
        'would be wrong', () async {
      final a = await makeSupplier('Supplier A2');
      final b = await makeSupplier('Supplier B2');
      final wh = await (db.select(db.warehouses)..limit(1)).getSingle();

      for (final s in [a, b]) {
        await db.into(db.purchaseInvoices).insert(
              PurchaseInvoicesCompanion.insert(
                invoiceNumber: '1001',
                supplierId: s,
                warehouseId: wh.id,
                invoiceDate: DateTime.now(),
                supplierInvoiceNumber: const Value('1001'),
              ),
            );
      }
      final rows = await (db.select(db.purchaseInvoices)
            ..where((p) => p.supplierInvoiceNumber.equals('1001')))
          .get();
      expect(rows.map((r) => r.supplierId).toSet().length, 2,
          reason: 'Two different suppliers can each issue their invoice #1001 '
              '— hence the constraint must be per-supplier, not global.');
    });

    test('the per-supplier duplicate probe the fix would use returns the '
        'right answer on existing data', () async {
      final supplierId = await makeSupplier('Supplier C');
      final wh = await (db.select(db.warehouses)..limit(1)).getSingle();
      await db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: 'SC-77',
              supplierId: supplierId,
              warehouseId: wh.id,
              invoiceDate: DateTime.now(),
              supplierInvoiceNumber: const Value('SC-77'),
            ),
          );

      // Proposed guard: SELECT 1 FROM purchase_invoices
      //   WHERE supplier_id = ? AND supplier_invoice_number = ?
      //     AND is_deleted = 0 AND id <> ?(edit)
      final hit = await (db.select(db.purchaseInvoices)
            ..where((p) =>
                p.supplierId.equals(supplierId) &
                p.supplierInvoiceNumber.equals('SC-77') &
                p.isDeleted.equals(false)))
          .get();
      expect(hit.length, 1);

      final miss = await (db.select(db.purchaseInvoices)
            ..where((p) =>
                p.supplierId.equals(supplierId) &
                p.supplierInvoiceNumber.equals('SC-78') &
                p.isDeleted.equals(false)))
          .get();
      expect(miss, isEmpty);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ISSUE 7 — purchase-returns screen filters
  // ═════════════════════════════════════════════════════════════════════════
  group('ISSUE 7 — purchase returns filters', () {
    // FIXED 2026-07-25 (البند 7) — originally asserted the BROKEN state (dates
    // only + an in-memory `contains()`). Now guards the fix.
    test('REGRESSION: the screen offers supplier + product filters and no '
        'longer filters in memory', () async {
      final screen =
          File('lib/presentation/screens/purchase_returns_screen.dart')
              .readAsStringSync();

      expect(screen.contains('setSupplierFilter'), isTrue,
          reason: 'supplier filter wired to the notifier');
      expect(screen.contains('setProductFilter'), isTrue,
          reason: 'item filter wired to the notifier');
      expect(screen.contains('setInvoiceQuery'), isTrue,
          reason: 'invoice-number search goes through the notifier → SQL');

      // The truncated in-memory search is what made "search for invoice X"
      // fail silently past the 500th row. It must not come back.
      expect(screen.contains('inv.invoiceNumber.toLowerCase().contains'), isFalse,
          reason: 'no in-memory filtering over an already-truncated page');
    });

    test('REGRESSION: the repository entry point accepts the three filters',
        () async {
      final repo = File('lib/domain/repositories/returns_repository.dart')
          .readAsStringSync();
      final start = repo.indexOf('getInvoicesForPurchaseReturn');
      final sig = repo.substring(start, start + 260);
      expect(sig.contains('fromDate'), isTrue);
      expect(sig.contains('toDate'), isTrue);
      expect(sig.contains('supplierId'), isTrue);
      expect(sig.contains('productId'), isTrue);
      expect(sig.contains('invoiceNumberLike'), isTrue);
    });

    test('FEASIBILITY: filtering returns BY ITEM across all invoices works on '
        'the existing schema (stock_movements + purchase_invoices join)',
        () async {
      final supplierA = await db.into(db.parties).insert(
            PartiesCompanion.insert(
                name: 'Supp A', isSupplier: const Value(true)),
          );
      final supplierB = await db.into(db.parties).insert(
            PartiesCompanion.insert(
                name: 'Supp B', isSupplier: const Value(true)),
          );
      final prodX = await db.into(db.products).insert(
            ProductsCompanion.insert(code: 'X', name: 'Item X'),
          );
      final prodY = await db.into(db.products).insert(
            ProductsCompanion.insert(code: 'Y', name: 'Item Y'),
          );
      final wh = await (db.select(db.warehouses)..limit(1)).getSingle();

      final invA = await db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: 'PA-1',
              supplierId: supplierA,
              warehouseId: wh.id,
              invoiceDate: DateTime.now(),
              status: const Value('partial_return'),
            ),
          );
      final invB = await db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: 'PB-1',
              supplierId: supplierB,
              warehouseId: wh.id,
              invoiceDate: DateTime.now(),
              status: const Value('partial_return'),
            ),
          );

      // Returns are stored ONLY as stock_movements rows
      // (movement/reference type = 'purchase_return', referenceId = the
      // ORIGINAL purchase invoice id). There is no purchase_returns header
      // table in this schema.
      Future<void> ret(int invId, int productId, double qty, double cost) =>
          db.into(db.stockMovements).insert(
                StockMovementsCompanion.insert(
                  productId: productId,
                  warehouseId: wh.id,
                  movementType: 'purchase_return',
                  quantity: -qty,
                  balanceAfter: 0,
                  unitCost: Value(cost),
                  referenceType: const Value('purchase_return'),
                  referenceId: Value(invId),
                ),
              );

      await ret(invA, prodX, 2, 10);
      await ret(invA, prodY, 1, 20);
      await ret(invB, prodX, 5, 10);

      // ── Proposed query for "search an item across ALL return invoices" ──
      final rows = await db.customSelect(
        '''
        SELECT pi.id            AS invoice_id,
               pi.invoice_number AS invoice_number,
               pi.supplier_id    AS supplier_id,
               SUM(ABS(sm.quantity))                 AS returned_qty,
               SUM(ABS(sm.quantity) * sm.unit_cost)  AS returned_value
        FROM stock_movements sm
        JOIN purchase_invoices pi ON pi.id = sm.reference_id
        WHERE sm.reference_type = 'purchase_return'
          AND sm.product_id = ?
        GROUP BY pi.id, pi.invoice_number, pi.supplier_id
        ORDER BY pi.id
        ''',
        variables: [Variable<int>(prodX)],
        readsFrom: {db.stockMovements, db.purchaseInvoices},
      ).get();

      expect(rows.length, 2,
          reason: 'Item X was returned on two different purchase invoices.');
      expect(rows[0].data['invoice_number'], 'PA-1');
      expect(rows[0].data['supplier_id'], supplierA);
      expect((rows[0].data['returned_qty'] as num).toDouble(), 2.0);
      expect(rows[1].data['invoice_number'], 'PB-1');
      expect((rows[1].data['returned_value'] as num).toDouble(), 50.0);

      // Supplier filter is a trivial extra predicate on the same join.
      final bySupplier = await db.customSelect(
        '''
        SELECT DISTINCT pi.invoice_number AS invoice_number
        FROM stock_movements sm
        JOIN purchase_invoices pi ON pi.id = sm.reference_id
        WHERE sm.reference_type = 'purchase_return'
          AND pi.supplier_id = ?
        ''',
        variables: [Variable<int>(supplierB)],
        readsFrom: {db.stockMovements, db.purchaseInvoices},
      ).get();
      expect(bySupplier.map((r) => r.data['invoice_number']), ['PB-1']);
    });

    test('the indexes needed by that query already exist', () async {
      final idx = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND tbl_name='stock_movements'",
          )
          .get();
      final names = idx.map((r) => r.data['name'] as String).toSet();
      expect(names, contains('idx_stock_movements_reference'));
      expect(names, contains('idx_stock_movements_product'));

      final pidx = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND tbl_name='purchase_invoices'",
          )
          .get();
      final pnames = pidx.map((r) => r.data['name'] as String).toSet();
      expect(pnames, contains('idx_purchase_invoices_supplier'));
    });
  });
}
