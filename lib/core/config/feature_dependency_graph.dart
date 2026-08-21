// ═══════════════════════════════════════════════════════════════════════════
// FEATURE DEPENDENCY GRAPH — declarative rules over FeatureKey
// ═══════════════════════════════════════════════════════════════════════════
//
// This file is the *rules* layer of the three-layer feature system:
//   1. `FeaturePolicy`            — pure data (12 bool flags).
//   2. `FeatureDependencyGraph`   — pure rules (this file).
//   3. `FeatureValidator`         — engine that applies rules to a policy.
//
// The graph is a compile-time constant so adding a rule costs one line and
// the unit test gets a free snapshot assertion.
//
// Relation types:
//   - `requires`  (enforced, hard)   A → B means "if A is on, B MUST be on".
//                                    Validator auto-enables B when A is on.
//   - `implies`   (hinted, soft)     A → B means "enabling A suggests B".
//                                    Validator emits a hint, does not force.
//   - `conflicts` (mutually exclusive) {A, B, …} means they cannot co-exist.
//                                    Last-writer-wins disables the others.
//   - `locked`    (immutable)        These flags cannot be disabled.
// ═══════════════════════════════════════════════════════════════════════════

import 'feature_key.dart';

class FeatureDependencyGraph {
  const FeatureDependencyGraph._();

  /// `A requires B` — if A is enabled, B must also be enabled. The
  /// validator auto-enables B and records the rule that fired.
  static const Map<FeatureKey, List<FeatureKey>> requires = {
    // Tables service obviously needs the POS surface and the kitchen
    // pipeline; you can't run tables without the order engine behind them.
    FeatureKey.posTables: [FeatureKey.posMain, FeatureKey.posKitchen],

    // لا `posReservations: [posTables]`: الحجزُ موعدُ خدمةٍ يحجز وقتَ إنسان،
    // والطاولةُ تحجز مكاناً — وصالونٌ أو عيادةٌ لا طاولاتِ فيها. وإبقاؤها
    // كان يُشغّل وحدةَ الطاولات قسراً على كلّ تنصيبٍ يفتح الحجوزات.

    // Delivery routing pulls orders from the POS.
    FeatureKey.posDelivery: [FeatureKey.posMain],

    // Offers / barcode / weight dialog are all POS add-ons.
    FeatureKey.posOffers: [FeatureKey.posMain],
    FeatureKey.posBarcode: [FeatureKey.posMain],
    FeatureKey.posWeightDialog: [FeatureKey.posMain, FeatureKey.posScale],

    // Restaurant modifiers / courses depend on the kitchen pipeline.
    FeatureKey.restaurantModifiers: [FeatureKey.posKitchen],
    FeatureKey.restaurantCourses: [FeatureKey.posKitchen],

    // Regions are a grouping layer above branches.
    FeatureKey.enterpriseRegions: [FeatureKey.enterpriseBranches],
  };

  /// `A implies B` — enabling A is a *hint* to enable B. The validator
  /// surfaces a UI suggestion but does not force. Used for pairings that
  /// are usually enabled together but aren't hard dependencies.
  static const Map<FeatureKey, List<FeatureKey>> implies = {
    // Kitchen installs typically want modifiers; not everyone uses them.
    FeatureKey.posKitchen: [FeatureKey.restaurantModifiers],

    // Manufacturing installs usually also use commercial papers (B2B).
    FeatureKey.enterpriseManufacturing: [FeatureKey.enterpriseCommercialPapers],
  };

  /// Features that are mutually exclusive. Inside each group, enabling
  /// one disables the others and records the displaced flags.
  ///
  /// Stored as a `List<Set>` so adding a new group is a self-contained
  /// edit — no need to extend multiple maps.
  static const List<Set<FeatureKey>> conflicts = [
    // A pure invoice-mode install (commercial B2B) is incompatible with
    // the tableside / kitchen flow: they model two different order
    // journeys.
    {FeatureKey.enterpriseInvoiceMode, FeatureKey.posTables},
  ];

  /// Hard-locked: cannot be disabled under any circumstances. Any override
  /// that tries gets silently rejected and audit-logged at `warning`.
  static const Set<FeatureKey> locked = {
    FeatureKey.coreAccounting,
    FeatureKey.coreInventory,
    FeatureKey.coreSales,
    FeatureKey.coreTreasury,
  };
}
