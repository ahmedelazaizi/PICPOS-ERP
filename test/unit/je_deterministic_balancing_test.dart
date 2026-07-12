// ═══════════════════════════════════════════════════════════════════════════
// Spec 139 — Deterministic & Honest Journal-Entry Balancing
// ═══════════════════════════════════════════════════════════════════════════
//
// The JE writer used to silently absorb any debit/credit imbalance up to 0.10
// into the largest business leg. This suite pins the honest behaviour:
//
// US1 (book honestly): a legitimate sub-cap residual is posted to the dedicated
//   «فروق تقريب» (4319) account — both a credit (gain) and a debit (loss) —
//   the entry balances EXACTLY, and NO business leg is mutated. Fail-closed when
//   the rounding account is unresolved.
// US2 (refuse loudly): a residual beyond the cap (0.01) is hard-failed with the
//   Arabic unbalanced-entry error (the exact substrings the sync dead-letter
//   classifier matches) and nothing is written. Boundary at exactly the cap.
// US3 (one source of truth): no divergent 0.10 / hardcoded 0.01 balance literal
//   survives in the three balancing paths.
//
// Harness mirrors test/unit/cheque_receipt_drift_repair_test.dart (in-memory
// AppDatabase.forTesting + explicit seed of exactly what the writer needs).

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/utils/financial_utils.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';
import 'package:ural_erp/services/journal_entry_diagnostics.dart';
import 'package:ural_erp/services/network_service.dart';

