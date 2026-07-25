// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 — W2-F finding F-02 (MAJOR)
// ═══════════════════════════════════════════════════════════════════════════
//
// updatePurchaseInvoice (edit-in-place of a posted purchase) used to move
// stock/WAC and the supplier balance to the NEW amounts but:
//   (a) NEVER reversed / re-posted the purchase GL journal entry — the JE
//       stayed frozen at the OLD amounts ("Handle payment difference in
//       treasury (simplified - just log if changed)"), so the inventory / AP
//       GL diverged from inventory_balances and the supplier subledger; and
//   (b) NEVER reversed the original safe/treasury payment — the safe was
//       never adjusted for the payment delta.
//
// The fix mirrors the sales sibling (SalesRepositoryImpl.updateFullSalesInvoice):
//   • reverse the old purchase JE (delete entry + lines, recompute the affected
//     account balances) then re-post via autoPostPurchase with the new header;
//   • reverse the original payment safe_transaction(s) + restore safes.balance,
//     then re-record the payment for the new `paid` — all in ONE transaction (R3).
//
// This test asserts the post-edit GL reflects the NEW totals (inventory Dr ==
// new subtotal, AP Cr == new remaining, JE balanced), the supplier balance and
// safe balance are correct, and inventory/WAC are consistent. Pre-fix, the
// inventory GL account would still read the OLD subtotal and the safe would
// never have moved — both assertions below fail.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

/// Id of the seeded `admin` user (role_id 1 = مدير النظام), who holds
/// `purchases_edit` via the system-admin bypass.
///
/// `updatePurchaseInvoice` now gates EVERY edit on `purchases_edit` and denies
/// a null identity — the policy is "holds the permission → unlimited edits,
/// posted or not; lacks it → no edit at all". These tests deliberately edit a
/// POSTED invoice, so they must act as a permitted user.
Future<int> _permittedEditorId(AppDatabase db) async {
  final row = await db
      .customSelect("SELECT id FROM users WHERE username = 'admin' LIMIT 1")
      .getSingle();
  return row.read<int>('id');
}

