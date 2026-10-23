// ═══════════════════════════════════════════════════════════════════════════
// SPEC 084 — Cashier roles get `sales_create` (and `sales_view`)
// ═══════════════════════════════════════════════════════════════════════════
//
// Pre-fix: the three cashier-style roles in `RoleGrantMatrix.defaultGrants`
// and the parallel imperative lists in `database_seeder_permissions.dart`
// (`cashierPermsIndices`, `advancedCashierPerms`, transitively
// `branchManagerPerms`) all lacked `sales_create`. Spec 077 gates the
// `/api/sales` POST on that exact perm — net effect: every cashier 403'd
// and four field invoices DEAD-LETTERed in a single test session.
//
// Post-fix: matrix + seeder both include `sales_create` + `sales_view`
// for the basic + advanced cashier; `sales_create` for the branch manager
// (it already has `sales_view`).
//
// These tests pin both declarations so a future refactor that drops
// either side fails loud, instead of re-introducing the silent 403 mode.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/role_grant_matrix.dart';

void main() {
  group('Spec 084 — matrix grants the essential sales perms', () {
    test('"كاشير" matrix includes sales_create + sales_view', () {
      final perms = RoleGrantMatrix.defaultGrants['كاشير'];
      expect(perms, isNotNull);
      expect(perms!.contains('sales_create'), isTrue,
          reason: 'Without sales_create, every POS save 403s — the very '
              'bug Spec 084 fixes. If this fails, a refactor dropped the '
              'matrix entry; restore it.');
      expect(perms.contains('sales_view'), isTrue,
          reason: 'sales_view enables الفواتير السابقة inside POS — '
              'bundled with sales_create as a sensible cashier default.');
    });

    test('"كاشير متقدم" matrix includes sales_create + sales_view', () {
      final perms = RoleGrantMatrix.defaultGrants['كاشير متقدم'];
      expect(perms, isNotNull);
      expect(perms!.contains('sales_create'), isTrue);
      expect(perms.contains('sales_view'), isTrue);
    });

    test('"مدير فرع" matrix includes sales_create '
        '(sales_view already present pre-spec)', () {
      final perms = RoleGrantMatrix.defaultGrants['مدير فرع'];
      expect(perms, isNotNull);
      expect(perms!.contains('sales_create'), isTrue,
          reason: 'Branch managers ring sales on busy days; they need the '
              'same gate-passing perm as their cashiers.');
      // sales_view was already in this role pre-Spec 084 — sanity check
      // it stayed there.
      expect(perms.contains('sales_view'), isTrue);
    });
  });

  group('Spec 084 — seeder lock-step with matrix (grep guard)', () {
    // Source-string grep guards on the seeder list literals. The seeder is
    // imperative + nested in a 1200-line method, so a real-DB assertion
    // would require booting the whole seedRolesAndPermissions chain. The
    // text-level check is faster and catches the only regression we care
    // about: the strings dropping out of the cashier/advanced-cashier
    // arrays. The matrix-vs-seeder count-of-missing-pairs test (Spec 078)
    // covers semantic drift.
    late String seederSrc;

    setUpAll(() {
      seederSrc = File('lib/data/database/database_seeder_permissions.dart')
          .readAsStringSync();
    });

    test('cashierPermsIndices list includes both sales perms', () {
      final listStart = seederSrc.indexOf('final cashierPermsIndices = [');
      expect(listStart, isNot(-1),
          reason: 'cashierPermsIndices declaration not found — structure '
              'changed; update this grep guard.');
      // Bound by the next `];` close — generous enough to cover the whole
      // list literal regardless of comment growth.
      final remaining = seederSrc.substring(listStart);
      final listEnd = remaining.indexOf('];');
      expect(listEnd, isNot(-1));
      final listBody = remaining.substring(0, listEnd);

      expect(listBody, contains("'sales_create'"),
          reason: 'Basic cashier seed must include sales_create or fresh '
              'installs immediately break under Spec 077 gates.');
      expect(listBody, contains("'sales_view'"),
          reason: 'Bundled with sales_create per Spec 084 design.');
    });

    test('advancedCashierPerms list includes both sales perms', () {
      final listStart = seederSrc.indexOf('final advancedCashierPerms = [');
      expect(listStart, isNot(-1));
      final remaining = seederSrc.substring(listStart);
      final listEnd = remaining.indexOf('];');
      final listBody = remaining.substring(0, listEnd);

      expect(listBody, contains("'sales_create'"),
          reason: 'Advanced cashier inherits into branchManagerPerms via '
              'spread; missing here would silently break branch manager too.');
      expect(listBody, contains("'sales_view'"));
    });

    test('branchManagerPerms transitively gets sales_create '
        'via advancedCashierPerms spread', () {
      // Verify the spread is still in place so the previous test's
      // sales_create propagates to branch manager.
      final listStart = seederSrc.indexOf('final branchManagerPerms = [');
      expect(listStart, isNot(-1));
      final remaining = seederSrc.substring(listStart);
      final listEnd = remaining.indexOf('];');
      final listBody = remaining.substring(0, listEnd);

      expect(listBody, contains('...advancedCashierPerms'),
          reason: 'Branch manager relies on the spread; without it our '
              'Spec 084 fix would not reach this role and the test for '
              'the matrix-vs-seeder lock-step would silently divide.');
    });
  });
}
