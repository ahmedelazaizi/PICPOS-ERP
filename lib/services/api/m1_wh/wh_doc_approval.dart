// WH-010 (owner decision 2026-10-26): a four-eyes approval proof of a warehouse
// action is bound to ONE DOCUMENT, one operation and one version of it.
//
//   issue : POST /api/m1/wh/approvals/proof   (phone of the REQUESTER)
//           { kind: transfer|voucher|count, ref, action, username+password | cardCode }
//           -> the approver (a supervisor standing next to the phone) proves HIS
//              credential on the host; the host signs a proof whose claims are
//              `doc` = ref, `dop` = '<kind>:<action>', `dv` = the document's
//              row_version now (null for a count task), `req`, `apr`, `dev`.
//   use   : `x-approval-proof` on the approve / reject / resolve call.
//           [WhApproval.approverOf] accepts it only when ref, operation and
//           version equal the document's NOW (`approval_mismatch` 403,
//           `approval_stale` 409), and a plain P5 proof is refused
//           (`approval_not_document_bound` 403). Signature, expiry, requester,
//           device, single use per operation and the approver's validity are
//           checked earlier by `ApiUserCtx.requirePermission` -> `ApprovalGate`.
//   rules : the approver is never the requester nor anyone who made / handled the
//           document (`self_approval`), holds `stock_adjust_approve` and has the
//           document's warehouse in HIS warehouse scope.
import 'package:shelf/shelf.dart';

import '../../../core/permissions/manager_approval_rules.dart';
import '../../../core/permissions/warehouse_permission_codes.dart';
import '../../../data/database/database.dart';
import '../../activity_logger.dart';
import '../approval_proof.dart';
import '../server_login_throttle.dart';
import 'wh_count_service.dart';
import 'wh_doc_store.dart';
import 'wh_http.dart';

const _approve = WarehousePermissionCodes.stockAdjustApprove;

/// What a proof is bound to / what the use is about.
class WhApprovalTarget {
  const WhApprovalTarget({required this.ref, required this.op, this.version, this.warehouseId});
  final String ref;
  final String op;
  final int? version;
  final int? warehouseId;
}

extension WhApproval on WhHttp {
  /// Who really approves: the signed-in user when he holds [code], otherwise the
  /// approver named by a proof bound to exactly [target].
  Future<int> approverOf(WhCtx ctx, String code, WhApprovalTarget target) async {
    if (await db.userHasPermission(ctx.userId, code)) return ctx.userId;
    final claims = ApprovalProof.parse(ctx.request.headers['x-approval-proof']);
    if (claims == null) return ctx.userId;
    if (claims.docId == null) throw WhError('approval_not_document_bound', 403);
    if (claims.docId != target.ref || claims.docOp != target.op) throw WhError('approval_mismatch', 403);
    if (claims.docVersion != target.version) throw WhError('approval_stale', 409);
    return claims.approverId;
  }
}

class WhApprovalProofIssuer {
  WhApprovalProofIssuer(this.db, this.store, this.counts) : _http = WhHttp(db);
  final AppDatabase db;
  final WhDocStore store;
  final WhCountService counts;
  final WhHttp _http;

  static const _actions = {
    'transfer': {'approve', 'reject', 'resolve'},
    'voucher': {'approve', 'reject'},
    'count': {'approve'},
  };