void main() {
  late AppDatabase db;
  late int branchId;
  late int warehouseId;
  late int supplierId;
  late int safeId;
  const double initialSafeBalance = 10000.0;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'main-f02',
            globalId: const Value('gid-br-f02'),
          ),
        );
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'wh-f02',
            branchId: Value(branchId),
            globalId: const Value('gid-wh-f02'),
          ),
        );
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'مورد F02',
            isSupplier: const Value(true),
            isCustomer: const Value(false),
            globalId: const Value('gid-supplier-f02'),
          ),
        );

    // Deterministic single default cash safe with a known opening balance so
    // the payment delta assertion is unambiguous.
    await db.delete(db.safes).go();
    safeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'F02 Cash Safe',
            safeType: const Value('cash'),
            isDefault: const Value(true),
            isActive: const Value(true),
            balance: const Value(initialSafeBalance),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<int> makeProduct(String code) {
    return db.insertProduct(
      ProductsCompanion.insert(
        code: code,
        name: 'منتج F02 $code',
        salePrice: const Value(200.0),
        costPrice: const Value(0.0),
        currentStock: const Value(0),
        trackInventory: const Value(true),
      ),
    );
  }

  // Sum of a JE's lines by predicate over its journal_entry_lines.
  Future<List<JournalEntryLine>> jeLines(int entryId) => (db
          .select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entryId)))
      .get();

  test(
      'edit that changes qty + paid reverses & re-posts the purchase JE (GL == '
      'new amounts, balanced) and adjusts the safe for the payment delta',
      () async {
    final productId = await makeProduct('F02-1');

    // ── ORIGINAL: pure-credit purchase, qty 10 @ 100, tax 0 → total 1000,
    //    paid 0. Creation posts inventory Dr 1000 / AP Cr 1000; safe untouched.
    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0.0,
      paymentMethod: 'credit',
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    final inventoryAcc = (await db.getAccountByCode('1136'))!;
    final cashAcc = (await db.getAccountByCode('1111'))!;

    // Sanity on the ORIGINAL posting.
    expect((await db.getAccountByCode('1136'))!.balance, closeTo(1000, 0.001),
        reason: 'creation debits inventory 1000');
    expect(
        (await (db.select(db.parties)..where((p) => p.id.equals(supplierId)))
                .getSingle())
            .balance,
        closeTo(1000, 0.001),
        reason: 'creation credits the supplier subledger 1000');
    expect((await db.getSafeById(safeId))!.balance,
        closeTo(initialSafeBalance, 0.001),
        reason: 'no payment at creation → safe untouched');

    // ── EDIT: qty 15 @ 100 → total 1500, and pay 400 (method credit → routes
    //    to the cash safe + an AP leg for the remaining 1100).
    await db.updatePurchaseInvoice(
      invoiceId: invoiceId,
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 400.0,
      paymentMethod: 'credit',
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: invoiceId,
          productId: productId,
          quantity: 15,
          unitCost: 100,
          total: 1500,
        ),
      ],
      userId: await _permittedEditorId(db),
    );

    // (1) Exactly ONE live purchase JE for the invoice, and it is the re-post
    //     (referenceType 'purchase'), not the stale 'purchase_invoice' one.
    final purchaseJes = await (db.select(db.journalEntries)
          ..where((e) =>
              (e.referenceType.equals('purchase') |
                  e.referenceType.equals('purchase_invoice')) &
              e.referenceId.equals(invoiceId)))
        .get();
    expect(purchaseJes, hasLength(1),
        reason: 'old JE reversed, exactly one re-posted JE remains');
    final je = purchaseJes.single;

    // (2) The re-posted JE balances and totals the NEW amount (1500).
    final lines = await jeLines(je.id);
    final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
    final totalCredit = lines.fold<double>(0, (s, l) => s + l.credit);
    expect(totalDebit, closeTo(totalCredit, 0.001),
        reason: 'the re-posted purchase JE must balance');
    expect(totalDebit, closeTo(1500, 0.001),
        reason: 'JE reflects the NEW total, not the old 1000');

    // (3) Inventory Dr == new subtotal (1500).
    final invLine = lines.firstWhere((l) => l.accountId == inventoryAcc.id);
    expect(invLine.debit, closeTo(1500, 0.001));

    // (4) البند 6 (owner-approved 2026-07-25) — the purchase JE now routes the
    //     WHOLE total through the supplier payable; the cash leg moved out to
    //     the payment voucher's own JE (Dr payable / Cr the paying safe's
    //     account). The ledger-level outcome is unchanged: net AP == remaining,
    //     net cash == paid. Pre-change this JE carried a cash line directly.
    expect(lines.where((l) => l.accountId == cashAcc.id), isEmpty,
        reason: 'البند 6: the purchase JE no longer credits cash directly — '
            'the settlement leg lives on the payment voucher');
    final apCredit = lines
        .where((l) => l.accountId != inventoryAcc.id)
        .fold<double>(0, (s, l) => s + l.credit);
    expect(apCredit, closeTo(1500, 0.001),
        reason: 'payables leg credits the FULL new total (pass-through)');

    // (4b) Net ledger position is what actually matters, and it is unchanged:
    //      supplier still owes 1100, cash still moved 400.
    Future<double> netByCodePrefix(String prefix) async {
      final r = await db.customSelect(
        'SELECT COALESCE(SUM(l.debit),0) - COALESCE(SUM(l.credit),0) AS n '
        'FROM journal_entry_lines l JOIN accounts a ON a.id = l.account_id '
        "WHERE a.code LIKE '$prefix%'",
      ).getSingle();
      return (r.data['n'] as num).toDouble();
    }

    expect(await netByCodePrefix('2111'), closeTo(-1100, 0.001),
        reason: 'net payable == new remaining');
    expect(await netByCodePrefix('1111'), closeTo(-400, 0.001),
        reason: 'net cash credited == new paid');

    // (5) Inventory GL ACCOUNT balance updated to the new subtotal — the core
    //     of F-02: pre-fix this stayed at the old 1000.
    expect((await db.getAccountByCode('1136'))!.balance, closeTo(1500, 0.001),
        reason: 'F-02: inventory GL account must track the edited amount');

    // (6) Supplier subledger == new remaining (1100).
    final supplierAfter =
        await (db.select(db.parties)..where((p) => p.id.equals(supplierId)))
            .getSingle();
    expect(supplierAfter.balance, closeTo(1100, 0.001));

    // (7) Safe adjusted for the payment delta: 0 → 400, so balance drops by 400.
    expect((await db.getSafeById(safeId))!.balance,
        closeTo(initialSafeBalance - 400, 0.001),
        reason: 'F-02: safe must move by (newPaid − oldPaid) = 400');

    // (8) Exactly ONE purchase-payment safe_transaction survives for the new
    //     payment (old ones reversed away).
    final payTxns = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals('purchase_invoice') &
              t.referenceId.equals(invoiceId) &
              t.transactionType.equals('payment')))
        .get();
    expect(payTxns, hasLength(1));
    expect(payTxns.single.amount, closeTo(400, 0.001));

    // (9) Inventory / WAC consistent with the NEW line (qty 15 @ 100).
    final product = (await db.getProductById(productId))!;
    expect(product.currentStock, closeTo(15, 0.001),
        reason: 'old 10 reversed, new 15 added');
    expect(product.costPrice, closeTo(100, 0.001),
        reason: 'WAC unchanged — same unit cost');
  });

  // ───────────────────────────────────────────────────────────────────────
  // F02-1 (BLOCKER): a prior addPurchasePayment posts a SEPARATE, balanced GL
  // 'payment' JE (Dr payables / Cr cash) keyed on the safe_txn id. On edit the
  // pre-fix _reverseOldPurchasePayment reversed the payment SAFE row but NOT
  // that GL 'payment' JE; autoPostPurchase then re-credited cash for the full
  // invoice.paid → cash credited TWICE and payables under-credited (the JE was
  // double-counted). The fix mirror-reverses the 'payment' JE inside the same
  // transaction. This test asserts the GL cash account nets to the ACTUAL total
  // paid, payables to the true remaining, and safe movement == GL cash movement.
  // Pre-fix: cash GL = -800 (not -400), payables = -200 (not -600) → FAILS.
  // ───────────────────────────────────────────────────────────────────────
  test(
      'edit after an addPurchasePayment does NOT double-count the payment GL '
      '(cash credit == actual paid, payables == remaining, safe == GL cash)',
      () async {
    final productId = await makeProduct('F02-DBL');

    // ORIGINAL: pure-credit purchase, qty 10 @ 100 → total 1000, paid 0.
    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0.0,
      paymentMethod: 'credit',
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    // A LATER partial payment of 400 → posts a SEPARATE GL 'payment' JE
    // (Dr payables 400 / Cr cash 400) and debits the default cash safe by 400.
    await db.addPurchasePayment(
      invoiceId: invoiceId,
      amount: 400.0,
      paymentMethod: 'cash',
    );

    expect((await db.getSafeById(safeId))!.balance,
        closeTo(initialSafeBalance - 400, 0.001),
        reason: 'payment debited the cash safe by 400');
    expect((await db.getAccountByCode('1111'))!.balance, closeTo(-400, 0.001),
        reason: 'payment JE credited cash 400 (net credit 400)');

    // EDIT: keep the same line and the same paid (400). The re-post must NOT
    // credit cash a second time on top of the still-live 'payment' JE.
    await db.updatePurchaseInvoice(
      invoiceId: invoiceId,
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 400.0,
      paymentMethod: 'credit',
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: invoiceId,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
      userId: await _permittedEditorId(db),
    );

    // (1) F02-1 core: cash GL nets to the ACTUAL total paid (400), NOT 800.
    final cashBalance = (await db.getAccountByCode('1111'))!.balance;
    expect(cashBalance, closeTo(-400, 0.001),
        reason: 'F02-1: cash credited once (400), not double-counted (800)');

    // (2) Payables (supplier has no sub-account → routes to control 2111) nets
    //     to the true remaining (600), NOT the double-counted 200.
    expect((await db.getAccountByCode('2111'))!.balance, closeTo(-600, 0.001),
        reason: 'F02-1: payables Cr == remaining 600, not under-credited 200');

    // (3) Inventory GL tracks the (unchanged) subtotal 1000.
    expect((await db.getAccountByCode('1136'))!.balance, closeTo(1000, 0.001));

    // (4) Safe balance movement == GL cash movement: safe moved out 400, and
    //     the GL cash account net credit is 400. Pre-fix cash moved 800 ≠ 400.
    final safeAfter = (await db.getSafeById(safeId))!.balance;
    final safeOutflow = initialSafeBalance - safeAfter; // 400
    final glCashCredit = -cashBalance; // 400 post-fix, 800 pre-fix
    expect(safeAfter, closeTo(initialSafeBalance - 400, 0.001),
        reason: 'net one payment of 400 out of the safe');
    expect(glCashCredit, closeTo(safeOutflow, 0.001),
        reason: 'F02-1: GL cash movement must equal the real safe outflow');

    // (5) Exactly ONE live purchase-payment safe_transaction survives.
    final payTxns = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals('purchase_invoice') &
              t.referenceId.equals(invoiceId) &
              t.transactionType.equals('payment')))
        .get();
    expect(payTxns, hasLength(1));
    expect(payTxns.single.amount, closeTo(400, 0.001));
  });

  // ───────────────────────────────────────────────────────────────────────
  // F02-2 (MAJOR): a payment made from a NON-DEFAULT safe must be re-recorded
  // onto the SAME safe on edit. Pre-fix the update-path re-record omitted
  // safeId, so the original safe was reversed but the re-record fell back to
  // the global default safe → per-safe misallocation. The fix threads the
  // original payment's safeId through. Pre-fix: non-default safe stays at
  // initial and the DEFAULT safe is (wrongly) debited → both asserts FAIL.
  // ───────────────────────────────────────────────────────────────────────
  test(
      'edit re-records the payment onto the ORIGINAL non-default safe, not the '
      'default one', () async {
    final productId = await makeProduct('F02-SAFE');

    // A second, NON-default cash safe with the same opening balance.
    final nonDefaultSafeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'F02 Secondary Cash',
            safeType: const Value('cash'),
            isDefault: const Value(false),
            isActive: const Value(true),
            balance: const Value(initialSafeBalance),
          ),
        );

    // ORIGINAL: qty 10 @ 100 → 1000, paid 400 FROM the non-default safe.
    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 400.0,
      paymentMethod: 'credit',
      safeId: nonDefaultSafeId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    expect((await db.getSafeById(nonDefaultSafeId))!.balance,
        closeTo(initialSafeBalance - 400, 0.001),
        reason: 'creation debited the non-default safe');
    expect((await db.getSafeById(safeId))!.balance,
        closeTo(initialSafeBalance, 0.001),
        reason: 'default safe untouched at creation');

    // EDIT: same line, same paid — updatePurchaseInvoice takes NO safeId, so the
    // re-record must honour the ORIGINAL payment's safe (the non-default one).
    await db.updatePurchaseInvoice(
      invoiceId: invoiceId,
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 400.0,
      paymentMethod: 'credit',
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: invoiceId,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
      userId: await _permittedEditorId(db),
    );

    // F02-2: the non-default safe carries the payment (net −400); the default
    // safe stays whole. Pre-fix these are swapped.
    expect((await db.getSafeById(nonDefaultSafeId))!.balance,
        closeTo(initialSafeBalance - 400, 0.001),
        reason: 'F02-2: payment re-recorded onto the ORIGINAL non-default safe');
    expect((await db.getSafeById(safeId))!.balance,
        closeTo(initialSafeBalance, 0.001),
        reason: 'F02-2: default safe must NOT be touched');

    // The payment safe_transaction is on the non-default safe.
    final payTxns = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals('purchase_invoice') &
              t.referenceId.equals(invoiceId) &
              t.transactionType.equals('payment')))
        .get();
    expect(payTxns, hasLength(1));
    expect(payTxns.single.safeId, nonDefaultSafeId);
  });
}
