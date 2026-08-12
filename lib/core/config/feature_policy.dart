// ═══════════════════════════════════════════════════════════════════════════
// FEATURE POLICY — immutable data layer for the feature-flag system
// ═══════════════════════════════════════════════════════════════════════════
//
// This class is PURE DATA. It holds the resolved set of feature flags for
// the current install at any given moment. Validation lives in
// `FeatureValidator`; dependency rules live in `FeatureDependencyGraph`.
//
// IMPORTANT: the class is `@immutable` + `const` constructor + value-based
// `operator ==` / `hashCode` so two policies with identical flags compare
// equal. The `AppConfig` ValueNotifier relies on this — without value
// equality it either over-rebuilds (reference equality ≠ value equality)
// or silently misses real updates (identical-check on a newly-built
// instance). See the plan file §6 "ValueNotifier equality trap" for the
// full rationale.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

import 'app_flavor.dart';
import 'brand.dart';
import 'business_profile.dart';
import 'feature_key.dart';

@immutable
class FeaturePolicy {
  final bool tablesEnabled;
  final bool kitchenEnabled;
  final bool deliveryEnabled;
  final bool reservationsEnabled;
  final bool scaleEnabled;
  final bool offersEnabled;
  final bool branchesEnabled;
  final bool hrEnabled;
  final bool posEnabled;
  final bool invoiceModeEnabled;
  final bool warehousesEnabled;
  final bool barcodeEnabled;

  // Phase-A-added flags (new keys from FeatureKey that aren't yet surfaced
  // in the 7 legacy profiles). Default to sensible values; Phase B's new
  // profiles will populate them explicitly.
  final bool manufacturingEnabled;
  final bool commercialPapersEnabled;
  final bool regionsEnabled;
  final bool modifiersEnabled;
  final bool coursesEnabled;
  final bool weightDialogEnabled;

  const FeaturePolicy({
    required this.tablesEnabled,
    required this.kitchenEnabled,
    required this.deliveryEnabled,
    required this.reservationsEnabled,
    required this.scaleEnabled,
    required this.offersEnabled,
    required this.branchesEnabled,
    required this.hrEnabled,
    required this.posEnabled,
    required this.invoiceModeEnabled,
    required this.warehousesEnabled,
    required this.barcodeEnabled,
    this.manufacturingEnabled = false,
    this.commercialPapersEnabled = false,
    this.regionsEnabled = false,
    this.modifiersEnabled = false,
    this.coursesEnabled = false,
    this.weightDialogEnabled = false,
  });

  // ─── lite — وجهتان حسب الماركة ────────────────────────────────────────
  //
  // `Brand.isPicPos` ثابتُ ترجمة، فلو بقي الفرعُ مطويّاً داخل `fromProfile`
  // لَما قاسه أيُّ اختبارٍ في البوابة (‏تشتغل على الافتراضي `uralcash`).
  // ثابتان مُسمّيان يُقاسان مباشرةً — نفسُ علاج `ScreenRegistry.litePicpos`.

  /// أصغر بروفايل: نقطة بيع + مخازن + صناديق + تقارير.
  ///
  /// `barcodeEnabled: true` عن قصد — نقطة بيع تجزئة بلا قارئ باركود مش
  /// قابلة للاستخدام. القاعدة `posBarcode requires posMain` متحققة
  /// (posEnabled: true)، فـ `FeatureValidator.validate` بيمرّرها بصفر
  /// قواعد مطبَّقة وصفر مرفوضات — ودي اللي `feature_validator_test`
  /// بيتحقق منها لكل بروفايل ما عدا unified.
  ///
  /// `scaleEnabled: false` ومعاه `weightDialogEnabled: false` لازم
  /// يتحركوا مع بعض: `posWeightDialog requires posScale`، فتشغيل الحوار
  /// لوحده كان هيخلّي الڤاليديتور يفعّل الميزان تلقائياً ويكسر التأكيد فوق.
  static const FeaturePolicy lite = FeaturePolicy(
    tablesEnabled: false,
    kitchenEnabled: false,
    deliveryEnabled: false,
    reservationsEnabled: false,
    scaleEnabled: false,
    offersEnabled: false,
    branchesEnabled: false,
    hrEnabled: false,
    posEnabled: true,
    invoiceModeEnabled: false,
    warehousesEnabled: true,
    barcodeEnabled: true,
  );

