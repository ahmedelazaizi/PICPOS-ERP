/// Contract of the desktop's warehouse-app routes (`/api/m1/*`), W1/W2 read
/// side. Decimals travel as strings. Mirrors
/// `lib/services/api/m1_wh/wh_read_handlers.dart` on the desktop.
library;

abstract final class WhPaths {
  static const info = '/api/m1/info';
  static const pair = '/api/pair';
  static const authSession = '/api/auth/session';
  static const session = '/api/m1/wh/session';
  static const items = '/api/m1/wh/items';
}

class WhWarehouse {
  const WhWarehouse({required this.id, required this.name});
  final int id;
  final String name;

  factory WhWarehouse.fromJson(Map<String, Object?> m) =>
      WhWarehouse(id: (m['id'] as num).toInt(), name: '${m['name'] ?? ''}');
}

/// `GET /api/m1/wh/session`: who is signed in on this paired phone and what
/// the server lets them see.
class WhSessionInfo {
  const WhSessionInfo({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.roleName,
    required this.branchId,
    required this.branchName,
    required this.permissions,
    required this.warehouses,
  });

  final int userId;
  final String username;
  final String displayName;
  final String? roleName;
  final int branchId;
  final String? branchName;
  final Set<String> permissions;
  final List<WhWarehouse> warehouses;

  bool can(String code) => permissions.contains(code);

  /// The «supervisor / manager» persona: may transfer. The clerk may not.
  bool get isSupervisorLevel => can('inventory_transfer');

  factory WhSessionInfo.fromJson(Map<String, Object?> m) {
    final user = (m['user'] as Map).cast<String, Object?>();
    final device = (m['device'] as Map).cast<String, Object?>();
    return WhSessionInfo(
      userId: (user['id'] as num).toInt(),
      username: '${user['username'] ?? ''}',
      displayName: '${user['displayName'] ?? ''}',
      roleName: user['roleName'] as String?,
      branchId: (device['branchId'] as num).toInt(),
      branchName: device['branchName'] as String?,
      permissions: {for (final p in (m['permissions'] as List? ?? const [])) '$p'},
      warehouses: [
        for (final w in (m['warehouses'] as List? ?? const [])) WhWarehouse.fromJson((w as Map).cast<String, Object?>()),
      ],
    );
  }
}

class WhStockLine {
  const WhStockLine({
    required this.warehouseId,
    required this.warehouse,
    required this.quantity,
    required this.reserved,
    this.blind = false,
  });
  final int warehouseId;
  final String? warehouse;

  /// Decimal string, as sent. Empty when [blind].
  final String quantity;
  final String reserved;

  /// The server withheld the quantity: a count of this item is open and the
  /// signed-in user is a counter (blind count).
  final bool blind;

  factory WhStockLine.fromJson(Map<String, Object?> m) => WhStockLine(
        warehouseId: (m['warehouseId'] as num).toInt(),
        warehouse: m['warehouse'] as String?,
        blind: m['blind'] == true,
        quantity: m['blind'] == true ? '' : '${m['quantity'] ?? '0'}',
        reserved: m['blind'] == true ? '' : '${m['reserved'] ?? '0'}',
      );
}

class WhItem {
  const WhItem({required this.id, required this.code, required this.barcode, required this.name, required this.stock});
  final int id;
  final String code;
  final String? barcode;
  final String name;
  final List<WhStockLine> stock;

  factory WhItem.fromJson(Map<String, Object?> m) => WhItem(
        id: (m['id'] as num).toInt(),
        code: '${m['code'] ?? ''}',
        barcode: m['barcode'] as String?,
        name: '${m['name'] ?? ''}',
        stock: [
          for (final s in (m['stock'] as List? ?? const [])) WhStockLine.fromJson((s as Map).cast<String, Object?>()),
        ],
      );
}
