import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:ural_erp/core/utils/uuid_v7.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/strategies/fiscal_year_sync_strategy.dart';

/// Spec 136 — fiscal-year silent-drift guard.
///
/// When the SERVER's `fiscal_years` row still has `global_id = NULL` (a
/// pre-globalId row it hasn't backfilled), pulling it must NOT blank the local
/// row's correctly-derived gid. The strategy derives the same deterministic gid
/// the startup backfill uses, matches Tier-1 on it, and keeps it on the row —
/// so the name+dates fallback stops firing and both instances converge.
void main() {
  late AppDatabase db;
  late FiscalYearSyncStrategy strategy;

  setUp(() async {
    db = AppDatabase.forTesting();
    strategy = FiscalYearSyncStrategy(db);
  });

  tearDown(() async => db.close());

  Map<String, dynamic> serverPayload({
    required int id,
    String? globalId,
    required String name,
    required DateTime start,
    required DateTime end,
  }) =>
      {
        'fiscal_years': [
          {
            'id': id,
            'globalId': globalId,
            'name': name,
            'startDate': start.millisecondsSinceEpoch ~/ 1000,
            'endDate': end.millisecondsSinceEpoch ~/ 1000,
            'isClosed': false,
            'isCurrent': true,
          }
        ],
      };

  test('NULL server gid does not blank the local deterministic gid', () async {
    const name = 'السنة المالية 2026';
    final start = DateTime(2026, 1, 1);
    final end = DateTime(2026, 12, 31, 23, 59, 59);
    final derived = UuidV7.deriveFiscalYearGlobalId(
        name: name, startDate: start, endDate: end);

    // Local row already healed (as the startup backfill would leave it).
    await db.into(db.fiscalYears).insertOnConflictUpdate(FiscalYearsCompanion(
          id: const Value(1),
          name: const Value(name),
          startDate: Value(start),
          endDate: Value(end),
          globalId: Value(derived),
        ));

    // Server still has NULL gid for the same year.
    await strategy.syncFromJson(serverPayload(
      id: 9, // drifted server id
      globalId: null,
      name: name,
      start: start,
      end: end,
    ));

    final rows = await db.select(db.fiscalYears).get();
    // No duplicate row created, and the gid was NOT blanked.
    final matching =
        rows.where((r) => r.name == name).toList(); // excludes "(مكرر)"
    expect(matching, hasLength(1),
        reason: 'must match the local row, not create a second');
    expect(matching.first.globalId, derived,
        reason: 'NULL server gid must not wipe the local deterministic gid');
  });

  test('a real server gid is still adopted verbatim', () async {
    const name = 'FY-with-server-gid';
    final start = DateTime(2027, 1, 1);
    final end = DateTime(2027, 12, 31);
    const serverGid = 'server-minted-gid-xyz';

    await strategy.syncFromJson(serverPayload(
      id: 5,
      globalId: serverGid,
      name: name,
      start: start,
      end: end,
    ));

    final row = await (db.select(db.fiscalYears)
          ..where((t) => t.name.equals(name)))
        .getSingle();
    expect(row.globalId, serverGid,
        reason: 'a present server gid remains authoritative');
  });
}
