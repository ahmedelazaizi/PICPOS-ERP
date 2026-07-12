// ═══════════════════════════════════════════════════════════════════════════
// MIRROR SETTINGS KEYS — Spec 131
// ═══════════════════════════════════════════════════════════════════════════
//
// Single canonical source for the settings keys touched by the mirror pair
// flow (FR-003 wipe targets) and the Spec 131 upgrade trigger (A5). Keep the
// literals here so the wipe and the reconcile read identical strings.
//
// The 6 `kPosDefault*` keys are CLEARED by `wipeSeededMasterDataForClient`
// when run on a mirror — they reference master-data ids that may not exist
// after the wipe + first-sync. The wildcard `kPosDefaultWarehouseBranchPrefix`
// covers per-branch override rows (`pos_default_warehouse_branch_<branchId>`).
//
// `kMirrorCacheIntegrityV1AppliedFlag` is set to 'true' after the first
// successful mirror first-sync on a build that includes Spec 131. Absence
// triggers a one-shot forced re-sync on upgrade boot.
// ═══════════════════════════════════════════════════════════════════════════

/// Default warehouse id for POS sales (global).
const String kPosDefaultWarehouseId = 'pos_default_warehouse_id';

/// Default safe id for cash POS sales.
const String kPosDefaultSafeId = 'pos_default_safe_id';

/// Default customer (party) id for POS sales.
const String kPosDefaultCustomerId = 'pos_default_customer_id';

/// Default branch id for POS sales.
const String kPosDefaultBranchId = 'pos_default_branch_id';

/// Default cost center id for POS sales.
const String kPosDefaultCostCenterId = 'pos_default_cost_center_id';

/// LIKE prefix for per-branch warehouse overrides, e.g.
/// `pos_default_warehouse_branch_3` → warehouse id used when branch 3 is
/// active. Cleared by the mirror wipe via
/// `DELETE FROM settings WHERE key LIKE 'pos_default_warehouse_branch_%'`.
const String kPosDefaultWarehouseBranchPrefix =
    'pos_default_warehouse_branch_';

/// All 5 exact-match `pos_default_*` keys, for the wipe's IN-list.
const List<String> kPosDefaultExactKeys = [
  kPosDefaultWarehouseId,
  kPosDefaultSafeId,
  kPosDefaultCustomerId,
  kPosDefaultBranchId,
  kPosDefaultCostCenterId,
];

/// Spec 131 upgrade trigger: 'true' after the first successful mirror
/// `performFirstSync()` on a build that includes Spec 131. Absence on a
/// mirror-mode boot forces a one-shot re-sync.
const String kMirrorCacheIntegrityV1AppliedFlag =
    'mirror_cache_integrity_v1_applied';
