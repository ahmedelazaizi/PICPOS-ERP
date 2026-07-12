// Spec 138 — Cheque-Receipt Drift Repair (follow-on to the Spec 133 read-only
// audit). Heals customer balances over-credited by the cheque-receipt
// double-credit bug present on builds ≤ 3.1.0+202.
//
// Strategy C (research.md §D3): per affected customer, post ONE reversing
// journal entry — Dr customer sub-account / Cr a prior-period-correction
// (suspense) account — for the full audited amount, paired with an
// `adjustPartyBalance` so the stored balance and the customer sub-account move
// together and the trial balance stays balanced. The phantom safe cash is
// deliberately left in place (FR-013): the Cr side must NOT route to retained
// earnings NOR to any P&L account — it lands in a BALANCE-SHEET suspense
// account (default code 2135 — حسابات جارية دائنة, credit-normal) so the
// correction has ZERO income-statement impact; the residual is a visible
// balance for separate support reconciliation against the overstated safe.
//
// FR-012 (research.md §D3): the Spec 133 audit excludes any party that already
// carries a `cheque_drift_repair` correction JE, so re-running it after a heal
// reports 0 for the healed population — WITHOUT any treasury/commercial-paper
// mutation (FR-013 stays intact).
//
// Direction (research.md §D4, proven by the round-trip test in
// `test/unit/cheque_receipt_drift_repair_test.dart`): the double-credit reduced
// the customer's AR balance twice (a customer credit is a NEGATIVE
// `adjustPartyBalance` delta — see `cheque_receipt_jes.dart` line 101), so the
// stored balance sits too LOW by the audited amount. The repair adds it back:
// `adjustPartyBalance(partyId, +overCreditTotal)` with a matching
// `Dr customer / Cr clearing` JE.
//
// Gate: server mode only (same predicate as the Spec 133 audit). Client /
// mirror installs receive the healed state through normal sync. Runs at most
// once per install (durable settings flag, set only after commit).

import 'dart:convert';

import '../core/logging/diagnostic_logger.dart';
import '../data/database/database.dart';
import '../domain/entities/accounting_entities.dart';
import 'cheque_receipt_drift_audit_service.dart';
import 'network_service.dart';

// ── Settings keys (Spec 138) ────────────────────────────────────────────────
// Kept as plain top-level consts in THIS file — deliberately NOT in
// `DeploymentSettingsKeys`. That class is guarded by
// `test/static/no_direct_network_mode_writes_test.dart`, which forbids any
// `setSetting(...)` on its owned keys outside the deployment committer. These
// repair flags are written only by this service, so they live here.
const String kChequeReceiptDriftRepairV1Applied =
    'cheque_receipt_drift_repair_v1_applied';
const String kChequeReceiptDriftRepairV1Report =
    'cheque_receipt_drift_repair_v1_report';

/// Fail-closed Arabic operator message shown when the prior-period-correction
/// (suspense/clearing) account is not mapped. Style mirrors the Spec 082
/// pre-flight-COA messages in `cheque_receipt_preflight.dart`.
const String kChequeDriftMissingCorrectionAccountMessage =
    'حساب التسوية/المقاصة (حسابات جارية دائنة - رمز 2135) غير مربوط في الدليل '
    'المحاسبي. يرجى مراجعة إعدادات الحسابات أو ربط حساب تسوية مناسب في الميزانية '
    'قبل تشغيل الإصلاح.';

/// Stable reason codes for `skipped` / `failed` results (asserted by tests and
/// mapped to Arabic operator text by the admin dialog).
class ChequeDriftRepairReason {
  ChequeDriftRepairReason._();
  static const notServer = 'notServer';
  static const alreadyApplied = 'alreadyApplied';
  static const missingCorrectionAccount = 'missingCorrectionAccount';
}

enum ChequeDriftRepairOutcome { healed, noop, skipped, failed }

/// Result of a `repair()` call — see contracts/repair-service.md.
class ChequeDriftRepairResult {
  final ChequeDriftRepairOutcome outcome;
  final int healedCount;
  final double totalHealed;

  /// Reason code for `skipped` / `failed` (see [ChequeDriftRepairReason]).
  final String? reason;

  const ChequeDriftRepairResult({
    required this.outcome,
    this.healedCount = 0,
    this.totalHealed = 0,
    this.reason,
  });

  factory ChequeDriftRepairResult.healed(int count, double total) =>
      ChequeDriftRepairResult(
        outcome: ChequeDriftRepairOutcome.healed,
        healedCount: count,
        totalHealed: total,
      );

