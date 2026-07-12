// ═══════════════════════════════════════════════════════════════════════════
// Feature 005 Phase 8 — Treasury Branch Isolation Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Reproduces the production bug where a branch-restricted user (e.g.
// "مدير فرع العقبة") opened the treasury screen and saw safes from EVERY
// branch — not just their own. The fix added watchSafesForBranches() to
// TreasuryDao + scopedSafesProvider in the Riverpod layer.
//
// These tests exercise the DAO method directly (the integration of the
// provider with branchScopeProvider is covered by the existing
// branch_scope_provider tests).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int adminBranchId;
  late int aqabaBranchId;
  late int superMarketMaanBranchId;
  late int restaurantMaanBranchId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    adminBranchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'الادارة',
            globalId: const Value('gid-br-admin'),
          ),
        );
    aqabaBranchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'العقبة',
            globalId: const Value('gid-br-aqaba'),
          ),
        );
    superMarketMaanBranchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'سوبر ماركت معان',
            globalId: const Value('gid-br-sm-maan'),
          ),
        );
    restaurantMaanBranchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'مطعم معان',
            globalId: const Value('gid-br-rest-maan'),
          ),
        );

    Future<void> seedSafe(String name, int branchId) async {
      await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: name,
              branchId: Value(branchId),
              globalId: Value('gid-safe-$name'),
            ),
          );
    }

    await seedSafe('صندوق نقد الادارة', adminBranchId);
    await seedSafe('صندوق نقد العقبة', aqabaBranchId);
    await seedSafe('صندوق نقد سوبر ماركت معان', superMarketMaanBranchId);
    await seedSafe('صندوق نقد مطعم معان', restaurantMaanBranchId);
  });

  tearDown(() => db.close());

  // The forTesting() DB also seeds 3 default NULL-branch safes (صندوق الكاشير,
  // الحساب البنكي, صندوق تحويل كليك). Branch-scoped queries keep those visible
  // by design — they represent the unscoped seed and would otherwise vanish
  // from every restricted user's screen, breaking balances. The tests below
  // assert against the *branch-specific* names rather than total counts.

  Set<String> branchedSafeNames(List<Safe> list) =>
      list.where((s) => s.branchId != null).map((s) => s.name).toSet();

  group('watchSafesForBranches — branch-restricted users', () {
    test('Aqaba manager sees only Aqaba branch-scoped safes', () async {
      final list = await db.watchSafesForBranches({aqabaBranchId}).first;
      expect(branchedSafeNames(list), {'صندوق نقد العقبة'},
          reason:
              'a branch-restricted user must not see other branches\' safes');
    });

    test('multi-branch grant sees the union, never others', () async {
      final list = await db.watchSafesForBranches(
          {aqabaBranchId, superMarketMaanBranchId}).first;
      expect(branchedSafeNames(list), {
        'صندوق نقد العقبة',
        'صندوق نقد سوبر ماركت معان',
      });
    });

    test('null branchIds (full access) returns every branch-scoped safe',
        () async {
      final list = await db.watchSafesForBranches(null).first;
      expect(branchedSafeNames(list), {
        'صندوق نقد الادارة',
        'صندوق نقد العقبة',
        'صندوق نقد سوبر ماركت معان',
        'صندوق نقد مطعم معان',
      });
    });

    test('empty allowed set still surfaces NULL-branch legacy safes only',
        () async {
      final list = await db.watchSafesForBranches(<int>{}).first;
      expect(branchedSafeNames(list), isEmpty,
          reason:
              'no branch-scoped safe leaks into a user with zero allowed branches');
    });

    test('legacy safes with NULL branch_id stay visible to every user',
        () async {
      await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'صندوق قديم بدون فرع',
              globalId: const Value('gid-safe-legacy'),
            ),
          );
      final list = await db.watchSafesForBranches({aqabaBranchId}).first;
      expect(
        list.map((s) => s.name),
        contains('صندوق قديم بدون فرع'),
        reason: 'NULL branch_id stays visible — keeps legacy data reconciling',
      );
    });
  });
}