void main() {
  late AppDatabase db;
  late int cashId; // asset, debit side
  late int salesId; // revenue, credit side
  late int roundingId; // 4319 «فروق تقريب»

  setUp(() async {
    db = AppDatabase.forTesting();
    await _clearDatabase(db);
    await _seedFiscalYear(db);
    // Business legs + the rounding-difference account (4319, detail leaf so
    // getLeafAccountByPurpose returns it directly).
    cashId = await _seedAccount(db, '1111', 'الصندوق', 'asset', 'detail', 'debit');
    salesId = await _seedAccount(db, '4111', 'المبيعات', 'revenue', 'detail', 'credit');
    roundingId =
        await _seedAccount(db, '4319', 'فروق تقريب', 'revenue', 'detail', 'credit');
    JournalEntryDiagnostics.lastRoundingAdjustment = 0;
    // Standalone → no client/server sync attempt inside createJournalEntry.
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    await db.close();
  });

  // ───────────────────────────────────────────────────────────────────────
  // US1 — book the residual honestly on 4319
  // ───────────────────────────────────────────────────────────────────────
  group('Spec 139 US1 — rounding remainder booked to 4319 (not a business leg)',
      () {
    test('positive residual (+0.001) → CREDIT leg on 4319, entry balances exactly',
        () async {
      // Debit 100.001 vs credit 100.000 → residual +1 minor unit (credit-short).
      final id = await _postJE(db, [
        JournalLine(accountId: cashId, debit: 100.001),
        JournalLine(accountId: salesId, credit: 100.000),
      ]);

      final lines = await _linesOf(db, id);
      // Balance is exact.
      final d = lines.fold<double>(0, (s, l) => s + l.debit);
      final c = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(FinancialUtils.toMinorUnits(d), FinancialUtils.toMinorUnits(c),
          reason: 'Σdebit must equal Σcredit exactly in minor units');

      // The residual lands on 4319 as a CREDIT of 0.001.
      final roundingLegs = lines.where((l) => l.accountId == roundingId).toList();
      expect(roundingLegs, hasLength(1),
          reason: 'exactly one rounding leg on 4319');
      expect(roundingLegs.single.credit, closeTo(0.001, 1e-9));
      expect(roundingLegs.single.debit, 0);

      // No business leg was mutated.
      final cash = lines.firstWhere((l) => l.accountId == cashId);
      final sales = lines.firstWhere((l) => l.accountId == salesId);
      expect(cash.debit, closeTo(100.001, 1e-9));
      expect(sales.credit, closeTo(100.000, 1e-9));

      // Diagnostic surfaces the routed residual (for the POS toast).
      expect(JournalEntryDiagnostics.lastRoundingAdjustment, closeTo(0.001, 1e-9));
    });

    test('negative residual (−0.001) → DEBIT leg on 4319, entry balances exactly',
        () async {
      // Debit 100.000 vs credit 100.001 → residual −1 minor unit (debit-short).
      final id = await _postJE(db, [
        JournalLine(accountId: cashId, debit: 100.000),
        JournalLine(accountId: salesId, credit: 100.001),
      ]);

      final lines = await _linesOf(db, id);
      final d = lines.fold<double>(0, (s, l) => s + l.debit);
      final c = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(FinancialUtils.toMinorUnits(d), FinancialUtils.toMinorUnits(c));

      final roundingLegs = lines.where((l) => l.accountId == roundingId).toList();
      expect(roundingLegs, hasLength(1));
      expect(roundingLegs.single.debit, closeTo(0.001, 1e-9),
          reason: 'debit-short → the rounding account takes a small loss (debit)');
      expect(roundingLegs.single.credit, 0);
      expect(JournalEntryDiagnostics.lastRoundingAdjustment, closeTo(-0.001, 1e-9));
    });

    test('perfectly balanced multi-leg entry posts with NO rounding leg (no regression)',
        () async {
      // Dr cash 114.000 = Cr sales 100.000 + Cr VAT-as-sales 14.000 (exact).
      final id = await _postJE(db, [
        JournalLine(accountId: cashId, debit: 114.000),
        JournalLine(accountId: salesId, credit: 100.000),
        JournalLine(accountId: salesId, credit: 14.000),
      ]);

      final lines = await _linesOf(db, id);
      final d = lines.fold<double>(0, (s, l) => s + l.debit);
      final c = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(FinancialUtils.toMinorUnits(d), FinancialUtils.toMinorUnits(c));
      expect(lines.where((l) => l.accountId == roundingId), isEmpty,
          reason: 'a balanced entry must not gain a rounding leg');
    });

    test('fail-closed: rounding account unresolved → throws, nothing written',
        () async {
      // Remove 4319 so getLeafAccountByPurpose(\'rounding_difference\') → null.
      // Default test mode is standalone (SyncInterceptor.instance == null →
      // isClientMode false) → server/standalone fail-closed path (throws).
      await (db.delete(db.accounts)..where((a) => a.code.equals('4319'))).go();
      final jeBefore = (await db.select(db.journalEntries).get()).length;

      await expectLater(
        _postJE(db, [
          JournalLine(accountId: cashId, debit: 100.001),
          JournalLine(accountId: salesId, credit: 100.000),
        ]),
        throwsA(anything),
        reason: 'must fail closed, never plug a business leg',
      );

      expect((await db.select(db.journalEntries).get()).length, jeBefore,
          reason: 'nothing written on fail-closed');
      // The cash/sales legs were NOT silently adjusted (no orphan entry).
      final anyRounding = await (db.select(db.journalEntryLines)).get();
      expect(anyRounding.where((l) => l.debit == 100.001 && l.credit == 0), isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // US2 — refuse a genuine imbalance loudly (dead-letter contract)
  // ───────────────────────────────────────────────────────────────────────
  group('Spec 139 US2 — imbalance beyond the cap is hard-failed', () {
    test('residual 0.05 (> cap) → throws with the Arabic dead-letter substrings; '
        'nothing written', () async {
      final jeBefore = (await db.select(db.journalEntries).get()).length;

      await expectLater(
        _postJE(db, [
          JournalLine(accountId: cashId, debit: 100.050),
          JournalLine(accountId: salesId, credit: 100.000),
        ]),
        throwsA(predicate((e) {
          final s = e.toString();
          // The exact substrings offline_sync_worker matches to dead-letter.
          return s.contains('خطأ في قيد اليومية') && s.contains('لا يساوي الدائن');
        })),
        reason: 'a 5-piaster imbalance is a real error, not rounding',
      );

      expect((await db.select(db.journalEntries).get()).length, jeBefore,
          reason: 'refused entries write nothing');
    });

    test('boundary: residual == cap (0.01) is booked; cap + 1 minor unit throws',
        () async {
      // Exactly at the cap → accepted and booked to 4319.
      final atCap = await _postJE(db, [
        JournalLine(accountId: cashId, debit: 100.010),
        JournalLine(accountId: salesId, credit: 100.000),
      ]);
      final lines = await _linesOf(db, atCap);
      expect(lines.where((l) => l.accountId == roundingId), hasLength(1),
          reason: 'residual == cap is a rounding remainder (booked)');
      expect(lines.firstWhere((l) => l.accountId == roundingId).credit,
          closeTo(0.010, 1e-9));

      // Just over the cap → refused.
      await expectLater(
        _postJE(db, [
          JournalLine(accountId: cashId, debit: 100.011),
          JournalLine(accountId: salesId, credit: 100.000),
        ]),
        throwsA(anything),
        reason: 'one minor unit beyond the cap is an error',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // H1 (committee) — client-mode graceful degradation when 4319 hasn't synced
  // ───────────────────────────────────────────────────────────────────────
  group('Spec 139 H1 — client-mode: missing 4319 degrades, never blocks', () {
    test('client + missing 4319 + sub-cap residual → absorbed into largest leg, '
        'no throw, still balances', () async {
      await (db.delete(db.accounts)..where((a) => a.code.equals('4319'))).go();
      final prev = SyncInterceptor.instance;
      SyncInterceptor.instance = _ClientModeInterceptor();
      try {
        // Dr cash 100.001 vs Cr sales 100.000 → residual +0.001; 4319 absent.
        final id = await _postJE(db, [
          JournalLine(accountId: cashId, debit: 100.001),
          JournalLine(accountId: salesId, credit: 100.000),
        ]);
        final lines = await _linesOf(db, id);
        final d = lines.fold<double>(0, (s, l) => s + l.debit);
        final c = lines.fold<double>(0, (s, l) => s + l.credit);
        expect(FinancialUtils.toMinorUnits(d), FinancialUtils.toMinorUnits(c),
            reason: 'client fallback still balances the entry exactly');
        expect(lines, hasLength(2),
            reason: 'no extra leg — the ≤cap residual is absorbed in place');
        final sales = lines.firstWhere((l) => l.accountId == salesId);
        expect(sales.credit, closeTo(100.001, 1e-9),
            reason: 'absorbed into the largest short-side (credit) leg, not a throw');
      } finally {
        SyncInterceptor.instance = prev;
      }
    });

    test('client mode does NOT relax the >cap hard-fail', () async {
      final prev = SyncInterceptor.instance;
      SyncInterceptor.instance = _ClientModeInterceptor();
      final jeBefore = (await db.select(db.journalEntries).get()).length;
      try {
        await expectLater(
          _postJE(db, [
            JournalLine(accountId: cashId, debit: 100.050),
            JournalLine(accountId: salesId, credit: 100.000),
          ]),
          throwsA(anything),
          reason: 'a >cap imbalance is a real error even in client mode',
        );
        expect((await db.select(db.journalEntries).get()).length, jeBefore);
      } finally {
        SyncInterceptor.instance = prev;
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Dead-letter contract (M2 + FR-006) — message ↔ offline_sync_worker wiring
  // ───────────────────────────────────────────────────────────────────────
  group('Spec 139 — dead-letter message contract', () {
    test('>cap hard-fail message carries BOTH sync-worker permanent substrings',
        () async {
      Object? caught;
      try {
        await _postJE(db, [
          JournalLine(accountId: cashId, debit: 100.050),
          JournalLine(accountId: salesId, credit: 100.000),
        ]);
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      final msg = caught.toString();
      expect(msg.contains('خطأ في قيد اليومية'), isTrue);
      expect(msg.contains('لا يساوي الدائن'), isTrue,
          reason: 'both substrings → offline_sync_worker dead-letters (permanent)');
    });

    test('standalone fail-closed message is RETRYABLE (no dead-letter substrings)',
        () async {
      await (db.delete(db.accounts)..where((a) => a.code.equals('4319'))).go();
      // Default test mode is standalone → the server/standalone fail-closed path.
      Object? caught;
      try {
        await _postJE(db, [
          JournalLine(accountId: cashId, debit: 100.001),
          JournalLine(accountId: salesId, credit: 100.000),
        ]);
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      final msg = caught.toString();
      expect(msg.contains('خطأ في قيد اليومية'), isFalse,
          reason: 'M2 — a fixable missing-account config error must NOT be '
              'permanently dead-lettered; it stays retryable');
      expect(msg.contains('لا يساوي الدائن'), isFalse);
    });

    test('offline_sync_worker still keys the permanent classifier on both substrings',
        () {
      final worker =
          File('lib/services/offline_sync_worker.dart').readAsStringSync();
      expect(worker.contains('خطأ في قيد اليومية'), isTrue);
      expect(worker.contains('لا يساوي الدائن'), isTrue,
          reason: 'the classifier the >cap throw depends on must keep matching these');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // US3 — one balance tolerance, one source of truth (static guard)
  // ───────────────────────────────────────────────────────────────────────
  group('Spec 139 US3 — single balance-tolerance source of truth', () {
    test('old 0.10 absorb envelope is gone; writer + factory both use the SoT minor-unit cap',
        () {
      final writer = File('lib/data/database/daos/accounting_dao_writes.dart')
          .readAsStringSync();
      final factory =
          File('lib/services/journal_entry_factory.dart').readAsStringSync();

      // Target the specific old-plug comparison shapes rather than a bare
      // '0.10' (which would false-trip on any unrelated literal) — L3.
      expect(writer.contains('<= 0.10'), isFalse,
          reason: 'the ≤0.10 absorb-into-largest-leg plug must be gone');
      expect(writer.contains('> 0.10'), isFalse);
      expect(writer.contains('balanceToleranceMinorUnits'), isTrue,
          reason: 'writer compares the residual against the SoT in minor units');

      expect(factory.contains('0.10'), isFalse,
          reason: 'factory pre-validation must not keep its own 0.10 threshold');
      expect(factory.contains('balanceToleranceMinorUnits'), isTrue,
          reason: 'factory pre-check aligned to the DAO in minor units (M1)');
    });

    test('FinancialUtils holds the single tolerance and assertBalanced uses it',
        () {
      final fu =
          File('lib/core/utils/financial_utils.dart').readAsStringSync();
      expect(fu.contains('balanceTolerance = 0.01'), isTrue,
          reason: 'the ONE authoritative tolerance definition');
      expect(fu.contains('diff > 0.01'), isFalse,
          reason: 'assertBalanced must reference the constant, not a literal');
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

Future<int> _postJE(AppDatabase db, List<JournalLine> lines) {
  return db.createJournalEntry(
    description: 'قيد اختبار Spec 139',
    date: DateTime(2026, 6, 15),
    lines: lines,
    referenceType: 'test_je', // isAutoPosted defaults false → dedup skipped
  );
}

Future<List<JournalEntryLine>> _linesOf(AppDatabase db, int entryId) {
  return (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entryId)))
      .get();
}

Future<int> _seedAccount(AppDatabase db, String code, String name, String type,
    String nature, String normalBalance) {
  return db.into(db.accounts).insert(
        AccountsCompanion.insert(
          code: code,
          name: name,
          accountType: type,
          accountNature: Value(nature),
          normalBalance: Value(normalBalance),
          balance: const Value(0.0),
        ),
      );
}

Future<void> _clearDatabase(AppDatabase db) async {
  // forTesting() runs the full startup seed; wipe to a known baseline.
  await db.delete(db.journalEntryLines).go();
  await db.delete(db.journalEntries).go();
  await db.delete(db.accountingPeriods).go();
  await db.delete(db.fiscalYears).go();
  await db.delete(db.accountMappings).go();
  await db.delete(db.accounts).go();
  await db.delete(db.settings).go();
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

/// Minimal fake to flip `SyncInterceptor.isClientMode` on for the H1 tests.
/// Only the two mode getters matter; the DAO's post-commit `submitJournalEntry`
/// call is wrapped in try/catch, so noSuchMethod (→ null → awaited harmlessly)
/// covers every other member.
class _ClientModeInterceptor implements SyncInterceptor {
  @override
  bool get isClientModeImpl => true;
  @override
  bool get isMirrorModeImpl => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
