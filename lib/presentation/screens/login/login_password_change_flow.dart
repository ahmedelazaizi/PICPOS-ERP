import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/providers.dart';
import '../../widgets/dialogs/force_change_password_dialog.dart';

/// Runs the forced password change and returns the user to continue with, or
/// `null` when the user cancelled (plan 2026-10-24, P2).
///
/// * [viaMain] false (standalone / main device): the local change, then the
///   refreshed row.
/// * [viaMain] true (client / mirror): the change is made on the main system
///   proving identity with [currentPassword] / [cardCode]; the login is then
///   completed with the NEW password through the normal path (so the branch
///   gate, the session and the credential stamp all apply).
Future<UserWithRole?> runForcedPasswordChange(
  BuildContext context,
  WidgetRef ref, {
  required String username,
  int? userId,
  bool viaMain = false,
  String? currentPassword,
  String? cardCode,
}) async {
  String? newPassword;
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ForceChangePasswordDialog(
      userId: userId,
      username: username,
      viaMain: viaMain,
      currentPassword: currentPassword,
      cardCode: cardCode,
      onPasswordChanged: (p) => newPassword = p,
    ),
  );
  if (changed != true) return null;
  final repo = ref.read(authRepositoryProvider);
  if (viaMain && newPassword != null) {
    return repo.authenticateUser(username, newPassword!);
  }
  return userId == null ? null : repo.getUserById(userId);
}
