// ignore_for_file: avoid_dynamic_calls
import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';

/// Spec 029 / US3 Bug B — operator-active carve-out window. If a local
/// shift is `status='open'` AND the server pull says `status='closed'`,
/// AND the local row was modified within this window, the local row
/// wins (operator activity beats stale server state). Outside this
/// window the standard `lastWriteWins` comparison applies.
const Duration _openShiftCarveOut = Duration(minutes: 5);

/// Feature 036 — reverse-direction carve-out (Beta Round 9 Issue 1).
///
/// If a local shift is `status='closed'` AND the server pull says
/// `status='open'`, AND the local close happened within this window,
/// the local row wins. Without this carve-out, the operator-reported
/// symptom was: cashier closes a shift, opens a new one, then a
/// pending mirror outbox push for the OLD shift's open event reaches
/// the server AFTER the close push had already updated server-side
/// `lastModifiedAt`, leaving the server in an inconsistent
/// "open with later stamp" state. The next DeltaPull then ran the
/// upsert at the bottom of this strategy and FLIPPED the local row
/// from closed back to open → `getCurrentOpenShift(userId)` started
/// returning the OLD shift → the new shift's closing report
/// aggregated BOTH shifts' invoices/cash on the same drawer-count.
///
/// 4 hours is generous enough to cover a full cashier shift plus
/// outbox lag, short enough that a genuine multi-day-offline scenario
/// would still resolve via `lastWriteWins` after the carve-out
/// expires. Triggers a `SHIFT-SYNC` diagnostic log so the field can
/// audit whenever the carve-out fires.
const Duration _closedShiftCarveOut = Duration(hours: 4);

class ShiftSyncStrategy extends SyncStrategy {
  ShiftSyncStrategy(super.db);

  @override
  String get tableName => 'shifts';

