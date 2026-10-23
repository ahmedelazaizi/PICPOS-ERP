// SEC-008 (audit 2026-10-23): party balances must not be readable without a
// verified identity, and a branch-restricted session must only receive the
// parties of its own scope (global parties + parties listing its branch).
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';

void main() {
  late AppDatabase db;
  late ApiHandler handler;
  late int branchA;
  late int branchB;
  late int restrictedUser;

  Future<void> party(String name,
      {bool global = true, String? branches, double balance = 777}) async {
    await db.into(db.parties).insert(PartiesCompanion.insert(
          name: name,
          isCustomer: const Value(true),
          isGlobal: Value(global),
          branchIds: Value(branches),
          balance: Value(balance),
          creditLimit: const Value(5000),
        ));
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    handler = ApiHandler(db);
    branchA = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع A', globalId: const Value('gid-br-sec008-a')));
    branchB = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع B', globalId: const Value('gid-br-sec008-b')));
    await party('P-global');
    await party('P-branchA', global: false, branches: '$branchA');
    await party('P-branchB', global: false, branches: '$branchB');
    final roleId = await db.into(db.roles).insert(RolesCompanion.insert(
        name: 'كاشير SEC008', isSystemRole: const Value(false)));
    restrictedUser = await db.createUser(
      username: 'sec008_cashier',
      password: 'test',
      displayName: 'C',
      roleId: roleId,
    );
    await db.setUserBranchAccess(restrictedUser, [branchA]);
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> get(String path, {int? userId}) async {
    final resp = await handler.buildRouter().call(shelf.Request(
          'GET',
          Uri.parse('http://localhost$path'),
          context: userId == null ? null : {ApiUserCtx.userIdKey: userId},
        ));
    expect(resp.statusCode, 200);
    return jsonDecode(await resp.readAsString()) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> rows(Map<String, dynamic> body, String key) =>
      (body[key] as List).cast<Map<String, dynamic>>();

  group('tokenless', () {
    test('GET /api/parties carries no balance / credit limit', () async {
      final list = rows(await get('/api/parties'), 'parties');
      expect(list, isNotEmpty);
      for (final p in list) {
        expect(p.containsKey('balance'), isFalse, reason: '${p['name']}');
        expect(p.containsKey('creditLimit'), isFalse);
      }
    });

    test('sync pull of parties carries no balance and no forward watermark',
        () async {
      final body = await get('/api/sync/pull?table=parties');
      expect(body['serverTime'], isNull,
          reason: 'zeroed balances must not advance the client watermark');
      for (final p in rows(body, 'rows')) {
        expect(p.containsKey('balance'), isFalse);
        expect(p.containsKey('credit_limit'), isFalse);
      }
    });
  });

  group('branch-restricted session', () {
    test('GET /api/parties returns only global + own-branch parties',
        () async {
      final body = await get('/api/parties', userId: restrictedUser);
      final names = rows(body, 'parties').map((p) => p['name']).toSet();
      expect(names, containsAll(['P-global', 'P-branchA']));
      expect(names, isNot(contains('P-branchB')));
      expect(rows(body, 'parties').first.containsKey('balance'), isTrue);
    });

    test('sync pull of parties returns only global + own-branch parties',
        () async {
      final body =
          await get('/api/sync/pull?table=parties', userId: restrictedUser);
      final names = rows(body, 'rows').map((p) => p['name']).toSet();
      expect(names, containsAll(['P-global', 'P-branchA']));
      expect(names, isNot(contains('P-branchB')));
      expect(body['serverTime'], isNotNull);
    });
  });

  test('full-access user (id 1) sees every party with balances', () async {
    final body = await get('/api/parties', userId: 1);
    final names = rows(body, 'parties').map((p) => p['name']).toSet();
    expect(names, containsAll(['P-global', 'P-branchA', 'P-branchB']));
  });
}
