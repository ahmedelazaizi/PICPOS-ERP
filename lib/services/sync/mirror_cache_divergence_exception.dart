// ═══════════════════════════════════════════════════════════════════════════
// MIRROR CACHE DIVERGENCE EXCEPTION — Spec 131
// ═══════════════════════════════════════════════════════════════════════════
//
// Thrown by the sale-time pre-flight check (FR-005) in
// `sales_transaction_orchestrator.dart` when a sale request references a
// master-data id that doesn't exist in the mirror's local cache. Also
// constructed in the same orchestrator when the server returns 500
// "Strict Mapping Violation" — both paths converge on the same Fatal
// screen (kind=ReconcileFatalKind.mirrorCacheDivergence).
//
// Same-process only — not thrown across an isolate boundary.
//
// See specs/131-mirror-cache-integrity/contracts/pos-preflight-check.md
// and contracts/fatal-screen-extension.md for the raise/catch contract.
// ═══════════════════════════════════════════════════════════════════════════

/// Which master-data table held the missing id at the divergence event.
enum MirrorMasterDataKind {
  warehouse,
  branch,
  customer,
  costCenter,
  safe,
}

extension MirrorMasterDataKindArabic on MirrorMasterDataKind {
  /// Human-readable Arabic noun used in the Fatal-screen `reasonAr`.
  String get arabicName {
    switch (this) {
      case MirrorMasterDataKind.warehouse:
        return 'مخزن';
      case MirrorMasterDataKind.branch:
        return 'فرع';
      case MirrorMasterDataKind.customer:
        return 'عميل';
      case MirrorMasterDataKind.costCenter:
        return 'مركز تكلفة';
      case MirrorMasterDataKind.safe:
        return 'خزينة';
    }
  }

  /// Lowercase identifier used in `[MIRROR-CACHE-DIVERGENCE] kind=<name>_missing`
  /// breadcrumbs — must stay snake_case and grep-stable.
  String get breadcrumbName {
    switch (this) {
      case MirrorMasterDataKind.warehouse:
        return 'warehouse';
      case MirrorMasterDataKind.branch:
        return 'branch';
      case MirrorMasterDataKind.customer:
        return 'customer';
      case MirrorMasterDataKind.costCenter:
        return 'cost_center';
      case MirrorMasterDataKind.safe:
        return 'safe';
    }
  }
}

class MirrorCacheDivergenceException implements Exception {
  /// Which master-data table the missing id belonged to.
  final MirrorMasterDataKind kind;

  /// The id the sale request asked for.
  final int requestedId;

  /// Up to 20 ids actually present in the mirror's cache for [kind] — sampled
  /// for the breadcrumb + Fatal-screen `details` expander. NOT used for logic.
  final List<int> cachedIds;

  /// Populated when the divergence came from a server 500
  /// "Strict Mapping Violation" response (FR-006 Site B).
  final String? serverResponse;

  /// Populated when the divergence came from a local FK 787 attempt
  /// (rare — the pre-flight check should catch it first).
  final String? localFkError;

  const MirrorCacheDivergenceException({
    required this.kind,
    required this.requestedId,
    required this.cachedIds,
    this.serverResponse,
    this.localFkError,
  });

  @override
  String toString() {
    return 'MirrorCacheDivergenceException('
        'kind=${kind.breadcrumbName} '
        'requested=$requestedId '
        'cachedSample=$cachedIds'
        '${serverResponse != null ? ' serverResponse=$serverResponse' : ''}'
        '${localFkError != null ? ' localFkError=$localFkError' : ''})';
  }
}
