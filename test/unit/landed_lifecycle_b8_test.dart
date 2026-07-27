// ═══════════════════════════════════════════════════════════════════════════
// Spec 149 pre-deploy batch B8 — S-LANDED-LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════════
//
// Fix 1 (PR-1)   — recalculateProductWAC now JOINs purchase_invoice_items to
//                   purchase_invoices and drops voided/soft-deleted invoices
//                   (and their landed allocations) from the WAC blend. Before
//                   this fix a void only flipped the invoice header — the
//                   item rows survived forever and kept contributing cost.
// Fix 2 (PUR-2a) — voidPurchaseInvoice's WAC recalc now runs AFTER both the
//                   invoice header and any applied landed-cost sheet have
//                   flipped status, so PR-1's exclusion actually has
//                   something to exclude (previously it ran too early —
//                   before either flip — so it was a no-op).
// Fix 3 (PUR-2b) — applyLandedCost now refuses to apply a DRAFT sheet whose
//                   parent purchase invoice was voided/deleted out from
//                   under it (void only reverses ALREADY-applied sheets).
// Fix 4 (PRET-1) — autoPostPurchaseReturn (a) throws instead of silently
//                   `return null`-ing when the inventory account is
//                   unmapped, so the transaction that already reversed
//                   stock/WAC/AP rolls back instead of leaving a half-
//                   applied return; (b) the JE dedup key now folds in the
//                   return's own voucher number instead of just
//                   invoiceId+amount, so two DISTINCT partial returns that
//                   happen to share the same amount both post their own JE.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/data/repositories/purchases_repository_impl.dart';
import 'package:ural_erp/domain/repositories/audit_repository_interface.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/domain/repositories/purchases_repository.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/services/accounting_service.dart';

