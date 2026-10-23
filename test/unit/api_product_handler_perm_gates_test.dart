// Spec 077 Batch 3 — Per-user permission gates on api_product_handler.dart.
//
// 8 endpoints map to 3 distinct permission codes:
//   - postProduct          → productsAdd
//   - putProduct           → productsEdit
//   - deleteProduct        → productsDelete
//   - postProductUnit      → productsUnits  (shared across the 3 unit routes)
//   - putProductUnit       → productsUnits
//   - deleteProductUnit    → productsUnits
//   - postProductBarcode   → productsBarcode  (shared across the 2 barcode routes)
//   - deleteProductBarcode → productsBarcode
//
// We exercise each DISTINCT code once via the ApiUserCtx helper (the
// gate behavior itself is identical to Batches 1/2; Batch 6's grep
// guard enforces every handler actually calls requirePermission).

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';

void main() {
  group('api_product_handler perm gates (Spec 077 Batch 3)', () {
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
              username: 'product_gate_test_cashier',
              passwordHash: 'x',
              displayName: 'Product Gate Test Cashier',
              roleId: Value(cashierRoleId),
            ),
          );
      cashierUserId = (await (db.select(db.users)
                ..where((u) => u.username.equals('product_gate_test_cashier')))
              .getSingle())
          .id;
    });

    tearDown(() async {
      await db.close();
    });

    Request reqWithUser(int? userId) => Request(
          'POST',
          Uri.parse('http://localhost:8080/api/products'),
          context: userId != null ? {ApiUserCtx.userIdKey: userId} : const {},
        );

    for (final code in [
      PermissionCodes.productsAdd,
      PermissionCodes.productsEdit,
      PermissionCodes.productsDelete,
      PermissionCodes.productsUnits,
      PermissionCodes.productsBarcode,
    ]) {
      test('admin passes $code', () async {
        expect(
          await ApiUserCtx.requirePermission(reqWithUser(1), db, code),
          isNull,
        );
      });

      test('cashier (default) denied on $code', () async {
        final resp = await ApiUserCtx.requirePermission(
            reqWithUser(cashierUserId), db, code);
        expect(resp, isNotNull,
            reason: 'Cashier role does not grant $code by default');
        expect(resp!.statusCode, equals(403));
      });
    }

    // ⚠️ كان «flag OFF auto-passes» ويؤكّد `isNull` — يثبّت العطب لا العقد.
    // المفتاحُ لا يُزرع في أيِّ تنصيبةٍ فكانت البوّاباتُ تمرّ في الإنتاج.
    test('المفتاحُ القديم لا يُعيد المرورَ التلقائيّ على الأكواد الخمسة',
        () async {
      await db.setSetting('server_per_user_perms_enabled', 'false');
      for (final code in [
        PermissionCodes.productsAdd,
        PermissionCodes.productsEdit,
        PermissionCodes.productsDelete,
        PermissionCodes.productsUnits,
        PermissionCodes.productsBarcode,
      ]) {
        final resp = await ApiUserCtx.requirePermission(
            reqWithUser(cashierUserId), db, code);
        expect(resp, isNotNull,
            reason: 'المفتاحُ المطفأ صراحةً لا يفتح $code');
        expect(resp!.statusCode, equals(403));
      }
    });

    test('بلا جلسةٍ متحقَّقة → 401 على الأكواد الخمسة', () async {
      for (final code in [
        PermissionCodes.productsAdd,
        PermissionCodes.productsEdit,
        PermissionCodes.productsDelete,
        PermissionCodes.productsUnits,
        PermissionCodes.productsBarcode,
      ]) {
        final resp =
            await ApiUserCtx.requirePermission(reqWithUser(null), db, code);
        expect(resp, isNotNull);
        expect(resp!.statusCode, equals(401));
      }
    });
  });
}
