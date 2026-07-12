// Spec 060 (D1-001) — Server-side per-user permission enforcement.
//
// Tests the new ApiUserCtx helper + the X-User-Id header extraction in
// ApiAuthMiddleware. Drives shelf Request objects directly rather than
// spinning up a full server.
//
// Phase 1: helper + 4 wired endpoints (deleteSalesInvoice, putUser,
// deleteUser, setRolePermissions, postJournalEntry). Phase 2 will sweep
// the remaining ~85.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_user_context.dart';

void main() {
  group('ApiUserCtx (Spec 060 / D1-001)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    Request makeRequest({int? userId}) {
      return Request(
        'GET',
        Uri.parse('http://localhost:8080/api/test'),
        context: userId != null
            ? {ApiUserCtx.userIdKey: userId}
            : const {},
      );
    }

    test('userIdOf returns null when context is empty', () {
      expect(ApiUserCtx.userIdOf(makeRequest()), isNull);
    });

    test('userIdOf returns stored userId when context has it', () {
      expect(ApiUserCtx.userIdOf(makeRequest(userId: 42)), equals(42));
    });

    test('isPerUserPermsEnabled is false by default (settings unset)',
        () async {
      expect(await ApiUserCtx.isPerUserPermsEnabled(db), isFalse);
    });

    test('isPerUserPermsEnabled is true when flag set', () async {
      await db.setSetting('server_per_user_perms_enabled', 'true');
      expect(await ApiUserCtx.isPerUserPermsEnabled(db), isTrue);
    });

    test('requirePermission auto-passes when flag is off', () async {
      // Flag OFF (default) → no DB lookup, no 401/403.
      final resp = await ApiUserCtx.requirePermission(
          makeRequest(userId: 1), db, 'sales_delete');
      expect(resp, isNull, reason: 'OFF mode → auto-pass');
    });

    test('requirePermission returns 401 when flag on + userId missing',
        () async {
      await db.setSetting('server_per_user_perms_enabled', 'true');
      final resp = await ApiUserCtx.requirePermission(
          makeRequest(), db, 'sales_delete');
      expect(resp, isNotNull);
      expect(resp!.statusCode, equals(401));
    });

    test('requirePermission returns 403 when user lacks permission',
        () async {
      await db.setSetting('server_per_user_perms_enabled', 'true');
      // Bootstrap admin (id=1) does NOT have sales_delete after spec 062's
      // segregation-of-duties seeder change (only criticalFinancialOps
      // are excluded, but sales_delete is NOT critical) — actually spec
      // 062 still grants sales_delete. We need a NON-admin user.
      // Insert a cashier user via raw INSERT with a cashier role id 2.
      // Cashier role doesn't get sales_delete by default.
      await db.into(db.users).insert(
            UsersCompanion.insert(
              username: 'test_cashier',
              passwordHash: 'x',
              displayName: 'Test Cashier',
              roleId: const Value(2), // cashier
            ),
          );
      final cashierId = (await (db.select(db.users)
                ..where((u) => u.username.equals('test_cashier')))
              .getSingle())
          .id;

      final resp = await ApiUserCtx.requirePermission(
          makeRequest(userId: cashierId), db, 'sales_delete');
      expect(resp, isNotNull);
      expect(resp!.statusCode, equals(403));
    });

    test('requirePermission auto-passes when user has the perm', () async {
      await db.setSetting('server_per_user_perms_enabled', 'true');
      // Bootstrap admin (id=1) has sales_delete (not in criticalFinancialOps).
      final resp = await ApiUserCtx.requirePermission(
          makeRequest(userId: 1), db, 'sales_delete');
      expect(resp, isNull);
    });
  });
}