void main() {
  late AppDatabase db;
  late PurchasesRepositoryImpl repo;
  late int branchId;
  late int warehouseId;
  late int supplierId;
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
    repo = PurchasesRepositoryImpl(db, svc);

    branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'main-b8',
            globalId: const Value('gid-br-b8'),
          ),
        );
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'wh-b8',
            branchId: Value(branchId),
            globalId: const Value('gid-wh-b8'),
          ),
        );
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'مورد B8',
            isSupplier: const Value(true),
            isCustomer: const Value(false),
            globalId: const Value('gid-supplier-b8'),
          ),
        );
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'B8-01',
        name: 'منتج اختبار B8',
        salePrice: const Value(200.0),
        costPrice: const Value(100.0),
        currentStock: const Value(0),
        trackInventory: const Value(true),
      ),
    );
  });

  tearDown(() async => db.close());

  /// Posts an UNPAID (credit) purchase invoice so void never hits the
  /// paid-in-full permission gate.
  Future<int> creditPurchase({required double qty, required double unitCost}) {
    final total = qty * unitCost;
    return db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0.0,
      paymentMethod: 'credit',
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: qty,
          unitCost: unitCost,
          total: total,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Fix 1 — PR-1: voided purchases drop out of the WAC recalc
  // ─────────────────────────────────────────────────────────────────────────
  group('PR-1 — recalculateProductWAC excludes voided purchases', () {
    test('two purchases blend; voiding one leaves ONLY the survivor\'s cost',
        () async {
      final invA = await creditPurchase(qty: 10, unitCost: 100);
      await creditPurchase(qty: 5, unitCost: 120);

      final blended = (await db.getProductById(productId))!.costPrice;
      expect(
        blended,
        closeTo((10 * 100.0 + 5 * 120.0) / 15.0, 0.001),
        reason: 'sanity: WAC blends both purchases before any void',
      );

      await db.voidPurchaseInvoice(invA, reason: 'اختبار PR-1', deletedBy: 1);

      final afterVoid = (await db.getProductById(productId))!.costPrice;
      expect(
        afterVoid,
        closeTo(120.0, 0.001),
        reason: 'only the surviving 5@120 purchase remains — the voided '
            '10@100 line must not contribute',
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Fix 2 — PUR-2a: recalc timing — landed allocation also unwinds on void
  // ─────────────────────────────────────────────────────────────────────────
  group('PUR-2a — void unwinds BOTH the raw purchase cost and its landed '
      'allocation', () {
    test('applied landed cost on a voided purchase leaves no trace in WAC',
        () async {
      // Baseline purchase — untouched throughout. Gives the post-void recalc
      // a surviving line to converge on (recalculateProductWAC no-ops on
      // zero surviving lines — the isEmpty guard — so a single-purchase
      // product can't prove this fix by itself).
      await creditPurchase(qty: 10, unitCost: 100);

      final invId = await creditPurchase(qty: 5, unitCost: 80);
      // Blended so far: (10*100 + 5*80) / 15 = 93.333...
      final sheetId = await db.createLandedCostSheet(
        purchaseInvoiceId: invId,
        sheetNumber: 'LCS-B8A-$invId',
      );
      await db.addLandedCostItem(
        sheetId: sheetId,
        costType: 'shipping',
        description: 'شحن',
        amount: 150.0,
      );
      await db.calculateAllocations(sheetId);
      await db.applyLandedCost(sheetId);

      const expectedAfterApply = ((10 * 100.0 + 5 * 80.0) + 150.0) / 15.0;
      final afterApply = (await db.getProductById(productId))!.costPrice;
      expect(
        afterApply,
        closeTo(expectedAfterApply, 0.01),
        reason: 'sanity: landed cost blended in before the void',
      );

      await db.voidPurchaseInvoice(invId, reason: 'اختبار PUR-2a', deletedBy: 1);

      final afterVoid = (await db.getProductById(productId))!.costPrice;
      expect(
        afterVoid,
        closeTo(100.0, 0.001),
        reason: 'only the surviving 10@100 purchase remains — no trace of '
            'the voided purchase\'s raw cost (80) or its landed allocation '
            '(150) may linger in WAC',
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Fix 3 — PUR-2b: applying a landed sheet whose invoice was voided
  // ─────────────────────────────────────────────────────────────────────────
  group('PUR-2b — applyLandedCost refuses a sheet whose invoice was voided',
      () {
    test('draft sheet + voided parent invoice → throws, no blend, no JE',
        () async {
      final invId = await creditPurchase(qty: 10, unitCost: 100);
      final sheetId = await db.createLandedCostSheet(
        purchaseInvoiceId: invId,
        sheetNumber: 'LCS-B8B-$invId',
      );
      await db.addLandedCostItem(
        sheetId: sheetId,
        costType: 'shipping',
        description: 'شحن',
        amount: 200.0,
      );
      await db.calculateAllocations(sheetId);

      final sheetBefore = await (db.select(db.landedCostSheets)
            ..where((s) => s.id.equals(sheetId)))
          .getSingle();
      expect(sheetBefore.status, 'draft',
          reason: 'sanity: sheet never applied');

      // Void only reverses ALREADY-applied sheets — this draft sheet is left
      // untouched, still pointing at a now-dead invoice.
      await db.voidPurchaseInvoice(invId, reason: 'اختبار PUR-2b', deletedBy: 1);

      final costBefore = (await db.getProductById(productId))!.costPrice;

      await expectLater(
        db.applyLandedCost(sheetId),
        throwsA(isA<StateError>()),
      );

      final costAfter = (await db.getProductById(productId))!.costPrice;
      expect(costAfter, costBefore,
          reason: 'a blocked apply must not blend any cost');

      final landedJes = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('landed_cost') &
                e.referenceId.equals(sheetId)))
          .get();
      expect(landedJes, isEmpty,
          reason: 'a blocked apply must not post a landed-cost JE');

      final sheetAfter = await (db.select(db.landedCostSheets)
            ..where((s) => s.id.equals(sheetId)))
          .getSingle();
      expect(sheetAfter.status, 'draft',
          reason: 'sheet status must stay draft — never silently applied');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Fix 4a — PRET-1: missing inventory account fails loud + rolls back
  // ─────────────────────────────────────────────────────────────────────────
  group('PRET-1a — autoPostPurchaseReturn fails loud on unmapped inventory '
      'account', () {
    test('missing inventory account throws and rolls back the WHOLE return '
        '(no half-applied stock/WAC/AP)', () async {
      final invId = await creditPurchase(qty: 10, unitCost: 100);
      final invoice = (await db.getPurchaseInvoiceById(invId))!;

      final stockBefore = (await db.getProductById(productId))!.currentStock;
      final wacBefore = (await db.getProductById(productId))!.costPrice;
      final balanceBefore = await _supplierBalance(db, supplierId);

      // Force the inventory account genuinely unresolvable — remove both the
      // mapping row (if syncDefaultAccounts seeded one) and the account
      // itself, so the fallback default code can't rescue it either.
      await (db.delete(db.accountMappings)
            ..where((m) => m.purpose.equals('inventory')))
          .go();
      // FK is enforced in tests now — the account still has a non-mapping
      // child, so force the deletion with FK momentarily off; the code under
      // test still runs with FK ON.
      await db.customStatement('PRAGMA foreign_keys = OFF');
      final deleted =
          await (db.delete(db.accounts)..where((a) => a.code.equals('1136')))
              .go();
      await db.customStatement('PRAGMA foreign_keys = ON');
      expect(deleted, 1,
          reason: 'the seeded inventory account (1136) must exist before '
              'we delete it — otherwise this test proves nothing');

      await expectLater(
        () => repo.processPurchaseReturn(
          invoice: invoice,
          returnItems: [
            PurchaseReturnItem(
              itemId: 0,
              productId: productId,
              returnQuantity: 5,
              unitCost: 100,
              taxAmount: 0,
              originalQuantity: 10,
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );

      final stockAfter = (await db.getProductById(productId))!.currentStock;
      final wacAfter = (await db.getProductById(productId))!.costPrice;
      final balanceAfter = await _supplierBalance(db, supplierId);
      expect(stockAfter, stockBefore,
          reason: 'stock reversal must roll back with the failed transaction');
      expect(wacAfter, wacBefore,
          reason: 'WAC reversal must roll back too');
      expect(balanceAfter, balanceBefore,
          reason: 'supplier AP adjustment must roll back too');

      final jes = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('purchase_return')))
          .get();
      expect(jes, isEmpty,
          reason: 'no half-applied JE — the return never committed at all');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Fix 4b — PRET-1: distinct same-amount partial returns no longer collide
  // ─────────────────────────────────────────────────────────────────────────
  group('PRET-1b — two distinct same-amount partial returns both post', () {
    test('second return of an identical amount is NOT silently deduped',
        () async {
      final invId = await creditPurchase(qty: 10, unitCost: 100);
      final invoice = (await db.getPurchaseInvoiceById(invId))!;

      Future<void> returnTwoUnits() => repo.processPurchaseReturn(
            invoice: invoice,
            returnItems: [
              PurchaseReturnItem(
                itemId: 0,
                productId: productId,
                returnQuantity: 2,
                unitCost: 100,
                taxAmount: 0,
                originalQuantity: 10,
              ),
            ],
          );

      await returnTwoUnits(); // event #1 — 200
      await returnTwoUnits(); // event #2 — ALSO 200 (same amount, distinct event)

      final jes = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('purchase_return') &
                e.isAutoPosted.equals(true)))
          .get();
      expect(jes, hasLength(2),
          reason: 'two DISTINCT return events sharing the same amount must '
              'both post their own JE — the old invoiceId+amount key '
              'collided and silently dropped the second');
      expect(jes.map((e) => e.id).toSet(), hasLength(2),
          reason: 'the two JEs must be genuinely distinct rows');

      // Net physical effect must reflect BOTH returns (4 units total).
      final stockAfter = (await db.getProductById(productId))!.currentStock;
      expect(stockAfter, 6, reason: '10 − 2 − 2 = 6');
    });
  });
}

/// Read the parties.balance column for assertions.
Future<double> _supplierBalance(AppDatabase db, int partyId) async {
  final row = await (db.select(db.parties)..where((p) => p.id.equals(partyId)))
      .getSingle();
  return row.balance;
}

// ═══════════════════════════════════════════════════════════════════════════
// Throwing stubs — only IAccountingRepository is exercised by this suite.
// ═══════════════════════════════════════════════════════════════════════════

class _ThrowingPartiesRepo implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in B8 landed-lifecycle tests');
}

class _ThrowingTreasuryRepo implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
          String referenceType, int referenceId) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in B8 landed-lifecycle tests');
}

class _ThrowingProductRepo implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in B8 landed-lifecycle tests');
}

class _ThrowingInventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in B8 landed-lifecycle tests');
}

class _ThrowingSettingsRepo implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in B8 landed-lifecycle tests');
}

class _ThrowingAuditRepo implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in B8 landed-lifecycle tests');
}
