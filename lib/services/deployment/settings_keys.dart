// ═══════════════════════════════════════════════════════════════════════════
// DEPLOYMENT SETTINGS KEYS — Spec 125 Mirror Foundation
// ═══════════════════════════════════════════════════════════════════════════
//
// Canonical list of `settings` table keys touched by the deployment-mode
// commit pipeline. Constants instead of magic strings → grep test in CI
// can enforce "no direct writes to these keys outside DeploymentModeCommitter".
//
// Per Spec 125 data-model.md §1.
// ═══════════════════════════════════════════════════════════════════════════

/// Settings keys read or written by `DeploymentModeCommitter`. All writes
/// MUST go through the committer — direct callers of `db.setSetting(...)`
/// for these keys are a bug (caught by `test/static/no_direct_network_mode_writes_test.dart`).
abstract class DeploymentSettingsKeys {
  // ── Existing keys reused (Spec 089 + R8) ───────────────────────────────
  static const networkMode = 'network_mode';
  static const clientFirstSyncCompleted = 'client_first_sync_completed';
  static const mirrorFirstSyncCompleted = 'mirror_first_sync_completed';

  // ── New keys added by Spec 125 ─────────────────────────────────────────

  /// Marks that the standalone wizard branch successfully seeded master data
  /// AND committed `network_mode='standalone'` atomically.
  static const standaloneSetupCompleted = 'standalone_setup_completed';

  /// Marks that the server wizard branch successfully started the HTTP
  /// server AND committed `network_mode='server'` atomically. Used by
  /// the reconciler to detect "DB says server but setup never finished".
  static const serverSetupCompleted = 'server_setup_completed';

  /// Records the last mode the committer successfully committed. Should
  /// always equal `network_mode` at steady state. Differing values indicate
  /// a crash between the two writes (logically impossible because both are
  /// in the same transaction, but kept for diagnostic resilience).
  static const lastCommittedMode = 'last_committed_mode';

  // ── Helper sets ────────────────────────────────────────────────────────

  /// All keys owned by the committer — used by grep test to enforce
  /// "no direct writes outside the orchestrator".
  static const Set<String> ownedKeys = {
    networkMode,
    clientFirstSyncCompleted,
    mirrorFirstSyncCompleted,
    standaloneSetupCompleted,
    serverSetupCompleted,
    lastCommittedMode,
  };
}
