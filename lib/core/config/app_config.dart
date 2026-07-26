/// Application configuration
/// Use --dart-define=IS_DEMO=true to build demo version
/// Use --dart-define=APP_FLAVOR=restaurant|cafe|supermarket|commercial for flavors
///
/// Phase C1 of the runtime-profile migration: every `features.*` /
/// `profile` getter is now backed by a `ValueNotifier` so the runtime
/// profile (loaded from settings during startup) propagates to the 905+
/// call sites that read `AppConfig.features.xxxEnabled`. Compile-time
/// defaults parsed from `APP_FLAVOR` are kept as the **initial** seed so
/// the app stays bootable on a fresh DB before settings are populated.
library;
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import 'app_flavor.dart';
import 'brand.dart';
import 'business_profile.dart';
import 'feature_policy.dart';
import '../navigation/screen_id.dart';
import '../navigation/screen_registry.dart';

export 'app_flavor.dart';
export 'business_profile.dart';
export 'feature_policy.dart';

class AppConfig {
  /// Check if running in demo mode
  static const bool isDemo = bool.fromEnvironment(
    'IS_DEMO',
    defaultValue: false,
  );

  /// Maximum products allowed in demo mode
  static const int maxDemoProducts = 50;

  /// Maximum customers allowed in demo mode
  static const int maxDemoCustomers = 50;

  /// Maximum suppliers allowed in demo mode
  static const int maxDemoSuppliers = 50;

  /// App version
  static const String version = '1.0.0';

  /// Compile-time `APP_FLAVOR` is now ONLY a seed for the very first boot
  /// before settings are read. Once the runtime profile is loaded from
  /// `settings.business_profile`, that value wins.
  static const String _flavorString = String.fromEnvironment(
    'APP_FLAVOR',
    defaultValue: 'unified',
  );

  static final AppFlavor _flavor = _parseFlavorFromEnv();
  static final BusinessProfile _initialProfile = _resolveInitialProfile();
  static final FeaturePolicy _initialFeatures =
      FeaturePolicy.fromProfile(_initialProfile);

  // ─── Phase C1: ValueNotifier bridge ──────────────────────────────────
  //
  // The `featuresListenable` and `profileListenable` are the canonical
  // source of "current" state. Riverpod's `featureFlagsProvider` syncs
  // into them via `updateFeatures` / `updateProfile`. The 905+ legacy
  // call sites of `AppConfig.features.xxxEnabled` keep working — they
  // get the latest value on the next rebuild — without needing to
  // become Consumers (Phase C2 migrates the always-mounted hot paths).

  static final ValueNotifier<FeaturePolicy> _featuresNotifier =
      ValueNotifier<FeaturePolicy>(_initialFeatures);
  static final ValueNotifier<BusinessProfile> _profileNotifier =
      ValueNotifier<BusinessProfile>(_initialProfile);

  /// Listen for live feature changes — e.g. wrap a widget in
  /// `ValueListenableBuilder(AppConfig.featuresListenable, ...)` to get
  /// rebuilds when the developer changes the profile at runtime.
  static ValueListenable<FeaturePolicy> get featuresListenable =>
      _featuresNotifier;

  /// Same for profile changes.
  static ValueListenable<BusinessProfile> get profileListenable =>
      _profileNotifier;

  /// Called by `_FeaturesBridge` (in `business_profile_provider.dart`)
  /// whenever the Riverpod-side `featureFlagsProvider` emits a new value.
  /// Uses value-based `!=` so identical-value emissions don't trigger
  /// pointless `ValueNotifier.notifyListeners` storms.
  static void updateFeatures(FeaturePolicy p) {
    if (_featuresNotifier.value != p) {
      _featuresNotifier.value = p;
    }
  }

  /// Same as [updateFeatures] but for the active profile. Kept separate
  /// so `allowedScreenIds` can react to a profile change even when the
  /// effective `FeaturePolicy` happens to compare equal (rare but
  /// possible when overrides cancel out a profile difference).
  static void updateProfile(BusinessProfile p) {
    if (_profileNotifier.value != p) {
      _profileNotifier.value = p;
    }
  }

