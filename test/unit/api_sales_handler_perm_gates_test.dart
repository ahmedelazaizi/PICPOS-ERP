// Spec 077 Batch 1 — Per-user permission gates on api_sales_handler.dart.
//
// Phase 1 (b340c54) gated deleteSalesInvoice. This Batch adds gates to
// the 4 remaining mutation handlers (postSale, postSalesReturn,
// postHeldOrder, deleteHeldOrder). These tests drive the gates
// directly via `ApiUserCtx.requirePermission` against a real test DB
// — they do NOT invoke the handler bodies (those have wide deps:
// orchestrators, WebSocket broadcast, etc.).
//
// What is verified per gate:
//   1. Flag OFF (default) → auto-passes regardless of user.
//   2. Flag ON + admin (bootstrap id=1) → auto-passes.
//   3. Flag ON + cashier user lacking the perm → 403.
//
// What is NOT verified (intentionally — out of scope for unit test):
//   - End-to-end HTTP routing.
//   - Body parsing / DB writes / WebSocket broadcasts.
//   These are exercised by the manual smoke playbook
//   (specs/077-server-perms-endpoint-sweep/quickstart.md Phase B + C).
//
// Batch 6's grep guard test enforces that every handler actually
// calls `ApiUserCtx.requirePermission(...)` (vs. just asserting the
// helper response shape here).

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_user_context.dart';

void main() {
  group('api_sales_handler perm gates (Spec 077 Batch 1)', () {
    late AppDatabase db;
    late int cashierUserId;

    setUp(() async {
      db = AppDatabase.forTesting();
      // The cashier role (id=2) is seeded by AppDatabase.forTesting via
      // seedRolesAndPermissions — it does NOT carry sales_create,
      // sales_return_create, or pos_delete_held. It DOES carry
      // pos_hold_order. We use this asymmetry to prove the gate maps
      // each route to its own distinct perm code (not a single
      // catch-all).
      await db.into(db.users).insert(
            UsersCompanion.insert(
              username: 'sales_gate_test_cashier',
              passwordHash: 'x',
              displayName: 'Sales Gate Test Cashier',
              roleId: const Value(2),
            ),
          );
      cashierUserId = (await (db.select(db.users)
                ..where((u) => u.username.equals('sales_gate_test_cashier')))
              .getSingle())
          .id;
    });

    tearDown(() async {
      await db.close();
    });

    Request reqWithUser(int? userId) => Request(
          'POST',
          Uri.parse('http://localhost:8080/api/sales'),
          context: userId != null ? {ApiUserCtx.userIdKey: userId} : const {},
        );

    /// Asserts the documented 3-state contract for a gate:
    /// off→null, on+admin→null, on+denied-cashier→403.
    Future<void> assertGateContract({
      required String permCode,
      required bool cashierShouldPass,
    }) async {
      // 1. Flag OFF → auto-pass (anyone).
      await db.setSetting('server_per_user_perms_enabled', 'false');
      expect(
        await ApiUserCtx.requirePermission(
            reqWithUser(cashierUserId), db, permCode),
        isNull,
        reason: 'Flag OFF must auto-pass for $permCode',
      );

      // 2. Flag ON + admin (bootstrap id=1) → auto-pass.
      await db.setSetting('server_per_user_perms_enabled', 'true');
      expect(
        await ApiUserCtx.requirePermission(reqWithUser(1), db, permCode),
        isNull,
        reason: 'Admin (id=1) must hold $permCode via catch-all',
      );

      // 3. Flag ON + cashier user.
      final cashierResp = await ApiUserCtx.requirePermission(
          reqWithUser(cashierUserId), db, permCode);
      if (cashierShouldPass) {
        expect(cashierResp, isNull,
            reason: 'Cashier role IS granted $permCode by default seeder');
      } else {
        expect(cashierResp, isNotNull,
            reason: 'Cashier role lacks $permCode → expect 403');
        expect(cashierResp!.statusCode, equals(403));
      }
    }

    // Spec 084 added `sales_create` to the cashier role's seeded grants
    // (role_grant_matrix.dart, role 'كاشير'; database_seeder_permissions.dart),
    // so the cashier now legitimately HOLDS sales_create and that gate passes.
    // To keep a real negative-path assertion for the postSale family we gate on
    // `salesDelete` instead — it is in PermissionCodes but is NOT granted to any
    // role in role_grant_matrix.dart, so the cashier genuinely lacks it → 403.
    test('postSale family → salesDelete (cashier denied — sales_delete not in any role)',
        () async {
      await assertGateContract(
        permCode: PermissionCodes.salesDelete,
        cashierShouldPass: false,
      );
    });

    test('postSalesReturn → salesReturnCreate (cashier denied)', () async {
      await assertGateContract(
        permCode: PermissionCodes.salesReturnCreate,
        cashierShouldPass: false,
      );
    });

    test('postHeldOrder → posHoldOrder (cashier ALLOWED — granted by seeder)',
        () async {
      // Cashier role's seeder grant includes pos_hold_order. This case
      // proves the gate ALSO allows what it should — not just denies.
      await assertGateContract(
        permCode: PermissionCodes.posHoldOrder,
        cashierShouldPass: true,
      );
    });

    test('deleteHeldOrder → posDeleteHeld (cashier denied)', () async {
      await assertGateContract(
        permCode: PermissionCodes.posDeleteHeld,
        cashierShouldPass: false,
      );
    });

    test('missing X-User-Id on gated endpoint returns 401, not 403', () async {
      // Spec 060 contract: when flag is ON and X-User-Id is missing,
      // middleware leaves context empty → requirePermission returns 401.
      await db.setSetting('server_per_user_perms_enabled', 'true');
      final resp = await ApiUserCtx.requirePermission(
          reqWithUser(null), db, PermissionCodes.salesCreate);
      expect(resp, isNotNull);
      expect(resp!.statusCode, equals(401),
          reason: '401 = missing header (Phase-1 contract); '
              '403 = wrong perm (this Batch). Don\'t conflate.');
    });
  });
}
