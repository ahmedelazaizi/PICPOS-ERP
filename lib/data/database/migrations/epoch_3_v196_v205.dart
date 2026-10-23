part of '../database.dart';

// Epoch 3, steps v196 → v205 (tables / reservations / permissions plan,
// docs/plans/2026-10-18-tables-reservations-permissions-plan.md §C-P0).
// New steps are APPENDED here in ascending order (v197 table-reservation
// engine, v198 booking services → products …); the next file starts at v206.
extension Epoch3V196ToV205Migrations on AppDatabase {
  Future<void> _migrateEpoch3V196ToV205(Migrator m, int from) async {
    // v196 — customers are the single reference for reservations (P3):
    // table_reservations.party_id (bookings.party_id already exists),
    // party indexes and the local party_dedup_suspects report table. Then the
    // owner-approved F.1 backfill links / creates customers by phone. The
    // backfill is data repair, so a failure is logged and never blocks boot
    // (rows stay guests; `backfillReservationParties(force: true)` re-runs it).
    if (from < 196) {
      await _safeMigrate(
          'v196 reservation parties', ensureReservationPartiesSchema);
      try {
        await backfillReservationParties();
      } catch (e) {
        debugPrint('[Migration] v196 reservation parties backfill: $e');
      }
    }
  }
}
