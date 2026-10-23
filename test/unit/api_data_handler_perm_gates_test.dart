// Spec 077 Batch 5 — Sampling test for api_data_handler.dart perm gates.
//
// Full coverage (every handler asserted) is enforced by Batch 6's
// grep guard test, which walks the source and verifies each
// Future<Response> handler either calls ApiUserCtx.requirePermission(...)
// or carries an `// EXEMPT-PER-USER:` comment.
//
// This file samples ~10 representative perm codes across the major
// domains gated by Batch 5 — proving the 3-state contract still
// holds for the bulk-inserted gates.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';

void main() {
  group('api_data_handler perm gates sample (Spec 077 Batch 5)', () {
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
              username: 'data_gate_test_cashier',
              passwordHash: 'x',
              displayName: 'Data Gate Test Cashier',
              roleId: Value(cashierRoleId),
            ),
          );
      cashierUserId = (await (db.select(db.users)
                ..where((u) => u.username.equals('data_gate_test_cashier')))
              .getSingle())
          .id;
    });

    tearDown(() async {
      await db.close();
    });

    Request reqWithUser(int? userId) => Request(
          'POST',
          Uri.parse('http://localhost:8080/api/test'),
          context: userId != null ? {ApiUserCtx.userIdKey: userId} : const {},
        );

    // Sample one representative code per major domain wired by Batch 5.
    final sampleCodes = <String, String>{
      'expenses (5.1)': PermissionCodes.posExpense,
      'receipts (5.2)': PermissionCodes.treasuryReceiptsCreate,
      'shifts (5.3) — NEW posShiftOpen': PermissionCodes.posShiftOpen,
      'inventory (5.4)': PermissionCodes.inventoryEdit,
      'safes operational (5.5)': PermissionCodes.treasuryManage,
      'settings (5.7)': PermissionCodes.settingsEdit,
      'categories (5.8)': PermissionCodes.categoriesAdd,
      'users (5.9)': PermissionCodes.usersManage,
      'warehouses (5.10) — NEW warehousesManage':
          PermissionCodes.warehousesManage,
      'branches (5.12)': PermissionCodes.branchesManage,
      'accounts (5.14)': PermissionCodes.accountingManage,
      'commercial papers (5.18) — NEW commercialPapersManage':
          PermissionCodes.commercialPapersManage,
      'price lists (5.25) — NEW priceListsManage':
          PermissionCodes.priceListsManage,
      'printers (5.26)': PermissionCodes.settingsPrinter,
      'backup (5.17)': PermissionCodes.settingsBackup,
    };

    sampleCodes.forEach((label, code) {
      test('$label → admin passes ($code)', () async {
        expect(
          await ApiUserCtx.requirePermission(reqWithUser(1), db, code),
          isNull,
        );
      });

      test('$label → cashier denied ($code)', () async {
        final resp = await ApiUserCtx.requirePermission(
            reqWithUser(cashierUserId), db, code);
        // posShiftOpen is granted to cashier by the seeder (Batch 0.5);
        // skip the deny assertion in that case — admin pass + flag-off
        // sweep still validate the wiring.
        if (code == PermissionCodes.posShiftOpen) {
          expect(resp, isNull,
              reason: 'Cashier seeder grants posShiftOpen — must pass');
        } else {
          expect(resp, isNotNull, reason: 'Cashier must be denied $code');
          expect(resp!.statusCode, equals(403));
        }
      });
    });

    // ⚠️ كان «flag OFF auto-passes» ويؤكّد `isNull` — يثبّت العطب لا العقد.
    // وهذا الملفُّ يغطّي ٧٧ بوّابةً من الـ١٠٤، أي أكبرَ حصّةٍ منها.
    test('المفتاحُ القديم لا يُعيد المرورَ التلقائيّ لأيٍّ من الأكواد',
        () async {
      await db.setSetting('server_per_user_perms_enabled', 'false');
      var checked = 0;
      for (final code in sampleCodes.values) {
        // `posShiftOpen` يمنحه البذّارُ للكاشير (‏Batch 0.5)، فمرورُه صحيحٌ
        // ولا يقيس شيئاً هنا. البقيّةُ لا يملكها الكاشيرُ فتقيس الحارسَ.
        if (code == PermissionCodes.posShiftOpen) continue;
        final resp = await ApiUserCtx.requirePermission(
            reqWithUser(cashierUserId), db, code);
        expect(resp, isNotNull,
            reason: 'المفتاحُ المطفأ صراحةً لا يفتح $code');
        expect(resp!.statusCode, equals(403));
        checked++;
      }
      // مرساةٌ: عددُ ناجحين > صفر. لو أُعيدت تسميةُ الأكواد وصارت الحلقةُ
      // فارغةً لمرّ الاختبارُ بلا أن يقيس شيئاً.
      expect(checked, greaterThan(10));
    });

    test('بلا جلسةٍ متحقَّقة → 401 لكلِّ الأكواد المعاينة', () async {
      for (final code in sampleCodes.values) {
        final resp =
            await ApiUserCtx.requirePermission(reqWithUser(null), db, code);
        expect(resp, isNotNull);
        expect(resp!.statusCode, equals(401));
      }
    });

    test('all 4 NEW Batch 0.5 codes are persisted in the DB', () async {
      // syncAllPermissions ran during AppDatabase.forTesting() bootstrap.
      // Spec 077 Batch 0.5 added 4 codes — they must be present.
      final allCodes = (await db.select(db.permissions).get())
          .map((p) => p.code)
          .toSet();
      expect(allCodes, contains(PermissionCodes.posShiftOpen));
      expect(allCodes, contains(PermissionCodes.warehousesManage));
      expect(allCodes, contains(PermissionCodes.commercialPapersManage));
      expect(allCodes, contains(PermissionCodes.priceListsManage));
    });
  });
}
