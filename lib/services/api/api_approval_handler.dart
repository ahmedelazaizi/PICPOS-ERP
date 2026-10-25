// ═══════════════════════════════════════════════════════════════════════════
// POST /api/approvals/grant - four-eyes manager approval decided on the MAIN
// (plan 2026-10-24, P5 / B.9). See `approval_proof.dart` for the proof format.
//
// Contract (docs/plans/2026-10-24-users-login-sync-logic-plan.md, "P5 -
// implemented contract"):
//   request  : device bearer + the REQUESTER's `X-Session-Token`
//              { permission, scope?, username?+password | cardCode | password }
//   200      : { proof, approvalId, approverId, approverName, requesterId,
//                permission, scope, critical, expiresAt, serverTime }
//   400      : invalid_request | unknown_permission
//   401      : session_required | invalid_credentials (the APPROVER's credential)
//   403      : self_approval | approver_not_authorised | branch_access_denied
//              | password_change_required (approver is on a temporary password)
//   429      : locked_out
//   503      : not_ready
// Every outcome is audited (`manager_approval` / `manager_approval_denied`).
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';

import '../../core/auth/bootstrap_admin.dart';
import '../../core/permissions/manager_approval_rules.dart';
import '../../core/permissions/permission_codes.dart';
import '../../data/database/database.dart';
import '../activity_logger.dart';
import 'api_errors.dart';
import 'api_handler_base.dart';
import 'api_session_token.dart';
import 'api_user_context.dart';
import 'approval_proof.dart';
import 'client_address.dart';
import 'server_login_throttle.dart';

class ApiApprovalHandler extends ApiHandlerBase {
  ApiApprovalHandler(super.db, super.wsClients);

  Response _fail(int status, String error, String code) =>
      jsonResponse({'error': error, 'code': code}, statusCode: status);

  static Set<String>? _known;
  static bool _isKnownPermission(String code) {
    _known ??= {for (final m in PermissionCodes.masterList) m['code']!};
    return _known!.contains(code);
  }

  Future<void> _audit(
    Request request, {
    required String action,
    required User requester,
    required String permission,
    User? approver,
    String? reason,
  }) async {
    try {
      await ActivityLogger(db).log(
        userId: requester.id,
        userName: requester.username,
        action: action,
        entityType: 'approval',
        entityId: approver?.id,
        description: 'approverId=${approver?.id ?? '-'} requesterId=${requester.id} '
            'permission=$permission offline=false '
            'device=${request.context['lanDeviceId'] ?? '-'}'
            '${reason == null ? '' : ' reason=$reason'}',
        ipAddress: ClientAddress.of(request),
      );
    } catch (_) {
      // Audit never turns a decision into a crash.
    }
  }

  /// Is [approver] allowed to act in the branch this call is made for?
  Future<bool> _approverHasBranch(Request request, User approver) async {
    final raw = request.headers['x-branch-id'];
    final branch = raw != null
        ? int.tryParse(raw)
        : request.context['lanDeviceBranchId'] as int?;
    if (branch == null || isBootstrapAdmin(approver.id, username: approver.username)) {
      return true;
    }
    final allowed = await db.getUserAccessibleBranchIds(approver.id);
    if (allowed.isEmpty) return db.isFullBranchAccessUser(approver.id);
    return allowed.contains(branch);
  }

