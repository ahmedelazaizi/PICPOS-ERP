// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/core/utils/uuid_v7.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

class FiscalYearSyncStrategy extends SyncStrategy {
  FiscalYearSyncStrategy(super.db);

  @override
  String get tableName => 'fiscalYears';

  @override
  String get apiEndpoint => '/api/fiscal-years';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final items = json['fiscal_years'] as List;
    // Cluster 028 / Bug 5 (mirror "السنوات المالية" duplicated): the previous
    // implementation called `insertOnConflictUpdate` keyed only on the
    // server's `id`, so a locally-seeded fiscal year (id=1, locally-minted
    // globalId) and the server's row (id=5, server-minted globalId) ended
    // up as two distinct rows. Mirrors thereafter showed two
    // "السنة المالية 2026" entries with identical date ranges. Mirror
    // mirror three-tier dedup pattern from BranchSyncStrategy.
    final seenServerIds = <int>{};
    final seenServerGlobalIds = <String>{};
    final seenLocalIds = <int>{};
    for (final f in items) {
      final serverId = parseInt(f['id']);
      final serverGlobalId = f['globalId'] as String?;
      final serverName = f['name'] as String;
      final startDate = DateTime.fromMillisecondsSinceEpoch(
          parseInt(f['startDate']) * 1000);
      final endDate = DateTime.fromMillisecondsSinceEpoch(
          parseInt(f['endDate']) * 1000);

      // Spec 136 — silent-drift guard. When the SERVER row still carries a
      // NULL globalId (a pre-globalId row the server hasn't backfilled yet),
      // do NOT adopt that NULL: it would wipe the local row's
      // correctly-derived gid and keep the name+dates fallback firing on every
      // pull (the field SYNC-WARN). Derive the SAME deterministic gid the
      // startup backfill uses (UuidV5 of name + y/m/d) so both instances
      // converge on it — and so Tier-1 below matches the locally-healed row
      // instead of falling through to the name+dates tier. Once the server
      // boots the +208 build its own backfill mints the identical gid and
      // everything stays on Tier-1.
      final effectiveGlobalId =
          (serverGlobalId != null && serverGlobalId.isNotEmpty)
              ? serverGlobalId
              : UuidV7.deriveFiscalYearGlobalId(
                  name: serverName, startDate: startDate, endDate: endDate);

      FiscalYearData? existing;
      String? matchTier;
      // Tier 1: globalId match (strongest) — uses the effective (derived when
      // the server's is NULL) gid so a NULL server gid no longer forces a
      // name+dates fallback.
      existing = await (db.select(db.fiscalYears)
            ..where((t) => t.globalId.equals(effectiveGlobalId)))
          .getSingleOrNull();
      if (existing != null) matchTier = 'globalId';
      // Tier 2: name + start + end match — catches the locally-seeded row
      // whose globalId differs from the server's. Real fiscal years have
      // unique date ranges so this triple is essentially the natural key.
      if (existing == null) {
        existing = await (db.select(db.fiscalYears)
              ..where((t) =>
                  t.name.equals(serverName) &
                  t.startDate.equals(startDate) &
                  t.endDate.equals(endDate)))
            .getSingleOrNull();
        if (existing != null) matchTier = 'name+dates';
      }
      // Tier 3: server id match (legacy).
      if (existing == null) {
        existing = await (db.select(db.fiscalYears)
              ..where((t) => t.id.equals(serverId)))
            .getSingleOrNull();
        if (existing != null) matchTier = 'serverId';
      }

      if (matchTier == 'name+dates' || matchTier == 'serverId') {
        await DiagnosticLogger.log(
          'SYNC-WARN',
          'fiscalYears matched on $matchTier fallback (name="$serverName" '
              'start=$startDate end=$endDate serverId=$serverId '
              'serverGlobalId=$serverGlobalId effectiveGlobalId=$effectiveGlobalId '
              'localId=${existing!.id} localGlobalId=${existing.globalId})',
        );
      }

      // Reuse the existing local id when matched so dependent FKs
      // (accounting_periods.fiscal_year_id, etc.) stay valid.
      final useId = existing?.id ?? serverId;
      final companion = FiscalYearsCompanion(
        id: Value(useId),
        name: Value(serverName),
        startDate: Value(startDate),
        endDate: Value(endDate),
        isClosed: Value(parseBool(f['isClosed'])),
        isCurrent: Value(parseBool(f['isCurrent'])),
        // Spec 136 — write the effective gid (server's, or the deterministic
        // derived one when the server's is NULL) so the local row never gets
        // its gid blanked by a not-yet-backfilled server.
        globalId: Value(effectiveGlobalId),
      );
      await db.into(db.fiscalYears).insertOnConflictUpdate(companion);
      if (existing != null &&
          existing.id == useId &&
          existing.globalId != effectiveGlobalId) {
        debugPrint(
            '[FiscalYearSync] merged local "$serverName" id=${existing.id} with effective globalId');
      }
      seenServerIds.add(serverId);
      seenServerGlobalIds.add(effectiveGlobalId);
      seenLocalIds.add(useId);
    }

    // One-shot dedup pass for sites that already accumulated multiple
    // rows from the previous (id-only) sync. Among rows sharing
    // (name + startDate + endDate), keep the one whose globalId
    // matches the server's response (or the lowest id), and soft-mark
    // the rest by appending a "(مكرر)" suffix to make them obvious.
    // We can't physically delete because accounting_periods rows
    // reference them via FK — same constraint as branches dedup.
    if (items.isNotEmpty) {
      final allYears = await db.select(db.fiscalYears).get();
      final byKey = <String, List<FiscalYearData>>{};
      for (final fy in allYears) {
        if (fy.name.contains('(مكرر')) continue;
        final key = '${fy.name}|${fy.startDate.toIso8601String()}|${fy.endDate.toIso8601String()}';
        byKey.putIfAbsent(key, () => []).add(fy);
      }
      for (final entry in byKey.entries) {
        if (entry.value.length < 2) continue;
        final group = entry.value;
        FiscalYearData keeper = group.first;
        for (final fy in group) {
          final isAuthoritative = fy.globalId != null &&
              fy.globalId!.isNotEmpty &&
              seenServerGlobalIds.contains(fy.globalId);
          if (isAuthoritative) {
            keeper = fy;
            break;
          }
          if (fy.id < keeper.id) keeper = fy;
        }
        for (final fy in group) {
          if (fy.id == keeper.id) continue;
          // Soft-mark — operator sees clearly which row to ignore;
          // accounting_periods FKs stay valid.
          await (db.update(db.fiscalYears)
                ..where((t) => t.id.equals(fy.id)))
              .write(FiscalYearsCompanion(
                  name: Value('${fy.name} (مكرر)')));
          await DiagnosticLogger.log(
            'SYNC-WARN',
            'fiscalYears deduped — soft-marked duplicate "${fy.name}" '
            '(localId=${fy.id} kept localId=${keeper.id})',
          );
        }
      }
    }

    if (items.isNotEmpty) {
      db.markTablesUpdated({db.fiscalYears});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db
        .into(db.fiscalYears)
        .insertOnConflictUpdate(record as FiscalYearsCompanion);
  }
}