// Server-side duplicate parties dedup (Spec 084d).
part of '../database.dart';

extension PartyDedupDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════════
  // SERVER-SIDE DUPLICATE PARTIES DEDUP (Spec 084d)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Field smoke V148 reported 3 delivery-company parties duplicated 2-3
  // times each on a production server (only the first row of each name
  // had a balance; copies had 0.000). The sync strategy emits a
  // SYNC-WARN line on name+phone fallback matches but never merges —
  // operator had to fix manually via SQL.
  //
  // Mirrors Spec 084c (branches dedup) — keep the two implementations
  // in lockstep when the audit/repair pattern evolves.
  //
  // Server mode only. The Settings UI gates the section on
  // `NetworkService.instance.isServerRunning`.

  /// Find groups of active parties sharing a name. Within each group,
  /// the row with the highest reference count is the suggested
  /// canonical pick (ties broken by lowest id). For parties, the
  /// "attached transactional refs" check is wider than branches —
  /// sales/purchase invoices, safe transactions (vouchers), and
  /// commercial papers all anchor a party to real money in the books.
  Future<List<DuplicatePartyGroup>> auditDuplicateParties() async {
    final rows = await customSelect(r'''
      WITH dup_names AS (
        SELECT name FROM parties
        WHERE is_active = TRUE
        GROUP BY name HAVING COUNT(*) > 1
      ),
      ref_counts AS (
        SELECT p.id, p.name, p.phone, p.balance, p.is_customer, p.is_supplier,
               p.global_id,
               (SELECT COUNT(*) FROM sales_invoices    WHERE customer_id = p.id)
             + (SELECT COUNT(*) FROM purchase_invoices WHERE supplier_id = p.id)
             + (SELECT COUNT(*) FROM safe_transactions WHERE party_id    = p.id)
             + (SELECT COUNT(*) FROM commercial_papers WHERE party_id    = p.id)
               AS ref_count,
               (SELECT COUNT(*) FROM sales_invoices    WHERE customer_id = p.id)
             + (SELECT COUNT(*) FROM purchase_invoices WHERE supplier_id = p.id)
             + (SELECT COUNT(*) FROM safe_transactions WHERE party_id    = p.id)
             + (SELECT COUNT(*) FROM commercial_papers WHERE party_id    = p.id)
               AS attached_txn_refs
        FROM parties p
        WHERE p.is_active = TRUE
          AND p.name IN (SELECT name FROM dup_names)
      )
      SELECT id, name, phone, balance, is_customer, is_supplier,
             global_id, ref_count, attached_txn_refs
      FROM ref_counts
      ORDER BY name, ref_count DESC, id ASC
    ''').get();

    final byName = <String, List<DuplicatePartyRow>>{};
    for (final r in rows) {
      final name = r.read<String>('name');
      byName.putIfAbsent(name, () => []).add(DuplicatePartyRow(
            id: r.read<int>('id'),
            name: name,
            phone: r.read<String?>('phone'),
            balance: (r.data['balance'] as num?)?.toDouble() ?? 0,
            isCustomer: (r.data['is_customer'] as int? ?? 0) == 1 ||
                r.data['is_customer'] == true,
            isSupplier: (r.data['is_supplier'] as int? ?? 0) == 1 ||
                r.data['is_supplier'] == true,
            globalId: r.read<String?>('global_id'),
            refCount: r.read<int>('ref_count'),
            attachedTxnRefs: r.read<int>('attached_txn_refs'),
          ));
    }

    return byName.entries.map((e) {
      final all = e.value;
      return DuplicatePartyGroup(
        name: e.key,
        canonical: all.first,
        duplicates: all.skip(1).toList(),
      );
    }).toList();
  }

  /// Run the dedup repair. Duplicates with ANY attached transactional
  /// row (invoice / voucher / commercial paper) are SKIPPED — those
  /// must be manually merged via party-merge tools (not part of this
  /// spec). Duplicates with zero refs are safely soft-deleted.
  ///
  /// All steps run inside `transaction()`; any exception rolls back.
  /// Each merged or skipped duplicate emits one `DiagnosticLogger`
  /// line tagged `PARTY-DEDUP`.
  Future<PartyDedupResult> repairDuplicateParties() async {
    return await transaction(() async {
      final groups = await auditDuplicateParties();
      final merged = <MergedPartyDedupRecord>[];
      final skipped = <SkippedPartyDedupRecord>[];

      for (final g in groups) {
        for (final dup in g.duplicates) {
          // J3 — the system cash party is never retired as a duplicate.
          if (await systemRoleOfParty(dup.id) != null) continue;
          if (dup.attachedTxnRefs > 0) {
            skipped.add(SkippedPartyDedupRecord(
              dupId: dup.id,
              canonicalId: g.canonical.id,
              name: g.name,
              attachedTxnRefs: dup.attachedTxnRefs,
              balance: dup.balance,
            ));
            await DiagnosticLogger.log(
              'PARTY-DEDUP',
              'SKIP dupId=${dup.id} → canonicalId=${g.canonical.id} '
                  'name="${g.name}" attachedTxnRefs=${dup.attachedTxnRefs} '
                  'balance=${dup.balance}',
            );
            continue;
          }

          // Soft-delete the duplicate. Parties without any
          // transactional refs are safe to retire — they're typically
          // sync-fallback duplicates that never accumulated history.
          // The party's balance is non-load-bearing in this case
          // (transactions adjust it; with zero refs the balance
          // must also be zero or close to it).
          await (update(parties)..where((p) => p.id.equals(dup.id))).write(
            PartiesCompanion(
              isActive: const Value(false),
              deletedAt: Value(DateTime.now()),
              lastModifiedAt: Value(DateTime.now()),
            ),
          );

          merged.add(MergedPartyDedupRecord(
            dupId: dup.id,
            canonicalId: g.canonical.id,
            name: g.name,
          ));
          await DiagnosticLogger.log(
            'PARTY-DEDUP',
            'merged dupId=${dup.id} → canonicalId=${g.canonical.id} '
                'name="${g.name}" (no attached refs — safe soft-delete)',
          );
        }
      }

      return PartyDedupResult(merged: merged, skipped: skipped);
    });
  }
}
