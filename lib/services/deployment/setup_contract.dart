// ═══════════════════════════════════════════════════════════════════════════
// SETUP CONTRACT — Spec 125 Mirror Foundation
// ═══════════════════════════════════════════════════════════════════════════
//
// Sealed class hierarchy representing the post-conditions for each of the
// four deployment modes. Consumed by `DeploymentModeCommitter` as the
// canonical description of "what it means to be fully committed to mode X".
//
// Per Spec 125 data-model.md §2.2.
// ═══════════════════════════════════════════════════════════════════════════

import '../network_service.dart';

/// Sealed contract describing post-conditions for a deployment mode commit.
///
/// Use [SetupContract.standalone], [.server], [.client], or [.mirror] to
/// construct an instance — never instantiate subclasses directly outside
/// the committer.
sealed class SetupContract {
  const SetupContract();

  /// The target NetworkMode this contract commits to.
  NetworkMode get targetMode;

  /// Short Arabic name for logging / UI ("مرآة"، "عميل"، ...).
  String get displayNameAr;
}

/// Standalone: single-device, no networking. Only requires seeded master data.
class StandaloneContract extends SetupContract {
  const StandaloneContract();

  @override
  NetworkMode get targetMode => NetworkMode.standalone;

  @override
  String get displayNameAr => 'مستقل';
}

/// Server: hosts an HTTP server on [port] that clients/mirrors connect to.
class ServerContract extends SetupContract {
  const ServerContract({required this.port});

  final int port;

  @override
  NetworkMode get targetMode => NetworkMode.server;

  @override
  String get displayNameAr => 'سيرفر';
}

/// Client: pairs with an HQ server and runs first-sync to wipe seeded data
/// + pull authoritative master data.
class ClientContract extends SetupContract {
  const ClientContract({
    required this.serverHost,
    required this.serverPort,
    required this.adminUsername,
    required this.adminPassword,
  });

  final String serverHost;
  final int serverPort;
  final String adminUsername;
  final String adminPassword;

  @override
  NetworkMode get targetMode => NetworkMode.client;

  @override
  String get displayNameAr => 'عميل';
}

/// Mirror: admin-console variant of client. Pairs, first-syncs, AND starts
/// heartbeat — used by financial/branch managers.
class MirrorContract extends SetupContract {
  const MirrorContract({
    required this.serverHost,
    required this.serverPort,
    required this.adminUsername,
    required this.adminPassword,
  });

  final String serverHost;
  final int serverPort;
  final String adminUsername;
  final String adminPassword;

  @override
  NetworkMode get targetMode => NetworkMode.mirror;

  @override
  String get displayNameAr => 'مرآة';
}
