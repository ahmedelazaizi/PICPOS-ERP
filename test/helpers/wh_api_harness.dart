// Real middleware + real router on an in-memory database for the warehouse
// phone API tests (plan 2026-10-23 W2-W5). NOT a test file.
//
// Two branches, warehouse A1/A2 in branch A and B1 in branch B, one paired
// warehouse phone per branch, and one user per persona (all allowed into
// branch A and warehouses A1/A2 except where a test narrows them).
import 'dart:convert';

import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:shelf/shelf.dart';

import 'package:picpos_erp/core/permissions/role_grant_matrix.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';
import 'package:picpos_erp/services/role_grant_preflight_service.dart';

class WhReply {
  WhReply(this.status, this.text);
  final int status;
  final String text;
  Map<String, dynamic> get json => (jsonDecode(text) as Map).cast<String, dynamic>();
  String? get error => json['error'] as String?;
}

class WhHarness {
  WhHarness._();
  late AppDatabase db;
  late LanPairingService pairing;
  late Handler app;
  late int branchA, branchB, a1, a2, b1;
  late int clerk, clerk2, keeper, supervisor, supervisor2, manager, admin;
  final tokens = <String, String>{};
  int _seq = 0;

  static Future<WhHarness> create() async {
    final h = WhHarness._();
    ApiSessionToken.setKeyForTesting('wh-harness-key');
    final db = h.db = AppDatabase.forTesting();
    await db.ensureLanPairingSchema();
    await RoleGrantPreflightService(db).grantMissingDefaults();
    await db.syncDefaultAccounts();
    h.branchA = await db.into(db.branches).insert(BranchesCompanion.insert(name: 'A', code: const Value('AAA')));
    h.branchB = await db.into(db.branches).insert(BranchesCompanion.insert(name: 'B', code: const Value('BBB')));
    Future<int> wh(String n, int b) => db.into(db.warehouses).insert(WarehousesCompanion.insert(name: n, branchId: Value(b)));
    h.a1 = await wh('A-main', h.branchA);
    h.a2 = await wh('A-second', h.branchA);
    h.b1 = await wh('B-main', h.branchB);

    Future<int> user(String name, String role) async {
      final r = await (db.select(db.roles)..where((x) => x.name.equals(role))).getSingle();
      final id = await db.into(db.users).insert(UsersCompanion.insert(
          username: name, passwordHash: 'x', displayName: 'U $name', roleId: Value(r.id)));
      await db.into(db.userBranchAccess).insert(UserBranchAccessCompanion.insert(userId: id, branchId: h.branchA));
      for (final w in [h.a1, h.a2]) {
        await db.into(db.userWarehouseAccess).insert(UserWarehouseAccessCompanion.insert(userId: id, warehouseId: w));
      }
      return id;
    }

    h.clerk = await user('clerk', kWarehouseClerkRole);
    h.clerk2 = await user('clerk2', kWarehouseClerkRole);
    h.keeper = await user('keeper', 'مخزني');
    h.supervisor = await user('sup', kWarehouseSupervisorRole);
    h.supervisor2 = await user('sup2', kWarehouseSupervisorRole);
    h.manager = await user('mgr', 'مدير مخزون');
    h.admin = await user('boss', 'مدير النظام');

    h.pairing = LanPairingService.forTesting(
        installSecret: 'per-install-secret-with-at-least-32-bytes', db: db, hasPermission: (_, _) async => true);
    ApiAuthMiddleware.setPairingService(h.pairing);
    ApiAuthMiddleware.markReady();
    await h.pairPhone('wh-A', h.branchA);
    await h.pairPhone('wh-B', h.branchB);
    h.app = ApiAuthMiddleware.createMiddleware()(ApiHandler(db).buildRouter().call);
    return h;
  }

  Future<void> pairPhone(String id, int branch) async {
    final offer = await pairing.issuePairingCode(
        serverHost: 'h', port: 1, serverFingerprint: 'ab' * 32, actorUserId: 1, deviceKind: 'warehouse', branchId: branch);
    final r = await pairing.pair(LanPairingRequest(
        code: offer.code, deviceId: id, deviceName: 'Phone $id', ip: '10.0.0.5', deviceKind: 'warehouse'));
    tokens[id] = r.token!;
  }

  /// One API call as [user] from phone [device]. [key] defaults to a fresh
  /// idempotency key; pass the same key to replay.
  Future<WhReply> call(
    String method,
    String path, {
    required int user,
    Object? body,
    String? key,
    String device = 'wh-A',
    Map<String, String> headers = const {},
  }) async {
    final isWrite = method != 'GET';
    final res = await app(Request(method, Uri.parse('http://lan$path'),
        headers: {
          'authorization': 'Bearer ${tokens[device]}',
          'x-device-id': device,
          'x-session-token': ApiSessionToken.mint(user),
          if (isWrite) 'x-idempotency-key': key ?? 'cmd-${_seq++}-${DateTime.now().microsecondsSinceEpoch}',
          ...headers,
        },
        body: body == null ? null : jsonEncode(body)));
    return WhReply(res.statusCode, await res.readAsString());
  }

  Future<int> product(String code, {bool trackExpiry = false, double cost = 10, String? barcode}) =>
      db.insertProduct(ProductsCompanion.insert(
        code: code, name: 'Item $code', salePrice: const Value(20.0), costPrice: Value(cost),
        trackInventory: const Value(true), trackExpiry: Value(trackExpiry), barcode: Value(barcode),
      ));

  Future<double> stock(int productId, int warehouseId) async {
    final b = await (db.select(db.inventoryBalances)
          ..where((x) => x.productId.equals(productId) & x.warehouseId.equals(warehouseId)))
        .getSingleOrNull();
    return b?.quantity ?? 0;
  }

  /// A purchase order in status [status] with one line per (productId, qty).
  Future<int> purchaseOrder(int warehouseId, Map<int, double> lines, {String status = 'sent'}) async {
    final supplier = await db.into(db.parties).insert(PartiesCompanion.insert(name: 'Supp', isSupplier: const Value(true)));
    final id = await db.createPurchaseOrder(
      supplierId: supplier,
      warehouseId: warehouseId,
      orderDate: DateTime(2026, 9, 1),
      items: [
        for (final e in lines.entries)
          PurchaseOrderItemsCompanion.insert(orderId: 0, productId: e.key, quantity: e.value, unitCost: 40, total: 40 * e.value),
      ],
    );
    await db.updatePurchaseOrderStatus(id, status);
    return id;
  }

  Future<void> dispose() async {
    ApiAuthMiddleware.clearPairingService();
    ApiAuthMiddleware.clearReady();
    await db.close();
  }
}
