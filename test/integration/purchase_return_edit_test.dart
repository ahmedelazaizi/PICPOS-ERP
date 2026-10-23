// ═══════════════════════════════════════════════════════════════════════════
// Feature 015 — Purchase Return Edit (regression suite)
// ═══════════════════════════════════════════════════════════════════════════
//
// Covers the spec's three priority scenarios:
//   US1  — qty=5 → edit qty=3 → supplier balance, stock, JE all reflect 3
//   US2  — closed-period edit refused with the Arabic message from 014
//   Edge — cash refund path: insufficient safe balance → fail closed
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/data/repositories/purchases_repository_impl.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/purchases_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';

void main() {
  late AppDatabase db;
  late PurchasesRepositoryImpl repo;
  late int branchId;
  late int warehouseId;
  late int supplierId;
  late int productId;
  late int cashSafeId;

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

    // Branch + warehouse + supplier + product (minimal world).
    branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'main',
            globalId: const Value('gid-br-edit'),
          ),
        );
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'wh-edit',
            branchId: Value(branchId),
            globalId: const Value('gid-wh-edit'),
          ),
        );
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'مورد التعديل',
            isSupplier: const Value(true),
            isCustomer: const Value(false),
            globalId: const Value('gid-supplier-edit'),
          ),
        );
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'EDIT-01',
        name: 'منتج التعديل',
        salePrice: const Value(150.0),
        costPrice: const Value(100.0),
        currentStock: const Value(0),
        trackInventory: const Value(true),
      ),
    );

    // The DB seeder already creates a default cash safe (`صندوق الكاشير`).
    // Reuse it instead of inserting a second default — `getDefaultSafeByType`
    // does `limit(1)` and would silently pick the seeded one if we added a
    // duplicate, leaving our balance updates pointing at the wrong row.
    final seededCashSafe = await db.getDefaultSafeByType('cash');
    cashSafeId = seededCashSafe!.id;
    await db.updateSafeBalance(cashSafeId, 10000);
  });

  tearDown(() async => db.close());

  /// Posts a credit purchase invoice for [qty] units of [productId] at [unitCost].
  /// Returns the invoice row so tests can drive editPurchaseReturn against it.
  Future<PurchaseInvoiceData> seedCreditPurchase({
    required double qty,
    required double unitCost,
    DateTime? date,
  }) async {
    final total = qty * unitCost;
    final invoiceId = await db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: 'P-EDIT-${DateTime.now().microsecondsSinceEpoch}',
            supplierId: supplierId,
            warehouseId: warehouseId,
            invoiceDate: date ?? DateTime(2026, 5, 1),
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
    // Bring the supplier balance to mirror what createPurchaseInvoice would do
    // (we owe them the full amount on a credit purchase).
    await db.adjustPartyBalance(supplierId, total);
    // Reflect the stock-in so reverseProductWAC has a non-zero stock to work
    // against during the return + edit cycle.
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: qty,
      type: 'purchase',
      referenceType: 'purchase_invoice',
      referenceId: invoiceId,
      unitCost: unitCost,
    );
    final invoice = await db.getPurchaseInvoiceById(invoiceId);
    return invoice!;
  }

  // ════════════════════════════════════════════════════════════════════════
  // US1 — happy path: qty=5 → edit to qty=3
  // ════════════════════════════════════════════════════════════════════════

  test(
      'US1: edit qty=5 → qty=3 leaves stock, supplier balance, and JE trail '
      'consistent with qty=3', () async {
    final invoice = await seedCreditPurchase(qty: 10, unitCost: 100);

    // 1) Post the original return for 5 units.
    await repo.processPurchaseReturn(
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
    );

    // Sanity: supplier balance was 1000 (10×100) → returning 5 reduces it
    //         by 500 → 500.
    final supplierAfterPost = await _supplierBalance(db, supplierId);
    expect(supplierAfterPost, 500,
        reason: 'after qty=5 return, supplier balance = 1000 − 500');

    final stockAfterPost = (await db.getProductById(productId))!.currentStock;
    expect(stockAfterPost, 5,
        reason: 'after qty=5 return, on-hand = 10 − 5');

    final autoJesAfterPost = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceType.equals('purchase_return') &
              e.isAutoPosted.equals(true)))
        .get();
    expect(autoJesAfterPost, hasLength(1),
        reason: 'one canonical JE after the original return');

    // 2) Edit the return down to qty=3.
    await repo.editPurchaseReturn(
      invoice: invoice,
      newReturnItems: [
        PurchaseReturnItem(
          itemId: 0,
          productId: productId,
          returnQuantity: 3,
          unitCost: 100,
          taxAmount: 0,
          originalQuantity: 10,
        ),
      ],
    );

    // 3) Final state must match qty=3.
    final supplierAfterEdit = await _supplierBalance(db, supplierId);
    expect(supplierAfterEdit, 700,
        reason: 'after edit to qty=3, supplier balance = 1000 − 300');

    final stockAfterEdit = (await db.getProductById(productId))!.currentStock;
    expect(stockAfterEdit, 7,
        reason: 'after edit to qty=3, on-hand = 10 − 3');

    // FR-008: audit trail preserves both posts. We expect:
    //   - original JE: still there, isAutoPosted flipped to FALSE
    //   - reverse JE:  flipped lines, isAutoPosted=false
    //   - new JE:      qty=3 amounts, isAutoPosted=true (canonical)
    final allReturnJes = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('purchase_return')))
        .get();
    expect(allReturnJes.length, greaterThanOrEqualTo(3),
        reason: 'audit trail must show original + reverse + new (≥3 entries)');

    final canonicalJes =
        allReturnJes.where((e) => e.isAutoPosted).toList();
    expect(canonicalJes, hasLength(1),
        reason: 'exactly one CANONICAL auto-posted JE must remain after edit');

    // The lone canonical JE's lines should sum to the new return's amount.
    final canonicalLines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(canonicalJes.single.id)))
        .get();
    final canonicalDebit =
        canonicalLines.fold<double>(0, (s, l) => s + l.debit);
    final canonicalCredit =
        canonicalLines.fold<double>(0, (s, l) => s + l.credit);
    expect(canonicalDebit, 300,
        reason: 'canonical JE debit (Dr Payables) = new return amount');
    expect(canonicalCredit, 300,
        reason: 'canonical JE credit (Cr Inventory) = new return amount');

    // The supplier-statement memo must also reflect the new amount and have
    // a compensating reverse row preserving the audit trail. Memos are
    // append-only, so the LATEST `purchase_return_balance` row (highest id)
    // is the canonical post-edit one.
    final memoRows = await (db.select(db.safeTransactions)
          ..where((t) => t.referenceId.equalsNullable(invoice.id))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    final canonicalMemo = memoRows
        .where((t) => t.category == 'purchase_return_balance')
        .last;
    expect(canonicalMemo.amount, 300,
        reason: 'canonical memo amount reflects the edited return');
    expect(
      memoRows.any((t) => t.category == 'purchase_return_balance_reverse'),
      isTrue,
      reason: 'compensating reverse memo row preserves the audit trail',
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // US1 #3 — description-only / no-op edit (items unchanged)
  // ════════════════════════════════════════════════════════════════════════

  test('US1: editing with the same items is a no-op (no extra JEs)', () async {
    final invoice = await seedCreditPurchase(qty: 10, unitCost: 100);
    await repo.processPurchaseReturn(
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
    );

    final jesBefore = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('purchase_return')))
        .get();

    // Same qty=5 → orchestrator should detect no-op and bail.
    await repo.editPurchaseReturn(
      invoice: invoice,
      newReturnItems: [
        PurchaseReturnItem(
          itemId: 0,
          productId: productId,
          returnQuantity: 5,
          unitCost: 100,
          taxAmount: 0,
          originalQuantity: 10,
        ),
      ],
    );

    final jesAfter = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('purchase_return')))
        .get();
    expect(jesAfter.length, jesBefore.length,
        reason: 'no-op edit must not insert any new JEs');
  });

  // ════════════════════════════════════════════════════════════════════════
  // US2 — closed-period edit refused
  // ════════════════════════════════════════════════════════════════════════

  test('US2: editing a return whose invoice date is in a closed fiscal year '
      'fails with the Feature 014 Arabic message', () async {
    // Open the 2025 fiscal year FIRST — autoPostPurchaseReturn validates
    // that a fiscal year exists for the JE date before posting, so the
    // initial return needs an open year to land in.
    await db.into(db.fiscalYears).insert(
          FiscalYearsCompanion.insert(
            name: 'FY2025',
            startDate: DateTime(2025, 1, 1),
            endDate: DateTime(2025, 12, 31),
          ),
        );

    final invoice = await seedCreditPurchase(
      qty: 10,
      unitCost: 100,
      date: DateTime(2025, 6, 15),
    );
    await repo.processPurchaseReturn(
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
    );

    // NOW close the year — the edit attempt below must hit the period gate.
    await (db.update(db.fiscalYears)
          ..where((y) => y.name.equals('FY2025')))
        .write(FiscalYearsCompanion(
      isClosed: const Value(true),
      closedAt: Value(DateTime.now()),
    ));

    // Now try to edit → must throw the canonical Arabic refusal.
    await expectLater(
      () => repo.editPurchaseReturn(
        invoice: invoice,
        newReturnItems: [
          PurchaseReturnItem(
            itemId: 0,
            productId: productId,
            returnQuantity: 3,
            unitCost: 100,
            taxAmount: 0,
            originalQuantity: 10,
          ),
        ],
      ),
      throwsA(isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains('الفترة المحاسبية'),
      )),
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // Edge case — cash refund cannot be reversed if safe lacks the balance
  // ════════════════════════════════════════════════════════════════════════

  test('Edge: cash refund reversal fails closed when safe balance is below '
      'the un-refund amount', () async {
    // شرطٌ لازمٌ منذ مواصفة 2026-08-18 (ح‑١): مرتجعُ مشترياتٍ نقديٌّ يُدخِل
    // نقداً الدرجَ فيستلزم ورديّةً مفتوحةً عليه. الموضوعُ هنا رفضُ عكسِ
    // الاسترداد عند قصورِ الرصيد، فالورديّةُ تهيئةٌ لا فرضيّة.
    await db.openShift(1, 0);
    // Mark the invoice as PAID so the original return triggers the cash
    // refund branch (safe balance grows by the refund amount).
    const paidTotal = 1000.0;
    final invoiceId = await db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: 'P-EDIT-PAID-${DateTime.now().microsecondsSinceEpoch}',
            supplierId: supplierId,
            warehouseId: warehouseId,
            invoiceDate: DateTime(2026, 5, 1),
            subtotal: const Value(paidTotal),
            tax: const Value(0),
            total: const Value(paidTotal),
            paid: const Value(paidTotal),
            paymentMethod: const Value('cash'),
            status: const Value('completed'),
          ),
        );
    await db.into(db.purchaseInvoiceItems).insert(
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: invoiceId,
            productId: productId,
            quantity: 10,
            unitCost: 100,
            total: paidTotal,
          ),
        );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 10,
      type: 'purchase',
      referenceType: 'purchase_invoice',
      referenceId: invoiceId,
      unitCost: 100,
    );
    final invoice = (await db.getPurchaseInvoiceById(invoiceId))!;

    // Original return for 5 units → 500 cash refund into the safe.
    await repo.processPurchaseReturn(
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
    );

    // Drain the safe so it can't cover the un-refund (500).
    await db.updateSafeBalance(cashSafeId, 100);

    // Edit attempt must fail closed with the Arabic safe-shortage message.
    await expectLater(
      () => repo.editPurchaseReturn(
        invoice: invoice,
        newReturnItems: [
          PurchaseReturnItem(
            itemId: 0,
            productId: productId,
            returnQuantity: 3,
            unitCost: 100,
            taxAmount: 0,
            originalQuantity: 10,
          ),
        ],
      ),
      throwsA(isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains('رصيد الخزنة'),
      )),
    );
  });
}

/// Read the parties.balance column for assertions. The repo wires
/// adjustPartyBalance through this same column.
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
      'Stub: ${inv.memberName} not expected in purchase-return-edit tests');
}

class _ThrowingTreasuryRepo implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
          String referenceType, int referenceId) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in purchase-return-edit tests');
}

class _ThrowingProductRepo implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in purchase-return-edit tests');
}

class _ThrowingInventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in purchase-return-edit tests');
}

class _ThrowingSettingsRepo implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in purchase-return-edit tests');
}

class _ThrowingAuditRepo implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in purchase-return-edit tests');
}
