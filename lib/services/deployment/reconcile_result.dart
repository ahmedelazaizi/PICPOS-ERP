// ═══════════════════════════════════════════════════════════════════════════
// RECONCILE RESULT — Spec 125 Mirror Foundation
// ═══════════════════════════════════════════════════════════════════════════
//
// Sealed result type returned by `NetworkService.reconcileWithDb(...)` (after
// Spec 125 extension). Replaces the previous `Future<void>` so callers MUST
// explicitly handle state-inconsistency by showing the Fatal screen rather
// than silently downgrading.
//
// Per Spec 125 contracts/reconciler.md.
// ═══════════════════════════════════════════════════════════════════════════

import '../network_service.dart';

/// Outcome of `NetworkService.reconcileWithDb(...)`.
sealed class ReconcileResult {
  const ReconcileResult();
}

/// State is consistent — system is ready to boot normally in [mode].
///
/// [forceFirstSync] is set to `true` by Spec 131's upgrade trigger when a
/// mirror device boots on a build that includes the mirror-cache-integrity
/// fix for the first time. The launcher (`main.dart`) inspects this flag
/// after `reconcileWithDb` returns and runs
/// `ClientFirstSyncService.performFirstSync()` BEFORE handing off to the
/// regular UI. Mirror gets a silent one-shot resync; existing client and
/// server installs see `forceFirstSync = false` unchanged.
class ReconcileOk extends ReconcileResult {
  const ReconcileOk(this.mode, {this.forceFirstSync = false});
  final NetworkMode mode;
  final bool forceFirstSync;
}

/// Kinds of fatal-state the Fatal screen handles.
///
/// Spec 125 added `modeStateMismatch` (network_mode disagrees with
/// pairing/first-sync state). Spec 130 adds `pgSchemaParity` for the
/// case where PostgreSQL schema diverges from the Drift schema in a way
/// the self-heal pass cannot fix (e.g., DDL permission denied). Spec 131
/// adds `mirrorCacheDivergence` for when the mirror's local master-data
/// cache no longer matches the server (pre-flight FK miss OR server-side
/// "Strict Mapping Violation"). Recovery is a forced re-pair.
enum ReconcileFatalKind {
  /// Spec 125 — DB `network_mode` doesn't match pairing/first-sync state.
  modeStateMismatch,

  /// Spec 130 — `_ensurePostgresSchemaParity` failed unrecoverably.
  /// Fatal screen offers an additional "إعادة محاولة الإصلاح الذاتى" button.
  pgSchemaParity,

  /// Spec 131 — mirror's master-data cache holds an id the server doesn't
  /// recognize (or vice versa). Surfaced by pre-flight FK check OR a
  /// server-side "Strict Mapping Violation" response. Fatal screen offers
  /// a primary "إعادة المزامنة مع السيرفر" button that re-runs
  /// `ClientFirstSyncService.performFirstSync()` and clears the POS cart.
  mirrorCacheDivergence,
}

/// State inconsistency detected — caller MUST show Fatal screen.
///
/// [reasonAr] is shown to the user (Arabic).
/// [reasonCode] is used for DiagnosticLogger tags (English upper-snake).
/// [dbMode] is whatever the DB said `network_mode` was (for the Fatal UI to
/// hint at what the system thought it was).
/// [kind] differentiates Spec 125 mode-state issues from Spec 130 schema
/// issues; defaults to `modeStateMismatch` so existing call sites keep
/// working unchanged.
/// [details] is a free-form list of English diagnostic strings the Fatal
/// screen may expose under a "تفاصيل تشخيصية" expander (Spec 130 fills
/// this with the failed entity names + error messages).
class ReconcileInconsistent extends ReconcileResult {
  const ReconcileInconsistent({
    required this.reasonAr,
    required this.reasonCode,
    required this.dbMode,
    this.kind = ReconcileFatalKind.modeStateMismatch,
    this.details = const [],
  });

  final String reasonAr;
  final String reasonCode;
  final NetworkMode dbMode;
  final ReconcileFatalKind kind;
  final List<String> details;
}

/// Known reason codes — kept as constants so callers + tests stay aligned.
abstract class ReconcileReasonCode {
  static const mirrorPairingMissing = 'MIRROR_PAIRING_MISSING';
  static const mirrorFirstSyncIncomplete = 'MIRROR_FIRSTSYNC_INCOMPLETE';
  static const clientFirstSyncIncomplete = 'CLIENT_FIRSTSYNC_INCOMPLETE';
  static const clientPairingMissing = 'CLIENT_PAIRING_MISSING';
  static const serverSetupIncomplete = 'SERVER_SETUP_INCOMPLETE';
  static const standaloneSetupIncomplete = 'STANDALONE_SETUP_INCOMPLETE';
  static const unknownMode = 'UNKNOWN_MODE';
  static const dbReadError = 'DB_READ_ERROR';
  // Spec 130 — PG schema parity unrecoverable failure.
  static const pgSchemaParity = 'PG_SCHEMA_PARITY';
  // Spec 131 — mirror master-data cache diverged from server.
  static const mirrorCacheDivergence = 'MIRROR_CACHE_DIVERGENCE';
}
