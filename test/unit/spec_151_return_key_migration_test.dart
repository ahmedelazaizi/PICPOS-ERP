// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 — v150 migration guards for the RETURN journal-entry re-key
// ═══════════════════════════════════════════════════════════════════════════
//
// These lock the three defects an adversarial committee found in the WIP
// return-key change (which the pure spec_151_return_key_test.dart missed
// because AppDatabase.forTesting() historically ran onCreate WITHOUT the
// idx_je_autopost_dedup index):
//
//   1. INDEX BLOCKER — the re-key makes every partial return of one invoice
//      share (reference_type='sales_return', reference_id=invoice.id). The
//      v120 UNIQUE index would reject the 2nd partial return and roll the whole
//      return transaction back. The v150 recreate exempts the return types.
//      A negative control proves the index is genuinely PRESENT and enforced
//      for a non-exempt type — so the return pass-through is the exemption at
//      work, not the index being absent.
//
//   2. BACKFILL — historical hash-keyed return JEs are re-keyed onto their
//      originating invoice id by parsing the invoice number out of the
//      description and matching it WHOLE (never LIKE). Invoice "12" must not
//      cross-match invoice "120" (the F-04 collision).
//
//   3. DOUBLE-CANCEL IDEMPOTENCY — reverseReturnAccountingEntry called twice
//      reverses the GL exactly ONCE (deterministic '<origGid>-rev' guard).
//
// Pure-unit: in-memory AppDatabase.forTesting() + seeded chart of accounts.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // 1 — INDEX BLOCKER regression
  // ─────────────────────────────────────────────────────────────────────────
  group('Spec 151 — idx_je_autopost_dedup exempts return types (BLOCKER)', () {
    late AppDatabase db;
    late int warehouseId;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.syncDefaultAccounts();
      // Make the harness faithful to a real v150 / fresh-install DB: guarantee
      // the return-exempt dedup index is present. Idempotent — onCreate and the
      // ensureSchemaDefaults self-heal may already have created it; this pins
      // it regardless so the BLOCKER can actually be exercised.
      await db.customStatement(kCreateJeAutopostDedupIndexSql);
      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'main-idx',
              globalId: const Value('gid-br-idx'),
            ),
          );
      warehouseId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'wh-idx',
              branchId: Value(branchId),
              globalId: const Value('gid-wh-idx'),
            ),
          );
    });

    tearDown(() async => db.close());

    test(
        'two partial returns of one invoice BOTH post — the shared '
        '(sales_return, invoiceId, is_auto_posted=1) pair is not rejected',
        () async {
      final invoiceId = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'INV-IDX-1',
              warehouseId: warehouseId,
              userId: 1,
              invoiceDate: DateTime.now(),
              subtotal: const Value(1000),
              tax: const Value(0),
              total: const Value(1000),
              paid: const Value(0),
              paymentMethod: const Value('credit'),
              status: const Value('completed'),
              globalId: const Value('gid-inv-idx-1'),
            ),
          );
      final invoice = (await db.getSalesInvoiceById(invoiceId))!;

      // Credit/AR refunds — the path proven by the A-02/A-01 tests to balance
      // with only syncDefaultAccounts seeded (no cash-safe dependency).
      final r1 = await db.autoPostSalesReturn(
        originalInvoice: invoice,
        returnAmount: 300,
        cogsAmount: 150,
        cashRefund: 0,
        bankRefund: 0,
        arRefund: 300,
        returnEventId: 'SRET-IDX-1',
      );
      // The SECOND partial return shares the invoice id — pre-fix this is the
      // row that violated idx_je_autopost_dedup and rolled everything back.
      final r2 = await db.autoPostSalesReturn(
        originalInvoice: invoice,
        returnAmount: 200,
        cogsAmount: 100,
        cashRefund: 0,
        bankRefund: 0,
        arRefund: 200,
        returnEventId: 'SRET-IDX-2',
      );

      expect(r1, isNotNull);
      expect(r2, isNotNull,
          reason: 'the second partial return must NOT be rejected by '
              'idx_je_autopost_dedup — that is the BLOCKER the exemption fixes');

      final jes = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('sales_return')))
          .get();
      expect(jes, hasLength(2),
          reason: 'both distinct partial returns must persist');
      expect(jes.every((e) => e.referenceId == invoice.id), isTrue,
          reason: 'both keyed on the shared originating invoice id');
      expect(jes.map((e) => e.globalId).toSet(), hasLength(2),
          reason: 'per-event uniqueness rides on distinct globalIds');
    });

    test(
        'control: the index IS enforced — a duplicate auto-posted (sale, refId) '
        'direct-insert throws (proves pass-through is the exemption, not '
        'an absent index)', () async {
      Future<void> insertSaleJe(String gid) =>
          db.into(db.journalEntries).insert(
                JournalEntriesCompanion.insert(
                  entryNumber: 'JE-$gid',
                  entryDate: DateTime.now(),
                  referenceType: const Value('sale'),
                  referenceId: const Value(987654),
                  isAutoPosted: const Value(true),
                  globalId: Value(gid),
                ),
              );

      await insertSaleJe('gid-sale-ctl-1');
      await expectLater(
        insertSaleJe('gid-sale-ctl-2'),
        throwsA(anything),
        reason: 'idx_je_autopost_dedup must still reject a second auto-posted '
            'JE for a NON-exempt reference type on the same reference_id',
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2 — BACKFILL: whole-number match, no "12" ↔ "120" cross-match (F-04)
  // ─────────────────────────────────────────────────────────────────────────
  group('Spec 151 — v150 return-JE referenceId backfill (exact, not LIKE)', () {
    late AppDatabase db;
    late int warehouseId;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.syncDefaultAccounts();
      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'main-bf',
              globalId: const Value('gid-br-bf'),
            ),
          );
      warehouseId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'wh-bf',
              branchId: Value(branchId),
              globalId: const Value('gid-wh-bf'),
            ),
          );
    });

    tearDown(() async => db.close());

    // Mirrors the sales branch of the v150 migration backfill VERBATIM so this
    // test locks the exact SQL semantics (extract-after-'فاتورة ' + whole-match
    // + COUNT=1). Kept identical to epoch_3.dart:if (from < 150).
    Future<void> runSalesBackfill() async {
      const marker = 'فاتورة ';
      String extractNo(String col) =>
          "substr($col, instr($col, '$marker') + length('$marker'))";
      await db.customStatement('''
        UPDATE journal_entries
        SET reference_id = (
          SELECT inv.id FROM sales_invoices inv
          WHERE inv.invoice_number = ${extractNo('journal_entries.description')}
        )
        WHERE reference_type = 'sales_return'
          AND is_auto_posted = 1
          AND instr(description, '$marker') > 0
          AND (
            SELECT COUNT(*) FROM sales_invoices inv2
            WHERE inv2.invoice_number = ${extractNo('journal_entries.description')}
          ) = 1
      ''');
    }

    test(
        'invoice "12" and decoy "120": each hash-keyed return JE re-keys to its '
        'OWN invoice id — no substring cross-match', () async {
      final inv12 = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: '12',
              warehouseId: warehouseId,
              userId: 1,
              invoiceDate: DateTime.now(),
              total: const Value(100),
              globalId: const Value('gid-inv-12'),
            ),
          );
      final inv120 = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: '120',
              warehouseId: warehouseId,
              userId: 1,
              invoiceDate: DateTime.now(),
              total: const Value(100),
              globalId: const Value('gid-inv-120'),
            ),
          );

      // Historical hash-keyed return JEs (the pre-fix state): reference_id is
      // an arbitrary hash, invoice number lives only in the description.
      final je12 = await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              entryNumber: 'JE-RET-12',
              entryDate: DateTime.now(),
              description: const Value('قيد مرتجع مبيعات فاتورة 12'),
              referenceType: const Value('sales_return'),
              referenceId: const Value(555001), // stale hash
              isAutoPosted: const Value(true),
              globalId: const Value('gid-je-ret-12'),
            ),
          );
      final je120 = await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              entryNumber: 'JE-RET-120',
              entryDate: DateTime.now(),
              description: const Value('قيد مرتجع مبيعات فاتورة 120'),
              referenceType: const Value('sales_return'),
              referenceId: const Value(555002), // stale hash
              isAutoPosted: const Value(true),
              globalId: const Value('gid-je-ret-120'),
            ),
          );

      await runSalesBackfill();

      final ret12 = await (db.select(db.journalEntries)
            ..where((e) => e.id.equals(je12)))
          .getSingle();
      final ret120 = await (db.select(db.journalEntries)
            ..where((e) => e.id.equals(je120)))
          .getSingle();

      expect(ret12.referenceId, inv12,
          reason: 'the "12" return must re-key to invoice 12 exactly');
      expect(ret120.referenceId, inv120,
          reason: 'the "120" return must re-key to invoice 120 — "12" must NOT '
              'sweep it (the F-04 LIKE collision)');
    });

    test('idempotent: re-running the backfill resolves to the same id',
        () async {
      final inv = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'INV-BF-IDEMP',
              warehouseId: warehouseId,
              userId: 1,
              invoiceDate: DateTime.now(),
              total: const Value(50),
              globalId: const Value('gid-inv-bf-idemp'),
            ),
          );
      final je = await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              entryNumber: 'JE-RET-IDEMP',
              entryDate: DateTime.now(),
              description: const Value('قيد مرتجع مبيعات فاتورة INV-BF-IDEMP'),
              referenceType: const Value('sales_return'),
              referenceId: const Value(777001),
              isAutoPosted: const Value(true),
              globalId: const Value('gid-je-ret-idemp'),
            ),
          );

      await runSalesBackfill();
      await runSalesBackfill(); // second pass must be a no-op / same result

      final row = await (db.select(db.journalEntries)
            ..where((e) => e.id.equals(je)))
          .getSingle();
      expect(row.referenceId, inv);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3 — DOUBLE-CANCEL idempotency: GL reversed exactly once
  // ─────────────────────────────────────────────────────────────────────────
  group('Spec 151 — cancelling a return twice reverses the GL exactly once',
      () {
    late AppDatabase db;
    late int warehouseId;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.syncDefaultAccounts();
      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'main-dc',
              globalId: const Value('gid-br-dc'),
            ),
          );
      warehouseId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'wh-dc',
              branchId: Value(branchId),
              globalId: const Value('gid-wh-dc'),
            ),
          );
    });

    tearDown(() async => db.close());

    test(
        'reverseReturnAccountingEntry called twice → ONE return_cancel JE, '
        'net GL per account == 0 (not double-reversed)', () async {
      final invoiceId = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'INV-DC-1',
              warehouseId: warehouseId,
              userId: 1,
              invoiceDate: DateTime.now(),
              subtotal: const Value(400),
              tax: const Value(0),
              total: const Value(400),
              paid: const Value(0),
              paymentMethod: const Value('credit'),
              status: const Value('completed'),
              globalId: const Value('gid-inv-dc-1'),
            ),
          );
      final invoice = (await db.getSalesInvoiceById(invoiceId))!;

      final jeId = await db.autoPostSalesReturn(
        originalInvoice: invoice,
        returnAmount: 400,
        cogsAmount: 200,
        cashRefund: 0,
        bankRefund: 0,
        arRefund: 400,
        returnEventId: 'SRET-DC-1',
      );
      expect(jeId, isNotNull);
      final returnJe = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('sales_return')))
          .getSingle();

      // Cancel TWICE (retry / resync / double click).
      await db.reverseReturnAccountingEntry(
        invoiceId: invoice.id,
        invNumber: invoice.invoiceNumber,
      );
      await db.reverseReturnAccountingEntry(
        invoiceId: invoice.id,
        invNumber: invoice.invoiceNumber,
      );

      final cancelJes = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('return_cancel')))
          .get();
      expect(cancelJes, hasLength(1),
          reason: 'the second cancel must be a deterministic-gid no-op — a '
              'second contra JE would double-reverse the GL');

      // Net per account across return JE + its single reversal == 0.
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
            reason: 'account #${e.key} must net to zero — reversed once only');
      }
    });
  });
}
