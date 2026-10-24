// Warehouse mobile app endpoints (plan 2026-10-23, W1/W2 read side).
//
//   GET /api/m1/info          public probe (serverId, apiLevel, tls, company)
//   GET /api/m1/wh/session    who am I here: user, device, permissions, scope
//   GET /api/m1/wh/items      read-only item + per-warehouse stock lookup
//
// Every /api/m1/wh/* call needs (1) a paired device of kind `warehouse`
// (checked again here although `LanDeviceRoutePolicy` already confines such
// devices), (2) a live signed-in user, (3) `warehouse_mobile_access`, and
// results are cut to [WhScope]. Nothing here writes. Cost is never returned.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';

import '../../../core/permissions/warehouse_permission_codes.dart';
import '../../../data/database/database.dart';
import '../../network_service.dart';
import '../api_user_context.dart';
import 'wh_scope.dart';

const int kWhApiLevel = 1;

/// Codes the app needs to decide which screens to show. Not a full dump of the
/// user's permissions.
const List<String> kWhVisiblePermissions = [
  WarehousePermissionCodes.warehouseMobileAccess,
  'inventory_view',
  'inventory_edit',
  'inventory_transfer',
];

class WhApi {
  WhApi(this.db);
  final AppDatabase db;

  Response _json(Object body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: const {'content-type': 'application/json'},
      );

  Response _error(String code, int status) => _json({'error': code}, status: status);

  /// `GET /api/m1/info` - no auth (exempt prefix), reveals nothing secret.
  Future<Response> info(Request request) async {
    final fp = NetworkService.instance.serverCertFingerprint ?? '';
    final tls = NetworkService.instance.httpScheme == 'https';
    return _json({
      'serverId': fp.isEmpty ? 'unsecured' : sha256.convert(utf8.encode(fp)).toString().substring(0, 16),
      'apiLevel': kWhApiLevel,
      'tls': tls,
      'companyName': await db.getSettingValue('company_name'),
    });
  }

  /// Device + user + permission gate shared by the /wh/ routes.
  Future<({int userId, int branchId, Response? denied})> _guard(
    Request request,
    List<String> permissions,
  ) async {
    const none = (userId: 0, branchId: 0);
    final branch = request.context['lanDeviceBranchId'];
    if (request.context['lanDeviceKind'] != 'warehouse' || branch is! int) {
      return (userId: none.userId, branchId: none.branchId, denied: _error('device_scope', 403));
    }
    for (final code in permissions) {
      final denied = await ApiUserCtx.requirePermission(request, db, code);
      if (denied != null) return (userId: none.userId, branchId: none.branchId, denied: denied);
    }
    return (userId: ApiUserCtx.userIdOf(request)!, branchId: branch, denied: null);
  }

  /// `GET /api/m1/wh/session`
  Future<Response> session(Request request) async {
    final g = await _guard(request, [WarehousePermissionCodes.warehouseMobileAccess]);
    if (g.denied != null) return g.denied!;
    final user = await db.getUserById(g.userId);
    final scope = await resolveWhScope(db, userId: g.userId, deviceBranchId: g.branchId);
    final branch = await (db.select(db.branches)..where((b) => b.id.equals(g.branchId))).getSingleOrNull();
    return _json({
      'user': {
        'id': g.userId,
        'username': user?.user.username,
        'displayName': user?.user.displayName,
        'roleName': user?.role?.name,
      },
      'device': {
        'id': request.context['lanDeviceId'],
        'kind': 'warehouse',
        'branchId': g.branchId,
        'branchName': branch?.name,
      },
      'permissions': [
        for (final c in kWhVisiblePermissions)
          if (await db.userHasPermission(g.userId, c)) c,
      ],
      'warehouses': [for (final w in scope.warehouses) {'id': w.id, 'name': w.name}],
      'serverTime': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// `GET /api/m1/wh/items?barcode=<code>` or `?q=<text>` (max 20 items).
  /// Stock is the per-warehouse quantity inside the caller's scope only.
  Future<Response> items(Request request) async {
    final g = await _guard(request, [WarehousePermissionCodes.warehouseMobileAccess, 'inventory_view']);
    if (g.denied != null) return g.denied!;
    final params = request.requestedUri.queryParameters;
    final barcode = (params['barcode'] ?? '').trim();
    final q = (params['q'] ?? '').trim();
    if (barcode.isEmpty && q.length < 2) return _error('query_too_short', 400);

    final List<Product> found;
    if (barcode.isNotEmpty) {
      final byProduct = await db.getProductByBarcode(barcode);
      final unit = byProduct == null ? await db.getUnitByBarcode(barcode) : null;
      final byUnit = unit == null
          ? null
          : await (db.select(db.products)..where((p) => p.id.equals(unit.productId))).getSingleOrNull();
      final p = byProduct ?? byUnit;
      found = p == null ? const [] : [p];
    } else {
      final like = '%${q.replaceAll('%', '').replaceAll('_', '')}%';
      found = await (db.select(db.products)
            ..where((p) => p.isActive.equals(true) & (p.name.like(like) | p.code.like(like)))
            ..limit(20))
          .get();
    }

    final scope = await resolveWhScope(db, userId: g.userId, deviceBranchId: g.branchId);
    final balances = found.isEmpty || scope.warehouses.isEmpty
        ? <InventoryBalance>[]
        : await (db.select(db.inventoryBalances)
              ..where((b) =>
                  b.productId.isIn([for (final p in found) p.id]) & b.warehouseId.isIn(scope.warehouseIds.toList())))
            .get();
    final names = {for (final w in scope.warehouses) w.id: w.name};
    return _json({
      'items': [
        for (final p in found)
          {
            'id': p.id,
            'code': p.code,
            'barcode': p.barcode,
            'name': p.name,
            // Decimals travel as strings (plan MC contracts).
            'stock': [
              for (final b in balances)
                if (b.productId == p.id)
                  {
                    'warehouseId': b.warehouseId,
                    'warehouse': names[b.warehouseId],
                    'quantity': b.quantity.toString(),
                    'reserved': b.reservedQuantity.toString(),
                  },
            ],
          },
      ],
      'warehouses': [for (final w in scope.warehouses) {'id': w.id, 'name': w.name}],
    });
  }
}