  /// البروفايل اللي التطبيق يقلع بيه على داتابيز جديدة.
  ///
  /// العلامة لها الأسبقية: منتج زي PicPos معرَّف كـ «لايت» أصلاً، فبيقلع على
  /// نطاقه الصح من أول تشغيل بدل ما يبان كل الشاشات لحد ما حد يضيّق النطاق
  /// من الويزارد. لو العلامة مصرّحتش بافتراضي (`''` — الحالة الافتراضية
  /// لـ UralCash) بنرجع لخريطة الـ `APP_FLAVOR` القديمة زي ما هي، فسلوك
  /// UralCash متغيّرش ولا مليمتر.
  ///
  /// ملاحظة: ده **بذرة الإقلاع الأول** بس. بعد كده
  /// `BusinessProfileNotifier.build()` بيقرا `settings.business_profile`
  /// والقيمة المحفوظة تكسب.
  static BusinessProfile _resolveInitialProfile() {
    if (Brand.defaultProfileCode.isNotEmpty) {
      for (final p in BusinessProfile.values) {
        if (p.code == Brand.defaultProfileCode) return p;
      }
      // كود مش معروف = غلطة كتابة في brand.dart. `assertKnownBrand()` مش
      // بتغطي الحالة دي، فنرمي بنفس المنطق: أحسن نقف عند الإقلاع من إننا
      // نشحن منتج بنطاق شاشات غلط وهو شكله سليم.
      throw StateError(
        'Brand.defaultProfileCode غير معروف: "${Brand.defaultProfileCode}". '
        'القيم المتاحة: ${BusinessProfile.values.map((p) => p.code).join(", ")}.',
      );
    }
    return FeaturePolicy.defaultProfileForFlavor(_flavor);
  }

  static AppFlavor _parseFlavorFromEnv() {
    switch (_flavorString) {
      case 'restaurant':      return AppFlavor.restaurant;
      case 'cafe':            return AppFlavor.cafe;
      case 'supermarket':     return AppFlavor.supermarket;
      case 'supermarket_pro': return AppFlavor.supermarketPro;
      case 'supermarket_plus':return AppFlavor.supermarketPlus;
      case 'commercial':      return AppFlavor.commercial;
      default:                return AppFlavor.unified;
    }
  }

  static AppFlavor get flavor => _flavor;
  static BusinessProfile get profile => _profileNotifier.value;
  static FeaturePolicy get features => _featuresNotifier.value;

  /// App name based on flavor
  static String get appName => _flavor.appName;

  /// Arabic app name
  static String get appNameAr => _flavor.appNameAr;

  /// Default business type for settings
  static String get defaultBusinessType => profile.defaultBusinessType;

  /// Feature flags for each flavor
  static bool get showTables => features.tablesEnabled;

  static bool get showKitchen => features.kitchenEnabled;

  static bool get showScale => features.scaleEnabled;

  static bool get showOffers => features.offersEnabled;

  static bool get showHR => features.hrEnabled;

  static bool get showBranches => features.branchesEnabled;

  /// NEW: Delivery enabled by default for Restaurant/Cafe
  static bool get showDelivery => features.deliveryEnabled;

  /// NEW: Reservations for tables
  static bool get showReservations => features.reservationsEnabled;

  /// NEW: Warehouses management
  static bool get showWarehouses => features.warehousesEnabled;

  /// NEW: Barcode scanner
  static bool get showBarcode => features.barcodeEnabled;

  /// Use Invoice-based screen instead of POS (for Commercial)
  static bool get showInvoiceMode => features.invoiceModeEnabled;

  /// Show POS screen (for all except pure commercial)
  static bool get showPOS => features.posEnabled;

  /// Stable screen identifiers for the current profile.
  static List<ScreenId> get allowedScreenIds =>
      ScreenRegistry.forProfile(profile);

  /// Screens to show based on flavor (indices from main.dart)
  /// Backward-compatibility bridge until navigation fully migrates to [ScreenId].
  static List<int> get allowedScreenIndices =>
      allowedScreenIds.map((screen) => screen.navigationIndex).toList(growable: false);
}
