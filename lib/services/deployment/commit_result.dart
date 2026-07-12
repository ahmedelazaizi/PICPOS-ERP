// ═══════════════════════════════════════════════════════════════════════════
// COMMIT RESULT — Spec 125 Mirror Foundation
// ═══════════════════════════════════════════════════════════════════════════
//
// Sealed result type for `DeploymentModeCommitter.commit(...)`. Callers
// (Setup Wizard, Developer Tools) MUST switch exhaustively on this — there
// is no third "partial" outcome by design.
//
// Per Spec 125 contracts/deployment-mode-committer.md.
// ═══════════════════════════════════════════════════════════════════════════

import '../network_service.dart';

/// Discrete step in the commit pipeline. Used in progress reporting and
/// in [CommitFailed.failedAtStep] for diagnostics.
enum CommitStep {
  /// Verify pre-conditions (port available, server reachable, etc.).
  preCheck,

  /// Mirror/Client only — establish handshake with HQ server.
  pairing,

  /// Mirror/Client only — wipe seeded data + pull authoritative master data.
  firstSync,

  /// Server only — bind HTTP listener on configured port.
  startHttpServer,

  /// Mirror only — kick off periodic heartbeat ping.
  startHeartbeat,

  /// Standalone only — populate default branch/warehouse/safes/etc.
  seedMasterData,

  /// Final atomic write to settings (network_mode + flags) inside a single
  /// DB transaction. If anything throws before this step, no DB mutation
  /// has occurred and rollback is purely about external side effects.
  finalDbCommit,
}

/// Outcome of `DeploymentModeCommitter.commit(...)`.
sealed class CommitResult {
  const CommitResult();
}

/// Commit succeeded — system is now fully in [mode] and ready for use.
class CommitOk extends CommitResult {
  const CommitOk({required this.mode, required this.totalDuration});

  final NetworkMode mode;
  final Duration totalDuration;
}

/// Commit failed at [failedAtStep]. The committer guarantees:
/// - No DB write to `network_mode` occurred.
/// - All side effects up to [failedAtStep] have been rolled back (best-effort).
/// - If rollback itself failed, [reasonCode] is prefixed with `ROLLBACK_FAILED_`.
class CommitFailed extends CommitResult {
  const CommitFailed({
    required this.failedAtStep,
    required this.reasonAr,
    required this.reasonCode,
    this.underlying,
  });

  final CommitStep failedAtStep;
  final String reasonAr;
  final String reasonCode;
  final Object? underlying;
}
