// ═══════════════════════════════════════════════════════════════════════════
// Feature 006 #6 — Supplier ledger surfaces purchase returns
// ═══════════════════════════════════════════════════════════════════════════
//
// Pre-fix: server-side postPurchaseReturn adjusted parties.balance for the
// unpaid portion but never wrote a safe_transactions memo row. Result —
// the supplier ledger had no line item explaining the change AND the
// opening-balance calculation (which subtracts purchase_return_balance
// memos) drifted.
//
// We don't drive the HTTP handler from the test (that needs a full shelf
// stack); we exercise getPartyStatement directly with the same memo-row
// shape the handler now writes after the fix.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branchId;
  late int warehouseId;
  late int supplierId;
  late int safeId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'main',
            globalId: const Value('gid-br-main'),
          ),
        );
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'main-wh',
            branchId: Value(branchId),
            globalId: const Value('gid-wh-main'),
          ),
        );
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'Acme Supplier',
            isSupplier: const Value(true),
            isCustomer: const Value(false),
            globalId: const Value('gid-supplier-acme'),
          ),
        );
    safeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'cash-main',
            branchId: Value(branchId),
            globalId: const Value('gid-safe-cash-main'),
          ),
        );
  });

  tearDown(() => db.close());

  Future<int> seedPurchase({required double total}) {
    return db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: 'P-${DateTime.now().microsecondsSinceEpoch}',
            supplierId: supplierId,
            warehouseId: warehouseId,
            invoiceDate: DateTime(2026, 5, 1),
            subtotal: Value(total),
            tax: const Value(0),
            total: Value(total),
            paid: const Value(0),
            paymentMethod: const Value('credit'),
          ),
        );
  }

  Future<void> seedPurchaseReturnMemo({
    required int invoiceId,
    required double amount,
  }) async {
    // This mirrors what api_purchase_handler.dart now inserts post-fix.
    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: 'PRET-${DateTime.now().microsecondsSinceEpoch}',
            safeId: safeId,
            transactionType: 'memo',
            category: 'purchase_return_balance',
            amount: amount,
            balanceAfter: 0,
            referenceType: const Value('purchase_return'),
            referenceId: Value(invoiceId),
            partyId: Value(supplierId),
            description: const Value('تسوية رصيد مرتجع مشتريات'),
          ),
        );
    // Mirror the handler's adjustPartyBalance call.
    await db.adjustPartyBalance(supplierId, -amount);
  }

  test('purchase return memo surfaces as a debit line in supplier ledger',
      () async {
    final invId = await seedPurchase(total: 1000);
    await seedPurchaseReturnMemo(invoiceId: invId, amount: 300);

    final entries = await db.getPartyStatement(supplierId);

    expect(entries, hasLength(2),
        reason: 'invoice + return memo both visible');

    final invoiceEntry = entries.firstWhere((e) => e.entryType == 'purchase');
    expect(invoiceEntry.credit, 1000);
    expect(invoiceEntry.debit, 0);

    final returnEntry = entries.firstWhere((e) => e.entryType == 'memo');
    expect(returnEntry.debit, 300,
        reason: 'memo for purchase return must show as debit (reduces AP credit)');
    expect(returnEntry.credit, 0);
    expect(returnEntry.description, contains('مرتجع مشتريات'));
  });

  test('running balance subtracts the return amount from supplier credit',
      () async {
    final invId = await seedPurchase(total: 1000);
    await seedPurchaseReturnMemo(invoiceId: invId, amount: 300);

    final entries = await db.getPartyStatement(supplierId);
    final last = entries.last;
    expect(last.balance, 700,
        reason: '1000 invoice − 300 return = 700 still owed to supplier');
  });

  test('without the memo (pre-fix behaviour) running balance overstates AP',
      () async {
    // Deliberately skip the memo: only adjust party.balance like the buggy
    // server path used to. The ledger's opening-balance calculation should
    // expose the drift — invoice credit goes in but no debit comes out.
    final invId = await seedPurchase(total: 1000);
    await db.adjustPartyBalance(supplierId, -300);
    expect(invId, isNotNull);

    final entries = await db.getPartyStatement(supplierId);
    final last = entries.last;
    expect(last.balance, 1000,
        reason: 'without the memo the ledger thinks we still owe the full 1000 — '
            'this is the bug the fix addresses');
  });
}
