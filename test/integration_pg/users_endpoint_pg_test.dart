// Spec 029 / US3 Bug A — `/api/users` admin-include regression.
//
// Production log on 2026-05-09T23:35:40 showed admin (id=1) dropped from
// `/api/users` despite the handler source containing the
// `u.id.equals(1)` literal that the static grep test asserts. That static
// guard cannot tell whether the row at id=1 actually exists at runtime,
// or whether the disjunction's IN-list semantics evaluate as expected.
//
// Three scenarios pin the contract end-to-end:
//   1. Empty `userBranchAccess` for admin + non-system role → admin in
//      response.
//   2. Admin row physically deleted server-side → handler self-heals and
//      admin is in the response.
//   3. Admin row renamed to `__dup_1_admin` → handler self-heals
//      (restores username='admin') and admin is in the response.
//
// The fix lives in `lib/services/api/api_handler.dart` (US3A T017–T019).
// On `main` (before the fix) all three should fail; on the feature branch
// they pass.

@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_handler.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;
  late ApiHandler handler;

  setUpAll(() async {
    fx = await bootPgTestSchema();
  });

  tearDownAll(() async {
    await fx.tearDown();
  });

  setUp(() async {
    // Reset the four tables this suite touches between tests so each
    // scenario starts from a known state. Order matters: child tables
    // (userBranchAccess, rolePermissions) before parents (users, roles).
    await fx.db.delete(fx.db.userBranchAccess).go();
    await fx.db.delete(fx.db.rolePermissions).go();
    await fx.db.delete(fx.db.users).go();
    await fx.db.delete(fx.db.roles).go();

    // Branch 2 must actually exist. Every scenario below writes
    // `userBranchAccess(branchId: 2)`, and PostgreSQL enforces the
    // `user_branch_access_branch_id_fkey` that SQLite-backed runs never
    // checked — so these three tests failed with 23503 the first time this
    // suite was ever pointed at a real server, for a fixture reason rather
    // than a product one. Idempotent: `branches` is not truncated between
    // tests, so this is a no-op after the first run.
    await fx.db.customStatement(
      "INSERT INTO branches (id, name) VALUES (2, 'فرع الاختبار') "
      'ON CONFLICT (id) DO NOTHING',
    );

    // A FRESH handler per test. `_ensureBootstrapAdminOnce` is gated by the
    // instance field `_adminSelfHealRan` and documented to run once per
    // process, so a handler shared via setUpAll means the first test consumes
    // the one shot and every later test silently never exercises the heal at
    // all — they were asserting against a code path that never ran.
    handler = ApiHandler(fx.db);
  });

  Future<Map<String, dynamic>> callGetUsers({int? branchId}) async {
    final qs = branchId != null ? '?branch_id=$branchId' : '';
    final request =
        shelf.Request('GET', Uri.parse('http://localhost/api/users$qs'));
    final response = await handler.buildRouter().call(request);
    final body = await response.readAsString();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<void> seedRole({
    required int id,
    required String name,
    required bool isSystem,
  }) async {
    await fx.db.into(fx.db.roles).insert(
          RolesCompanion.insert(
            name: name,
            isSystemRole: d.Value(isSystem),
          ).copyWith(id: d.Value(id)),
        );
  }

  Future<void> seedUser({
    required int id,
    required String username,
    required int roleId,
    bool isActive = true,
  }) async {
    await fx.db.into(fx.db.users).insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: 'hash',
            displayName: username,
            roleId: d.Value(roleId),
            isActive: d.Value(isActive),
          ).copyWith(id: d.Value(id)),
        );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // B11 — الـPIN ممنوع يخرج على السلك
  //
  // الاستجابة دي بتروح لكل حامل bearer على الشبكة المحلية عمداً، عشان العميل
  // يصادق محلياً وهو offline. ده مقبول لهاش كلمة مرور Argon2id (ذاكرة-صعب،
  // وملحه جوّاه). **مش مقبول للـPIN**: ٤-٦ أرقام = ١٫١ مليون احتمال على
  // الأكثر، فأي KDF مهما كان بيتكسر في وقت معقول.
  //
  // ومحدش بيصادق بالـPIN في المنتج أصلاً (`verifyUserPin` بلا أي مُنادٍ
  // إنتاجي)، فالحقل كان بيتبعت على الشبكة **بلا أي مستهلك للمصادقة**.
  // ═══════════════════════════════════════════════════════════════════════
  group('/api/users — الـPIN مايخرجش', () {
    test('الاستجابة مفيهاش حقل pin إطلاقاً', () async {
      await seedRole(id: 1, name: 'مدير النظام', isSystem: true);
      await seedUser(id: 1, username: 'admin', roleId: 1);
      // مستخدم عنده PIN فعلاً — لو الحقل بيتبعت، هيبان هنا.
      await seedUser(id: 2, username: 'cashier_pin', roleId: 1);
      await fx.db.updateUserPin(2, '1234');

      final response = await callGetUsers();
      final users = (response['users'] as List).cast<Map<String, dynamic>>();
      expect(users, isNotEmpty, reason: 'تجهيزة: الاستجابة مش فاضية');

      for (final u in users) {
        expect(u.containsKey('pin'), isFalse,
            reason: 'الـPIN بيتبعت لكل حامل bearer على الشبكة المحلية — '
                'وهو ٤-٦ أرقام، يعني بيتكسر offline مهما كان الـKDF');
      }
    });
  });

  group('/api/users — admin always included (Bug A)', () {
    test(
      'admin (id=1) is present when userBranchAccess for id=1 is empty '
      'and admin role is not flagged as system role',
      () async {
        // Worst-case data shape from the production incident.
        await seedRole(id: 1, name: 'مدير النظام', isSystem: false);
        await seedRole(id: 2, name: 'كاشير', isSystem: false);
        await seedUser(id: 1, username: 'admin', roleId: 1);
        await seedUser(id: 2, username: 'cashier_a', roleId: 2);
        await seedUser(id: 3, username: 'cashier_b', roleId: 2);
        // Cashiers can access branch 2; admin is NOT in userBranchAccess.
        await fx.db.into(fx.db.userBranchAccess).insert(
              UserBranchAccessCompanion.insert(userId: 2, branchId: 2),
            );
        await fx.db.into(fx.db.userBranchAccess).insert(
              UserBranchAccessCompanion.insert(userId: 3, branchId: 2),
            );

        final response = await callGetUsers(branchId: 2);
        final users = (response['users'] as List).cast<Map<String, dynamic>>();
        final adminPresent = users.any((u) => u['id'] == 1);
        expect(
          adminPresent,
          isTrue,
          reason:
              'admin (id=1) MUST be in response even when userBranchAccess '
              'is empty for the admin and the admin role is not flagged as '
              'system role. See Feature 011 / Issue 9 chain failure root '
              'cause.',
        );
      },
    );

    test(
      'SEC-001: a physically deleted bootstrap row is NOT re-created as admin/admin',
      () async {
        await seedRole(id: 1, name: 'مدير النظام', isSystem: false);
        await seedRole(id: 2, name: 'كاشير', isSystem: false);
        await seedUser(id: 2, username: 'cashier_a', roleId: 2);
        await fx.db.into(fx.db.userBranchAccess).insert(
              UserBranchAccessCompanion.insert(userId: 2, branchId: 2),
            );
        // No row inserted for id=1.
        final before = (await fx.db.select(fx.db.users).get()).length;

        await callGetUsers(branchId: 2);

        // Audit 2026-10-23 SEC-001: a known-password system-admin must never
        // be silently created. Recovery is an explicit operator action.
        final after = await fx.db.select(fx.db.users).get();
        expect(after.length, before);
        expect(after.where((u) => u.username == 'admin'), isEmpty);
      },
    );

    test(
      'an admin that lives at id != 1 is still included (resolved by username)',
      () async {
        // The literal `1` in `_getUsers`'s allowed-id set cannot cover an admin
        // sitting elsewhere. Deny it both other routes into the set: no
        // userBranchAccess row for this branch, and a role NOT flagged
        // isSystemRole (Feature 011 / Issue 9).
        await seedRole(id: 1, name: 'مدير النظام', isSystem: false);
        await seedRole(id: 2, name: 'كاشير', isSystem: false);
        await seedUser(id: 2, username: 'cashier_a', roleId: 2);
        await fx.db.into(fx.db.userBranchAccess).insert(
              UserBranchAccessCompanion.insert(userId: 2, branchId: 2),
            );
        await seedUser(id: 500, username: 'admin', roleId: 1);

        final response = await callGetUsers(branchId: 2);
        final users = (response['users'] as List).cast<Map<String, dynamic>>();

        expect(
          users.any((u) => u['username'] == 'admin'),
          isTrue,
          reason: '/api/users must resolve the bootstrap admin by username, '
              'not by hardcoded id.',
        );
      },
    );

    test(
      'admin self-heal restores a `__dup_1_admin` renamed row to username=admin',
      () async {
        // The Issue 9 chain failure also leaves the id=1 row renamed.
        // Self-heal must reset the username back to canonical.
        await seedRole(id: 1, name: 'مدير النظام', isSystem: false);
        await seedRole(id: 2, name: 'كاشير', isSystem: false);
        await seedUser(id: 1, username: '__dup_1_admin', roleId: 1);
        await seedUser(id: 2, username: 'cashier_a', roleId: 2);
        await fx.db.into(fx.db.userBranchAccess).insert(
              UserBranchAccessCompanion.insert(userId: 2, branchId: 2),
            );

        final response = await callGetUsers(branchId: 2);
        final users = (response['users'] as List).cast<Map<String, dynamic>>();
        final admin = users.firstWhere(
          (u) => u['id'] == 1,
          orElse: () => <String, dynamic>{},
        );
        expect(
          admin,
          isNotEmpty,
          reason: 'admin (id=1) should appear in the response after self-heal',
        );
        expect(
          admin['username'],
          equals('admin'),
          reason:
              'self-heal must restore the canonical username; '
              '__dup_1_admin is a corruption marker that breaks login flows',
        );
      },
    );
  });
}
