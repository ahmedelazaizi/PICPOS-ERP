// Spec 077 Batch 4 — Per-user permission gates on api_purchase_handler.dart.
//
// 5 endpoints map to 5 distinct permission codes:
//   - postPurchase            → purchasesCreate
//   - postPurchaseReturn      → purchasesReturnCreate
//   - postPurchaseReturnEdit  → purchasesReturnEdit
//   - putPurchase             → purchasesEdit
//   - deletePurchase          → purchasesDelete
//
// Tests assert the 3-state contract per code (flag-OFF auto-pass,
// admin pass, cashier deny).

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_user_context.dart';

void main() {
  group('api_purchase_handler perm gates (Spec 077 Batch 4)', () {
    late AppDatabase db;
    late int cashierUserId;

    setUp(() async {
      db = AppDatabase.forTesting();
      final cashierRoleId = (await (db.select(db.roles)
                ..where((r) => r.name.equals('كاشير')))
              .getSingle())
          .id;
      await db.into(db.users).insert(
            UsersCompanion.insert(
              username: 'purchase_gate_test_cashier',
              passwordHash: 'x',
              displayName: 'Purchase Gate Test Cashier',
              roleId: Value(cashierRoleId),
            ),
          );
      cashierUserId = (await (db.select(db.users)
                ..where((u) => u.username.equals('purchase_gate_test_cashier')))
              .getSingle())
          .id;
    });

    tearDown(() async {
      await db.close();
    });

    Request reqWithUser(int? userId) => Request(
          'POST',
          Uri.parse('http://localhost:8080/api/purchases'),
          context: userId != null ? {ApiUserCtx.userIdKey: userId} : const {},
        );

    final purchaseCodes = [
      PermissionCodes.purchasesCreate,
      PermissionCodes.purchasesReturnCreate,
      PermissionCodes.purchasesReturnEdit,
      PermissionCodes.purchasesEdit,
      PermissionCodes.purchasesDelete,
    ];

    for (final code in purchaseCodes) {
      test('admin passes $code', () async {
        expect(
          await ApiUserCtx.requirePermission(reqWithUser(1), db, code),
          isNull,
        );
      });

      test('cashier (default) denied on $code', () async {
        final resp = await ApiUserCtx.requirePermission(
            reqWithUser(cashierUserId), db, code);
        expect(resp, isNotNull);
        expect(resp!.statusCode, equals(403));
      });
    }

    // ⚠️ كان «flag OFF auto-passes» ويؤكّد `isNull` — يثبّت العطب لا العقد.
    test('المفتاحُ القديم لا يُعيد المرورَ التلقائيّ لأكواد المشتريات',
        () async {
      await db.setSetting('server_per_user_perms_enabled', 'false');
      for (final code in purchaseCodes) {
        final resp = await ApiUserCtx.requirePermission(
            reqWithUser(cashierUserId), db, code);
        expect(resp, isNotNull,
            reason: 'المفتاحُ المطفأ صراحةً لا يفتح $code');
        expect(resp!.statusCode, equals(403));
      }
    });

    test('بلا جلسةٍ متحقَّقة → 401 لأكواد المشتريات', () async {
      for (final code in purchaseCodes) {
        final resp =
            await ApiUserCtx.requirePermission(reqWithUser(null), db, code);
        expect(resp, isNotNull);
        expect(resp!.statusCode, equals(401));
      }
    });
  });
}
