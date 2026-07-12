// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 — RETURN journal-entry key invariants (A-02 · A-01 · F-04)
// ═══════════════════════════════════════════════════════════════════════════
//
// Root cause (all three): the sales/purchase RETURN JE used to be stored under
// `referenceId = hash(invoiceId + amount)` — a non-unique hash that neither the
// cancel/reverse query nor the edit-reverse query could reconstruct. The fix
// keys the return JE on the ORIGINATING invoice id (same id the stock/safe/AR
// rows use) and carries per-return-event uniqueness on the deterministic
// journal_entries.globalId instead. These tests lock that contract in.
//
//   A-02  post a sales return → reverse it → the GL legs (contra-revenue /
//         COGS / AR) are actually reversed (net GL of post+cancel == 0), not
//         just stock/cash. Pre-fix the reverse query matched ZERO rows.
//   A-01  two partial returns of the SAME amount on one invoice → BOTH JEs
//         post (no silent dedup drop), each balanced; a true retry still dedups.
//   F-04  two purchase returns for invoices whose numbers are substrings
//         ("12" / "120") → editing one must NOT reverse or flip the other's JE.
//
// Pure-unit: in-memory AppDatabase.forTesting() + seeded chart of accounts.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/data/repositories/purchases_repository_impl.dart';
import 'package:ural_erp/data/repositories/returns_repository_impl.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/domain/repositories/audit_repository_interface.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/domain/repositories/purchases_repository.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/services/accounting_service.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // A-02 — sales-return cancel actually reverses the GL (contra-revenue/COGS/AR)
  // ─────────────────────────────────────────────────────────────────────────
  group('A-02 — cancelling a sales return reverses its GL legs (not just stock)',
      () {
    late AppDatabase db;
    late int warehouseId;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.syncDefaultAccounts();
      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'main-a02',
              globalId: const Value('gid-br-a02'),
            ),
          );
      warehouseId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'wh-a02',
              branchId: Value(branchId),
              globalId: const Value('gid-wh-a02'),
            ),
          );
    });

    tearDown(() async => db.close());

    test(
        'post credit-sale return → reverseReturnAccountingEntry contra-posts '
        'every leg → net GL per account == 0 (AR + contra-revenue reversed)',
        () async {
      final invoiceId = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'INV-A02-1',
              warehouseId: warehouseId,
              userId: 1,
              invoiceDate: DateTime.now(),
              subtotal: const Value(200.0),
              tax: const Value(30.0),
              total: const Value(230.0),
              paid: const Value(0.0),
              paymentMethod: const Value('credit'),
              status: const Value('completed'),
              globalId: const Value('gid-inv-a02-1'),
            ),
          );
      final invoice = (await db.getSalesInvoiceById(invoiceId))!;

      // Post the return JE directly (net 200 + VAT 30, credit sale → AR refund).
      final jeId = await db.autoPostSalesReturn(
        originalInvoice: invoice,
        returnAmount: 230.0,
        cogsAmount: 100.0,
        cashRefund: 0,
        bankRefund: 0,
        arRefund: 230.0,
        vatAmount: 30.0,
        returnEventId: 'SRET-A02-1',
      );
      expect(jeId, isNotNull, reason: 'the return JE must post');

      final returnJe = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('sales_return')))
          .getSingle();
      // The KEY of the fix: the return JE is keyed on the invoice id so the
      // reverse query (which filters referenceId == invoiceId) can find it.
      expect(returnJe.referenceId, invoice.id,
          reason: 'return JE must be keyed on the originating invoice id, '
              'NOT a hash — otherwise cancel reverses nothing');

      final returnLines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(returnJe.id)))
          .get();
      // Sanity: an AR (customer receivable) credit leg must be present — the
      // A-02 bug is precisely that this leg (and contra-revenue) never reversed.
      final arLine = returnLines
          .where((l) => l.description == 'تسوية ذمم مدينة')
          .single;
      expect(arLine.credit, closeTo(230.0, 0.001));

      // Reverse the return (what cancelSalesReturn's step 4 calls).
      await db.reverseReturnAccountingEntry(
        invoiceId: invoice.id,
        invNumber: invoice.invoiceNumber,
      );

      final cancelJes = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('return_cancel')))
          .get();
      expect(cancelJes, hasLength(1),
          reason: 'the reverse must find the return JE and post a contra — '
              'pre-fix it matched zero rows and posted nothing');

      // Net effect per account across the return JE + its reversal must be zero.
      final entryIds = {returnJe.id, cancelJes.single.id};
      final allLines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.isIn(entryIds)))
          .get();
      final netByAccount = <int, double>{};
      for (final l in allLines) {
        netByAccount[l.accountId] =
            (netByAccount[l.accountId] ?? 0) + l.debit - l.credit;
      }
      expect(netByAccount, isNotEmpty);
      for (final e in netByAccount.entries) {
        expect(e.value, closeTo(0.0, 0.001),
            reason: 'account #${e.key} must net to zero after post + cancel '
                '(the contra-revenue / COGS / AR legs are all reversed)');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // A-01 — two same-amount partial returns do not collide; true retry dedups
  // ─────────────────────────────────────────────────────────────────────────
  group('A-01 — same-amount partial returns each get their own balanced JE',
      () {
    late AppDatabase db;
    late ReturnsRepositoryImpl repo;
    late int warehouseId;
    late int productId;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.syncDefaultAccounts();
      final accRepo = DriftAccountingRepository(db);
      final svc = AccountingService(
        accRepo,
        _ThrowingPartiesRepo(),
        _ThrowingTreasuryRepo(),
        _ThrowingProductRepo(),
        _ThrowingInventoryRepo(),
        _ThrowingSettingsRepo(),
        _ThrowingAuditRepo(),
      );
      repo = ReturnsRepositoryImpl(db, svc);

      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'main-a01',
              globalId: const Value('gid-br-a01'),
            ),
          );
      warehouseId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'wh-a01',
              branchId: Value(branchId),
              globalId: const Value('gid-wh-a01'),
            ),
          );
      productId = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'A01-01',
          name: 'منتج A01',
          salePrice: const Value(100.0),
          costPrice: const Value(50.0),
          currentStock: const Value(20),
          trackInventory: const Value(true),
        ),
      );
    });

    tearDown(() async => db.close());

    test(
        'two partial returns of qty=3 (same amount) on one invoice → TWO '
        'distinct balanced sales-return JEs (no silent dedup drop)', () async {
      final invoiceId = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'INV-A01-1',
              warehouseId: warehouseId,
              userId: 1,
              invoiceDate: DateTime.now(),
              subtotal: const Value(1000.0),
              tax: const Value(0.0),
              total: const Value(1000.0),
              paid: const Value(1000.0),
              paymentMethod: const Value('cash'),
              status: const Value('completed'),
              globalId: const Value('gid-inv-a01-1'),
            ),
          );
      final itemId = await db.into(db.salesInvoiceItems).insert(
            SalesInvoiceItemsCompanion.insert(
              invoiceId: invoiceId,
              productId: productId,
              quantity: 10,
              unitPrice: 100,
              total: 1000,
              costPrice: const Value(50.0),
            ),
          );
      final invoice = (await db.getSalesInvoiceById(invoiceId))!;
      final productCache = <int, ProductEntity>{
        productId: ProductEntity(
          id: productId,
          code: 'A01-01',
          name: 'منتج A01',
          salePrice: 100.0,
          costPrice: 50.0,
          currentStock: 20,
          minStock: 0,
        ),
      };

      // First partial return of qty 3.
      final r1 = await repo.processSalesReturn(
        invoice: invoice,
        returnQuantities: {itemId: 3.0},
        productCache: productCache,
        userId: 1,
        userName: 'A01',
        isFullReturn: false,
      );
      expect(r1, isTrue);

      // Second partial return of qty 3 — SAME amount as the first.
      final r2 = await repo.processSalesReturn(
        invoice: invoice,
        returnQuantities: {itemId: 3.0},
        productCache: productCache,
        userId: 1,
        userName: 'A01',
        isFullReturn: false,
      );
      expect(r2, isTrue);

      final jes = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('sales_return')))
          .get();
      expect(jes, hasLength(2),
          reason: 'each distinct partial return must post its own JE — the old '
              'amount-only hash collapsed the second one into the first');

      // Both keyed on the shared invoice id, but with DISTINCT globalIds.
      expect(jes.every((e) => e.referenceId == invoice.id), isTrue,
          reason: 'return JEs share the originating invoice id (reverse key)');
      expect(jes.map((e) => e.globalId).toSet(), hasLength(2),
          reason: 'per-return-event uniqueness rides on the globalId');

      for (final je in jes) {
        final lines = await (db.select(db.journalEntryLines)
              ..where((l) => l.entryId.equals(je.id)))
            .get();
        final debit = lines.fold<double>(0.0, (s, l) => s + l.debit);
        final credit = lines.fold<double>(0.0, (s, l) => s + l.credit);
        expect(debit, greaterThan(0));
        expect(debit, closeTo(credit, 0.001),
            reason: 'each partial-return JE must independently balance');
      }
    });

    test(
        'a genuine retry (same returnEventId) still dedups → no second JE',
        () async {
      final invoiceId = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'INV-A01-2',
              warehouseId: warehouseId,
              userId: 1,
              invoiceDate: DateTime.now(),
              subtotal: const Value(500.0),
              tax: const Value(0.0),
              total: const Value(500.0),
              paid: const Value(0.0),
              paymentMethod: const Value('credit'),
              status: const Value('completed'),
              globalId: const Value('gid-inv-a01-2'),
            ),
          );
      final invoice = (await db.getSalesInvoiceById(invoiceId))!;

      final first = await db.autoPostSalesReturn(
        originalInvoice: invoice,
        returnAmount: 200.0,
        cogsAmount: 100.0,
        cashRefund: 0,
        bankRefund: 0,
        arRefund: 200.0,
        returnEventId: 'SRET-RETRY-1',
      );
      expect(first, isNotNull);

      // Same event id (a retried submission of the SAME return) → deduped.
      final second = await db.autoPostSalesReturn(
        originalInvoice: invoice,
        returnAmount: 200.0,
        cogsAmount: 100.0,
        cashRefund: 0,
        bankRefund: 0,
        arRefund: 200.0,
        returnEventId: 'SRET-RETRY-1',
      );
      expect(second, isNull, reason: 'a true retry (same gid) must dedup');

      final jes = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('sales_return')))
          .get();
      expect(jes, hasLength(1),
          reason: 'only the first of two identical events may post');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // F-04 — editing a purchase return must not cross-reverse a substring twin
  // ─────────────────────────────────────────────────────────────────────────
  group('F-04 — purchase-return edit reverses only its own invoice', () {
    late AppDatabase db;
    late PurchasesRepositoryImpl repo;
    late int branchId;
    late int warehouseId;
    late int supplierId;
    late int productId;

    setUp(() async {
      db = AppDatabase.forTesting();
      final accRepo = DriftAccountingRepository(db);
      final svc = AccountingService(
        accRepo,
        _ThrowingPartiesRepo(),
        _ThrowingTreasuryRepo(),
        _ThrowingProductRepo(),
        _ThrowingInventoryRepo(),
        _ThrowingSettingsRepo(),
        _ThrowingAuditRepo(),
      );
      repo = PurchasesRepositoryImpl(db, svc);

      branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'main-f04',
              globalId: const Value('gid-br-f04'),
            ),
          );
      warehouseId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'wh-f04',
              branchId: Value(branchId),
              globalId: const Value('gid-wh-f04'),
            ),
          );
      supplierId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'مورد F04',
              isSupplier: const Value(true),
              isCustomer: const Value(false),
              globalId: const Value('gid-supplier-f04'),
            ),
          );
      productId = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'F04-01',
          name: 'منتج F04',
          salePrice: const Value(150.0),
          costPrice: const Value(100.0),
          currentStock: const Value(0),
          trackInventory: const Value(true),
        ),
      );
      // Seeded default cash safe — reuse (see purchase_return_edit_test.dart).
      final seededCashSafe = await db.getDefaultSafeByType('cash');
      await db.updateSafeBalance(seededCashSafe!.id, 100000);
    });

    tearDown(() async => db.close());

    Future<PurchaseInvoiceData> seedCreditPurchase({
      required String invoiceNumber,
      required double qty,
      required double unitCost,
    }) async {
      final total = qty * unitCost;
      final invoiceId = await db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: invoiceNumber,
              supplierId: supplierId,
              warehouseId: warehouseId,
              invoiceDate: DateTime(2026, 5, 1),
              subtotal: Value(total),
              tax: const Value(0),
              total: Value(total),
              paid: const Value(0),
              paymentMethod: const Value('credit'),
              status: const Value('completed'),
            ),
          );
      await db.into(db.purchaseInvoiceItems).insert(
            PurchaseInvoiceItemsCompanion.insert(
              invoiceId: invoiceId,
              productId: productId,
              quantity: qty,
              unitCost: unitCost,
              total: total,
            ),
          );
      await db.adjustPartyBalance(supplierId, total);
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: qty,
        type: 'purchase',
        referenceType: 'purchase_invoice',
        referenceId: invoiceId,
        unitCost: unitCost,
      );
      return (await db.getPurchaseInvoiceById(invoiceId))!;
    }

    test(
        'invoice numbers "12" and "120": editing 12\'s return leaves 120\'s '
        'return JE untouched (not reversed, isAutoPosted not flipped)',
        () async {
      // "120" contains "12" as a substring — the old `description LIKE
      // '%فاتورة 12%'` reverse match would sweep both.
      final inv12 = await seedCreditPurchase(
          invoiceNumber: '12', qty: 5, unitCost: 100);
      final inv120 = await seedCreditPurchase(
          invoiceNumber: '120', qty: 5, unitCost: 100);

      // Post a full return for each invoice.
      for (final inv in [inv12, inv120]) {
        await repo.processPurchaseReturn(
          invoice: inv,
          returnItems: [
            PurchaseReturnItem(
              itemId: 0,
              productId: productId,
              returnQuantity: 5,
              unitCost: 100,
              taxAmount: 0,
              originalQuantity: 5,
            ),
          ],
        );
      }

      // Capture invoice 120's canonical return JE BEFORE the edit.
      final inv120Before = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('purchase_return') &
                e.isAutoPosted.equals(true) &
                e.referenceId.equalsNullable(inv120.id)))
          .get();
      expect(inv120Before, hasLength(1));
      final inv120JeId = inv120Before.single.id;

      // Edit invoice 12's return down to qty 3.
      await repo.editPurchaseReturn(
        invoice: inv12,
        newReturnItems: [
          PurchaseReturnItem(
            itemId: 0,
            productId: productId,
            returnQuantity: 3,
            unitCost: 100,
            taxAmount: 0,
            originalQuantity: 5,
          ),
        ],
      );

      // Invoice 120 must be completely untouched by editing invoice 12.
      final inv120After = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('purchase_return') &
                e.referenceId.equalsNullable(inv120.id)))
          .get();
      expect(inv120After, hasLength(1),
          reason: 'editing invoice 12 must NOT post a reverse JE against '
              'invoice 120');
      expect(inv120After.single.id, inv120JeId,
          reason: 'invoice 120\'s return JE identity is unchanged');
      expect(inv120After.single.isAutoPosted, isTrue,
          reason: 'invoice 120\'s return JE must NOT be flipped to '
              'isAutoPosted=false by editing invoice 12 (the F-04 bug)');

      // Sanity: invoice 12 DID go through reverse + recreate.
      final inv12Canonical = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('purchase_return') &
                e.isAutoPosted.equals(true) &
                e.referenceId.equalsNullable(inv12.id)))
          .get();
      expect(inv12Canonical, hasLength(1),
          reason: 'invoice 12 keeps exactly one canonical JE after its edit');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Throwing stubs — the standalone return paths exercised here never call into
// AccountingService (only the Drift DAO), so any stub hit is a real bug.
// ═══════════════════════════════════════════════════════════════════════════

class _ThrowingPartiesRepo implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in spec-151 return-key tests');
}

class _ThrowingTreasuryRepo implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
          String referenceType, int referenceId) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in spec-151 return-key tests');
}

class _ThrowingProductRepo implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in spec-151 return-key tests');
}

class _ThrowingInventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in spec-151 return-key tests');
}

class _ThrowingSettingsRepo implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in spec-151 return-key tests');
}

class _ThrowingAuditRepo implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in spec-151 return-key tests');
}
