// ═══════════════════════════════════════════════════════════════════════════
// FEATURE KEY — compile-time-safe enumeration of every toggleable feature
// ═══════════════════════════════════════════════════════════════════════════
//
// Every feature flag in the system is identified by a value of this enum,
// not a raw string. The `settingKey` extension below is the ONLY place
// string keys appear — which means:
//   - IDE refactors work (renaming an enum value updates every call site)
//   - typos become compile errors
//   - unit tests can round-trip every enum value through the string form
//
// Namespacing convention: `feature.<module>.<flag>`
//   - `core.*`        — hard-locked features; cannot be disabled
//   - `pos.*`         — point-of-sale surfaces
//   - `restaurant.*`  — table-service / kitchen features
//   - `enterprise.*`  — multi-branch / HR / manufacturing / B2B
//
// Adding a new feature:
//   1. Add the enum value here.
//   2. Map it in `FeatureKeyX.settingKey` + `tryFromSettingKey`.
//   3. Register its metadata in `FeatureCatalog`.
//   4. Reference it in `FeatureDependencyGraph` if it has dependencies.
//   5. Set its default in each `BusinessProfile` via `FeaturePolicy.fromProfile`.
// ═══════════════════════════════════════════════════════════════════════════

/// Every toggleable feature flag in the system. The set of values is
/// intentionally closed — adding a new feature is a deliberate code
/// change, not a configuration update.
enum FeatureKey {
  // ── Core (hard-locked — always on) ──────────────────────────────────────
  coreAccounting,
  coreInventory,
  coreSales,
  coreTreasury,

  // ── POS surfaces ────────────────────────────────────────────────────────
  posMain,
  posTables,
  posKitchen,
  posScale,
  posBarcode,
  posOffers,
  posDelivery,
  posReservations,
  posWeightDialog,

  // ── Restaurant-specific ─────────────────────────────────────────────────
  restaurantModifiers,
  restaurantCourses,

  // ── Enterprise / Wholesale ──────────────────────────────────────────────
  enterpriseBranches,
  enterpriseRegions,
  enterpriseHr,
  enterpriseManufacturing,
  enterpriseCommercialPapers,
  enterpriseInvoiceMode,
  enterpriseWarehouses,
}

extension FeatureKeyX on FeatureKey {
  /// Canonical string used as the settings-table key. Change carefully —
  /// existing installs store overrides under these exact keys.
  String get settingKey {
    switch (this) {
      // Core
      case FeatureKey.coreAccounting:     return 'feature.core.accounting';
      case FeatureKey.coreInventory:      return 'feature.core.inventory';
      case FeatureKey.coreSales:          return 'feature.core.sales';
      case FeatureKey.coreTreasury:       return 'feature.core.treasury';
      // POS
      case FeatureKey.posMain:            return 'feature.pos.main';
      case FeatureKey.posTables:          return 'feature.pos.tables';
      case FeatureKey.posKitchen:         return 'feature.pos.kitchen';
      case FeatureKey.posScale:           return 'feature.pos.scale';
      case FeatureKey.posBarcode:         return 'feature.pos.barcode';
      case FeatureKey.posOffers:          return 'feature.pos.offers';
      case FeatureKey.posDelivery:        return 'feature.pos.delivery';
      case FeatureKey.posReservations:    return 'feature.pos.reservations';
      case FeatureKey.posWeightDialog:    return 'feature.pos.weight_dialog';
      // Restaurant
      case FeatureKey.restaurantModifiers: return 'feature.restaurant.modifiers';
      case FeatureKey.restaurantCourses:   return 'feature.restaurant.courses';
      // Enterprise
      case FeatureKey.enterpriseBranches:        return 'feature.enterprise.branches';
      case FeatureKey.enterpriseRegions:         return 'feature.enterprise.regions';
      case FeatureKey.enterpriseHr:              return 'feature.enterprise.hr';
      case FeatureKey.enterpriseManufacturing:   return 'feature.enterprise.manufacturing';
      case FeatureKey.enterpriseCommercialPapers: return 'feature.enterprise.commercial_papers';
      case FeatureKey.enterpriseInvoiceMode:     return 'feature.enterprise.invoice_mode';
      case FeatureKey.enterpriseWarehouses:      return 'feature.enterprise.warehouses';
    }
  }

  /// Parses a persisted key back to its enum value, or `null` if the key
  /// is foreign (e.g. left over from an older schema or a typo). Callers
  /// silently ignore `null` — never crash on unknown keys.
  static FeatureKey? tryFromSettingKey(String key) {
    for (final v in FeatureKey.values) {
      if (v.settingKey == key) return v;
    }
    return null;
  }

  /// `true` if this flag can never be disabled — wired to the validator's
  /// locked-set. Kept on the enum extension so business code doesn't have
  /// to import the dependency graph just to ask.
  bool get isCore {
    switch (this) {
      case FeatureKey.coreAccounting:
      case FeatureKey.coreInventory:
      case FeatureKey.coreSales:
      case FeatureKey.coreTreasury:
        return true;
      default:
        return false;
    }
  }

  /// Coarse namespace for UI grouping. Lines up with the settings-key
  /// prefix after `feature.<module>.`.
  String get module {
    final parts = settingKey.split('.');
    return parts.length >= 3 ? parts[1] : 'other';
  }
}
