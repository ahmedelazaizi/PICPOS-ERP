// PR-2 (pre-deploy remediation batch B6) — purchase-invoice void reversal
// journal entry carries a deterministic globalId (R9).
//
// Root cause fixed by this batch: PurchasesRepositoryImpl.voidInvoice /
// deleteInvoice called `_db.voidPurchaseInvoice` UNCONDITIONALLY, even in
// client/mirror mode — writing the full stock/AP/treasury/GL reversal
// LOCALLY, never telling the server, with the reversal JE carrying NO
// globalId at all. The next DeltaPull then re-asserted the still-active
// invoice from HQ, leaving the local reversal permanently orphaned.
//
// This suite pins the DAO-level half of the fix (deterministic reversal-JE
// identity — see purchase_dao.dart::voidPurchaseInvoice), which both the
// new client-mode server submit AND the standalone/server path rely on to
// converge on ONE reversal JE row instead of two. The client-mode network
// submit path itself (ClientWriteInterceptor.submitVoidPurchase) is NOT
// covered here — it depends on ServerProxy/NetworkService.buildServerUrl(),
// which reads SharedPreferences and isn't safely fakeable from a bare
// `flutter_test` unit test without a platform-channel mock + injectable
// proxy that doesn't exist yet in this codebase (grep confirmed no
// Fake/Mock ServerProxy or ClientWriteInterceptor anywhere under test/).
// See the batch report for the full rationale.

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/utils/journal_entry_gid.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int supplierId;
  late int warehouseId;
  late int inventoryAccountId;
  late int payableAccountId;

  setUp(() async {
    db = AppDatabase.forTesting();

    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'Main Warehouse',
            isDefault: const Value(true),
          ),
        );
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'Void-Test Supplier',
            isSupplier: const Value(true),
          ),
        );
    inventoryAccountId = await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            code: 'INV-VOID-TEST',
            name: 'Inventory (void test)',
            accountType: 'asset',
            accountNature: const Value('debit'),
            normalBalance: const Value('debit'),
            level: const Value(1),
            balance: const Value(0),
            isSystem: const Value(false),
          ),
        );
    payableAccountId = await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            code: 'AP-VOID-TEST',
            name: 'Payables (void test)',
            accountType: 'liability',
            accountNature: const Value('credit'),
            normalBalance: const Value('credit'),
            level: const Value(1),
            balance: const Value(0),
            isSystem: const Value(false),
          ),
        );
  });

  tearDown(() => db.close());

  /// Seeds a purchase invoice that is already locked + auto-posted (mirrors
  /// the state a real invoice reaches after createPurchaseInvoice/
  /// autoPostPurchase), with a BALANCED 2-line original JE so
  /// voidPurchaseInvoice's swap-debit/credit reversal also balances.
  /// Deliberately PARTIALLY paid (not fully paid) so the isPaidInFull
  /// critical-op permission gate never triggers — out of scope here.
  ///
  /// Dates use `DateTime.now()` (not a hardcoded calendar date) because
  /// `AppDatabase.forTesting()`'s `beforeOpen` self-heal
  /// (`database_startup.dart::ensureOpenFiscalYear`) auto-creates a fiscal
  /// year spanning Jan 1 – Dec 31 of whatever year the test actually runs
  /// in — both this invoice's date AND the reversal JE's `DateTime.now()`
  /// (posted inside voidPurchaseInvoice) must fall inside that same window
  /// or `validateFinancialPeriod` throws "no fiscal year covers this date".
  Future<int> seedLockedInvoiceWithPostedJe(String invoiceGlobalId) async {
    final now = DateTime.now();
    final invoiceId = await db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: 'PUR-VOID-$invoiceGlobalId',
            supplierId: supplierId,
            warehouseId: warehouseId,
            invoiceDate: now,
            total: const Value(100.0),
            paid: const Value(40.0),
            status: const Value('partial'),
            isLocked: const Value(true),
            globalId: Value(invoiceGlobalId),
          ),
        );

    final origEntryId = await db.into(db.journalEntries).insert(
          JournalEntriesCompanion.insert(
            entryNumber: 'JE-ORIG-$invoiceGlobalId',
            entryDate: now,
            description: const Value('قيود مشتريات تجريبية'),
            referenceType: const Value('purchase_invoice'),
            referenceId: Value(invoiceId),
            isAutoPosted: const Value(true),
            globalId: Value('je-orig-$invoiceGlobalId'),
          ),
        );
    await db.into(db.journalEntryLines).insert(
          JournalEntryLinesCompanion.insert(
            entryId: origEntryId,
            accountId: inventoryAccountId,
            debit: const Value(100.0),
            credit: const Value(0),
          ),
        );
    await db.into(db.journalEntryLines).insert(
          JournalEntryLinesCompanion.insert(
            entryId: origEntryId,
            accountId: payableAccountId,
            debit: const Value(0),
            credit: const Value(100.0),
          ),
        );

    return invoiceId;
  }

  Future<List<JournalEntryData>> reversalJesFor(int invoiceId) =>
      (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('purchase_invoice_void') &
                e.referenceId.equals(invoiceId)))
          .get();

  group('PR-2 / R9 — voidPurchaseInvoice reversal JE globalId', () {
    test(
        'no explicit globalId → reversal JE derives je-purchase-<invoiceGlobalId>-void',
        () async {
      final invoiceId = await seedLockedInvoiceWithPostedJe('inv-gid-A');

      await db.voidPurchaseInvoice(invoiceId);

      final reversalJes = await reversalJesFor(invoiceId);
      expect(reversalJes, hasLength(1),
          reason: 'exactly one reversal JE must be posted for the void');
      final expectedGid = JournalEntryGid.compute(
        sourceType: JournalEntryGid.sourcePurchase,
        sourceGid: 'inv-gid-A',
        verb: 'void',
      );
      expect(reversalJes.first.globalId, expectedGid,
          reason: 'deterministic gid derived from the invoice\'s own '
              'globalId — client/mirror and server must converge on this '
              'SAME value without needing to coordinate a random id');

      // Invoice ends up voided AND soft-deleted (long-standing "Phase 4"
      // behavior — void sets status='voided' + isDeleted=true together).
      // Query the row directly: getPurchaseInvoiceById filters
      // isDeleted=false, so it (correctly) returns null for a voided invoice.
      final invoice = await (db.select(db.purchaseInvoices)
            ..where((i) => i.id.equals(invoiceId)))
          .getSingle();
      expect(invoice.status, 'voided');
      expect(invoice.isDeleted, isTrue,
          reason: 'void soft-deletes the invoice for the audit trail');
    });

    test(
        'caller-supplied globalId overrides the derived value — threads the '
        'SAME id the repo sent to the server submit (R9)', () async {
      final invoiceId = await seedLockedInvoiceWithPostedJe('inv-gid-B');
      const callerGid = 'explicit-void-op-gid-xyz';

      await db.voidPurchaseInvoice(invoiceId, globalId: callerGid);

      final reversalJes = await reversalJesFor(invoiceId);
      expect(reversalJes, hasLength(1));
      expect(reversalJes.first.globalId, callerGid,
          reason: 'the caller-minted globalId (threaded into the server '
              'submit in client/mirror mode) must land verbatim on the '
              'local/standalone reversal JE too, so both sides use the '
              'identical identity');
    });

    test('re-voiding is an idempotent no-op and does NOT double-post',
        () async {
      final invoiceId = await seedLockedInvoiceWithPostedJe('inv-gid-C');
      await db.voidPurchaseInvoice(invoiceId);
      expect(await reversalJesFor(invoiceId), hasLength(1));

      // A retry (outbox replay / duplicate server submit) hits an invoice
      // that void already soft-deleted: getPurchaseInvoiceById returns null
      // and voidPurchaseInvoice short-circuits (silent no-op) BEFORE any
      // second reversal is attempted. The invariant the server-side
      // idempotency short-circuit relies on is "no second reversal JE" — it
      // holds here whether the retry throws or returns silently.
      await db.voidPurchaseInvoice(invoiceId, globalId: 'a-different-gid');
      expect(await reversalJesFor(invoiceId), hasLength(1),
          reason: 'the idempotent retry must not post a second reversal JE');
    });
  });
}
