// ═══════════════════════════════════════════════════════════════════════════
// MIRROR PAIRING SERVICE — Spec 097
// ═══════════════════════════════════════════════════════════════════════════
//
// Single source of truth for "pair this device as a mirror to an HQ server".
// Two call sites share this:
//   1. Setup Wizard (`setup_wizard_screen.dart::_pairMirror`)  — first-time
//      pairing during initial install.
//   2. Mirror Pairing Dialog (`mirror_pairing_dialog.dart`)    — re-pairing
//      from Developer Tools' _ChangeModeSection when an existing install
//      flips from non-mirror to mirror.
//
// Steps (in order — each can fail and short-circuit):
//   1. Persist server address + port to NetworkService so the handshake has
//      a target.
//   2. /api/health handshake via `NetworkService.testServerConnection` —
//      proves reachability AND extracts + persists the API bearer token.
//   3. POST /api/auth/verify-admin via `ServerProxy.verifyAdmin` — proves
//      the admin credentials and returns the local-user id.
//   4. `MirrorState.setPaired(...)` — stamps server identity + admin id +
//      handshake timestamp so the mirror badge has something to display.
//
// The service deliberately does NOT call `NetworkService.setMode(mirror)`
// — that's the responsibility of the orchestrator (wizard's _finishSetup,
// or Dev Tools' changeMode). Pairing succeeds without flipping the mode so
// callers can fall back cleanly if the user changes their mind on a later
// step or the mode-change confirmation is declined.
// ═══════════════════════════════════════════════════════════════════════════

import '../data/database/sync_interceptor.dart';
import 'mirror_state.dart';
import 'network_service.dart';
import 'server_proxy.dart';

class MirrorPairingService {
  MirrorPairingService._();
  static final MirrorPairingService instance = MirrorPairingService._();

  /// Pair this device as a mirror against the HQ server at [host]:[port],
  /// authenticating with the given admin credentials. On success, server
  /// identity is recorded in [MirrorState] and the API bearer token is
  /// persisted by `NetworkService.testServerConnection`.
  /// [acquireAdminSession] — Spec 151 P1-8b. When true (mirror pairing), mint
  /// a signed admin session token from the just-verified credential and make
  /// the admin the acting identity BEFORE the caller runs the mirror's first
  /// `fullSync`. Without it, that transactional first-sync goes out tokenless
  /// and the server fail-closes every branch-scoped GET to zero rows, leaving
  /// the mirror with reference data but no cross-branch transactions. Client
  /// pairing passes false — an isolated client must NOT obtain full access.
  Future<MirrorPairingResult> pair({
    required String host,
    required int port,
    required String adminUsername,
    required String adminPassword,
    bool acquireAdminSession = false,
  }) async {
    if (host.trim().isEmpty) {
      return MirrorPairingResult.failed(
        outcome: MirrorPairingOutcome.missingFields,
        message: 'أدخل عنوان السيرفر أولاً',
      );
    }
    if (adminUsername.trim().isEmpty || adminPassword.isEmpty) {
      return MirrorPairingResult.failed(
        outcome: MirrorPairingOutcome.missingFields,
        message: 'أدخل اسم المستخدم وكلمة المرور لحساب المدير على HQ-Server',
      );
    }

    final ns = NetworkService.instance;

    // Step 1 — persist server address so the handshake has a target AND so
    // a wizard/dialog restart finds the same host.
    ns.setServerAddress(host, port: port);
    await ns.saveSettings();

    // Step 2 — /api/health handshake. Also extracts + persists the API token
    // (see `NetworkService.testServerConnection`).
    final connectionResult = await ns.testServerConnection(host, port);
    if (!(connectionResult['success'] as bool? ?? false)) {
      return MirrorPairingResult.failed(
        outcome: MirrorPairingOutcome.connectionFailed,
        message: 'فشل الاتصال بـ HQ-Server: ${connectionResult['error']}',
      );
    }

    // Step 3 — verify admin identity. Bearer token was just persisted by
    // step 2, so this call authenticates immediately.
    final verification = await ServerProxy.instance.verifyAdmin(
      username: adminUsername,
      password: adminPassword,
    );
    if (!verification.isSuccess) {
      switch (verification.outcome) {
        case MirrorAdminVerificationOutcome.invalidCredentials:
          return MirrorPairingResult.failed(
            outcome: MirrorPairingOutcome.invalidCredentials,
            message: 'اسم المستخدم أو كلمة المرور غير صحيحة',
          );
        case MirrorAdminVerificationOutcome.notAdmin:
          return MirrorPairingResult.failed(
            outcome: MirrorPairingOutcome.notAdmin,
            message: 'هذا المستخدم ليس مديراً — وضع المرآة متاح للمدراء فقط',
          );
        case MirrorAdminVerificationOutcome.error:
          return MirrorPairingResult.failed(
            outcome: MirrorPairingOutcome.verificationError,
            message:
                'تعذّر التحقق من المدير: ${verification.errorDetail ?? ""}',
          );
        case MirrorAdminVerificationOutcome.ok:
          break; // unreachable — !isSuccess above
      }
    }

    // Step 3b (Spec 151 P1-8b) — mint the admin session token NOW, while the
    // plaintext credential is still in hand (the wizard/dialog wipe the
    // password field immediately after this call returns). The mirror's first
    // `fullSync` runs next — before the operator ever logs in interactively —
    // so we also make the verified admin the acting identity
    // (`currentUserId`) so `hasSessionToken()` / `sessionTokenForCurrentUser()`
    // resolve to this token during that sync. `bypassModeGate` is required
    // because `NetworkService.setMode(mirror)` has not run yet (pairing
    // precedes it), so `isClientMode` is still false at this instant. A real
    // interactive login later overwrites `currentUserId` and mints its own
    // token. Failures are swallowed inside `acquireSession` (the sync simply
    // degrades to reference-only and DeltaPull backfills post-login).
    if (acquireAdminSession && verification.userId != null) {
      SyncInterceptor.currentUserId = verification.userId;
      await ServerProxy.instance.acquireSession(
        userId: verification.userId!,
        username: adminUsername,
        password: adminPassword,
        bypassModeGate: true,
      );
    }

    // Step 4 — record server identity + admin id in MirrorState. The
    // `serverDisplayName` mirrors the wizard's historical choice (host:port);
    // MM.B reads the real company name from /api/settings later.
    await MirrorState.instance.setPaired(
      serverDisplayName: '$host:$port',
      adminUserId: verification.userId,
    );

    return MirrorPairingResult.success(
      adminUserId: verification.userId!,
      adminDisplayName: verification.displayName ?? adminUsername,
    );
  }
}

enum MirrorPairingOutcome {
  ok,
  missingFields,
  connectionFailed,
  invalidCredentials,
  notAdmin,
  verificationError,
}

class MirrorPairingResult {
  const MirrorPairingResult._({
    required this.outcome,
    this.adminUserId,
    this.adminDisplayName,
    this.message,
  });

  factory MirrorPairingResult.success({
    required int adminUserId,
    required String adminDisplayName,
  }) =>
      MirrorPairingResult._(
        outcome: MirrorPairingOutcome.ok,
        adminUserId: adminUserId,
        adminDisplayName: adminDisplayName,
      );

  factory MirrorPairingResult.failed({
    required MirrorPairingOutcome outcome,
    required String message,
  }) =>
      MirrorPairingResult._(outcome: outcome, message: message);

  final MirrorPairingOutcome outcome;
  final int? adminUserId;
  final String? adminDisplayName;
  final String? message;

  bool get isSuccess => outcome == MirrorPairingOutcome.ok;
}
