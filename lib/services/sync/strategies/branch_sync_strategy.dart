// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/branch_dedup_extension.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';

class BranchSyncStrategy extends SyncStrategy {
  BranchSyncStrategy(super.db);

  // Feature 035 / FR-005 — names the seeder uses for the default
  // "main branch" row. Tier 4 re-link will only re-attach an inactive
  // row to a server identity if its name is in this allowlist; that
  // keeps the heuristic conservative and prevents resurrecting any
  // row that an operator deliberately renamed and deactivated.
  // Kept in sync with the Cluster 029 retroactive cleanup pass below.
  static const _knownSeedNames = <String>['الفرع الرئيسي', 'Main Branch'];

  @override
  String get tableName => 'branches';

  @override
  String get apiEndpoint => '/api/branches';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final branches = json['branches'] as List;
    // Feature 035 / FR-011 — wrap the whole sync pass in a transaction so
    // a mid-flight failure doesn't leave the local table half-merged.
    // Constitution Principle IV (atomic persistence for multi-step writes).
    await db.transaction(() async {
      await _syncFromJsonImpl(branches);
    });

    // Force UI refresh after sync (outside transaction — pure event emit).
    if (branches.isNotEmpty) {
      db.markTablesUpdated({db.branches});
    }
  }

  Future<void> _syncFromJsonImpl(List<dynamic> branches) async {
    // Cluster 023 / Issue 5 — track every branch the server returned so we
    // can deactivate locally-known branches the server has dropped (the
    // user reported deleted "الفرع الرئيسي" still showing in the mirror's
    // filter). The endpoint returns every branch unpaginated, so absence
    // == server-side delete.
    final seenServerIds = <int>{};
    final seenServerGlobalIds = <String>{};
    final seenLocalIds = <int>{};
    // Spec 029 corrective patch (2026-05-10) — track local ids already
    // matched/upserted IN THIS BATCH. If two server rows both fallback to
    // the same local row by name, that's a server-side duplicate (the
    // server has multiple "الفرع الرئيسي" rows with different globalIds).
    // Without this guard the second server row's globalId overwrites the
    // first's on the same local row, and a third row overwrites again —
    // the flip-flop the mirror log on 2026-05-10T10:50 exposed (localId=5
    // had its globalId rewritten 3× in a single pull cycle). Now the
    // first server row claims the local row; subsequent server rows
    // matching the same local row via name fallback are recorded as
    // server-side dupes and SKIPPED on the mirror (log only). The server
    // operator must dedup their branches table before the symptom fully
    // disappears, but at least the mirror stays stable.
    final claimedLocalIds = <int>{};
    for (final b in branches) {
      final serverId = parseInt(b['id']);
      final serverGlobalId = b['globalId'] as String?;
      final serverName = b['name'] as String;

      // FIX 2026-04-28: Three-tier dedup to prevent duplicates after the
      // first DeltaPull on a freshly-paired client. Without this the local
      // seeded "الفرع الرئيسي" (id=1, locally-minted globalId) and the
      // server's "الفرع الرئيسي" (id=5, server-minted globalId) become two
      // different rows.
      Branche? existing;
      String? matchTier;
      // Feature 035 / FR-001..003: each tier picks the best match using
      // an ORDER BY + LIMIT 1 rather than getSingleOrNull(), so legacy
      // polluted state (multiple rows sharing a name/id) never throws
      // StateError. Selection: active rows first, then row whose globalId
      // equals the server's (a proxy for "this is already the canonical
      // row"), then smallest id (deterministic tie-break).
      OrderingTerm activeFirst($BranchesTable t) =>
          OrderingTerm(expression: t.isActive, mode: OrderingMode.desc);
      OrderingTerm gidMatchFirst($BranchesTable t) => OrderingTerm(
            expression: t.globalId.equalsNullable(serverGlobalId),
            mode: OrderingMode.desc,
          );
      OrderingTerm idAsc($BranchesTable t) =>
          OrderingTerm(expression: t.id, mode: OrderingMode.asc);

      // Tier 1: globalId match (strongest). Schema enforces UNIQUE on
      // global_id since v119, but the ORDER BY + LIMIT 1 is harmless and
      // future-proofs against any schema relaxation.
      if (serverGlobalId != null && serverGlobalId.isNotEmpty) {
        existing = await (db.select(db.branches)
              ..where((t) => t.globalId.equals(serverGlobalId))
              ..orderBy([activeFirst, idAsc])
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) matchTier = 'globalId';
      }
      // Tier 2: name match — catches the locally-seeded default that has
      // a different globalId from the server's row but the same display
      // name. THIS is where pre-fix sync crashed: the post-dedup state
      // routinely has multiple rows sharing a name.
      if (existing == null) {
        existing = await (db.select(db.branches)
              ..where((t) => t.name.equals(serverName))
              ..orderBy([activeFirst, gidMatchFirst, idAsc])
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) matchTier = 'name';
      }
      // Tier 3: server id match (legacy)
      if (existing == null) {
        existing = await (db.select(db.branches)
              ..where((t) => t.id.equals(serverId))
              ..orderBy([activeFirst, gidMatchFirst, idAsc])
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) matchTier = 'serverId';
      }

      // Feature 035 / FR-005 Tier 4: re-link an inactive locally-seeded
      // default instead of inserting a fresh row. Conservative — only
      // fires when exactly ONE inactive row matches the knownSeedNames
      // allowlist and hasn't already been resolved this pass. The
      // rename-on-server symptom (US1's original goal) is solved here:
      // the seeded "الفرع الرئيسي" gets its globalId + name rewritten
      // to the server's instead of being orphaned by an insert.
      if (existing == null) {
        final candidates = await (db.select(db.branches)
              ..where((t) =>
                  t.isActive.equals(false) &
                  t.name.isIn(_knownSeedNames) &
                  t.id.isNotIn(seenLocalIds))
              ..orderBy([idAsc]))
            .get();
        if (candidates.length == 1) {
          existing = candidates.first;
          matchTier = 'relink';
        }
      }

      // Telemetry: emit a structured WARN whenever a row matched on a
      // weaker fallback tier. Helps diagnose drift in the field without
      // changing behavior.
      if (matchTier == 'name' ||
          matchTier == 'serverId' ||
          matchTier == 'relink') {
        await DiagnosticLogger.log(
          'SYNC-WARN',
          'branches matched on $matchTier fallback (name="$serverName" '
              'serverId=$serverId serverGlobalId=$serverGlobalId '
              'localId=${existing!.id} localGlobalId=${existing.globalId})',
        );
      }

      // Spec 029 corrective patch — server-side duplicate guard. If the
      // local row we just matched was ALREADY claimed by a previous
      // server row in this batch (via name fallback), we are looking at
      // a server-side duplicate. Record the seen-server-id so the
      // straggler-cleanup loop downstream still sees this entry, but
      // SKIP the upsert so we don't flip-flop the local row's globalId.
      if (existing != null &&
          claimedLocalIds.contains(existing.id) &&
          (matchTier == 'name' || matchTier == 'serverId')) {
        await DiagnosticLogger.log(
          'SYNC-WARN',
          'branches server-side DUPLICATE detected — skipped to keep '
              'mirror stable (name="$serverName" duplicate '
              'serverId=$serverId serverGlobalId=$serverGlobalId '
              'already-claimed localId=${existing.id}). The server has '
              'multiple "$serverName" rows; operator should dedup the '
              'server\'s branches table.',
        );
        // Still record the seen-server-id so the orphan-cleanup loop
        // doesn't deactivate the local row in this same pull cycle.
        seenServerIds.add(serverId);
        if (serverGlobalId != null && serverGlobalId.isNotEmpty) {
          seenServerGlobalIds.add(serverGlobalId);
        }
        seenLocalIds.add(existing.id);
        continue;
      }

      // Use existing local id when matched so dependent FKs stay valid.
      final useId = existing?.id ?? serverId;
      final companion = BranchesCompanion(
        id: Value(useId),
        name: Value(serverName),
        code: Value(b['code'] as String?),
        globalId: Value(serverGlobalId),
        address: Value(b['address'] as String?),
        phone: Value(b['phone'] as String?),
        isActive: Value(parseBool(b['isActive'], true)),
        costCenterId: Value(parseIntNullable(b['costCenterId'])),
        regionId: Value(parseIntNullable(b['regionId'])),
      );
      await db.into(db.branches).insertOnConflictUpdate(companion);
      if (existing != null && existing.id == useId && existing.globalId != serverGlobalId) {
        debugPrint('[BranchSync] Merged local "$serverName" id=${existing.id} with server globalId');
      }
      seenServerIds.add(serverId);
      if (serverGlobalId != null && serverGlobalId.isNotEmpty) {
        seenServerGlobalIds.add(serverGlobalId);
      }
      seenLocalIds.add(useId);
      claimedLocalIds.add(useId);
    }

    // Cluster 023 / Issue 5 — propagate server-side deletes. Any active
    // local branch that the server didn't return is now stale; deactivate
    // it so it stops appearing in dropdown filters. Soft-delete only —
    // never hard-delete, because dependent FKs (warehouses, safes,
    // invoices, JEs) still reference these rows. Deactivation is enough
    // to remove them from the active-only filters the user complained
    // about. Match by globalId first (strongest), then id (legacy server
    // ids); rows with neither match get deactivated.
    if (branches.isNotEmpty) {
      // Spec 088 USR-2 — on mirror mode, DO NOT auto-deactivate based on
      // sync-response absence. A mirror's response can be filtered by
      // the calling user's server-side scope; absence is NOT proof of
      // deletion. Server-side soft-delete (a row returned with
      // isActive=false) is still honored in the upsert pass above
      // (insertOnConflictUpdate), which remains the canonical channel
      // for branch retirement (FR-202). Client mode behavior is
      // unchanged (FR-204).
      if (SyncInterceptor.isMirrorMode) {
        final localBranches = await (db.select(db.branches)
              ..where((b) => b.isActive.equals(true)))
            .get();
        final skipped = <Branche>[];
        for (final local in localBranches) {
          if (seenLocalIds.contains(local.id)) continue;
          final byGid = local.globalId != null &&
              local.globalId!.isNotEmpty &&
              seenServerGlobalIds.contains(local.globalId);
          final byId = seenServerIds.contains(local.id);
          if (!byGid && !byId) skipped.add(local);
        }
        if (skipped.isNotEmpty) {
          final names =
              skipped.map((b) => '${b.name}(localId=${b.id})').join(', ');
          await DiagnosticLogger.log(
            'SYNC-INFO',
            'branches skipped — mirror mode: not deactivating '
            '${skipped.length} branch(es) absent from server response '
            '($names). Spec 088 USR-2 / FR-201/FR-203.',
          );
        }
        return;
      }
      final localBranches = await (db.select(db.branches)
            ..where((b) => b.isActive.equals(true)))
          .get();
      final orphaned = <Branche>[];
      for (final local in localBranches) {
        if (seenLocalIds.contains(local.id)) continue;
        final byGid = local.globalId != null &&
            local.globalId!.isNotEmpty &&
            seenServerGlobalIds.contains(local.globalId);
        final byId = seenServerIds.contains(local.id);
        if (!byGid && !byId) orphaned.add(local);
      }
      for (final stale in orphaned) {
        await (db.update(db.branches)..where((t) => t.id.equals(stale.id)))
            .write(const BranchesCompanion(isActive: Value(false)));
        await DiagnosticLogger.log(
          'SYNC-WARN',
          'branches deactivated locally because absent from server response '
          '(localId=${stale.id} name="${stale.name}" '
          'localGlobalId=${stale.globalId}). Cluster 023 / Issue 5 propagation.',
        );
      }

      // Cluster 023 / Issue 5 — one-shot dedup pass for sites that already
      // accumulated multiple "الفرع الرئيسي"-style rows from earlier
      // R8/Tier-2 name-fallback matches. Among rows sharing a name, keep
      // the one whose globalId equals the server's (or, failing that, the
      // lowest id) and deactivate the rest. Never hard-delete (FKs).
      final allActive = await (db.select(db.branches)
            ..where((b) => b.isActive.equals(true)))
          .get();
      final byName = <String, List<Branche>>{};
      for (final br in allActive) {
        byName.putIfAbsent(br.name, () => []).add(br);
      }
      for (final entry in byName.entries) {
        if (entry.value.length < 2) continue;
        final group = entry.value;
        Branche keeper = group.first;
        for (final br in group) {
          final isAuthoritative = br.globalId != null &&
              br.globalId!.isNotEmpty &&
              seenServerGlobalIds.contains(br.globalId);
          if (isAuthoritative) {
            keeper = br;
            break;
          }
          if (br.id < keeper.id) keeper = br;
        }
        for (final br in group) {
          if (br.id == keeper.id) continue;
          // Feature 035 / FR-009: repoint dependent FKs to the keeper
          // BEFORE soft-deactivating the loser. Pre-fix, the FKs stayed
          // pointing at the now-inactive row, hiding historical data
          // from active-branch-filtered reports.
          await db.remapBranchFks(br.id, keeper.id);
          await (db.update(db.branches)..where((t) => t.id.equals(br.id)))
              .write(const BranchesCompanion(isActive: Value(false)));
          await DiagnosticLogger.log(
            'SYNC-WARN',
            'branches deduped — deactivated duplicate "${br.name}" '
            '(localId=${br.id} kept localId=${keeper.id}, FKs remapped). '
            'Cluster 023 / Issue 5 dedup.',
          );
        }
      }

      // Cluster 029 — extra cleanup for the "renamed on server" case:
      // local has an active "الفرع الرئيسي" with a locally-minted
      // globalId NOT in the server's response. The earlier name-based
      // dedup couldn't catch it (different names), and the orphan
      // deactivation also passes when local id happens to coincide with
      // a server id (different branch, same numeric id). Deactivate any
      // such row — the server clearly owns the branch namespace under
      // a different name + globalId now.
      final stragglers = await (db.select(db.branches)
            ..where((b) => b.isActive.equals(true) & b.name.isIn(_knownSeedNames)))
          .get();
      for (final s in stragglers) {
        // Skip if the server actually returned this exact row (matching
        // globalId) — operator may legitimately keep this name on HQ.
        if (s.globalId != null &&
            s.globalId!.isNotEmpty &&
            seenServerGlobalIds.contains(s.globalId)) {
          continue;
        }
        // Skip if no server branches at all — without authority we can't
        // declare this a straggler.
        if (seenServerGlobalIds.isEmpty && seenServerIds.isEmpty) continue;
        await (db.update(db.branches)..where((t) => t.id.equals(s.id)))
            .write(const BranchesCompanion(isActive: Value(false)));
        await DiagnosticLogger.log(
          'SYNC-WARN',
          'branches deactivated locally-seeded "${s.name}" '
          '(localId=${s.id} localGlobalId=${s.globalId}) — server\'s '
          'branch list does not include it. Cluster 029 retroactive cleanup.',
        );
      }
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.branches).insertOnConflictUpdate(record as BranchesCompanion);
  }
}