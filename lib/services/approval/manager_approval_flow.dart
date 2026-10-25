// ═══════════════════════════════════════════════════════════════════════════
// Four-eyes manager approval on a device (plan 2026-10-24, P5 / B.9).
//
//  * On the main / a standalone device the second user is verified locally
//    (this device IS the authority).
//  * On a branch device or a mirror the decision belongs to the MAIN:
//    `POST /api/approvals/grant` answers with a signed proof that is then held
//    by [ApprovalProofCarrier] and travels with the operation.
//  * The main unreachable:
//      - a mirror is online-only: refused (no silent local approval);
//      - a CRITICAL operation (`criticalFinancialOps`) is refused - owner
//        decision: no offline approval for critical operations;
//      - any other operation falls back to the local check, audited with
//        `offline: true` so the main sees it later.
// Pure Dart: every dependency is injected, so the whole matrix is unit tested.
// ═══════════════════════════════════════════════════════════════════════════
import '../../core/permissions/manager_approval_rules.dart';
import '../../core/permissions/permission_codes.dart';
import 'approval_proof_carrier.dart';

enum ManagerApprovalKind {
  approved,
  selfApproval,
  notAuthorised,
  branchDenied,
  invalidCredentials,
  lockedOut,
  passwordChangeRequired,
  sessionRequired,
  offlineRefusedCritical,
  offlineRefusedMirror,
  error,
}

class ManagerApprovalDecision {
  const ManagerApprovalDecision(
    this.kind, {
    this.approverId,
    this.approverName,
    this.proof,
    this.offline = false,
  });

  final ManagerApprovalKind kind;
  final int? approverId;
  final String? approverName;
  final String? proof;

  /// Decided on this device without the main (non-critical, branch device only).
  final bool offline;

  bool get approved => kind == ManagerApprovalKind.approved;
}

/// One answer of the main (`status` + decoded JSON). A network failure is an
/// exception thrown by [ApprovalWirePort.grant], never a status.
class ApprovalWireResult {
  const ApprovalWireResult(this.status, this.json);
  final int status;
  final Map<String, dynamic> json;
  String? get code => json['code'] as String?;
}

abstract interface class ApprovalWirePort {
  Future<ApprovalWireResult> grant(Map<String, dynamic> body);
}

class LocalApprover {
  const LocalApprover({
    required this.id,
    required this.name,
    required this.permissions,
  });
  final int id;
  final String name;
  final List<String> permissions;
}

abstract interface class LocalApproverPort {
  /// Authenticates [input] (password or card) on THIS device; null = refused.
  Future<LocalApprover?> authenticate(String input);
}

typedef ApprovalAudit =
    Future<void> Function({
      required String permission,
      required int? approverId,
      required int? requesterId,
      required bool offline,
    });

class ManagerApprovalFlow {
  ManagerApprovalFlow({
    required this.wire,
    required this.local,
    required this.requesterId,
    required this.isClientMode,
    required this.isMirror,
    this.audit,
    ApprovalProofCarrier? carrier,
  }) : carrier = carrier ?? ApprovalProofCarrier.instance;

  final ApprovalWirePort wire;
  final LocalApproverPort local;
  final int? Function() requesterId;

  /// A branch device or a mirror (the main is somewhere else).
  final bool Function() isClientMode;
  final bool Function() isMirror;
  final ApprovalAudit? audit;
  final ApprovalProofCarrier carrier;

  static bool isCritical(String permission) =>
      PermissionCodes.criticalFinancialOps.contains(permission);

  Future<ManagerApprovalDecision> approve({
    required String input,
    required String permission,
    String? scope,
    String? username,
  }) async {
    if (!isClientMode()) {
      return _local(input, permission, offline: false);
    }
    try {
      final r = await wire.grant({
        'permission': permission,
        'scope': ?scope,
        'username': ?username,
        'password': input,
      });
      return _fromWire(r, permission);
    } catch (_) {
      // The main did not answer.
      if (isMirror()) {
        return const ManagerApprovalDecision(
          ManagerApprovalKind.offlineRefusedMirror,
        );
      }
      if (isCritical(permission)) {
        return const ManagerApprovalDecision(
          ManagerApprovalKind.offlineRefusedCritical,
        );
      }
      return _local(input, permission, offline: true);
    }
  }

  ManagerApprovalDecision _fromWire(ApprovalWireResult r, String permission) {
    if (r.status == 200) {
      final proof = r.json['proof'] as String?;
      if (proof == null)
        return const ManagerApprovalDecision(ManagerApprovalKind.error);
      carrier.hold(proof, permission: permission);
      return ManagerApprovalDecision(
        ManagerApprovalKind.approved,
        approverId: (r.json['approverId'] as num?)?.toInt(),
        approverName: r.json['approverName'] as String?,
        proof: proof,
      );
    }
    final kind = switch ((r.status, r.code)) {
      (403, 'self_approval') => ManagerApprovalKind.selfApproval,
      (403, 'approver_not_authorised') => ManagerApprovalKind.notAuthorised,
      (403, 'branch_access_denied') => ManagerApprovalKind.branchDenied,
      (403, 'password_change_required') =>
        ManagerApprovalKind.passwordChangeRequired,
      (401, 'invalid_credentials') => ManagerApprovalKind.invalidCredentials,
      (401, 'session_required') => ManagerApprovalKind.sessionRequired,
      (429, _) => ManagerApprovalKind.lockedOut,
      _ => ManagerApprovalKind.error,
    };
    return ManagerApprovalDecision(kind);
  }

  Future<ManagerApprovalDecision> _local(
    String input,
    String permission, {
    required bool offline,
  }) async {
    final approver = await local.authenticate(input);
    if (approver == null) {
      return const ManagerApprovalDecision(
        ManagerApprovalKind.invalidCredentials,
      );
    }
    final requester = requesterId();
    if (requester != null && approver.id == requester) {
      return ManagerApprovalDecision(
        ManagerApprovalKind.selfApproval,
        approverId: approver.id,
        approverName: approver.name,
      );
    }
    if (!ManagerApprovalRules.canApprove(
      approverId: approver.id,
      requesterId: requester,
      approverPermissions: approver.permissions,
      permission: permission,
    )) {
      return ManagerApprovalDecision(
        ManagerApprovalKind.notAuthorised,
        approverId: approver.id,
        approverName: approver.name,
      );
    }
    // Only the OFFLINE decision needs a device-side audit row (it reaches the main
    // later with the activity-log sync); an online grant is audited by the main,
    // and on the main itself the approval is its own record.
    if (offline) {
      try {
        await audit?.call(
          permission: permission,
          approverId: approver.id,
          requesterId: requester,
          offline: offline,
        );
      } catch (_) {
        // The audit row is best-effort: the approval itself already succeeded.
      }
    }
    return ManagerApprovalDecision(
      ManagerApprovalKind.approved,
      approverId: approver.id,
      approverName: approver.name,
      offline: offline,
    );
  }
}
