// ═══════════════════════════════════════════════════════════════════════════
// JournalEntryGid — canonical deterministic globalId for auto-posted JEs
// ═══════════════════════════════════════════════════════════════════════════
//
// Spec 129 F5 / FR-501. Replaces the fragile `[IDEM:…]` description-tag dedup
// scanner with a deterministic identity string that mirror + server compute
// identically for the same logical operation. The Tier-1 globalId UNIQUE
// constraint on `journal_entries` then catches duplicates structurally.
//
// Canonical schema:
//   je-<sourceType>-<sourceGid>-<verb>
//
// Where:
//   sourceType — short stable code per origin. Closed set:
//                cp, stockadj, saleret, purret, shiftopen, shiftclose, safeclose
//   sourceGid  — UUIDv7 of the originating entity (commercial_papers.globalId,
//                stock_adjustments.globalId, etc.)
//   verb       — short logical transition / status string. Per-site list in
//                specs/129-mirror-broadcast-discipline/data-model.md §2.2
//
// `compute` is pure-sync — callers emit the `[GID-AUTOPOST]` DiagnosticLogger
// line themselves (see the usage example below), so DAOs can pass the result
// straight into their Drift companion. The high-volume sale/purchase/return
// autopost paths instead use `computeAndLog`, which bundles compute + the
// standard diagnostic in one call (it is intentionally NOT pure-sync); other
// sites with a different log/fallback shape keep `compute` + their own log.
//
// Usage:
//   final gid = JournalEntryGid.compute(
//     sourceType: 'cp',
//     sourceGid: paper.globalId,
//     verb: newStatus,
//   );
//   unawaited(DiagnosticLogger.log(
//     DiagnosticLogger.gidAutopost,
//     'sourceType=cp sourceGid=${paper.globalId.substring(0, 8)} verb=$newStatus',
//   ));
//   await db.into(db.journalEntries).insert(
//     JournalEntriesCompanion.insert(..., globalId: Value(gid)),
//   );

import 'dart:async';

import '../logging/diagnostic_logger.dart';

class JournalEntryGid {
  JournalEntryGid._();

  /// Canonical schema: `je-<sourceType>-<sourceGid>-<verb>`.
  ///
  /// Pure-function. Same args ⇒ same string, on mirror and on server.
  /// All three components must be non-empty ASCII; `sourceType` and `verb`
  /// must not contain hyphens (they would break round-trip parsing if any
  /// downstream code ever needs to split the string).
  static String compute({
    required String sourceType,
    required String sourceGid,
    required String verb,
  }) {
    assert(sourceType.isNotEmpty, 'sourceType must not be empty');
    assert(!sourceType.contains('-'), 'sourceType must not contain hyphens: $sourceType');
    assert(sourceGid.isNotEmpty, 'sourceGid must not be empty');
    assert(verb.isNotEmpty, 'verb must not be empty');
    assert(!verb.contains('-'), 'verb must not contain hyphens: $verb');
    return 'je-$sourceType-$sourceGid-$verb';
  }

  /// [compute] + the standard `[GID-AUTOPOST]` diagnostic in one call, so the
  /// sourceGid truncation length (16) and the log shape stay identical across
  /// the high-volume sale / purchase / return auto-post paths. Returns the gid.
  ///
  /// The caller still owns the `sourceGid` fallback (e.g.
  /// `inv.globalId ?? 'invid${inv.id}'`). Sites with a *different* fallback or
  /// log shape on purpose — treasury shift/safe-close (null → random UUID,
  /// `shiftId=`, 8-char trunc), commercial papers, stock adjustment — keep
  /// their own `compute()` + `log()` and intentionally do not use this helper.
  static String computeAndLog({
    required String sourceType,
    required String sourceGid,
    required String verb,
    required Object invId,
    String suffix = '',
  }) {
    final gid = compute(sourceType: sourceType, sourceGid: sourceGid, verb: verb);
    final shortGid =
        sourceGid.length >= 16 ? sourceGid.substring(0, 16) : sourceGid;
    unawaited(DiagnosticLogger.log(
      DiagnosticLogger.gidAutopost,
      'sourceType=$sourceType sourceGid=$shortGid verb=$verb invId=$invId$suffix',
    ));
    return gid;
  }

  // ── Canonical sourceType values (extension by future specs) ─────────────
  static const sourceCommercialPaper = 'cp';
  static const sourceStockAdjustment = 'stockadj';
  static const sourceSalesReturn = 'saleret';
  static const sourcePurchaseReturn = 'purret';
  static const sourceShiftOpen = 'shiftopen';
  static const sourceShiftClose = 'shiftclose';
  static const sourceSafeClose = 'safeclose';
  // Spec 135: base sale/purchase autopost JE. The highest-volume autopost
  // path — previously minted a random globalId so the client JE and the
  // server JE for one invoice survived DeltaPull as duplicates (the
  // (referenceType, referenceId) dedup can't match across instances because
  // referenceId is a local autoincrement). Keyed on the invoice's shared
  // globalId so both sides converge and the UNIQUE index dedups.
  static const sourceSale = 'sale';
  static const sourcePurchase = 'purchase';
  // Spec 144 (S-COST): landed-cost apply JE. Sheets are local (no globalId of
  // their own), so the sourceGid is keyed on the sheet id — this gives the JE a
  // stable globalId so a retry after a rolled-back apply reuses the SAME id and
  // converges with the already-submitted server row instead of duplicating.
  static const sourceLandedCost = 'landedcost';
  // Spec 146 (S-MFG-GL): manufacturing order JEs (start / overhead / complete /
  // reverse). Orders have no globalId column, so the sourceGid is keyed on the
  // local order id (`order<id>`); the verb distinguishes the four postings.
  // A retried post reuses the SAME gid → the journal_entries.globalId UNIQUE
  // index dedups instead of duplicating. Verbs: start, overhead, complete,
  // revstart (all hyphen-free per compute()'s asserts).
  static const sourceManufacturing = 'mfg';
  // Spec 147 (S-COUNT): the aggregate settlement JE of an inventory count.
  // Both count subsystems post ONE entry per session — the full audit
  // (`audit<id>`) and the cycle-count task (`cycle<id>`) — verb `settle`.
  // Sessions have no globalId column, so the sourceGid keys on the local
  // audit/task id; a retry reuses the SAME gid → journal_entries.globalId
  // UNIQUE dedups. ponytail: local-id key ⇒ multi-device false-collision
  // edge (same class as 146's `order<id>`); real fix = the deferred
  // count-table-sync spec that threads a caller-minted UUID.
  static const sourceInventoryCount = 'invcount';
}
