// UUID v7 helper — time-ordered, index-friendly global identifier.
//
// Why v7:
//   - First 48 bits are a unix-millis timestamp, so records inserted in
//     chronological order also sort lexicographically. That keeps the
//     UNIQUE index on `global_id` dense and fast (no random-insert fragmentation
//     like v4 would cause).
//   - Remaining 74 bits are cryptographically random → collision odds are
//     negligible across client + server combined.
//   - Same identifier works in SQLite (TEXT) and PostgreSQL (UUID or TEXT).
//
// Usage at every creation site:
//   final gid = UuidV7.generate();
//   await dao.insert(..., globalId: Value(gid));
//   await ClientWriteInterceptor.sendCreate(tableName: '...', globalId: gid, payload: {...});

import 'package:uuid/uuid.dart';

class UuidV7 {
  UuidV7._();

  static const Uuid _uuid = Uuid();

  /// Generates a new UUID v7 string in canonical 8-4-4-4-12 hex form.
  /// Example: `0190c4e8-7c6d-7a2e-b9a3-4f6b8c0d1e2f`.
  static String generate() => _uuid.v7();

  /// Derives a deterministic UUIDv5 string from
  /// `(saleGlobalId, rawMaterialId, sequenceIndex)` so retrying a
  /// fire-and-forget submitSale reproduces identical
  /// `sale_bom_consumptions.global_id` values for each row.
  ///
  /// Feature 009 / T015 — see `contracts/server-submit-payload.md` §3 and
  /// `tasks.md` T013(e). Uses the same `(NAMESPACE_URL, composite-name)`
  /// pattern that `sales_mutations_dao.dart` already uses for safe-txn
  /// deterministic ids — different namespace URI prefix keeps the two
  /// streams collision-free.
  static String deriveConsumptionGlobalId({
    required String saleGlobalId,
    required int rawMaterialId,
    required int sequenceIndex,
  }) {
    return _uuid.v5(
      Uuid.NAMESPACE_URL,
      'sale_bom_consumption:$saleGlobalId:$rawMaterialId:$sequenceIndex',
    );
  }

  /// Derives a deterministic UUIDv5 for the `shift_closing` row written to
  /// `safe_transactions` when a shift is closed. Both CLIENT and SERVER
  /// compute the SAME globalId from the shift's globalId + the safe's
  /// globalId, so the existing `safe_transactions.globalId` UNIQUE index
  /// (and the new globalId pre-check inside `_closeShiftSafes`) catches the
  /// cross-side duplicate that drove the v122 NEG-BAL regression.
  ///
  /// Feature 041 / Route B.1 — see `specs/041-shift-closing-globalid-dedup/spec.md`.
  /// Pre-fix each side minted a fresh UuidV7 and used its own local shift
  /// id as `referenceId`, so neither the `(safeId, refType, refId)` check
  /// at treasury_dao.dart:622 nor the globalId dedup at
  /// api_data_handler.dart:1793 matched, producing two `shift_closing`
  /// rows per (safe, shift) and driving `safes.balance` to -1× actual.
  static String deriveShiftClosingGlobalId({
    required String shiftGlobalId,
    required String safeGlobalId,
  }) {
    return _uuid.v5(
      Uuid.NAMESPACE_URL,
      'shift_closing:$shiftGlobalId:$safeGlobalId',
    );
  }

