// ═══════════════════════════════════════════════════════════════════════════
// UserRegionAccessSyncStrategy — race-condition tests (Feature 005)
// ═══════════════════════════════════════════════════════════════════════════
//
// Mirrors the user_branch_access regression suite. Verifies that:
//   1. Newly written local rows survive a confirming sync.
//   2. Server-side deletions propagate correctly.
//   3. Repeated syncs are idempotent (no churn).
//
// Pre-005 the strategy did a blanket DELETE+INSERT inside a transaction.
// That was vulnerable to the same race that produced the cashier-permissions
// outage reported on 2026-05-03.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/strategies/user_region_access_sync_strategy.dart';

void main() {
  late AppDatabase db;
  late UserRegionAccessSyncStrategy strategy;
  late int regionA;
  late int regionB;
  late int userA;
  late int userB;

  Future<int> seedRegion(String name) async {
    return db.into(db.regions).insert(
          RegionsCompanion.insert(
            name: name,
            globalId: Value('gid-region-$name'),
          ),
        );
  }

  Future<int> seedUser(String username) async {
    return db.into(db.users).insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: 'hash',
            displayName: username,
          ).copyWith(
            globalId: Value('gid-$username'),
          ),
        );
  }

  Future<List<UserRegionAccessData>> readAll() {
    return db.select(db.userRegionAccess).get();
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    strategy = UserRegionAccessSyncStrategy(db);
    regionA = await seedRegion('A');
    regionB = await seedRegion('B');
    userA = await seedUser('userA');
    userB = await seedUser('userB');
  });

  tearDown(() async {
    await db.close();
  });

  group('syncFromJson', () {
    test('inserts new rows from server snapshot when local is empty', () async {
      await strategy.syncFromJson({
        'user_region_access': [
          {'userId': userA, 'regionId': regionA},
          {'userId': userB, 'regionId': regionB},
        ],
      });

      final rows = await readAll();
      expect(rows, hasLength(2));
      expect(
        rows.map((r) => '${r.userId}_${r.regionId}').toSet(),
        {'${userA}_$regionA', '${userB}_$regionB'},
      );
    });

    test('PRESERVES a freshly-written local row when server snapshot agrees',
        () async {
      // Production race: dialog wrote (userA, regionA) locally a microsecond
      // before the WS-triggered sync arrived. The server snapshot also
      // includes it. Old DELETE+INSERT would briefly orphan the row.
      await db.into(db.userRegionAccess).insert(
            UserRegionAccessCompanion.insert(userId: userA, regionId: regionA),
          );

      await strategy.syncFromJson({
        'user_region_access': [
          {'userId': userA, 'regionId': regionA},
        ],
      });

      final rows = await readAll();
      expect(rows, hasLength(1),
          reason: 'local row must survive a sync that confirms it');
      expect(rows.first.userId, userA);
      expect(rows.first.regionId, regionA);
    });

    test('removes server-side deleted rows (deletion propagation)', () async {
      await db.into(db.userRegionAccess).insert(
            UserRegionAccessCompanion.insert(userId: userA, regionId: regionA),
          );
      await db.into(db.userRegionAccess).insert(
            UserRegionAccessCompanion.insert(userId: userB, regionId: regionB),
          );

      // Server removed userB's row; only userA's remains in snapshot.
      await strategy.syncFromJson({
        'user_region_access': [
          {'userId': userA, 'regionId': regionA},
        ],
      });

      final rows = await readAll();
      expect(rows, hasLength(1));
      expect(rows.first.userId, userA);
    });

    test('idempotent: repeated calls with same snapshot produce no churn',
        () async {
      final snapshot = {
        'user_region_access': [
          {'userId': userA, 'regionId': regionA},
          {'userId': userB, 'regionId': regionB},
        ],
      };

      await strategy.syncFromJson(snapshot);
      final firstPass = await readAll();

      await strategy.syncFromJson(snapshot);
      final secondPass = await readAll();

      expect(secondPass.length, firstPass.length);
      expect(
        secondPass.map((r) => '${r.userId}_${r.regionId}').toSet(),
        firstPass.map((r) => '${r.userId}_${r.regionId}').toSet(),
      );
    });
  });
}