  // EXEMPT-PER-USER: the REQUESTER is identified by his session; the APPROVER
  // proves his own credential in the body. Sits behind the device bearer.
  Future<Response> grant(Request request) async {
    try {
      if (!ApiSessionToken.isReady) {
        return _fail(503, 'Session auth not ready', 'not_ready');
      }
      final requesterId = ApiUserCtx.userIdOf(request);
      if (requesterId == null || !await ApiUserCtx.isUserLive(db, requesterId)) {
        return _fail(401, 'Missing or invalid X-Session-Token', 'session_required');
      }
      final decoded = json.decode(await request.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return _fail(400, 'invalid body', 'invalid_request');
      }
      final permission = (decoded['permission'] as String?)?.trim() ?? '';
      if (permission.isEmpty) {
        return _fail(400, 'permission required', 'invalid_request');
      }
      if (!_isKnownPermission(permission)) {
        return _fail(400, 'unknown permission', 'unknown_permission');
      }
      final username = (decoded['username'] as String?)?.trim();
      final password = decoded['password'] as String?;
      final cardCode = (decoded['cardCode'] as String?)?.trim();
      final useCard = cardCode != null && cardCode.isNotEmpty;
      final hasPassword = password != null && password.isNotEmpty;
      if (!useCard && !hasPassword) {
        return _fail(400, 'password or cardCode required', 'invalid_request');
      }

      final requester = await (db.select(db.users)
            ..where((u) => u.id.equals(requesterId)))
          .getSingle();
      final keys = <String>[
        'approval:requester:$requesterId',
        if (useCard) 'approval:card:${cardCode.hashCode}'
        else if (username != null && username.isNotEmpty)
          'approval:user:${username.toLowerCase()}',
      ];
      if (keys.any(ServerLoginThrottle.isLockedOut)) {
        return _fail(429, 'Too many attempts, try again later', 'locked_out');
      }

      final UserWithRole? found = useCard
          ? await db.authenticateByCardCode(cardCode)
          : (username != null && username.isNotEmpty)
              ? await db.authenticateUser(username, password!)
              : await db.authenticateByPasswordOrCard(password!);
      if (found == null) {
        keys.forEach(ServerLoginThrottle.recordFailure);
        await _audit(request,
            action: 'manager_approval_denied',
            requester: requester,
            permission: permission,
            reason: 'invalid_credentials');
        return _fail(401, 'Invalid credentials', 'invalid_credentials');
      }
      keys.forEach(ServerLoginThrottle.recordSuccess);
      final approver = found.user;

      Future<Response> deny(int status, String error, String code) async {
        await _audit(request,
            action: 'manager_approval_denied',
            requester: requester,
            permission: permission,
            approver: approver,
            reason: code);
        return _fail(status, error, code);
      }

      if (approver.id == requesterId) {
        return deny(403, 'You cannot approve your own action', 'self_approval');
      }
      if (approver.forcePasswordChange) {
        return deny(403, 'Approver must change the temporary password',
            'password_change_required');
      }
      final codes = await db.getUserPermissionCodes(approver.id);
      if (!ManagerApprovalRules.canApprove(
        approverId: approver.id,
        requesterId: requesterId,
        approverPermissions: codes,
        permission: permission,
      )) {
        return deny(403, 'Approver lacks authority for this operation',
            'approver_not_authorised');
      }
      if (!await _approverHasBranch(request, approver)) {
        return deny(403, 'Approver has no access to this branch', 'branch_access_denied');
      }

      final scope = (decoded['scope'] as String?)?.trim();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final proof = ApprovalProof.mint(
        permission: permission,
        requesterId: requesterId,
        approverId: approver.id,
        deviceId: request.context['lanDeviceId'] as String?,
        scope: scope == null || scope.isEmpty ? null : scope,
        nowMs: nowMs,
      );
      if (proof == null) return _fail(503, 'Session auth not ready', 'not_ready');
      await _audit(request,
          action: 'manager_approval',
          requester: requester,
          permission: permission,
          approver: approver);
      final claims = ApprovalProof.parse(proof)!;
      return jsonResponse({
        'proof': proof,
        'approvalId': claims.nonce,
        'approverId': approver.id,
        'approverName': approver.displayName,
        'requesterId': requesterId,
        'permission': permission,
        'scope': claims.scope,
        'critical': PermissionCodes.criticalFinancialOps.contains(permission),
        'expiresAt': claims.expiresAtMs,
        'serverTime': nowMs,
      });
    } catch (e) {
      debugPrint('[API] approvals.grant error: $e');
      return ApiErrors.fail(e, 'Failed to grant approval');
    }
  }
}