  Future<Response> issue(Request request) => _http.run(request, [WarehousePermissionCodes.warehouseMobileAccess], (ctx) async {
        final body = await WhHttp.body(request);
        final kind = '${body['kind'] ?? ''}';
        final action = '${body['action'] ?? ''}';
        final ref = '${body['ref'] ?? ''}'.trim();
        if (ref.isEmpty || _actions[kind]?.contains(action) != true) throw WhError('bad_request', 400);

        // The target document: in the REQUESTER's scope, in a state that allows the action.
        int? version;
        int? warehouseId;
        final actors = <int?>{ctx.userId};
        if (kind == 'count') {
          final s = (await counts.tasksIn(ctx.scope.warehouseIds)).where((t) => t.ref == ref).firstOrNull;
          if (s == null || !s.readyForApproval) throw WhError('doc_not_found', 404);
          warehouseId = s.warehouseId;
          actors.addAll([...s.counters, s.task.assignedTo]);
        } else {
          final doc = await store.mustGet(ref);
          final visible = ctx.scope.allows(doc.warehouseId) || (doc.toWarehouseId != null && ctx.scope.allows(doc.toWarehouseId!));
          if (doc.kind != kind || !visible) throw WhError('doc_not_found', 404);
          if (nextWhState(kind, doc.state, action) == null) {
            throw WhError('invalid_transition', 409, {'state': doc.state, 'action': action});
          }
          version = doc.rowVersion;
          warehouseId = doc.warehouseId;
          actors.addAll([doc.createdBy, doc.data['dispatchedBy'] as int?, doc.data['receivedBy'] as int?]);
        }

        final approver = await _authenticate(body, ctx.userId);
        if (actors.contains(approver.id)) throw WhError('self_approval', 403);
        final codes = await db.getUserPermissionCodes(approver.id);
        if (!ManagerApprovalRules.canApprove(
            approverId: approver.id, requesterId: ctx.userId, approverPermissions: codes, permission: _approve)) {
          throw WhError('approver_not_authorised', 403);
        }
        // WH-010 (4): HIS warehouse scope must cover the document, not only the requester's.
        final theirs = await db.getWarehouseScopeForUser(approver.id);
        if (theirs != null && !theirs.contains(warehouseId)) throw WhError('warehouse_forbidden', 403);

        final op = '$kind:$action';
        final proof = ApprovalProof.mint(
          permission: _approve,
          requesterId: ctx.userId,
          approverId: approver.id,
          deviceId: ctx.deviceId,
          docId: ref,
          docOp: op,
          docVersion: version,
        );
        if (proof == null) throw WhError('not_ready', 503);
        final claims = ApprovalProof.parse(proof)!;
        await ActivityLogger(db).log(
          userId: ctx.userId,
          userName: '#${ctx.userId}',
          action: 'wh_approval_proof',
          entityType: 'wh_approval',
          entityId: approver.id,
          description: 'doc=$ref op=$op v=${version ?? '-'} req=${ctx.userId} apr=${approver.id} device=${ctx.deviceId}',
        );
        return WhHttp.json({
          'proof': proof,
          'ref': ref,
          'op': op,
          'version': version,
          'approverId': approver.id,
          'approverName': approver.displayName,
          'expiresAt': claims.expiresAtMs,
        });
      });

  /// The approver proves HIS credential (password or card), throttled per
  /// requester and per credential like `/api/approvals/grant`.
  Future<User> _authenticate(Map<String, Object?> body, int requesterId) async {
    final username = '${body['username'] ?? ''}'.trim();
    final password = '${body['password'] ?? ''}';
    final card = '${body['cardCode'] ?? ''}'.trim();
    final byCard = card.isNotEmpty;
    if (!byCard && (username.isEmpty || password.isEmpty)) throw WhError('bad_request', 400);
    final keys = ['wh_approval:requester:$requesterId', if (byCard) 'wh_approval:card:${card.hashCode}' else 'wh_approval:user:${username.toLowerCase()}'];
    if (keys.any(ServerLoginThrottle.isLockedOut)) throw WhError('locked_out', 429);
    final found = byCard ? await db.authenticateByCardCode(card) : await db.authenticateUser(username, password);
    if (found == null) {
      keys.forEach(ServerLoginThrottle.recordFailure);
      // 403, not 401: a wrong SUPERVISOR credential must not look like the requester's session ended.
      throw WhError('invalid_credentials', 403);
    }
    keys.forEach(ServerLoginThrottle.recordSuccess);
    if (found.user.forcePasswordChange) throw WhError('password_change_required', 403);
    return found.user;
  }
}
