// ═══════════════════════════════════════════════════════════════════════════
// MIRROR PARITY REPORT — Spec 131 audit dialog (FR-010)
// ═══════════════════════════════════════════════════════════════════════════
//
// In-memory shape produced by the admin "تدقيق مزامنة المرآة" audit dialog.
// Compares the mirror's local master-data ids with the server's, per table.
// Not persisted — re-computed on each press.
//
// See specs/131-mirror-cache-integrity/contracts/audit-tool.md.
// ═══════════════════════════════════════════════════════════════════════════

class MirrorParityRow {
  /// Table name e.g. 'warehouses', 'branches', 'safes'.
  final String table;
  final int localCount;
  final int serverCount;

  /// IDs the server has but the mirror does NOT.
  final List<int> missingOnMirror;

  /// IDs the mirror has but the server does NOT.
  final List<int> extraOnMirror;

  const MirrorParityRow({
    required this.table,
    required this.localCount,
    required this.serverCount,
    required this.missingOnMirror,
    required this.extraOnMirror,
  });

  bool get isInSync =>
      localCount == serverCount &&
      missingOnMirror.isEmpty &&
      extraOnMirror.isEmpty;
}

class MirrorParityReport {
  final DateTime runAt;
  final List<MirrorParityRow> rows;
  final Duration elapsed;

  const MirrorParityReport({
    required this.runAt,
    required this.rows,
    required this.elapsed,
  });

  bool get hasAnyDrift => rows.any((r) => !r.isInSync);

  int get driftCount => rows.where((r) => !r.isInSync).length;
}