  /// PicPos-lite — [lite] زائدَ المطبخِ والإضافات.
  ///
  /// قرارُ المالك 2026-08-12: «إدارة الإضافات والمعدلات» كانت موصولةً في
  /// «التكاملات والخدمات» ومحجوبةً بالعلَم وحدَه.
  ///
  /// والعلمان يتحرّكان معاً: الملفاتُ الأربعةُ التي تفتح المطبخ (restaurant ·
  /// cafe · supermarketPlus · unified) تفتح `modifiersEnabled` معه بلا
  /// استثناء، و`requires` يفرض `restaurantModifiers → posKitchen` بينما
  /// `implies` يقترح العكس. ففتحُ أحدهما وحدَه يترك الڤاليديتور يصحّح.
  ///
  /// ولا تُمَسّ [lite]: UralCash مطروحٌ ولايته قد تكون منصَّبةً عند عميل.
  static const FeaturePolicy litePicpos = FeaturePolicy(
    tablesEnabled: false,
    kitchenEnabled: true,
    deliveryEnabled: false,
    reservationsEnabled: false,
    scaleEnabled: false,
    offersEnabled: false,
    branchesEnabled: false,
    hrEnabled: false,
    posEnabled: true,
    invoiceModeEnabled: false,
    warehousesEnabled: true,
    barcodeEnabled: true,
    modifiersEnabled: true,
  );

  // ─── Profile factories (unchanged from Phase-0 behaviour) ─────────────

  factory FeaturePolicy.fromProfile(BusinessProfile profile) {
    switch (profile) {
      case BusinessProfile.restaurant:
        return const FeaturePolicy(
          tablesEnabled: true,
          kitchenEnabled: true,
          deliveryEnabled: true,
          reservationsEnabled: true,
          scaleEnabled: false,
          offersEnabled: false,
          branchesEnabled: false,
          hrEnabled: false,
          posEnabled: true,
          invoiceModeEnabled: false,
          warehousesEnabled: true,
          barcodeEnabled: false,
          modifiersEnabled: true,
          coursesEnabled: true,
        );
      case BusinessProfile.cafe:
        return const FeaturePolicy(
          tablesEnabled: true,
          kitchenEnabled: true,
          deliveryEnabled: true,
          reservationsEnabled: true,
          scaleEnabled: false,
          offersEnabled: false,
          branchesEnabled: false,
          hrEnabled: false,
          posEnabled: true,
          invoiceModeEnabled: false,
          warehousesEnabled: true,
          barcodeEnabled: false,
          modifiersEnabled: true,
        );
      case BusinessProfile.supermarket:
        return const FeaturePolicy(
          tablesEnabled: false,
          kitchenEnabled: false,
          deliveryEnabled: false,
          reservationsEnabled: false,
          scaleEnabled: true,
          offersEnabled: true,
          branchesEnabled: false,
          hrEnabled: false,
          posEnabled: true,
          invoiceModeEnabled: false,
          warehousesEnabled: true,
          barcodeEnabled: true,
          weightDialogEnabled: true,
        );
      case BusinessProfile.supermarketPro:
        return const FeaturePolicy(
          tablesEnabled: false,
          kitchenEnabled: false,
          deliveryEnabled: false,
          reservationsEnabled: false,
          scaleEnabled: true,
          offersEnabled: true,
          branchesEnabled: false,
          hrEnabled: true,
          posEnabled: true,
          invoiceModeEnabled: false,
          warehousesEnabled: true,
          barcodeEnabled: true,
          weightDialogEnabled: true,
        );
      case BusinessProfile.supermarketPlus:
        return const FeaturePolicy(
          tablesEnabled: true,
          kitchenEnabled: true,
          deliveryEnabled: true,
          reservationsEnabled: true,
          scaleEnabled: true,
          offersEnabled: true,
          branchesEnabled: false,
          hrEnabled: true,
          posEnabled: true,
          invoiceModeEnabled: false,
          warehousesEnabled: true,
          barcodeEnabled: true,
          weightDialogEnabled: true,
          modifiersEnabled: true,
        );
      case BusinessProfile.commercial:
        return const FeaturePolicy(
          tablesEnabled: false,
          kitchenEnabled: false,
          deliveryEnabled: false,
          reservationsEnabled: false,
          scaleEnabled: false,
          offersEnabled: false,
          branchesEnabled: true,
          hrEnabled: true,
          posEnabled: false,
          invoiceModeEnabled: true,
          warehousesEnabled: true,
          barcodeEnabled: true,
          manufacturingEnabled: true,
          commercialPapersEnabled: true,
          regionsEnabled: true,
        );
      // الشرحُ الكاملُ على الثابتَين [lite] و[litePicpos] فوق.
      case BusinessProfile.lite:
        // UralCash-lite تبقى حرفياً؛ PicPos-lite تفتح المطبخَ والإضافات.
        // نفسُ نمط `ScreenRegistry.lite` / `litePicpos` — الفرعُ في سطر
        // الاختيار وحدَه، والوجهتان ثابتان مُسمّيان كي يقيسهما اختبارٌ
        // واحدٌ مهما كانت ماركةُ البناء.
        return Brand.isPicPos ? litePicpos : lite;
      case BusinessProfile.unified:
        return const FeaturePolicy(
          tablesEnabled: true,
          kitchenEnabled: true,
          deliveryEnabled: true,
          reservationsEnabled: true,
          scaleEnabled: true,
          offersEnabled: true,
          branchesEnabled: true,
          hrEnabled: true,
          posEnabled: true,
          invoiceModeEnabled: true,
          warehousesEnabled: true,
          barcodeEnabled: true,
          manufacturingEnabled: true,
          commercialPapersEnabled: true,
          regionsEnabled: true,
          modifiersEnabled: true,
          coursesEnabled: true,
          weightDialogEnabled: true,
        );
    }
  }

