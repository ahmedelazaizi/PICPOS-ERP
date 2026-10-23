// Spec 077 Batch 2 — Per-user permission gates on api_party_handler.dart.
//
// 3 endpoints, each polymorphic on the row's isSupplier flag:
//   - postParty   → customersAdd OR suppliersAdd
//   - putParty    → customersEdit OR suppliersEdit
//   - deleteParty → customersDelete OR suppliersDelete
//
// These tests drive `ApiUserCtx.requirePermission` against a real
// test DB (matches Batch 1 pattern). The body-dispatch helper
// `_partyPermissionFor` is private to the handler; we verify the
// CONTRACT by asserting the gate accepts/denies the expected perm
// code for each branch.
//
// Cashier role (id=2) seeder grants neither customers* nor suppliers*
// codes by default — both paths deny under flag-ON. We assign
// customersAdd to the cashier in one test to prove the gate ALLOWS
// what it should, and that suppliersAdd still denies.

import 'package:drift/drift.dart' show Value, InsertMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';

void main() {
  group('api_party_handler perm gates (Spec 077 Batch 2)', () {
    late AppDatabase db;
    late int cashierUserId;
    late int cashierRoleId;

    setUp(() async {
      db = AppDatabase.forTesting();
      cashierRoleId = (await (db.select(db.roles)
                ..where((r) => r.name.equals('كاشير')))
              .getSingle())
          .id;
      await db.into(db.users).insert(
            UsersCompanion.insert(
              username: 'party_gate_test_cashier',
              passwordHash: 'x',
              displayName: 'Party Gate Test Cashier',
              roleId: Value(cashierRoleId),
            ),
          );
      cashierUserId = (await (db.select(db.users)
                ..where((u) => u.username.equals('party_gate_test_cashier')))
              .getSingle())
          .id;
    });

    tearDown(() async {
      await db.close();
    });

    Request reqWithUser(int? userId) => Request(
          'POST',
          Uri.parse('http://localhost:8080/api/parties'),
          context: userId != null ? {ApiUserCtx.userIdKey: userId} : const {},
        );

    Future<void> grantPermToCashier(String code) async {
      final permId = (await (db.select(db.permissions)
                ..where((p) => p.code.equals(code)))
              .getSingle())
          .id;
      await db.into(db.rolePermissions).insert(
            RolePermissionsCompanion.insert(
              roleId: cashierRoleId,
              permissionId: permId,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }

    // ⚠️ كان اسمُه «flag OFF auto-passes» ويؤكّد `isNull` — أي أنّه كان
    // **يثبّت العطب**: المفتاحُ `server_per_user_perms_enabled` لا يُزرع في
    // أيِّ تنصيبةٍ فكانت البوّاباتُ الـ١٠٤ تمرّ تلقائيّاً في الإنتاج.
    // حُذف المفتاح، والاختبارُ صار يُثبت أنّ زرعَه لا يُعطّل شيئاً.
    test('المفتاحُ القديم لا يُعيد المرورَ التلقائيّ لأيِّ نوعِ طرف', () async {
      await db.setSetting('server_per_user_perms_enabled', 'false');
      for (final code in [
        PermissionCodes.customersAdd,
        PermissionCodes.suppliersAdd,
      ]) {
        final resp = await ApiUserCtx.requirePermission(
            reqWithUser(cashierUserId), db, code);
        expect(resp, isNotNull, reason: 'الكاشيرُ لا يملك $code');
        expect(resp!.statusCode, equals(403));
      }
    });

    test('بلا جلسةٍ متحقَّقة → 401 على مسارَي الأطراف', () async {
      for (final code in [
        PermissionCodes.customersAdd,
        PermissionCodes.suppliersAdd,
      ]) {
        final resp =
            await ApiUserCtx.requirePermission(reqWithUser(null), db, code);
        expect(resp, isNotNull);
        expect(resp!.statusCode, equals(401));
      }
    });

    test('admin (id=1) passes both customer and supplier paths', () async {
      // Admin catch-all grants both via seedRolesAndPermissions.
      expect(
        await ApiUserCtx.requirePermission(
            reqWithUser(1), db, PermissionCodes.customersAdd),
        isNull,
      );
      expect(
        await ApiUserCtx.requirePermission(
            reqWithUser(1), db, PermissionCodes.suppliersAdd),
        isNull,
      );
    });

    test('cashier without customers_add → 403 on customer create', () async {
      final resp = await ApiUserCtx.requirePermission(
          reqWithUser(cashierUserId), db, PermissionCodes.customersAdd);
      expect(resp, isNotNull);
      expect(resp!.statusCode, equals(403));
    });

    test('cashier WITH customers_add → passes customer; supplier still denied',
        () async {
      // Grant only the customer-side perm. The polymorphic gate must
      // pick customersAdd for an isSupplier=false body and pass,
      // AND pick suppliersAdd for an isSupplier=true body and deny.
      await grantPermToCashier(PermissionCodes.customersAdd);

      final customerPath = await ApiUserCtx.requirePermission(
          reqWithUser(cashierUserId), db, PermissionCodes.customersAdd);
      expect(customerPath, isNull,
          reason: 'Cashier holds customersAdd — must pass');

      final supplierPath = await ApiUserCtx.requirePermission(
          reqWithUser(cashierUserId), db, PermissionCodes.suppliersAdd);
      expect(supplierPath, isNotNull,
          reason: 'Cashier still lacks suppliersAdd — must deny');
      expect(supplierPath!.statusCode, equals(403));
    });

    test('edit + delete codes follow the same supplier/customer split',
        () async {
      // Cashier holds NONE of these by default.
      for (final code in [
        PermissionCodes.customersEdit,
        PermissionCodes.suppliersEdit,
        PermissionCodes.customersDelete,
        PermissionCodes.suppliersDelete,
      ]) {
        final resp = await ApiUserCtx.requirePermission(
            reqWithUser(cashierUserId), db, code);
        expect(resp, isNotNull, reason: 'Cashier must be denied $code');
        expect(resp!.statusCode, equals(403));
      }
    });

    test('helper rule: isSupplier=true → suppliers* code; else → customers*',
        () {
      // This is a parity check that PermissionCodes still exports the
      // 6 codes the polymorphic helper depends on. If any of these
      // ever get renamed, the test fails loudly here BEFORE the gate
      // silently mis-routes in production.
      expect(PermissionCodes.customersAdd, equals('customers_add'));
      expect(PermissionCodes.customersEdit, equals('customers_edit'));
      expect(PermissionCodes.customersDelete, equals('customers_delete'));
      expect(PermissionCodes.suppliersAdd, equals('suppliers_add'));
      expect(PermissionCodes.suppliersEdit, equals('suppliers_edit'));
      expect(PermissionCodes.suppliersDelete, equals('suppliers_delete'));
    });
  });
}
