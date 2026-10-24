// ApiHandler - branch scope of the `/api/users` feed (P1 / M1, plan 2026-10-24).
part of '../api_handler.dart';

/// Which branches' users (and credentials) a `/api/users` caller receives.
extension ApiHandlerUsersFeedScope on ApiHandler {
  /// The caller's FULL scope, narrowed to the paired device's own branch.
  ///
  /// * The head-only `_extractBranchId` handed a multi-branch manager the users
  ///   of his first branch only (MIR-010); this uses the whole list.
  /// * A device bound to a branch (`lanDeviceBranchId`, set from the pairing
  ///   code) receives that branch's users only, whatever `?branch_id=` or the
  ///   user's wider access say: its credentials are its branch's credentials.
  /// * A `mirror` device is not branch-bound and keeps the user's full scope.
  /// * The fail-closed sentinel (no identity) is never widened.
  ///
  /// `null` means "no restriction" (full-access user, no device branch).
  Future<List<int>?> _usersFeedScope(
    Request request, {
    required bool failClosedOnNoIdentity,
  }) async {
    final scope = await _resolveBranchScope(
      request,
      failClosedOnNoIdentity: failClosedOnNoIdentity,
    );
    if (scope != null && scope.length == 1 && scope.first == _kNoBranchAccess) {
      return scope;
    }
    final deviceBranch = request.context['lanDeviceBranchId'];
    if (deviceBranch is int && request.context['lanDeviceKind'] != 'mirror') {
      return <int>[deviceBranch];
    }
    return scope;
  }
}