  /// Derives a deterministic UUIDv5 for a return-memo `safe_transactions`
  /// row from the underlying invoice's globalId + party id. Both the
  /// mirror's local placeholder and the server's authoritative memo
  /// derive the SAME globalId, so the SafeTransactionSyncStrategy's
  /// Tier 1 (globalId match) dedup catches the pair regardless of any
  /// id mismatch on `referenceId`.
  ///
  /// Cluster 028 / Bug 1 — without this, mirror and server compute
  /// `referenceId` from their respective AUTOINCREMENT id of the
  /// purchase invoice (mirror's local id vs. server's id, almost
  /// always different), so the Tier 2 `(refType, refId, partyId)`
  /// fallback misses and the supplier statement shows TWO rows
  /// (`PRET-LOC-1` + `PRET-1`).
  static String deriveReturnMemoGlobalId({
    required String invoiceGlobalId,
    required String returnType, // 'purchase_return' | 'sales_return'
    required int partyId,
    String? returnEventId,
  }) {
    // Spec 136 ISS-7 — when a per-return-event id is supplied, include it so
    // MULTIPLE partial returns against the SAME invoice get DISTINCT memo
    // globalIds (the original key — invoice+type+party — was constant per
    // invoice, so the 2nd partial return collided on UNIQUE(global_id):
    // 23505 server-side / 2067 locally, rejecting the whole return). The
    // event id is minted once per return by the caller and threaded to BOTH
    // the local insert and the server submit, so the two sides still converge
    // (R9). When absent (older client), the key falls back to the original
    // format — backward compatible.
    final eventPart =
        (returnEventId != null && returnEventId.isNotEmpty)
            ? ':$returnEventId'
            : '';
    return _uuid.v5(
      Uuid.NAMESPACE_URL,
      'return_memo:$returnType:$invoiceGlobalId:$partyId$eventPart',
    );
  }

  /// Derives a deterministic UUIDv5 for a SEEDED master-data default row so
  /// the SQLite client/standalone and the PostgreSQL server compute the SAME
  /// globalId for the same logical row.
  ///
  /// Spec 136 / ISS-2 — pre-fix every seeder minted a fresh [generate] gid, so
  /// the server's "الفرع الرئيسي" (`019e821e…`) and the client's
  /// (`019e8209…`) were two different identifiers for one logical branch. The
  /// sync layer's Tier-1 globalId match therefore always missed and fell back
  /// to name matching, which then tripped the server-side-duplicate guard
  /// (ISS-1). Deriving the seeded gid deterministically makes both sides
  /// converge on the Tier-1 path with no name fallback.
  ///
  /// [seedKey] MUST be the canonical, install-invariant identity of the row
  /// (its seed name, safeType, or fiscal-year natural key) — NOT a value that
  /// can diverge per install. Used only for rows the seeder creates on EVERY
  /// install; user-created master rows keep the random [generate] gid.
  static String deriveSeedGlobalId({
    required String table,
    required String seedKey,
  }) {
    return _uuid.v5(Uuid.NAMESPACE_URL, 'master_seed:$table:$seedKey');
  }

  /// Deterministic globalId for a fiscal year, derived from its natural key
  /// (name + start + end) — which is exactly the Tier-2 match key the
  /// `FiscalYearSyncStrategy` already uses. Both the PG server and the SQLite
  /// client compute the SAME gid for "السنة المالية 2026" (Jan 1 – Dec 31),
  /// so the sync Tier-1 globalId match converges instead of NULL-on-both-sides
  /// name fallback (Spec 136 ISS-2). Used by every fiscal-year creation site
  /// AND the boot backfill so they all derive identically.
  static String deriveFiscalYearGlobalId({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    // Key on the wall-clock DATE components (year-month-day), NOT an epoch.
    // A fiscal year is identified by its calendar span; deriving from
    // `toUtc().millisecondsSinceEpoch` made the gid timezone-dependent, so a
    // server in UTC and a client in UTC+3 derived DIFFERENT gids for the same
    // logical year (Spec 136 review P1-2). Date components are timezone-stable
    // and also absorb the close-year path's time-of-day differences
    // (Jan-1 00:00:00 vs Jan-1 23:59:59) so both creation sites converge.
    String d(DateTime t) => '${t.year}-${t.month}-${t.day}';
    return deriveSeedGlobalId(
      table: 'fiscal_years',
      seedKey: '$name|${d(startDate)}|${d(endDate)}',
    );
  }

  /// Returns `true` if [value] looks like any UUID (v1–v7) in canonical form.
  /// Used by migrations and sync layer sanity checks — we don't want to
  /// accidentally treat an integer id as a global id.
  static bool isValid(String? value) {
    if (value == null || value.length != 36) return false;
    return _uuidPattern.hasMatch(value);
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-7][0-9a-fA-F]{3}-'
    r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
}
