// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 — A-03: voidSalesInvoice must reverse the sale ATOMICALLY.
// ═══════════════════════════════════════════════════════════════════════════
//
// Bug (finding A-03): voidSalesInvoice reverses stock, treasury and the
// customer AR, then posts the reversal journal entry inside a try/catch that
// did NOT rethrow ("the void itself is NOT rolled back"). When
// createJournalEntry throws (closed period, missing 4319 rounding account, a
// view/unmapped account line), the surrounding db.transaction() still COMMITTED
// the subledger reversals while the original sale JE stayed live → GL diverges
// permanently from stock/treasury/AR (there is no auto-repair for
// 'sales_invoice_void').
//
// Red rules exercised: R3 (multi-step reversal must be atomic — all-or-nothing)
// and fail-loud (a failed reversal must never be swallowed).
//
// Test strategy
// -------------
// 1. RED anchor — INJECTED reversal-JE failure. Post a normal cash sale (which
//    auto-posts a balanced 'sale' JE and locks the invoice), then flip one of
//    that JE's accounts to accountNature='view'. createJournalEntry refuses to
//    post to a parent/'view' account (accounting_dao_writes.dart guard), so the
//    void's reversal JE throws — exactly the class of failure A-03 describes.
//    We assert all-or-nothing: the void THROWS, the invoice is NOT voided, and
//    stock + treasury are NOT half-reversed. Under the OLD swallow this test
//    fails on every axis (void committed silently, no throw). Under the fix the
//    whole transaction rolls back.
// 2. GREEN control — success path is unchanged AND the reversal is symmetric:
//    a normal void restores stock + treasury, marks the invoice voided, and
//    posts a balanced 'sales_invoice_void' JE whose lines net the original sale
//    JE to zero for every account (GL returns to its pre-sale state).
//
// Harness mirrors test/integration/pir_void_invoice_test.dart (full
// forTesting() seed) + the standalone-mode discipline of
// test/unit/je_deterministic_balancing_test.dart.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/network_service.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int productId;
  late int cashSafeId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'void_atomic',
      password: 'test123',
      displayName: 'Void Atomicity Tester',
      roleId: roleId,
    );

    // Spec 062: grant the void-paid-invoice critical-op permission so the gate
    // in voidSalesInvoice lets us void fully-paid invoices.
    final voidPerm = await (db.select(db.permissions)
          ..where((p) => p.code.equals(PermissionCodes.voidPaidInvoice))
          ..limit(1))
        .getSingle();
    await db.addPermissionToRole(roleId, voidPerm.id);

    warehouseId = (await db.getDefaultWarehouse())!.id;
    cashSafeId = (await db.getDefaultSafeByType('cash'))!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'VOID-ATOM-01',
        name: 'منتج ذرية الإلغاء',
        salePrice: const Value(200.0),
        costPrice: const Value(120.0),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100.0,
      type: 'adjustment',
    );

    // Standalone → createJournalEntry / autopost take the local path, no sync.
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    await db.close();
  });

  // Helper: read the auto-posted sale JE for an invoice (same predicate the
  // void uses to find the entry it reverses).
  Future<JournalEntryData?> saleJEFor(int invoiceId) {
    return (db.select(db.journalEntries)
          ..where((e) =>
              (e.referenceType.equals('sale') |
                  e.referenceType.equals('sales_invoice')) &
              e.referenceId.equals(invoiceId) &
              e.isAutoPosted.equals(true))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<JournalEntryLine>> linesOf(int entryId) {
    return (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(entryId)))
        .get();
  }

  Future<double> stockOf() async => (await db.getProductById(productId))!.currentStock;
  Future<double> cashBalance() async =>
      (await (db.select(db.safes)..where((s) => s.id.equals(cashSafeId)))
              .getSingle())
          .balance;

  Future<int> postCashSale({
    required String number,
    required double qty,
    required double unitPrice,
  }) {
    final total = qty * unitPrice;
    return db.createSalesInvoice(
      invoiceNumber: number,
      warehouseId: warehouseId,
      userId: userId,
      subtotal: total,
      discount: 0.0,
      tax: 0.0,
      total: total,
      paid: total,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: qty,
          unitPrice: unitPrice,
          total: total,
        ),
      ],
    );
  }

  group('Spec 151 A-03 — void is atomic (all-or-nothing) and fails loud', () {
    test(
        'injected reversal-JE failure rolls back the ENTIRE void '
        '(stock + treasury NOT half-reversed, invoice stays active, throws)',
        () async {
      final invoiceId = await postCashSale(number: 'VATOM-FAIL', qty: 10, unitPrice: 200);

      // Post-sale baseline: stock reduced, cash elevated, sale JE posted+locked.
      final stockAfterSale = await stockOf();
      final cashAfterSale = await cashBalance();
      expect(stockAfterSale, 90.0, reason: 'sale should reduce stock by 10');

      final je = await saleJEFor(invoiceId);
      expect(je, isNotNull, reason: 'cash sale must auto-post a JE');
      final jeLines = await linesOf(je!.id);
      expect(jeLines, isNotEmpty);

      final inv0 = await (db.select(db.salesInvoices)
            ..where((i) => i.id.equals(invoiceId)))
          .getSingle();
      expect(inv0.isLocked, isTrue, reason: 'autopost must lock the invoice');

      // INJECT the failure: turn an account referenced by the sale JE into a
      // parent/'view' account. createJournalEntry refuses to post the reversal
      // to it → the reversal JE throws inside voidSalesInvoice.
      final poisonedAccountId = jeLines.first.accountId;
      await (db.update(db.accounts)
            ..where((a) => a.id.equals(poisonedAccountId)))
          .write(const AccountsCompanion(accountNature: Value('view')));

      // The void must surface the failure, not swallow it.
      await expectLater(
        db.voidSalesInvoice(invoiceId, reason: 'اختبار ذرية', deletedBy: userId),
        throwsA(anything),
        reason: 'a failed reversal JE must propagate, not be swallowed',
      );

      // All-or-nothing: nothing about the void persisted.
      final invAfter = await (db.select(db.salesInvoices)
            ..where((i) => i.id.equals(invoiceId)))
          .getSingle();
      expect(invAfter.status, isNot('voided'),
          reason: 'invoice must NOT be marked voided when the reversal fails');
      expect(invAfter.isDeleted, isFalse,
          reason: 'invoice must NOT be soft-deleted when the reversal fails');

      expect(await stockOf(), stockAfterSale,
          reason: 'stock must NOT be restored (would be a half-reversal)');
      expect(await cashBalance(), cashAfterSale,
          reason: 'treasury must NOT be reversed (would be a half-reversal)');

      final voidJEs = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('sales_invoice_void') &
                e.referenceId.equals(invoiceId)))
          .get();
      expect(voidJEs, isEmpty, reason: 'no reversal JE should be committed');

      // The original sale JE is still live (nothing reversed it).
      expect(await saleJEFor(invoiceId), isNotNull,
          reason: 'the original sale JE must remain untouched after rollback');
    });

    test(
        'success path unchanged: void restores stock + treasury, marks voided, '
        'and posts a balanced reversal JE that nets the sale JE to zero',
        () async {
      final stockBaseline = await stockOf();
      final cashBaseline = await cashBalance();

      final invoiceId = await postCashSale(number: 'VATOM-OK', qty: 5, unitPrice: 100);
      final saleJE = await saleJEFor(invoiceId);
      expect(saleJE, isNotNull);
      final saleLines = await linesOf(saleJE!.id);

      await db.voidSalesInvoice(invoiceId, reason: 'عكس ناجح', deletedBy: userId);

      // Subledgers restored.
      final inv = await (db.select(db.salesInvoices)
            ..where((i) => i.id.equals(invoiceId)))
          .getSingle();
      expect(inv.status, 'voided');
      expect(inv.isDeleted, isTrue);
      expect(await stockOf(), stockBaseline, reason: 'stock fully restored');
      expect(await cashBalance(), cashBaseline, reason: 'cash fully reversed');

      // A balanced reversal JE exists.
      final voidJE = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('sales_invoice_void') &
                e.referenceId.equals(invoiceId))
            ..limit(1))
          .getSingleOrNull();
      expect(voidJE, isNotNull, reason: 'a reversal JE must be posted');
      final voidLines = await linesOf(voidJE!.id);
      final vDr = voidLines.fold<double>(0, (s, l) => s + l.debit);
      final vCr = voidLines.fold<double>(0, (s, l) => s + l.credit);
      expect(vDr, closeTo(vCr, 1e-6), reason: 'reversal JE must balance');

      // GL nets to zero: for every account, (sale ± reversal) debit−credit == 0.
      final net = <int, double>{};
      for (final l in saleLines) {
        net[l.accountId] = (net[l.accountId] ?? 0) + l.debit - l.credit;
      }
      for (final l in voidLines) {
        net[l.accountId] = (net[l.accountId] ?? 0) + l.debit - l.credit;
      }
      for (final entry in net.entries) {
        expect(entry.value, closeTo(0, 1e-6),
            reason: 'account ${entry.key} must net to zero after the reversal');
      }
    });
  });
}
