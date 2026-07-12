/// Structured warning emitted by sync strategies and aggregated by
/// [ClientFirstSyncService.performFirstSync] so the Setup Wizard can
/// surface a non-zero count to the user instead of silently merging
/// near-duplicate rows.
///
/// A warning is *not* an error: the sync still succeeded for the row,
/// but it took a fallback path (e.g. matched by name when globalId
/// did not match) — which is a signal worth investigating.
library;

enum SyncWarningSeverity { info, warn, error }

class SyncWarning {
  const SyncWarning({
    required this.table,
    required this.reason,
    this.rowKey,
    this.severity = SyncWarningSeverity.warn,
  });

  /// Logical table name — e.g. `'branches'`, `'parties'`.
  final String table;

  /// Best-available identifier for the row that triggered the warning
  /// (server-side id, globalId, name, or composite key). Free-form so
  /// each strategy can choose what's most useful for diagnostics.
  final String? rowKey;

  /// Short, human-readable reason in English (developer-facing).
  /// User-facing strings stay in the wizard's banner.
  final String reason;

  final SyncWarningSeverity severity;

  @override
  String toString() {
    final key = rowKey == null ? '' : ' [$rowKey]';
    return '[${severity.name.toUpperCase()}] $table$key — $reason';
  }
}
