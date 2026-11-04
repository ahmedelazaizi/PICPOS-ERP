// Fixes of 2026-10-30 verified on REAL PostgreSQL (previously SQLite-only):
//  1. party_profile_dao: getPartyProfileMetrics / getPartySettlementRows
//     (owner-log crash "String is not a subtype of num?").
//  2. delta_upsert_sql: pulling an existing product/group keeps the
//     ON DELETE CASCADE children (ON CONFLICT(id) DO UPDATE, not REPLACE).
//  3. database_numbering: seed from MAX(numeric tail), gaps 1,2,5 - 2 => 6.
//  4. failed_autopost_retry: posts the missing journal once, idempotent.
//  5. negative stock cost adjustment: post, void, edit.
//  6. server_invoice_number: two terminals / two globalIds => 2 numbers.
//  7. sale_cost_resolver: zero_cost_policy warn / block.
@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/sale_cost_resolver.dart';
import 'package:picpos_erp/services/api/api_sales_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';
import 'package:shelf/shelf.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;
  late AppDatabase db;
  late int wh;
  late int user;
  var seq = 0;

  setUpAll(() async {
    fx = await bootPgTestSchema();
    db = fx.db;
    await db.customSelect('SELECT 1').get();
    await db.select(db.accounts).get(); // force migration + startup path
    await db.syncDefaultAccounts();
    await db.setSetting('enable_negative_sales', 'true');
    wh = (await db.getDefaultWarehouse())!.id;
    // The seeded admin carries the permissions edit/void paths enforce.
    user = (await db
            .customSelect("SELECT id FROM users WHERE username = 'admin' LIMIT 1")
            .getSingle())
        .read<int>('id');
  });

  tearDownAll(() async {
    await fx.tearDown();
  });

  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.first as int;

  // ───────────────────────── 1. party profile metrics ─────────────────────
  group('1. party_profile_dao on PostgreSQL', () {
    test('customer settled sale: metrics + settlement rows do not throw',
        () async {
      final cust = await db
          .into(db.parties)
          .insert(PartiesCompanion.insert(name: 'pp-customer'));
      final issued = DateTime(2026, 8, 1);
      final due = DateTime(2026, 8, 11);
      final inv = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'PP-S-1',
              warehouseId: wh,
              userId: user,
              customerId: d.Value(cust),
              invoiceDate: issued,
              dueDate: d.Value(due),
              total: const d.Value(1000),
              paid: const d.Value(1000),
            ),
          );
      final safe = await db
          .into(db.safes)
          .insert(SafesCompanion.insert(name: 'pp-safe'));
      final pay = await db.into(db.payments).insert(PaymentsCompanion.insert(
            paymentNumber: 'PAY-PP-1',
            paymentDate: DateTime(2026, 8, 6), // 5 days before due
            amount: 1000,
            safeId: safe,
            paymentType: 'receipt',
            partyId: d.Value(cust),
          ));
      await db
          .into(db.paymentAllocations)
          .insert(PaymentAllocationsCompanion.insert(
            paymentId: pay,
            invoiceType: 'sales',
            invoiceId: inv,
            allocatedAmount: 1000,
          ));

      final m = await db.getPartyProfileMetrics(partyId: cust, supplier: false);
      expect(m.settledInvoices, 1);
      expect(m.avgSettlementDays, closeTo(-5, 0.01));
      expect(m.onTimeSettlements, 1);

      final rows = await db.getPartySettlementRows(partyId: cust, supplier: false);
      expect(rows, hasLength(1));
      expect(rows.single.invoiceId, inv);
      expect(rows.single.invoiceNumber, 'PP-S-1');
      expect(rows.single.total, 1000);
      expect(rows.single.paid, 1000);
      expect(rows.single.allocationCount, 1);
      expect(rows.single.lastPaymentDate, isNotNull);
      expect(rows.single.lastPaymentDate!.year, 2026);
      expect(rows.single.lastPaymentDate!.month, 8);
      expect(rows.single.dueDate.day, 11);
    });

    test('supplier path (purchase invoices + purchase orders) runs too',
        () async {
      final sup = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'pp-supplier', isSupplier: const d.Value(true)));
      await db.into(db.purchaseOrders).insert(PurchaseOrdersCompanion.insert(
            orderNumber: 'PP-PO-1',
            supplierId: sup,
            warehouseId: wh,
            orderDate: DateTime(2026, 8, 1),
            expectedDate: d.Value(DateTime(2026, 8, 5)),
            receivedAt: d.Value(DateTime(2026, 8, 9)),
          ));
      final m = await db.getPartyProfileMetrics(partyId: sup, supplier: true);
      expect(m.settledInvoices, 0);
      expect(m.receivedOrders, 1);
      expect(m.onTimeOrders, 0);
      expect(await db.getPartySettlementRows(partyId: sup, supplier: true),
          isEmpty);
    });
  });

  // ───────────────────────── 2. delta upsert, no cascade ──────────────────
  group('2. delta upsert keeps CASCADE children on PostgreSQL', () {
    test('pulling an existing product / modifier group keeps children',
        () async {
      DeltaPullService.instance.initialize(db);
      await db.ensureModifierTables();
      await db.customStatement(
          "INSERT INTO products (id, code, name, global_id) "
          "VALUES (941, 'DP-1', 'prod', 'dp-gid-1')");
      await db.customStatement(
          "INSERT INTO modifier_groups (id, name) VALUES (907, 'size')");
      await db.customStatement(
          "INSERT INTO modifier_items (id, group_id, name) "
          "VALUES (901, 907, 'big')");
      await db.customStatement(
          'INSERT INTO product_modifier_groups (product_id, modifier_group_id) '
          'VALUES (941, 907)');

      await DeltaPullService.instance.upsertRowForTest('products', {
        'id': 941,
        'global_id': 'dp-gid-1',
        'code': 'DP-1',
        'name': 'prod edited',
        'sale_price': 12.5,
        'last_modified_at': 1700000000,
        'row_version': 2,
      });
      expect(await count("SELECT COUNT(*) FROM products WHERE name='prod edited'"),
          1);
      expect(await count('SELECT COUNT(*) FROM product_modifier_groups'), 1);

      await DeltaPullService.instance.upsertRowForTest('modifier_groups', {
        'id': 907,
        'name': 'size edited',
        'last_modified_at': 1700000000,
        'row_version': 2,
      });
      expect(
          await count(
              "SELECT COUNT(*) FROM modifier_groups WHERE name='size edited'"),
          1);
      expect(await count('SELECT COUNT(*) FROM modifier_items'), 1);
      expect(await count('SELECT COUNT(*) FROM product_modifier_groups'), 1);
    });
  });

  // ───────────────────────── 3. numbering seed from MAX ───────────────────
  group('3. numbering seeded from MAX on PostgreSQL', () {
    Future<void> seedInvoice(String number) =>
        db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
              invoiceNumber: number,
              warehouseId: wh,
              userId: user,
              invoiceDate: DateTime(2026, 3, 5),
            ));

    test('gaps 1,2,5 then 2 deleted -> next is NUM-6 then NUM-7', () async {
      await seedInvoice('NUM-1');
      await seedInvoice('NUM-2');
      await seedInvoice('NUM-5');
      await (db.delete(db.salesInvoices)
            ..where((s) => s.invoiceNumber.equals('NUM-2')))
          .go();
      expect(await db.transaction(() => db.generateInvoiceNumber('NUM')),
          'NUM-6');
      expect(await db.transaction(() => db.generateInvoiceNumber('NUM')),
          'NUM-7');
    });

    test('longer prefix and non-numeric tails do not pollute the counter',
        () async {
      await seedInvoice('NUMB-3');
      await seedInvoice('NUMB-9');
      await seedInvoice('NUMB-abc');
      expect(await db.transaction(() => db.generateInvoiceNumber('NUMB')),
          'NUMB-10');
      await seedInvoice('NUMC-3');
      await seedInvoice('NUMCX-9');
      await seedInvoice('NUMC-abc');
      expect(await db.transaction(() => db.generateInvoiceNumber('NUMC')),
          'NUMC-4');
    });
  });

  // ───────────────────────── 4. failed autopost retry ─────────────────────
  group('4. retryFailedAutoposts on PostgreSQL', () {
    test('sale row: journal created once, row resolved, 2nd call no-op',
        () async {
      final id = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'FAP-1',
              warehouseId: wh,
              userId: user,
              invoiceDate: DateTime(2026, 8, 4),
              subtotal: const d.Value(100),
              total: const d.Value(100),
              paid: const d.Value(100),
              cashPaid: const d.Value(100),
              paymentMethod: const d.Value('cash'),
              saleType: const d.Value('default'),
            ),
          );
      final rowId = await db.into(db.failedAutoposts).insert(
          FailedAutopostsCompanion.insert(
              invoiceId: id,
              referenceType: 'sale',
              errorMessage: 'simulated failure'));
      Future<int> je() async => (await (db.select(db.journalEntries)
                ..where((e) =>
                    e.referenceType.equals('sale') & e.referenceId.equals(id)))
              .get())
          .length;
      expect(await je(), 0);

      final r1 = await db.retryFailedAutoposts();
      expect(r1.resolved, 1);
      expect(await je(), 1);
      final row = await (db.select(db.failedAutoposts)
            ..where((f) => f.id.equals(rowId)))
          .getSingle();
      expect(row.isResolved, isTrue);
      expect(row.resolvedAt, isNotNull);

      final r2 = await db.retryFailedAutoposts();
      expect(r2.resolved, 0);
      expect(await je(), 1);
    });
  });

  // ───────────────────────── 5. negative stock adjustment ─────────────────
  group('5. negative stock cost adjustment on PostgreSQL', () {
    late int supplierId;

    setUpAll(() async {
      supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'neg supplier', isSupplier: const d.Value(true)));
    });

    Future<int> negProduct({double cost = 10}) async {
      final p = await db.insertProduct(ProductsCompanion.insert(
        code: 'NEG-${seq++}-${DateTime.now().microsecondsSinceEpoch}',
        name: 'neg product',
        costPrice: d.Value(cost),
        trackInventory: const d.Value(true),
      ));
      await db.adjustStock(
        productId: p,
        warehouseId: wh,
        quantity: -2,
        type: 'sale',
        referenceType: 'sale',
        referenceId: 9000,
        postAdjustmentJournal: false,
      );
      return p;
    }

    List<PurchaseInvoiceItemsCompanion> lines(int p, double qty, double cost) =>
        [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: p,
            quantity: qty,
            unitCost: cost,
            total: qty * cost,
          ),
        ];

    Future<int> create(int p, double qty, double cost) =>
        db.createPurchaseInvoice(
          supplierId: supplierId,
          warehouseId: wh,
          items: lines(p, qty, cost),
          paid: 0,
          paymentMethod: 'credit',
        );

    Future<void> edit(int id, int p, double qty, double cost) =>
        db.updatePurchaseInvoice(
          invoiceId: id,
          supplierId: supplierId,
          warehouseId: wh,
          items: lines(p, qty, cost),
          paid: 0,
          paymentMethod: 'credit',
          userId: user,
        );

    // The schema is shared across tests in this file, so account nets are
    // measured as deltas against the value taken before each scenario.
    Future<double> net(String purpose) async {
      final acc = (await db.getAccountByPurpose(purpose))!.id;
      final ls = await (db.select(db.journalEntryLines)
            ..where((l) => l.accountId.equals(acc)))
          .get();
      return ls.fold<double>(0, (s, l) => s + l.debit - l.credit);
    }

    Future<int> entries(String type, int id) async => (await (db.select(
                db.journalEntries)
              ..where((e) =>
                  e.referenceType.equals(type) & e.referenceId.equals(id)))
            .get())
        .length;

    test('sell negative, buy dearer, void => adjustment effects zero',
        () async {
      final cogs0 = await net('cogs');
      final inv0 = await net('inventory');
      final p = await negProduct();
      final id = await create(p, 3, 12); // adjustment 2 * (12 - 10) = 4
      expect(await entries('negative_stock_cost_adjustment', id), 1);
      expect(await net('cogs') - cogs0, closeTo(4, 0.001));
      expect(await net('inventory') - inv0, closeTo(36 - 4, 0.001));

      await db.voidPurchaseInvoice(id, reason: 'pg');
      expect(await net('cogs') - cogs0, closeTo(0, 0.001));
      expect(await net('inventory') - inv0, closeTo(0, 0.001));
      expect(await entries('negative_stock_cost_adjustment_void', id), 1);

      await db.voidPurchaseInvoice(id, reason: 'pg again'); // no-op
      expect(await entries('negative_stock_cost_adjustment_void', id), 1);
      expect(await net('cogs') - cogs0, closeTo(0, 0.001));
    });

    test('editing the purchase recomputes the adjustment, void zeroes it',
        () async {
      final cogs0 = await net('cogs');
      final inv0 = await net('inventory');
      final p = await negProduct();
      final id = await create(p, 3, 12);
      await edit(id, p, 4, 15); // 2 * (15 - 10) = 10
      expect(await net('cogs') - cogs0, closeTo(10, 0.001));
      expect(await net('inventory') - inv0, closeTo(60 - 10, 0.001));
      expect(await entries('negative_stock_cost_adjustment', id), 1);

      await edit(id, p, 3, 11); // 2
      expect(await net('cogs') - cogs0, closeTo(2, 0.001));
      expect(await net('inventory') - inv0, closeTo(33 - 2, 0.001));

      await edit(id, p, 3, 11); // idempotent
      expect(await net('cogs') - cogs0, closeTo(2, 0.001));
      expect(await entries('negative_stock_cost_adjustment', id), 1);

      await db.voidPurchaseInvoice(id, reason: 'pg');
      expect(await net('cogs') - cogs0, closeTo(0, 0.001));
      expect(await net('inventory') - inv0, closeTo(0, 0.001));
      expect(await entries('negative_stock_cost_adjustment_void', id), 1);
    });

    test('editing the cost down to the sale cost cancels the adjustment',
        () async {
      final cogs0 = await net('cogs');
      final inv0 = await net('inventory');
      final p = await negProduct();
      final id = await create(p, 3, 12);
      await edit(id, p, 3, 10);
      expect(await net('cogs') - cogs0, closeTo(0, 0.001));
      expect(await net('inventory') - inv0, closeTo(30, 0.001));
      expect(await entries('negative_stock_cost_adjustment', id), 0);
    });
  });

  // ───────────────────────── 6. server invoice number ─────────────────────
  group('6. two terminals, same client number, on PostgreSQL', () {
    late ApiSalesHandler handler;

    setUpAll(() async {
      await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
            name: '2026-pgfix',
            startDate: DateTime(2026, 1, 1),
            endDate: DateTime(2026, 12, 31),
          ));
      await (db.update(db.branches)..where((b) => b.id.equals(1)))
          .write(const BranchesCompanion(code: d.Value('BR')));
      handler = ApiSalesHandler(db, {});
    });

    Future<Response> post(String gid, String number) => handler.postSale(
          Request(
            'POST',
            Uri.parse('http://localhost/api/sales'),
            body: jsonEncode({
              'globalId': gid,
              'invoiceNumber': number,
              'clientIpSuffix': 'CL',
              'branchId': 1,
              'subtotal': 10.0,
              'total': 10.0,
              'paid': 10.0,
              'paymentMethod': 'cash',
              'warehouseId': wh,
              'userId': user,
              'items': [],
            }),
            headers: {'Content-Type': 'application/json'},
            context: {ApiUserCtx.userIdKey: user},
          ),
        );

    Future<Map<String, dynamic>> body(Response r) async =>
        jsonDecode(await r.readAsString()) as Map<String, dynamic>;

    test('A and B both send POS-1 => BR-POS-1, BR-POS-2; resend = duplicate',
        () async {
      final a = await post('pg-gid-A-1', 'POS-1');
      final b = await post('pg-gid-B-1', 'POS-1');
      expect(a.statusCode, 200);
      expect(b.statusCode, 200);
      final ja = await body(a);
      final jb = await body(b);
      expect(ja['invoiceNumber'], 'BR-POS-1');
      expect(jb['invoiceNumber'], 'BR-POS-2');

      final bAgain = await body(await post('pg-gid-B-1', 'POS-1'));
      final aAgain = await body(await post('pg-gid-A-1', 'POS-1'));
      expect(bAgain['duplicate'], true);
      expect(bAgain['invoiceNumber'], 'BR-POS-2');
      expect(bAgain['serverId'], jb['serverId']);
      expect(aAgain['duplicate'], true);
      expect(aAgain['invoiceNumber'], 'BR-POS-1');

      final rows = await (db.select(db.salesInvoices)
            ..where((s) => s.invoiceNumber.like('BR-POS-%')))
          .get();
      expect(rows.map((r) => r.invoiceNumber).toSet(),
          {'BR-POS-1', 'BR-POS-2'});
      expect(rows.length, 2);

      final c = await body(await post('pg-gid-C-1', 'POS-1'));
      expect(c['invoiceNumber'], 'BR-POS-3');
    });
  });

  // ───────────────────────── 7. sale cost resolver ────────────────────────
  group('7. SaleCostResolver / zero_cost_policy on PostgreSQL', () {
    Future<int> product({double cost = 0}) => db.insertProduct(
          ProductsCompanion.insert(
            code: 'NSC-${seq++}-${DateTime.now().microsecondsSinceEpoch}',
            name: 'resolver product',
            costPrice: d.Value(cost),
            trackInventory: const d.Value(true),
          ),
        );

    Future<int> sellNegative(int productId, {double? cost}) =>
        db.createSalesInvoice(
          invoiceNumber:
              'NSC-${seq++}-${DateTime.now().microsecondsSinceEpoch}',
          warehouseId: wh,
          userId: user,
          subtotal: 30,
          discount: 0,
          tax: 0,
          total: 30,
          paid: 30,
          paymentMethod: 'cash',
          deferAutoPost: true,
          items: [
            SalesInvoiceItemsCompanion.insert(
              invoiceId: 0,
              productId: productId,
              quantity: 3,
              unitPrice: 10,
              total: 30,
              costPrice:
                  cost == null ? const d.Value.absent() : d.Value(cost),
            ),
          ],
        );

    Future<double> snapshot(int invoiceId) async =>
        (await (db.select(db.salesInvoiceItems)
                  ..where((i) => i.invoiceId.equals(invoiceId)))
                .getSingle())
            .costPrice;

    tearDown(() async {
      await db.setSetting('zero_cost_policy', 'warn');
    });

    test('default is warn and saves with zero cost without throwing',
        () async {
      // The key is never written before this test runs (it is the first one).
      expect(kDefaultZeroCostPolicy, 'warn');
      expect(await SaleCostResolver(db).policy(), 'warn');
      final p = await product();
      expect(await snapshot(await sellNegative(p)), 0);
    });

    test('block + no known cost => CostRequiredException', () async {
      await db.setSetting('zero_cost_policy', 'block');
      final p = await product();
      await expectLater(
          sellNegative(p),
          throwsA(isA<CostRequiredException>()
              .having((e) => e.productId, 'productId', p)));
    });

    test('provisional cost is stored on the line and on the product',
        () async {
      final p = await product();
      final id = await sellNegative(p, cost: 7);
      expect(await snapshot(id), closeTo(7, 0.001));
      expect((await db.getProductById(p))!.costPrice, closeTo(7, 0.001));
    });

    test('product cost wins; purchase average used when cost is zero',
        () async {
      final withCost = await product(cost: 6);
      expect(await snapshot(await sellNegative(withCost)), closeTo(6, 0.001));

      final sup = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'avg supplier', isSupplier: const d.Value(true)));
      final bought = await product();
      for (final c in [10.0, 20.0]) {
        await db.createPurchaseInvoice(
          supplierId: sup,
          warehouseId: wh,
          items: [
            PurchaseInvoiceItemsCompanion.insert(
                invoiceId: 0,
                productId: bought,
                quantity: 2,
                unitCost: c,
                total: 2 * c),
          ],
          paid: 0,
          paymentMethod: 'credit',
        );
      }
      await (db.update(db.products)..where((x) => x.id.equals(bought)))
          .write(const ProductsCompanion(costPrice: d.Value(0)));
      final resolver = SaleCostResolver(db);
      final avg = await resolver.resolve(productId: bought);
      expect(avg.source, SaleCostSource.purchaseAverage);
      expect(avg.cost, closeTo(15, 0.001));

      final never = await product();
      expect((await resolver.resolve(productId: never)).source,
          SaleCostSource.none);
    });

    test('negative-stock adjustment direction (dearer / cheaper purchase)',
        () async {
      final sup = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'dir supplier', isSupplier: const d.Value(true)));
      Future<List<double>> adjustmentFor(double buyCost) async {
        final p = await product(cost: 10);
        await db.adjustStock(
          productId: p,
          warehouseId: wh,
          quantity: -2,
          type: 'sale',
          referenceType: 'sale',
          referenceId: 9000,
          postAdjustmentJournal: false,
        );
        final invoiceId = await db.createPurchaseInvoice(
          supplierId: sup,
          warehouseId: wh,
          items: [
            PurchaseInvoiceItemsCompanion.insert(
                invoiceId: 0,
                productId: p,
                quantity: 3,
                unitCost: buyCost,
                total: 3 * buyCost),
          ],
          paid: 0,
          paymentMethod: 'credit',
        );
        final entry = await (db.select(db.journalEntries)
              ..where((e) =>
                  e.referenceType.equals('negative_stock_cost_adjustment') &
                  e.referenceId.equals(invoiceId)))
            .getSingle();
        final ls = await (db.select(db.journalEntryLines)
              ..where((l) => l.entryId.equals(entry.id)))
            .get();
        final cogs = (await db.getAccountByPurpose('cogs'))!.id;
        final inv = (await db.getAccountByPurpose('inventory'))!.id;
        double sum(int acc, double Function(JournalEntryLine) f) => ls
            .where((l) => l.accountId == acc)
            .fold<double>(0, (s, l) => s + f(l));
        return [
          sum(cogs, (l) => l.debit),
          sum(cogs, (l) => l.credit),
          sum(inv, (l) => l.debit),
          sum(inv, (l) => l.credit),
        ];
      }

      final up = await adjustmentFor(12);
      expect(up[0], closeTo(4, 0.001));
      expect(up[1], 0);
      expect(up[2], 0);
      expect(up[3], closeTo(4, 0.001));
      final down = await adjustmentFor(8);
      expect(down[0], 0);
      expect(down[1], closeTo(4, 0.001));
      expect(down[2], closeTo(4, 0.001));
      expect(down[3], 0);
    });
  });
}
