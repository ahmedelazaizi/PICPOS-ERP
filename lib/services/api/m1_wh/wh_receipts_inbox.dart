// WH-002 (review 2026-10-25): the accountant's side of R-A. A phone receipt
// moves nothing until somebody with `purchases_create` converts it into the
// purchase invoice; before this the only way was a hand-made HTTP call from a
// paired phone. This service is what the desktop screen
// (`WhReceiptsInboxDialog`) and the desktop LAN route
// (`/api/m1/wh/desk/receipts`) call: it lists the SUBMITTED receipts and
// converts one through the unchanged [WhReceiptPosting].
//
// Rules enforced HERE (not in the screen):
//   * the user must hold `purchases_create`;
//   * a user restricted to some warehouses only sees/converts those;
//   * a receipt converts once (the state machine refuses a second `convert`).
import '../../../core/permissions/permission_codes.dart';
import '../../../data/database/database.dart';
import '../../activity_logger.dart';
import '../mirror_console_guard.dart';
import 'wh_doc_store.dart';
import 'wh_http.dart';
import 'wh_receipt_posting.dart';

class _Scope {
  const _Scope(this.warehouses, this.branches);
  final Set<int>? warehouses;
  final List<int>? branches;
}

class WhReceiptsInbox {
  /// [mirror]: the caller is a branch-manager console - the user's BRANCH scope
  /// applies too (a warehouse of a branch outside it is neither listed nor
  /// convertible), and a user with no explicit warehouse rows is limited by
  /// branch alone (a branch manager is assigned branches, not warehouses).
  WhReceiptsInbox(this.db, {this.mirror = false}) : store = WhDocStore(db);
  final AppDatabase db;
  final WhDocStore store;
  final bool mirror;

  static const _permission = PermissionCodes.purchasesCreate;

  Future<void> _require(int userId) async {
    if (!await db.userHasPermission(userId, _permission)) throw WhError('permission_denied', 403);
  }

  Future<_Scope> _scope(int userId) async {
    final w = (await db.getWarehouseScopeForUser(userId))?.toSet();
    final branches = mirror ? await MirrorConsole.scopeOf(db, userId) : null;
    final warehouses = mirror && w != null && w.isEmpty ? null : w;
    return _Scope(warehouses, branches);
  }

  Future<bool> _allowed(_Scope scope, int warehouseId) async {
    if (scope.warehouses != null && !scope.warehouses!.contains(warehouseId)) return false;
    final branches = scope.branches;
    if (branches == null) return true;
    final wh = await db.getWarehouseById(warehouseId);
    return wh?.branchId != null && branches.contains(wh!.branchId);
  }

  /// Submitted receipts waiting for the accountant, oldest first.
  Future<List<Map<String, Object?>>> list(int userId) async {
    await _require(userId);
    final scope = await _scope(userId);
    final docs = await store.list(kind: 'po_receipt', states: ['submitted']);
    final out = <Map<String, Object?>>[];
    for (final d in docs.reversed) {
      if (!await _allowed(scope, d.warehouseId)) continue;
      final po = d.refId == null ? null : await db.getPurchaseOrderById(int.parse(d.refId!));
      final supplier = po == null ? null : await db.getPartyById(po.supplierId);
      final warehouse = await db.getWarehouseById(d.warehouseId);
      final author = await (db.select(db.users)..where((u) => u.id.equals(d.createdBy))).getSingleOrNull();
      final lines = <Map<String, Object?>>[];
      for (final l in await store.lines(d.id)) {
        final p = await db.getProductById(l.productId);
        lines.add({
          'productId': l.productId,
          'name': p?.name ?? '#${l.productId}',
          'quantity': fmtQty(l.qty),
          'condition': l.condition,
          if (l.batchNumber != null) 'batchNumber': l.batchNumber,
        });
      }
      out.add({
        'globalId': d.gid,
        'version': d.rowVersion,
        'orderNumber': po?.orderNumber ?? '#${d.refId}',
        'supplier': supplier?.name,
        'warehouse': warehouse?.name,
        'warehouseId': d.warehouseId,
        'createdBy': author?.displayName ?? author?.username ?? '#${d.createdBy}',
        'createdAt': d.row['created_at'],
        'lines': lines,
      });
    }
    return out;
  }

  /// Converts [gid] into the purchase invoice as [userId]. [audit] false when
  /// the caller already writes the activity-log line (the HTTP path does it in
  /// `WhDocStore.command`).
  Future<Map<String, Object?>> convert(String gid, int userId, {bool audit = true, int? expectedVersion}) async {
    await _require(userId);
    final doc = await store.mustGet(gid);
    if (doc.kind != 'po_receipt' || !await _allowed(await _scope(userId), doc.warehouseId)) {
      throw WhError('doc_not_found', 404);
    }
    final result = await db.transaction(() => WhReceiptPosting(db, store).convert(doc, userId, expectedVersion: expectedVersion));
    if (audit) {
      final u = await (db.select(db.users)..where((x) => x.id.equals(userId))).getSingleOrNull();
      await ActivityLogger(db).log(
        userId: userId,
        userName: u?.username ?? '#$userId',
        action: 'wh_receipt_convert',
        entityType: 'wh_mobile_doc',
        entityId: doc.id,
        description: 'wh_mobile_doc receipt_convert',
        deviceInfo: 'desktop',
      );
    }
    return result;
  }
}