  /// Maps the old compile-time `AppFlavor` → the matching `BusinessProfile`.
  /// Retained for Phase-A so existing startup code keeps working; removed
  /// entirely in Phase E.
  static BusinessProfile defaultProfileForFlavor(AppFlavor flavor) {
    switch (flavor) {
      case AppFlavor.restaurant:      return BusinessProfile.restaurant;
      case AppFlavor.cafe:            return BusinessProfile.cafe;
      case AppFlavor.supermarket:     return BusinessProfile.supermarket;
      case AppFlavor.supermarketPro:  return BusinessProfile.supermarketPro;
      case AppFlavor.supermarketPlus: return BusinessProfile.supermarketPlus;
      case AppFlavor.commercial:      return BusinessProfile.commercial;
      case AppFlavor.unified:         return BusinessProfile.unified;
    }
  }

  // ─── Accessors via FeatureKey — type-safe read path for Phase A+ ──────

  /// Reads a feature by its enum key. Core flags are always `true`.
  /// Unknown keys should be impossible since the enum is closed, but we
  /// fall back to `false` defensively.
  bool flag(FeatureKey key) {
    switch (key) {
      // Core — hard-locked, always on.
      case FeatureKey.coreAccounting:
      case FeatureKey.coreInventory:
      case FeatureKey.coreSales:
      case FeatureKey.coreTreasury:
        return true;
      // POS
      case FeatureKey.posMain:         return posEnabled;
      case FeatureKey.posTables:       return tablesEnabled;
      case FeatureKey.posKitchen:      return kitchenEnabled;
      case FeatureKey.posScale:        return scaleEnabled;
      case FeatureKey.posBarcode:      return barcodeEnabled;
      case FeatureKey.posOffers:       return offersEnabled;
      case FeatureKey.posDelivery:     return deliveryEnabled;
      case FeatureKey.posReservations: return reservationsEnabled;
      case FeatureKey.posWeightDialog: return weightDialogEnabled;
      // Restaurant
      case FeatureKey.restaurantModifiers: return modifiersEnabled;
      case FeatureKey.restaurantCourses:   return coursesEnabled;
      // Enterprise
      case FeatureKey.enterpriseBranches:        return branchesEnabled;
      case FeatureKey.enterpriseRegions:         return regionsEnabled;
      case FeatureKey.enterpriseHr:              return hrEnabled;
      case FeatureKey.enterpriseManufacturing:   return manufacturingEnabled;
      case FeatureKey.enterpriseCommercialPapers: return commercialPapersEnabled;
      case FeatureKey.enterpriseInvoiceMode:     return invoiceModeEnabled;
      case FeatureKey.enterpriseWarehouses:      return warehousesEnabled;
    }
  }

  /// Returns a new policy with exactly one flag changed. Core flags can
  /// *technically* be flipped here — the `FeatureValidator` rejects such
  /// attempts before they reach a real persist path, but this method
  /// stays pure-data so unit tests can simulate illegal inputs.
  FeaturePolicy setFlag(FeatureKey key, bool value) {
    switch (key) {
      case FeatureKey.coreAccounting:
      case FeatureKey.coreInventory:
      case FeatureKey.coreSales:
      case FeatureKey.coreTreasury:
        // Data-layer honours the request; validator enforces the lock.
        return this;
      case FeatureKey.posMain:
        return copyWith(posEnabled: value);
      case FeatureKey.posTables:
        return copyWith(tablesEnabled: value);
      case FeatureKey.posKitchen:
        return copyWith(kitchenEnabled: value);
      case FeatureKey.posScale:
        return copyWith(scaleEnabled: value);
      case FeatureKey.posBarcode:
        return copyWith(barcodeEnabled: value);
      case FeatureKey.posOffers:
        return copyWith(offersEnabled: value);
      case FeatureKey.posDelivery:
        return copyWith(deliveryEnabled: value);
      case FeatureKey.posReservations:
        return copyWith(reservationsEnabled: value);
      case FeatureKey.posWeightDialog:
        return copyWith(weightDialogEnabled: value);
      case FeatureKey.restaurantModifiers:
        return copyWith(modifiersEnabled: value);
      case FeatureKey.restaurantCourses:
        return copyWith(coursesEnabled: value);
      case FeatureKey.enterpriseBranches:
        return copyWith(branchesEnabled: value);
      case FeatureKey.enterpriseRegions:
        return copyWith(regionsEnabled: value);
      case FeatureKey.enterpriseHr:
        return copyWith(hrEnabled: value);
      case FeatureKey.enterpriseManufacturing:
        return copyWith(manufacturingEnabled: value);
      case FeatureKey.enterpriseCommercialPapers:
        return copyWith(commercialPapersEnabled: value);
      case FeatureKey.enterpriseInvoiceMode:
        return copyWith(invoiceModeEnabled: value);
      case FeatureKey.enterpriseWarehouses:
        return copyWith(warehousesEnabled: value);
    }
  }

