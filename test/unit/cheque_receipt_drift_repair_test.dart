// ═══════════════════════════════════════════════════════════════════════════
// Spec 138 — Cheque-Receipt Drift Repair
// ═══════════════════════════════════════════════════════════════════════════
//
// Regression + safety suite for `ChequeReceiptDriftRepairService`. Pattern
// mirrors `test/unit/paper_autopost_idempotency_test.dart` (in-memory
// `AppDatabase.forTesting`) and the seed helpers of
// `test/unit/spec_082_cheque_clearing_je_test.dart` (fiscal year + accounts).
//
// US1 (heal): seed the drift signature (a received cheque still `pending` plus
//   a matching receipt-voucher safe-transaction) after applying the phantom
//   over-credit leg to a customer, plus a NON-drifted control customer. Run
//   `repair()` and assert the drifted balance is restored, a balanced
//   `cheque_drift_repair` JE exists, treasury is byte-for-byte untouched
//   (FR-013), and the control customer is unchanged (FR-011/SC-006).
//
//   Direction proof (research.md §D4): balance B0 → phantom leg (−amount) →
//   B0−amount → repair (+amount) → B0. The round-trip pins the `+overCreditTotal`
//   sign for the money mutation.
//
// US2 (safe/once-only/scoped): second run → skipped(alreadyApplied); clean DB
//   run-twice → noop then skipped; standalone/client/mirror → skipped(notServer);
//   unmapped clearing → failed(missingCorrectionAccount); an exception mid-loop
//   rolls the WHOLE run back (flag unset, re-runnable — FR-003); a healed party
//   is never adjusted twice even if the flag is cleared (R2). All write nothing
//   on skip/fail.
//
// FR-002: the customer GL sub-account balance equals `parties.balance` after a
//   heal (they agree).
//
// US3 (observability): after a heal, the report settings blob is well-formed
//   (incl. `byUserId` — R5) and a completion log line was emitted.

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';
import 'package:ural_erp/services/cheque_receipt_drift_audit_service.dart';
import 'package:ural_erp/services/cheque_receipt_drift_repair_service.dart';
import 'package:ural_erp/services/network_service.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await _clearDatabase(db);
    await _seedFiscalYear(db);
    await _seedAccounts(db);
    await _seedSafe(db, balance: 10000.0);
    DiagnosticLogger.enableTestMode();
    // Repair runs server-only (FR-006). Default to server; individual guard
    // tests override.
    NetworkService.instance.debugSetModeForTests(NetworkMode.server);
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    await db.close();
  });

  group('Spec 138 US1 — heal over-credited customer balances', () {
    test(
        'restores the drifted balance, posts a balanced cheque_drift_repair JE, '
        'leaves treasury + control customer untouched', () async {
      const b0 = 1000.0;
      const overCredit = 500.0;

      // Drifted customer: apply the phantom (extra) credit leg then seed the
      // drift signature so the Spec 133 audit flags it.
      final driftedId = await _seedCustomer(db, name: 'عميل متأثر', balance: b0);
      await db.adjustPartyBalance(driftedId, -overCredit); // phantom leg
      await _seedDrift(db,
          partyId: driftedId, chequeNumber: 'CHK-138-1', amount: overCredit);

      // Control customer: NOT in the audited population.
      const controlBalance = 750.0;
      final controlId =
          await _seedCustomer(db, name: 'عميل غير متأثر', balance: controlBalance);

      // Sanity: the audit flags exactly the drifted customer, by overCredit.
      final before = await ChequeReceiptDriftAuditService(db).getBreakdown();
      expect(before, hasLength(1));
      expect(before.single.partyId, driftedId);
      expect(before.single.overCreditTotal, overCredit);

      // Capture treasury + commercial-paper baseline (FR-013 — must be
      // byte-for-byte unchanged).
      final safeBefore = await _safeBalance(db, 1);
      final stBefore = await _safeTxnsFor(db, driftedId);
      final cpBefore = await _cpRowsFor(db, driftedId);

      // ── Act ──
      final result = await ChequeReceiptDriftRepairService(db).repair();

      // ── Assert ──
      expect(result.outcome, ChequeDriftRepairOutcome.healed);
      expect(result.healedCount, 1);
      expect(result.totalHealed, overCredit);

      // (a) Balance restored to B0 (moved by +overCredit — proven direction).
      expect(await _balance(db, driftedId), b0);

      // (b) A balanced cheque_drift_repair JE exists (Dr==Cr).
      final jes = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('cheque_drift_repair')))
          .get();
      expect(jes, hasLength(1),
          reason: 'one correction JE per healed customer');
      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(jes.single.id)))
          .get();
      final debits = lines.fold<double>(0, (s, l) => s + l.debit);
      final credits = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(debits, credits, reason: 'trial balance stays balanced');
      expect(debits, overCredit);
      // Cr side lands on the BALANCE-SHEET suspense account (code 2135 —
      // liability, credit-normal) so the correction has ZERO P&L impact.
      final clearing = await db.getAccountByCode('2135');
      expect(clearing!.accountType, 'liability',
          reason: 'the suspense account must be balance-sheet (no P&L impact)');
      final creditLine = lines.firstWhere((l) => l.credit > 0);
      expect(creditLine.accountId, clearing.id,
          reason: 'the correction credit routes to the clearing/suspense acct');

      // (c) FR-012 / SC-004 — a re-run of the Spec 133 audit now reports 0 for
      // the healed party (excluded because it carries a cheque_drift_repair JE),
      // WITHOUT any treasury/commercial-paper mutation.
      expect(await ChequeReceiptDriftAuditService(db).getBreakdown(), isEmpty,
          reason: 'healed party is excluded from the audit population');
      expect(await ChequeReceiptDriftAuditService(db).getAffectedCustomerCount(),
          0);
      expect(await ChequeReceiptDriftAuditService(db).getTotalOverCredit(), 0.0);

      // (d) FR-013 — treasury byte-for-byte unchanged: FULL safe_transactions
      // row equality (Drift data classes compare every column), safe balance,
      // AND commercial_papers rows + statuses unchanged (so an illicit status
      // mutation would be caught, not masked by the audit exclusion).
      expect(await _safeBalance(db, 1), safeBefore,
          reason: 'repair must never touch safes.balance');
      expect(await _safeTxnsFor(db, driftedId), stBefore,
          reason: 'every safe_transactions row identical before/after');
      final cpAfter = await _cpRowsFor(db, driftedId);
      expect(cpAfter, cpBefore,
          reason: 'commercial_papers rows + statuses unchanged (no status '
              'surgery — the audit-0 result comes from the JE exclusion, not '
              'from flipping the cheque out of pending)');
      expect(cpAfter.map((p) => p.status).toList(), ['pending'],
          reason: 'the drifted cheque is still pending after repair');

      // (e) FR-011/SC-006 — control customer unchanged (no collateral fix).
      expect(await _balance(db, controlId), controlBalance);
    });

    test('multiple drifted cheques for one customer heal by the audited sum',
        () async {
      const b0 = 2000.0;
      final id = await _seedCustomer(db, name: 'عميل ٣ شيكات', balance: b0);
      // Three phantom legs totalling 1300.
      for (final (n, amt) in [('A', 500.0), ('B', 300.0), ('C', 500.0)]) {
        await db.adjustPartyBalance(id, -amt);
        await _seedDrift(db, partyId: id, chequeNumber: 'CHK-3-$n', amount: amt);
      }

      final result = await ChequeReceiptDriftRepairService(db).repair();

      expect(result.outcome, ChequeDriftRepairOutcome.healed);
      expect(result.healedCount, 1);
      expect(result.totalHealed, 1300.0);
      expect(await _balance(db, id), b0, reason: 'B0 − 1300 + 1300 == B0');
    });

    test('FR-002 — after repair the customer GL sub-account balance equals '
        'parties.balance (they agree)', () async {
      const b0 = 1000.0;
      const overCredit = 500.0;

      // A dedicated postable customer sub-account (asset) linked to the party,
      // plus the counter accounts for the opening + phantom legs.
      final subId = await _insertAccount(db, '1121001', 'ذمة عميل مباشرة', 'asset');
      final equityId = await _insertAccount(db, '313', 'أرباح مبقاة', 'equity');
      final cashId = await _insertAccount(db, '1111', 'الصندوق', 'asset');

      final partyId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'عميل بحساب فرعي',
              isCustomer: const Value(true),
              isSupplier: const Value(false),
              balance: const Value(b0),
              accountId: Value(subId),
              globalId: const Value('gid-fr002'),
            ),
          );

      // Establish the TRUE AR = B0 on the sub-account (Dr sub / Cr equity).
      await db.createJournalEntry(
        description: 'رصيد افتتاحي',
        date: DateTime(2026, 6, 1),
        referenceType: 'opening_balance',
        lines: [
          JournalLine(accountId: subId, debit: b0, credit: 0),
          JournalLine(accountId: equityId, debit: 0, credit: b0),
        ],
      );
      // The ORIGINAL bugged credit leg on the GL sub-account (Dr cash / Cr sub),
      // mirrored by the phantom parties.balance leg — both now over-credited.
      await db.createJournalEntry(
        description: 'قيد الازدواج (محاكاة)',
        date: DateTime(2026, 6, 2),
        lines: [
          JournalLine(accountId: cashId, debit: overCredit, credit: 0),
          JournalLine(accountId: subId, debit: 0, credit: overCredit),
        ],
      );
      await db.adjustPartyBalance(partyId, -overCredit);
      await _seedDrift(db,
          partyId: partyId, chequeNumber: 'CHK-FR002', amount: overCredit);

      // Pre: both the stored balance and the GL sub-account are drifted low and
      // they already agree at B0 − amount.
      expect(await _balance(db, partyId), b0 - overCredit);
      expect((await db.getAccountById(subId))!.balance, b0 - overCredit,
          reason: 'GL sub-account also carries the double-credit');

      await ChequeReceiptDriftRepairService(db).repair();

      final partyAfter = await _balance(db, partyId);
      final subAfter = (await db.getAccountById(subId))!.balance;
      expect(partyAfter, b0);
      expect(subAfter, b0, reason: 'the Dr landed on the customer sub-account');
      expect(subAfter, partyAfter,
          reason: 'FR-002 invariant: stored balance == GL sub-account balance');
    });
  });

  group('Spec 138 US2 — safe, once-only, correctly-scoped', () {
    test('second run is skipped(alreadyApplied) and changes nothing', () async {
      const b0 = 1000.0;
      final id = await _seedCustomer(db, name: 'عميل', balance: b0);
      await db.adjustPartyBalance(id, -500.0);
      await _seedDrift(db, partyId: id, chequeNumber: 'CHK-X', amount: 500.0);

      final first = await ChequeReceiptDriftRepairService(db).repair();
      expect(first.outcome, ChequeDriftRepairOutcome.healed);
      final balanceAfterFirst = await _balance(db, id);
      final jeCountAfterFirst = await _jeCount(db);

      final second = await ChequeReceiptDriftRepairService(db).repair();
      expect(second.outcome, ChequeDriftRepairOutcome.skipped);
      expect(second.reason, ChequeDriftRepairReason.alreadyApplied);
      expect(await _balance(db, id), balanceAfterFirst,
          reason: 'no second correction — would under-credit');
      expect(await _jeCount(db), jeCountAfterFirst);
    });

    test('clean install → noop, flag set, zero rows changed', () async {
      final jeCountBefore = await _jeCount(db);

      final result = await ChequeReceiptDriftRepairService(db).repair();

      expect(result.outcome, ChequeDriftRepairOutcome.noop);
      expect(await _jeCount(db), jeCountBefore);
      expect(await db.getSettingValue(kChequeReceiptDriftRepairV1Applied),
          'true',
          reason: 'a clean install is "done" — flag is set so we never re-scan');
    });

    for (final mode in [
      NetworkMode.standalone,
      NetworkMode.client,
      NetworkMode.mirror,
    ]) {
      test('${mode.name} mode → skipped(notServer), zero changes', () async {
        NetworkService.instance.debugSetModeForTests(mode);
        const b0 = 1000.0;
        final id = await _seedCustomer(db, name: 'عميل', balance: b0);
        await db.adjustPartyBalance(id, -500.0);
        await _seedDrift(db, partyId: id, chequeNumber: 'CHK-Y', amount: 500.0);
        final balanceBefore = await _balance(db, id);
        final jeCountBefore = await _jeCount(db);

        final result = await ChequeReceiptDriftRepairService(db).repair();

        expect(result.outcome, ChequeDriftRepairOutcome.skipped);
        expect(result.reason, ChequeDriftRepairReason.notServer,
            reason: 'only server mode runs the repair; clients + mirrors '
                'receive the healed state via sync (FR-006)');
        expect(await _balance(db, id), balanceBefore);
        expect(await _jeCount(db), jeCountBefore);
        expect(await db.getSettingValue(kChequeReceiptDriftRepairV1Applied),
            isNull,
            reason: 'refusing to run must not set the completion flag');
      });
    }

    test('unmapped clearing account → failed(missingCorrectionAccount), '
        'zero changes', () async {
      // Remove the suspense/clearing account (code 2135) so resolution returns
      // null and the repair fails closed.
      await (db.delete(db.accounts)..where((a) => a.code.equals('2135'))).go();

      const b0 = 1000.0;
      final id = await _seedCustomer(db, name: 'عميل', balance: b0);
      await db.adjustPartyBalance(id, -500.0);
      await _seedDrift(db, partyId: id, chequeNumber: 'CHK-Z', amount: 500.0);
      final balanceBefore = await _balance(db, id);
      final jeCountBefore = await _jeCount(db);

      final result = await ChequeReceiptDriftRepairService(db).repair();

      expect(result.outcome, ChequeDriftRepairOutcome.failed);
      expect(result.reason, ChequeDriftRepairReason.missingCorrectionAccount);
      expect(await _balance(db, id), balanceBefore,
          reason: 'fail closed — post nothing when the Cr account is unmapped');
      expect(await _jeCount(db), jeCountBefore);
      expect(await db.getSettingValue(kChequeReceiptDriftRepairV1Applied),
          isNull);
    });

    test('clean install run twice → noop then skipped(alreadyApplied)',
        () async {
      final first = await ChequeReceiptDriftRepairService(db).repair();
      expect(first.outcome, ChequeDriftRepairOutcome.noop);
      expect(await db.getSettingValue(kChequeReceiptDriftRepairV1Applied),
          'true');

      final jeCountAfterFirst = await _jeCount(db);
      final second = await ChequeReceiptDriftRepairService(db).repair();
      expect(second.outcome, ChequeDriftRepairOutcome.skipped);
      expect(second.reason, ChequeDriftRepairReason.alreadyApplied);
      expect(await _jeCount(db), jeCountAfterFirst, reason: 'zero further rows');
    });

    test('exception mid-transaction rolls back the WHOLE run; flag stays '
        'unset; re-runnable (FR-003 atomicity)', () async {
      const b0 = 1000.0;

      // Good party (larger amount → processed FIRST, ordered by amount DESC):
      // resolves via the receivables-control fallback and posts successfully.
      final goodId = await _seedCustomer(db, name: 'سليم', balance: b0);
      await db.adjustPartyBalance(goodId, -700.0);
      await _seedDrift(db, partyId: goodId, chequeNumber: 'CHK-OK', amount: 700.0);

      // Bad party (smaller amount → processed SECOND): its accountId points at a
      // `view` (parent) account, so createJournalEntry throws the view-account
      // guard mid-loop — AFTER the good party already posted.
      final viewId = await db.into(db.accounts).insert(
            AccountsCompanion.insert(
              code: '1129',
              name: 'حساب رئيسي (view)',
              accountType: 'asset',
              accountNature: const Value('view'),
              balance: const Value(0.0),
            ),
          );
      final badId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'خطأ',
              isCustomer: const Value(true),
              isSupplier: const Value(false),
              balance: const Value(b0),
              accountId: Value(viewId),
              globalId: const Value('gid-bad'),
            ),
          );
      await db.adjustPartyBalance(badId, -500.0);
      await _seedDrift(db, partyId: badId, chequeNumber: 'CHK-BAD', amount: 500.0);

      final goodBalanceBefore = await _balance(db, goodId); // 300

      await expectLater(
        ChequeReceiptDriftRepairService(db).repair(),
        throwsA(anything),
        reason: 'a view-account customer sub-account fails the JE post',
      );

      // Full rollback: no correction JE, the good party (which DID post before
      // the throw) is reverted too, and the flag is never set → re-runnable.
      expect(
        await (db.select(db.journalEntries)
              ..where((e) => e.referenceType.equals('cheque_drift_repair')))
            .get(),
        isEmpty,
        reason: 'no correction JE survives the rollback',
      );
      expect(await _balance(db, goodId), goodBalanceBefore,
          reason: 'atomicity: the good party posted then rolled back with the run');
      expect(await db.getSettingValue(kChequeReceiptDriftRepairV1Applied),
          isNull,
          reason: 'interrupted run leaves the flag unset — fully re-runnable');
    });

    test('R2 — a healed party is never adjusted twice even if the once-only '
        'flag is cleared', () async {
      const b0 = 1000.0;
      final id = await _seedCustomer(db, name: 'عميل', balance: b0);
      await db.adjustPartyBalance(id, -500.0);
      await _seedDrift(db, partyId: id, chequeNumber: 'CHK-DUP', amount: 500.0);

      final first = await ChequeReceiptDriftRepairService(db).repair();
      expect(first.outcome, ChequeDriftRepairOutcome.healed);
      expect(await _balance(db, id), b0);

      // Simulate reaching the already-healed party WITHOUT the flag (e.g. a
      // concurrent run whose out-of-transaction population still listed it, or a
      // manual flag reset). The party carries a cheque_drift_repair JE, so both
      // the audit exclusion (layer 3) and the per-party belt (layer 2) prevent a
      // second balance adjustment.
      await db.setSetting(kChequeReceiptDriftRepairV1Applied, 'false');
      final second = await ChequeReceiptDriftRepairService(db).repair();

      expect(await _balance(db, id), b0,
          reason: 'the balance must never be adjusted a second time');
      final repairJes = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('cheque_drift_repair')))
          .get();
      expect(repairJes, hasLength(1), reason: 'no second correction JE');
      expect(second.outcome, ChequeDriftRepairOutcome.noop,
          reason: 'population is now empty (the party is already healed)');
    });
  });

  group('Spec 138 US3 — repair audit trail', () {
    test('report blob is well-formed and a completion log line is emitted',
        () async {
      final id = await _seedCustomer(db, name: 'عميل تقرير', balance: 1000.0);
      await db.adjustPartyBalance(id, -500.0);
      await _seedDrift(db, partyId: id, chequeNumber: 'CHK-R', amount: 500.0);

      // R5 — the operator's userId is threaded from the dialog as `changedBy`.
      await ChequeReceiptDriftRepairService(db).repair(changedBy: 7);

      // Report blob.
      final blob =
          await db.getSettingValue(kChequeReceiptDriftRepairV1Report);
      expect(blob, isNotNull);
      final decoded = jsonDecode(blob!) as List;
      expect(decoded, hasLength(1));
      final entry = decoded.single as Map<String, dynamic>;
      expect(entry['partyId'], id);
      expect(entry['name'], 'عميل تقرير');
      expect(entry['amount'], 500.0);
      expect(entry['at'], isA<String>());
      expect(DateTime.tryParse(entry['at'] as String), isNotNull);
      expect(entry['byUserId'], 7,
          reason: 'R5 — operator accountability captured in the report blob');

      // Completion log line.
      final completion = DiagnosticLogger.testLog
          .where((l) => l.contains('CHEQUE-RECEIPT-DRIFT-REPAIR'))
          .toList();
      expect(completion, isNotEmpty);
      expect(completion.last, contains('healed=1'));
      expect(completion.last, contains('total=500.00'));
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _clearDatabase(AppDatabase db) async {
  // AppDatabase.forTesting() runs the full startup seed (fiscal year, COA,
  // safes, settings). Wipe to a known baseline before seeding exactly what the
  // repair needs — mirrors spec_082_cheque_clearing_je_test's _clearDatabase.
  await db.delete(db.paperStatusHistory).go();
  await db.delete(db.commercialPapers).go();
  await db.delete(db.safeTransactions).go();
  await db.delete(db.journalEntryLines).go();
  await db.delete(db.journalEntries).go();
  await db.delete(db.accountingPeriods).go();
  await db.delete(db.fiscalYears).go();
  await db.delete(db.accountMappings).go();
  await db.delete(db.accounts).go();
  await db.delete(db.parties).go();
  await db.delete(db.safes).go();
  await db.delete(db.settings).go();
}

Future<int> _seedCustomer(AppDatabase db,
    {required String name, required double balance}) {
  return db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: name,
          isCustomer: const Value(true),
          isSupplier: const Value(false),
          balance: Value(balance),
          globalId: Value('gid-party-$name'),
        ),
      );
}

/// Seed the drift signature for [partyId]: a received cheque still `pending`
/// plus a matching non-deleted receipt-voucher safe-transaction whose
/// description carries the cheque number.
Future<void> _seedDrift(AppDatabase db,
    {required int partyId,
    required String chequeNumber,
    required double amount}) async {
  await db.into(db.commercialPapers).insert(
        CommercialPapersCompanion.insert(
          paperNumber: chequeNumber,
          type: 'cheque',
          direction: 'received',
          partyId: partyId,
          amount: amount,
          issueDate: DateTime(2026, 6, 1),
          dueDate: DateTime(2026, 7, 15),
          status: const Value('pending'),
          globalId: Value('gid-cp-$chequeNumber'),
        ),
      );
  await db.into(db.safeTransactions).insert(
        SafeTransactionsCompanion.insert(
          voucherNumber: 'RV-$chequeNumber',
          safeId: 1,
          transactionType: 'receipt',
          category: 'sales',
          amount: amount,
          balanceAfter: 10000.0,
          partyId: Value(partyId),
          description: Value('سند قبض بشيك رقم $chequeNumber'),
          globalId: Value('gid-st-$chequeNumber'),
        ),
      );
}

Future<double> _balance(AppDatabase db, int partyId) async {
  final p = await (db.select(db.parties)..where((x) => x.id.equals(partyId)))
      .getSingle();
  return p.balance;
}

Future<double> _safeBalance(AppDatabase db, int safeId) async {
  final s =
      await (db.select(db.safes)..where((x) => x.id.equals(safeId))).getSingle();
  return s.balance;
}

Future<List<SafeTransactionData>> _safeTxnsFor(AppDatabase db, int partyId) {
  return (db.select(db.safeTransactions)
        ..where((t) => t.partyId.equals(partyId))
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .get();
}

Future<int> _jeCount(AppDatabase db) async {
  final rows = await db.select(db.journalEntries).get();
  return rows.length;
}

Future<List<CommercialPaperData>> _cpRowsFor(AppDatabase db, int partyId) {
  return (db.select(db.commercialPapers)
        ..where((c) => c.partyId.equals(partyId))
        ..orderBy([(c) => OrderingTerm.asc(c.id)]))
      .get();
}

Future<int> _insertAccount(
    AppDatabase db, String code, String name, String type) {
  return db.into(db.accounts).insert(
        AccountsCompanion.insert(
          code: code,
          name: name,
          accountType: type,
          balance: const Value(0.0),
        ),
      );
}

Future<void> _seedAccounts(AppDatabase db) async {
  // Receivables control (customer sub-account fallback) + balance-sheet
  // suspense/clearing account (code 2135, liability) for the correction Cr side.
  await _insertAccount(db, '1121', 'ذمم عملاء محليون', 'asset');
  await _insertAccount(db, '2135', 'حسابات جارية - دائنة', 'liability');
}

Future<void> _seedSafe(AppDatabase db, {required double balance}) async {
  await db.into(db.safes).insert(
        SafesCompanion.insert(
          id: const Value(1),
          name: 'خزينة تجريبية',
          safeType: const Value('cash'),
          balance: Value(balance),
          isDefault: const Value(true),
          isActive: const Value(true),
        ),
      );
}

Future<void> _seedFiscalYear(AppDatabase db) async {
  await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          id: const Value(1),
          name: '2026',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 12, 31),
        ),
      );
  for (int m = 1; m <= 12; m++) {
    await db.into(db.accountingPeriods).insert(
          AccountingPeriodsCompanion.insert(
            fiscalYearId: 1,
            name: 'شهر $m - 2026',
            month: m,
            year: 2026,
            startDate: DateTime(2026, m, 1),
            endDate: DateTime(2026, m + 1, 0, 23, 59, 59),
          ),
        );
  }
}