  @override
  String get apiEndpoint => '/api/shifts';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final shifts = json['shifts'] as List;
    for (final s in shifts) {
      final serverId = parseInt(s['id']);
      final serverGlobalId = s['globalId'] as String?;
      final serverUserId = parseInt(s['userId']);
      final serverStartTime = DateTime.parse(s['startTime'] as String);
      final serverEndTimeRaw = s['endTime'];
      final serverStatus = s['status'] as String;

      // Feature 012 / Issue C-SHIFT-LOOP: previously the strategy upserted
      // by serverId only. On a CLIENT/MIRROR device the local `shifts.id`
      // is auto-incremented locally and is INDEPENDENT of the server's
      // auto-increment. If those id spaces collide on the same number for
      // two different logical shifts (one local-open + one server-closed),
      // upsertById SILENTLY OVERWRITES the local open shift's row → the
      // cashier's `getCurrentOpenShift` query returns null → the shift-
      // open dialog re-fires mid-sale.
      //
      // Three-tier match (mirrors BranchSyncStrategy):
      //   T1: globalId match  — strongest cross-device identity.
      //   T2: (userId, startTime) match — same logical shift, locally-
      //        minted id, no globalId yet (waiting for server roundtrip).
      //   T3: serverId match — last-resort legacy path; only safe when
      //        the local row IS the same logical shift.
      Shift? existing;
      if (serverGlobalId != null && serverGlobalId.isNotEmpty) {
        existing = await (db.select(db.shifts)
              ..where((t) => t.globalId.equals(serverGlobalId))
              ..limit(1))
            .getSingleOrNull();
      }
      existing ??= await (db.select(db.shifts)
            ..where((t) =>
                t.userId.equals(serverUserId) &
                t.startTime.equals(serverStartTime))
            ..limit(1))
          .getSingleOrNull();

      // Tier 3 fallback: by-id, BUT only if it points at this same user
      // AND this same start-time (sanity check). Otherwise we'd be
      // overwriting an unrelated locally-minted row that happens to share
      // the same auto-increment value as the server's id.
      if (existing == null) {
        final byId = await (db.select(db.shifts)
              ..where((t) => t.id.equals(serverId))
              ..limit(1))
            .getSingleOrNull();
        if (byId != null &&
            byId.userId == serverUserId &&
            byId.startTime == serverStartTime) {
          existing = byId;
        } else if (byId != null) {
          // ID collision for a DIFFERENT logical shift — refuse to
          // overwrite and instead INSERT the server row at a fresh local
          // id (let the autoincrement assign one). This is the rare case
          // the loop-bug depends on; logging it here makes future field
          // diagnoses cheap.
          debugPrint(
            '[ShiftSync] id-collision: server shift #$serverId targets a '
            'local row owned by userId=${byId.userId} '
            '(vs server userId=$serverUserId). Inserting at fresh local id.',
          );
          await db.into(db.shifts).insert(
                ShiftsCompanion.insert(
                  startTime: serverStartTime,
                  endTime: Value(serverEndTimeRaw != null
                      ? DateTime.parse(serverEndTimeRaw as String)
                      : null),
                  userId: serverUserId,
                  openingBalance: Value(parseDouble(s['openingBalance'])),
                  expectedCash: Value(parseDoubleNullable(s['expectedCash'])),
                  actualCash: Value(parseDoubleNullable(s['actualCash'])),
                  variance: Value(parseDoubleNullable(s['variance'])),
                  status: serverStatus,
                  notes: Value(s['notes'] as String?),
                  closingSnapshot: Value(s['closingSnapshot'] as String?),
                  branchId: Value(
                      parseIntNullable(s['branchId'] ?? s['branch_id'])),
                  globalId: Value(serverGlobalId),
                ),
              );
          continue;
        }
      }

      // Spec 029 / US3 Bug B — `lastWriteWins` semantics with an
      // operator-active open-shift carve-out. Without this, a stale
      // server `status='closed'` row clobbers a freshly-opened local
      // shift, the next login fires the SHIFT-GUARD `suppressed
      // re-prompt` warning, and the cashier sees their open shift
      // disappear on the next DeltaPull.
      //
      // Decision tree (only when an `existing` local row was matched):
      //   1. Local is OPEN, server says CLOSED, local was modified
      //      within `_openShiftCarveOut` → preserve local. Skip upsert.
      //   2. (Feature 036) Local is CLOSED, server says OPEN, local
      //      `endTime` is within `_closedShiftCarveOut` → preserve
      //      local. Skip upsert. Blocks the "phantom re-opened shift"
      //      symptom where the next close-report bundles two shifts'
      //      invoices on the same drawer.
      //   3. Local is strictly newer than server → preserve local.
      //      Skip upsert.
      //   4. Otherwise → fall through to the upsert (server wins or
      //      ties go to server, matching `lastWriteWins`).
      //
      // See specs/029-sync-regression-hardening/contracts/bug-b-shift-sync.md
      // and SYNC_ARCHITECTURE.md §3.1. The carve-out is a documented
      // sub-rule WITHIN `lastWriteWins`, not a fifth conflict policy.
      if (existing != null) {
        final serverLastModifiedRaw = s['lastModifiedAt'];
        final serverLastModified = serverLastModifiedRaw is String
            ? DateTime.tryParse(serverLastModifiedRaw)
            : null;
        // Effective server timestamp falls back to startTime when
        // lastModifiedAt is missing (older servers, pre-Spec-029 builds).
        final effectiveServerStamp = serverLastModified ?? serverStartTime;
        final localStamp = existing.lastModifiedAt ?? existing.createdAt;
        final ageOfLocal = DateTime.now().difference(localStamp);

        final localOpenAndRecent = existing.status == 'open' &&
            serverStatus == 'closed' &&
            ageOfLocal < _openShiftCarveOut;

        if (localOpenAndRecent) {
          unawaited(
            DiagnosticLogger.log(
              'SHIFT-SYNC',
              'preserving local OPEN shift id=${existing.id} '
                  'userId=${existing.userId} (server says closed; local '
                  'active <${_openShiftCarveOut.inMinutes}min)',
            ),
          );
          await _reconcileShiftGlobalId(
              existing.id, existing.globalId, serverGlobalId);
          continue;
        }

        // Feature 036 — reverse carve-out: protect a recently-closed
        // local shift from being flipped back to open. The "age" here
        // is measured from `endTime` when available (the actual close
        // moment is the load-bearing signal — not when the row was
        // last touched by an unrelated DeltaPull), falling back to the
        // generic localStamp for legacy rows missing endTime.
        final localClosedAge = existing.status == 'closed'
            ? DateTime.now().difference(existing.endTime ?? localStamp)
            : Duration.zero;
        final localClosedAndRecent = existing.status == 'closed' &&
            serverStatus == 'open' &&
            localClosedAge < _closedShiftCarveOut;

        if (localClosedAndRecent) {
          unawaited(
            DiagnosticLogger.log(
              'SHIFT-SYNC',
              'preserving local CLOSED shift id=${existing.id} '
                  'userId=${existing.userId} (server says open; local '
                  'closed ${localClosedAge.inMinutes}min ago < '
                  '${_closedShiftCarveOut.inHours}h carve-out). This '
                  'prevents the next shift-close report from bundling '
                  'BOTH shifts\' invoices via a re-opened phantom shift.',
            ),
          );
          await _reconcileShiftGlobalId(
              existing.id, existing.globalId, serverGlobalId);
          continue;
        }

        if (localStamp.isAfter(effectiveServerStamp)) {
          unawaited(
            DiagnosticLogger.log(
              'SHIFT-SYNC',
              'local newer for shift id=${existing.id}; skipping pull',
            ),
          );
          await _reconcileShiftGlobalId(
              existing.id, existing.globalId, serverGlobalId);
          continue;
        }
      } else if (serverStatus == 'open') {
        // Feature 048 (v130) — phantom-open-shift detector. When the
        // server reports `status='open'` for a shift the local DB has
        // NEVER seen (no globalId match, no (userId,startTime) match,
        // no id match), one of the following is true:
        //   1. Another device's open shift legitimately needs to land
        //      here via DeltaPull (e.g. multi-device admin scenario).
        //   2. The server accumulated a phantom open shift because a
        //      previous close call from THIS or another mirror never
        //      propagated — exactly the field symptom that drove
        //      Feature 048's server-side duplicate-open guard.
        //
        // We can't tell the two apart from the row alone, so don't
        // block the INSERT — just log a SYNC-WARN with all the
        // identifying info. Field debuggers reading the diagnostic
        // log will see "phantom" entries multiply when the server
        // has stale open shifts that need data repair.
        unawaited(
          DiagnosticLogger.log(
            'SYNC-WARN',
            'shifts phantom open-shift detected — server reports '
                'status=open for shift serverId=$serverId '
                'globalId=$serverGlobalId userId=$serverUserId '
                'startTime=$serverStartTime, but local has no matching '
                'row across all 3 dedup tiers. This MIGHT be a stale '
                'server-side open that was never closed (operator '
                'should review shift report on the server and close '
                'orphan opens). Feature 048 v130 detector.',
          ),
        );
      }

      await db.into(db.shifts).insertOnConflictUpdate(
        ShiftsCompanion(
          // Re-use the local id when matched; otherwise take the server's.
          id: Value(existing?.id ?? serverId),
          startTime: Value(serverStartTime),
          endTime: Value(serverEndTimeRaw != null
              ? DateTime.parse(serverEndTimeRaw as String)
              : null),
          userId: Value(serverUserId),
          openingBalance: Value(parseDouble(s['openingBalance'])),
          expectedCash: Value(parseDoubleNullable(s['expectedCash'])),
          actualCash: Value(parseDoubleNullable(s['actualCash'])),
          variance: Value(parseDoubleNullable(s['variance'])),
          status: Value(serverStatus),
          notes: Value(s['notes'] as String?),
          // v151 — `Absent` when the server omits the key, NOT `Value(null)`:
          // an older server that doesn't know the column would otherwise wipe
          // a snapshot this device captured locally at close time.
          closingSnapshot: s.containsKey('closingSnapshot')
              ? Value(s['closingSnapshot'] as String?)
              : const Value.absent(),
          // Spec 008 / FR-001: pull the server's branchId so the close-time
          // logic on this client uses the same value the open-time client
          // recorded. Tolerates both `branchId` and snake_case `branch_id`
          // for forward compatibility with API renames.
          branchId: Value(parseIntNullable(s['branchId'] ?? s['branch_id'])),
          globalId: Value(serverGlobalId ?? existing?.globalId),
        ),
      );
    }
    // Force UI refresh after sync
    if (shifts.isNotEmpty) {
      db.markTablesUpdated({db.shifts});
    }
  }

  /// R9 identity reconcile (Spec 136): the lastWriteWins carve-outs above may
  /// legitimately PRESERVE local content over the server's, but the server's
  /// cross-device `globalId` must STILL be adopted when the local row has none.
  /// Otherwise Tier-1 globalId dedup keeps missing this shift forever — a
  /// freshly-opened local shift's createdAt always beats a server row whose
  /// JSON omits `lastModifiedAt` (effectiveServerStamp falls back to startTime),
  /// so the "local newer" carve-out always fires, the upsert that would adopt
  /// the globalId is skipped, and the shift re-duplicates across devices. This
  /// is an identity-only write; status/balances stay governed by the carve-out.
  Future<void> _reconcileShiftGlobalId(
      int localId, String? localGlobalId, String? serverGlobalId) async {
    if (serverGlobalId == null || serverGlobalId.isEmpty) return;
    if (localGlobalId != null && localGlobalId.isNotEmpty) return;
    await (db.update(db.shifts)..where((t) => t.id.equals(localId)))
        .write(ShiftsCompanion(globalId: Value(serverGlobalId)));
    unawaited(DiagnosticLogger.log(
      'SHIFT-SYNC',
      'backfilled server globalId onto local shift id=$localId before '
      'lastWriteWins skip (R9 cross-device identity reconcile)',
    ));
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.shifts).insertOnConflictUpdate(record as ShiftsCompanion);
  }
}