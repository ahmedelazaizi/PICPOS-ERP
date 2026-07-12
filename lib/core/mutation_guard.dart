// ═══════════════════════════════════════════════════════════════════════════
// MUTATION GUARD (data classes) — Feature 004 (Multi-Branch Governance, US3)
// ═══════════════════════════════════════════════════════════════════════════
//
// Pure data + exception types with no Riverpod dependency. Importable from
// the Drift database layer (`lib/data/database/database.dart`) without
// pulling Flutter/Riverpod into the schema module.
//
// The Riverpod provider that mirrors this state lives in
// `lib/data/providers/mutation_guard_provider.dart`.
// ═══════════════════════════════════════════════════════════════════════════

/// Snapshot of whether the current session may issue write mutations.
class MutationGuard {
  const MutationGuard._(this.canMutate, this.reason);

  factory MutationGuard.allow() => const MutationGuard._(true, '');
  factory MutationGuard.readOnly({required String reason}) =>
      MutationGuard._(false, reason);

  final bool canMutate;
  final String reason;

  /// Static mirror of the latest provider value, updated whenever
  /// `mutationGuardProvider` rebuilds. DAO write paths that lack Riverpod
  /// access (Drift extensions) read this snapshot to decide whether to
  /// short-circuit with [MutationDeniedException]. Default = allow so a
  /// DAO call before the provider has ever been evaluated (e.g. during
  /// app boot, tests, or background workers) never accidentally trips
  /// the guard.
  static MutationGuard current = MutationGuard.allow();
}

/// Thrown by DAO write paths that are gated on the mutation guard when
/// `MutationGuard.current.canMutate == false`. Distinct from
/// `AccountLinkageException` so callers can present a different UI message.
class MutationDeniedException implements Exception {
  MutationDeniedException(this.reason);
  final String reason;
  @override
  String toString() => 'العملية مرفوضة: $reason';
}

/// Static mirror of `AuthState.isCrossBranchElevated`. Updated by
/// `AuthNotifier._recomputeElevation()` whenever the elevation flag changes.
/// DAOs use this to prefix activity-log descriptions with `[ELEVATED]` per
/// FR-025 without needing access to a Riverpod ref. Kept separate from
/// [MutationGuard.current] because elevation status (elevated yes/no) and
/// mutation status (can-write yes/no) diverge during a connection drop —
/// the session is still elevated, but mutations are denied.
class ElevationSnapshot {
  static bool isCrossBranchElevated = false;
}

/// Feature 004 (US3, FR-025) — prefix DAO-emitted activity-log descriptions
/// with `[ELEVATED]` when the session is a cross-branch-elevated System
/// Admin. Centralised so every touched DAO emits the same marker.
String maybeMarkElevated(String description) {
  return ElevationSnapshot.isCrossBranchElevated
      ? '[ELEVATED] $description'
      : description;
}
