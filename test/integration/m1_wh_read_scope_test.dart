// Plan 2026-10-23 W1: the warehouse phone's API surface, through the REAL
// middleware + router on an in-memory database.
//   * a `warehouse` device is confined to /api/m1/info, /api/auth/session and
//     /api/m1/wh/* (device_scope everywhere else, incl. /api/sync/pull);
//   * a revoked device is refused;
//   * /api/m1/wh/* needs warehouse_mobile_access, a live user and a warehouse
//     device;
//   * warehouses are cut to (device branch) ∩ (user warehouse access).
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:picpos_erp/core/permissions/role_grant_matrix.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';
import 'package:picpos_erp/services/role_grant_preflight_service.dart';

void main() {
  late AppDatabase db;
  late LanPairingService pairing;
  late Handler app;
  late int branchA, branchB, whA1, whA2, whB1, clerkId, noAccessId, otherBranchUserId;
  late String tokenA, tokenB;

  Future<int> user(String name, String role, {bool active = true}) async {
    final r = await (db.select(db.roles)..where((x) => x.name.equals(role))).getSingle();
    return db.into(db.users).insert(UsersCompanion.insert(
        username: name, passwordHash: 'x', displayName: 'U $name', roleId: Value(r.id), isActive: Value(active)));
  }

  Future<int> warehouse(String n, int branch) =>
      db.into(db.warehouses).insert(WarehousesCompanion.insert(name: n, branchId: Value(branch)));

  Future<String> pairDevice(String id, int branch) async {
    final offer = await pairing.issuePairingCode(
        serverHost: 'h', port: 1, serverFingerprint: 'ab' * 32, actorUserId: 1, deviceKind: 'warehouse', branchId: branch);
    final r = await pairing.pair(LanPairingRequest(
        code: offer.code, deviceId: id, deviceName: 'Phone $id', ip: '10.0.0.5', deviceKind: 'warehouse'));
    return r.token!;
  }

  Request req(String path, {required String device, required String token, int? asUser, String method = 'GET'}) =>
      Request(method, Uri.parse('http://lan$path'), headers: {
        'authorization': 'Bearer $token',
        'x-device-id': device,
        if (asUser != null) 'x-session-token': ApiSessionToken.mint(asUser),
      });

  Future<Map<String, dynamic>> bodyOf(Response r) async => jsonDecode(await r.readAsString()) as Map<String, dynamic>;

  setUp(() async {
    ApiSessionToken.setKeyForTesting('m1-wh-test-key');
    db = AppDatabase.forTesting();
    await db.ensureLanPairingSchema();
    await RoleGrantPreflightService(db).grantMissingDefaults();
    branchA = await db.into(db.branches).insert(BranchesCompanion.insert(name: 'A', code: const Value('AAA')));
    branchB = await db.into(db.branches).insert(BranchesCompanion.insert(name: 'B', code: const Value('BBB')));
    whA1 = await warehouse('A-main', branchA);
    whA2 = await warehouse('A-second', branchA);
    whB1 = await warehouse('B-main', branchB);

    clerkId = await user('clerk', kWarehouseClerkRole);
    noAccessId = await user('cashier', 'كاشير');
    otherBranchUserId = await user('clerkB', kWarehouseClerkRole);
    // The clerk may use branch A and only warehouse A-main.
    await db.into(db.userBranchAccess).insert(UserBranchAccessCompanion.insert(userId: clerkId, branchId: branchA));
    await db.into(db.userWarehouseAccess).insert(UserWarehouseAccessCompanion.insert(userId: clerkId, warehouseId: whA1));
    await db.into(db.userBranchAccess).insert(UserBranchAccessCompanion.insert(userId: otherBranchUserId, branchId: branchB));
    await db.into(db.userWarehouseAccess).insert(UserWarehouseAccessCompanion.insert(userId: otherBranchUserId, warehouseId: whB1));

    pairing = LanPairingService.forTesting(
        installSecret: 'per-install-secret-with-at-least-32-bytes', db: db, hasPermission: (_, _) async => true);
    ApiAuthMiddleware.setPairingService(pairing);
    ApiAuthMiddleware.markReady();
    tokenA = await pairDevice('wh-A', branchA);
    tokenB = await pairDevice('wh-B', branchB);
    final router = ApiHandler(db).buildRouter();
    app = ApiAuthMiddleware.createMiddleware()(router.call);
  });

  tearDown(() async {
    ApiAuthMiddleware.clearPairingService();
    ApiAuthMiddleware.clearReady();
    await db.close();
  });

  test('/api/m1/info is public and reveals no secret', () async {
    final res = await app(Request('GET', Uri.parse('http://lan/api/m1/info')));
    expect(res.statusCode, 200);
    final body = await bodyOf(res);
    expect(body.keys, containsAll(['serverId', 'apiLevel', 'tls']));
    expect(body['apiLevel'], 1);
  });

  group('device-kind confinement (ADR-W3)', () {
    for (final path in [
      '/api/sync/pull?table=users',
      '/api/parties',
      '/api/products',
      '/api/sales',
      '/api/users',
      '/api/accounts',
      '/api/settings',
    ]) {
      test('warehouse device -> 403 device_scope on $path', () async {
        final res = await app(req(path, device: 'wh-A', token: tokenA, asUser: clerkId));
        expect(res.statusCode, 403);
        expect((await bodyOf(res))['error'], 'device_scope');
      });
    }

    test('warehouse device may reach /api/m1/wh/* and the session endpoint', () async {
      final ok = await app(req('/api/m1/wh/session', device: 'wh-A', token: tokenA, asUser: clerkId));
      expect(ok.statusCode, 200);
      final sess = await app(Request('POST', Uri.parse('http://lan/api/auth/session'),
          headers: {'authorization': 'Bearer $tokenA', 'x-device-id': 'wh-A'}, body: '{}'));
      expect(sess.statusCode, isNot(403), reason: 'must pass the route policy (400 for the empty body)');
    });

    test('a revoked device is refused everywhere', () async {
      await pairing.revoke('wh-A', actorUserId: 1);
      final res = await app(req('/api/m1/wh/session', device: 'wh-A', token: tokenA, asUser: clerkId));
      expect(res.statusCode, 401);
      expect((await bodyOf(res))['error'], 'device_revoked', reason: 'the phone wipes itself on this answer');
    });

    test('a non-warehouse paired device does not get warehouse routes', () async {
      final offer = await pairing.issuePairingCode(serverHost: 'h', port: 1, actorUserId: 1, deviceKind: 'admin');
      final r = await pairing.pair(LanPairingRequest(
          code: offer.code, deviceId: 'adm-1', deviceName: 'Admin', ip: '10.0.0.7', deviceKind: 'admin'));
      final res = await app(req('/api/m1/wh/session', device: 'adm-1', token: r.token!, asUser: clerkId));
      expect(res.statusCode, 403);
      expect((await bodyOf(res))['error'], 'device_scope');
    });
  });

  group('session + scope', () {
    test('no signed-in user -> 401', () async {
      final res = await app(req('/api/m1/wh/session', device: 'wh-A', token: tokenA));
      expect(res.statusCode, 401);
    });

    test('a user without warehouse_mobile_access -> 403 permission', () async {
      final res = await app(req('/api/m1/wh/session', device: 'wh-A', token: tokenA, asUser: noAccessId));
      expect(res.statusCode, 403);
      expect(await res.readAsString(), contains('warehouse_mobile_access'));
    });

    test('a deactivated user -> 401', () async {
      await (db.update(db.users)..where((u) => u.id.equals(clerkId))).write(const UsersCompanion(isActive: Value(false)));
      final res = await app(req('/api/m1/wh/session', device: 'wh-A', token: tokenA, asUser: clerkId));
      expect(res.statusCode, 401);
    });

    test('clerk on a branch-A phone sees only A-main (user scope ∩ device branch)', () async {
      final body = await bodyOf(await app(req('/api/m1/wh/session', device: 'wh-A', token: tokenA, asUser: clerkId)));
      expect((body['warehouses'] as List).map((w) => (w as Map)['id']), [whA1]);
      expect((body['device'] as Map)['branchId'], branchA);
      expect((body['user'] as Map)['roleName'], kWarehouseClerkRole);
      expect(body['permissions'], containsAll(['warehouse_mobile_access', 'inventory_view']));
      expect(body['permissions'], isNot(contains('inventory_transfer')), reason: 'clerk has no transfers');
    });

    test('the same clerk on a branch-B phone sees nothing (not allowed into branch B)', () async {
      final body = await bodyOf(await app(req('/api/m1/wh/session', device: 'wh-B', token: tokenB, asUser: clerkId)));
      expect(body['warehouses'], isEmpty);
    });

    test('a branch-B clerk never sees branch-A warehouses even on a branch-A phone', () async {
      final body =
          await bodyOf(await app(req('/api/m1/wh/session', device: 'wh-A', token: tokenA, asUser: otherBranchUserId)));
      expect(body['warehouses'], isEmpty);
      expect(whA2, isNot(whB1));
    });
  });

  group('items lookup (read-only)', () {
    late int productId;
    setUp(() async {
      productId = await db.into(db.products).insert(ProductsCompanion.insert(
          code: 'P-1', name: 'Milk 1L', barcode: const Value('6221234567890')));
      for (final (wh, qty) in [(whA1, 12.0), (whA2, 5.0), (whB1, 99.0)]) {
        await db.into(db.inventoryBalances).insert(
            InventoryBalancesCompanion.insert(productId: productId, warehouseId: wh, quantity: Value(qty)));
      }
    });

    test('barcode lookup returns stock for the allowed warehouse only, as strings, no cost', () async {
      final res = await app(req('/api/m1/wh/items?barcode=6221234567890', device: 'wh-A', token: tokenA, asUser: clerkId));
      expect(res.statusCode, 200);
      final text = await res.readAsString();
      final body = jsonDecode(text) as Map<String, dynamic>;
      final item = (body['items'] as List).single as Map;
      expect(item['name'], 'Milk 1L');
      final stock = (item['stock'] as List).cast<Map>();
      expect(stock.map((s) => s['warehouseId']), [whA1]);
      expect(stock.single['quantity'], '12.0');
      expect(text.toLowerCase(), isNot(contains('cost')));
    });

    test('text search needs two characters; unknown barcode is an empty list, not an error', () async {
      expect((await app(req('/api/m1/wh/items?q=m', device: 'wh-A', token: tokenA, asUser: clerkId))).statusCode, 400);
      final miss = await app(req('/api/m1/wh/items?barcode=000', device: 'wh-A', token: tokenA, asUser: clerkId));
      expect((await bodyOf(miss))['items'], isEmpty);
      final byName = await bodyOf(await app(req('/api/m1/wh/items?q=Milk', device: 'wh-A', token: tokenA, asUser: clerkId)));
      expect((byName['items'] as List).length, 1);
    });

    test('items need inventory_view too', () async {
      final r = await (db.select(db.roles)..where((x) => x.name.equals(kWarehouseClerkRole))).getSingle();
      final p = await (db.select(db.permissions)..where((x) => x.code.equals('inventory_view'))).getSingle();
      await (db.delete(db.rolePermissions)
            ..where((x) => x.roleId.equals(r.id))
            ..where((x) => x.permissionId.equals(p.id)))
          .go();
      final res = await app(req('/api/m1/wh/items?barcode=6221234567890', device: 'wh-A', token: tokenA, asUser: clerkId));
      expect(res.statusCode, 403);
    });
  });
}