  FeaturePolicy copyWith({
    bool? tablesEnabled,
    bool? kitchenEnabled,
    bool? deliveryEnabled,
    bool? reservationsEnabled,
    bool? scaleEnabled,
    bool? offersEnabled,
    bool? branchesEnabled,
    bool? hrEnabled,
    bool? posEnabled,
    bool? invoiceModeEnabled,
    bool? warehousesEnabled,
    bool? barcodeEnabled,
    bool? manufacturingEnabled,
    bool? commercialPapersEnabled,
    bool? regionsEnabled,
    bool? modifiersEnabled,
    bool? coursesEnabled,
    bool? weightDialogEnabled,
  }) {
    return FeaturePolicy(
      tablesEnabled: tablesEnabled ?? this.tablesEnabled,
      kitchenEnabled: kitchenEnabled ?? this.kitchenEnabled,
      deliveryEnabled: deliveryEnabled ?? this.deliveryEnabled,
      reservationsEnabled: reservationsEnabled ?? this.reservationsEnabled,
      scaleEnabled: scaleEnabled ?? this.scaleEnabled,
      offersEnabled: offersEnabled ?? this.offersEnabled,
      branchesEnabled: branchesEnabled ?? this.branchesEnabled,
      hrEnabled: hrEnabled ?? this.hrEnabled,
      posEnabled: posEnabled ?? this.posEnabled,
      invoiceModeEnabled: invoiceModeEnabled ?? this.invoiceModeEnabled,
      warehousesEnabled: warehousesEnabled ?? this.warehousesEnabled,
      barcodeEnabled: barcodeEnabled ?? this.barcodeEnabled,
      manufacturingEnabled: manufacturingEnabled ?? this.manufacturingEnabled,
      commercialPapersEnabled:
          commercialPapersEnabled ?? this.commercialPapersEnabled,
      regionsEnabled: regionsEnabled ?? this.regionsEnabled,
      modifiersEnabled: modifiersEnabled ?? this.modifiersEnabled,
      coursesEnabled: coursesEnabled ?? this.coursesEnabled,
      weightDialogEnabled: weightDialogEnabled ?? this.weightDialogEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FeaturePolicy &&
      other.tablesEnabled == tablesEnabled &&
      other.kitchenEnabled == kitchenEnabled &&
      other.deliveryEnabled == deliveryEnabled &&
      other.reservationsEnabled == reservationsEnabled &&
      other.scaleEnabled == scaleEnabled &&
      other.offersEnabled == offersEnabled &&
      other.branchesEnabled == branchesEnabled &&
      other.hrEnabled == hrEnabled &&
      other.posEnabled == posEnabled &&
      other.invoiceModeEnabled == invoiceModeEnabled &&
      other.warehousesEnabled == warehousesEnabled &&
      other.barcodeEnabled == barcodeEnabled &&
      other.manufacturingEnabled == manufacturingEnabled &&
      other.commercialPapersEnabled == commercialPapersEnabled &&
      other.regionsEnabled == regionsEnabled &&
      other.modifiersEnabled == modifiersEnabled &&
      other.coursesEnabled == coursesEnabled &&
      other.weightDialogEnabled == weightDialogEnabled;

  @override
  int get hashCode => Object.hashAll([
        tablesEnabled,
        kitchenEnabled,
        deliveryEnabled,
        reservationsEnabled,
        scaleEnabled,
        offersEnabled,
        branchesEnabled,
        hrEnabled,
        posEnabled,
        invoiceModeEnabled,
        warehousesEnabled,
        barcodeEnabled,
        manufacturingEnabled,
        commercialPapersEnabled,
        regionsEnabled,
        modifiersEnabled,
        coursesEnabled,
        weightDialogEnabled,
      ]);
}
