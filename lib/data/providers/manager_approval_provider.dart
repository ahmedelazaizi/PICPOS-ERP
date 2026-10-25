// Riverpod wiring of the four-eyes approval flow (plan 2026-10-24, P5).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/activity_logger.dart';
import '../../services/approval/manager_approval_flow.dart';
import '../../services/network_service.dart';
import '../../domain/repositories/auth_repository.dart';
import '../database/sync_interceptor.dart';
import '../../services/server_proxy.dart';
import 'auth_providers.dart';
import 'providers.dart' show databaseProvider;
import 'repository_providers.dart' show authRepositoryProvider;

/// `POST /api/approvals/grant` through the device's own [ServerProxy].
class ServerApprovalPort implements ApprovalWirePort {
  const ServerApprovalPort();

  @override
  Future<ApprovalWireResult> grant(Map<String, dynamic> body) async {
    final (status, json) = await ServerProxy.instance.postApprovalGrant(body);
    return ApprovalWireResult(status, json);
  }
}

final managerApprovalFlowProvider = Provider<ManagerApprovalFlow>((ref) {
  final repo = ref.read(authRepositoryProvider);
  return ManagerApprovalFlow(
    wire: const ServerApprovalPort(),
    local: _RepoApprover(repo),
    requesterId: () => ref.read(authProvider).user?.id,
    isClientMode: () => SyncInterceptor.isClientMode,
    isMirror: () => NetworkService.instance.isMirror,
    audit: ({
      required String permission,
      required int? approverId,
      required int? requesterId,
      required bool offline,
    }) async {
      final requester = ref.read(authProvider).user;
      await ActivityLogger(ref.read(databaseProvider)).log(
        userId: requesterId,
        userName: requester?.username ?? '-',
        action: 'manager_approval',
        entityType: 'approval',
        entityId: approverId,
        description: 'approverId=$approverId requesterId=$requesterId '
            'permission=$permission offline=$offline',
      );
    },
  );
});

class _RepoApprover implements LocalApproverPort {
  _RepoApprover(this._repo);
  final IAuthRepository _repo;

  @override
  Future<LocalApprover?> authenticate(String input) async {
    final found = await _repo.authenticateByPasswordOrCard(input);
    if (found == null) return null;
    final perms = await _repo.getUserPermissionCodes(found.user.id);
    return LocalApprover(
      id: found.user.id,
      name: found.user.displayName,
      permissions: perms,
    );
  }
}