  factory ChequeDriftRepairResult.noop() =>
      const ChequeDriftRepairResult(outcome: ChequeDriftRepairOutcome.noop);

  factory ChequeDriftRepairResult.skipped(String reason) =>
      ChequeDriftRepairResult(
        outcome: ChequeDriftRepairOutcome.skipped,
        reason: reason,
      );

  factory ChequeDriftRepairResult.failed(String reason) =>
      ChequeDriftRepairResult(
        outcome: ChequeDriftRepairOutcome.failed,
        reason: reason,
      );
}

class ChequeReceiptDriftRepairService {
  ChequeReceiptDriftRepairService(this._db);

  final AppDatabase _db;

  /// Heal the over-credited customer balances detected by the Spec 133 audit.
  ///
  /// [changedBy] is the logged-in admin user id (from the dialog). It is
  /// threaded into `adjustPartyBalance` so the per-customer AR audit trail
  /// (FR-008) is written. When there is no user context (0), the DAO simply
  /// skips the `field_audit_logs` row (its own `changedBy > 0` guard).
  ///
  /// Pre-conditions are checked in order and fail closed (write nothing):
  ///   1. server mode          → skipped(notServer)
  ///   2. not already applied  → skipped(alreadyApplied)   (fast pre-check;
  ///      re-checked authoritatively INSIDE the transaction — R2)
  ///   3. population empty      → noop + set the applied flag (clean == done)
  ///   4. correction account    → failed(missingCorrectionAccount)
  ///
  /// All balance/ledger mutations AND the applied-flag + report writes run
  /// inside ONE `db.transaction()` (FR-003/R2). On the server's SQLite engine
  /// write transactions serialize, so a concurrent second run re-reads the flag
  /// at the start of its transaction, sees `'true'`, and aborts — the balance
  /// can never be adjusted twice. Belt-and-suspenders: each party is skipped if
  /// it already carries a non-deleted `cheque_drift_repair` JE, so the
  /// unconditional `adjustPartyBalance` never fires without a freshly-posted JE.
  Future<ChequeDriftRepairResult> repair({int changedBy = 0}) async {
    // 1. Server gate (FR-006).
    if (!NetworkService.instance.isServer) {
      return ChequeDriftRepairResult.skipped(ChequeDriftRepairReason.notServer);
    }

    // 2. Once-only fast pre-check (cheap early-out; the authoritative re-check
    //    happens INSIDE the transaction below — R2).
    if (await _db.getSettingValue(kChequeReceiptDriftRepairV1Applied) ==
        'true') {
      return ChequeDriftRepairResult.skipped(
          ChequeDriftRepairReason.alreadyApplied);
    }

    // 3. Population — recomputed at apply time from the Spec 133 audit (FR-007).
    final population = await ChequeReceiptDriftAuditService(_db).getBreakdown();
    if (population.isEmpty) {
      // Clean / already-repaired install is "done" — set the flag so we never
      // re-scan (FR-005), but write no ledger rows.
      await _db.setSetting(kChequeReceiptDriftRepairV1Applied, 'true');
      return ChequeDriftRepairResult.noop();
    }

    // 4. Correction (Cr) account mapped — fail closed if not (FR-013 / Spec 082
    //    pre-flight discipline). Resolution mirrors `cheque_receipt_jes.dart`.
    final clearingCode = await _db.getMappedAccountCode(
      'cheque_drift_clearing',
      AccountingDao.accountPurposes['cheque_drift_clearing']!,
    );
    final clearingAccount = await _db.getAccountByCode(clearingCode);
    if (clearingAccount == null) {
      return ChequeDriftRepairResult.failed(
          ChequeDriftRepairReason.missingCorrectionAccount);
    }

    final repairedAt = DateTime.now();

    // 5. Effect — atomic (FR-003). The transaction returns whether it aborted on
    //    the in-transaction flag re-check, plus the healed count/total/report so
    //    the flag+report land inside the SAME commit (R2).
    final (:aborted, :healedCount, :totalHealed, :report) =
        await _db.transaction(() async {
      // R2(a) — authoritative once-only re-check INSIDE the serialized
      // transaction: a concurrent run that already committed set the flag; abort.
      if (await _db.getSettingValue(kChequeReceiptDriftRepairV1Applied) ==
          'true') {
        return (
          aborted: true,
          healedCount: 0,
          totalHealed: 0.0,
          report: const <Map<String, dynamic>>[],
        );
      }

      final report = <Map<String, dynamic>>[];
      double total = 0;
      int healed = 0;

      for (final rec in population) {
        final amount = rec.overCreditTotal;

        // R4 — never post a degenerate JE nor permanently flag a zero/negative
        // row as repaired; leave it visible for manual triage.
        if (amount <= 0) continue;

        // R2(b) belt — skip if a non-deleted `cheque_drift_repair` JE already
        // exists for this party (e.g. a concurrent run posted it after our
        // out-of-transaction getBreakdown). Guarantees `adjustPartyBalance`
        // never fires without a freshly-posted matching JE.
        final alreadyPosted = await (_db.select(_db.journalEntries)
              ..where((e) => e.referenceType.equals('cheque_drift_repair'))
              ..where((e) => e.referenceId.equals(rec.partyId))
              ..where((e) => e.isDeleted.equals(false))
              ..limit(1))
            .getSingleOrNull();
        if (alreadyPosted != null) continue;

        // Customer sub-account: `party.accountId`, else the mapped receivables
        // control account — exactly as `cheque_receipt_jes.dart:62-76`.
        Account? customerAccount;
        final party = await (_db.select(_db.parties)
              ..where((p) => p.id.equals(rec.partyId))
              ..limit(1))
            .getSingleOrNull();
        if (party?.accountId != null) {
          customerAccount = await _db.getAccountById(party!.accountId!);
        }
        customerAccount ??= await _db.getAccountByCode(
          await _db.getMappedAccountCode(
            'receivables',
            AccountingDao.accountPurposes['receivables']!,
          ),
        );
        if (customerAccount == null) {
          // No sub-account and no receivables-control fallback — the correction
          // cannot be posted for this customer. Fail closed for the WHOLE run
          // (throw rolls the transaction back; the applied flag was not set, so
          // the repair stays re-runnable once the COA is fixed).
          throw StateError(
            'تعذّر إيجاد حساب فرعي للعميل "${rec.partyName}" ولا يوجد حساب ذمم '
            'العملاء الرئيسي. يرجى مراجعة بطاقة العميل أو إعدادات الحسابات.',
          );
        }

        // Reversing JE: Dr customer sub-account / Cr clearing suspense.
        await _db.createJournalEntry(
          description: 'تصحيح ازدواج قبض شيكات — تسوية فرق سابق',
          date: repairedAt,
          lines: [
            JournalLine(
              accountId: customerAccount.id,
              debit: amount,
              credit: 0,
              description: 'تصحيح رصيد العميل — ${rec.partyName}',
            ),
            JournalLine(
              accountId: clearingAccount.id,
              debit: 0,
              credit: amount,
              description: 'مقاصة فرق ازدواج قبض الشيكات',
            ),
          ],
          referenceType: 'cheque_drift_repair',
          referenceId: rec.partyId,
          isAutoPosted: true,
        );

        // Stored balance moves with the ledger: +overCreditTotal (D4).
        await _db.adjustPartyBalance(
          rec.partyId,
          amount,
          changedBy: changedBy,
          changeReason: 'إصلاح ازدواج قبض شيكات - Spec 138',
        );

        report.add({
          'partyId': rec.partyId,
          'name': rec.partyName,
          'amount': amount,
          'at': repairedAt.toIso8601String(),
          'byUserId': changedBy, // R5 — operator accountability (FR-008)
        });
        total += amount;
        healed++;
      }

      // R2(a) — flag + report written INSIDE the transaction, so they are atomic
      // with the heal (no "report lost between commit and setSetting" window).
      await _db.setSetting(
          kChequeReceiptDriftRepairV1Report, jsonEncode(report));
      await _db.setSetting(kChequeReceiptDriftRepairV1Applied, 'true');

      return (
        aborted: false,
        healedCount: healed,
        totalHealed: total,
        report: report,
      );
    });

    // A concurrent run beat us to it (flag already set inside the txn).
    if (aborted) {
      return ChequeDriftRepairResult.skipped(
          ChequeDriftRepairReason.alreadyApplied);
    }

    await DiagnosticLogger.log(
      'CHEQUE-RECEIPT-DRIFT-REPAIR',
      'healed=$healedCount total=${totalHealed.toStringAsFixed(2)}',
    );

    // Every population row was already healed / skipped (belt or amount<=0):
    // no new correction posted → noop (the flag is still set — the install is
    // "done").
    if (healedCount == 0) return ChequeDriftRepairResult.noop();
    return ChequeDriftRepairResult.healed(healedCount, totalHealed);
  }
}
