// ═══════════════════════════════════════════════════════════════════════════
// BUSINESS PROFILE CATALOG — labels + previews for each profile
// ═══════════════════════════════════════════════════════════════════════════
//
// Single source of truth for user-facing profile metadata (Arabic name,
// description, enabled/disabled feature-key previews). Consumed by the
// setup wizard's business-profile step and by the developer-tools
// "change profile" flow so the two UIs stay in lock-step.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

import 'business_profile.dart';
import 'feature_key.dart';
import 'feature_policy.dart';

@immutable
class BusinessProfileMeta {
  final BusinessProfile profile;
  final String arabicName;
  final String arabicDescription;

  /// Features that are ON by default for this profile. Derived from
  /// `FeaturePolicy.fromProfile(profile)` — never hand-coded; the catalog
  /// stays in sync with policy changes automatically.
  final List<FeatureKey> enabledByDefault;

  /// Non-core features that are OFF by default. Used by the wizard's
  /// "see what you'll miss" secondary preview row.
  final List<FeatureKey> disabledByDefault;

  const BusinessProfileMeta._({
    required this.profile,
    required this.arabicName,
    required this.arabicDescription,
    required this.enabledByDefault,
    required this.disabledByDefault,
  });

  factory BusinessProfileMeta.build({
    required BusinessProfile profile,
    required String arabicName,
    required String arabicDescription,
  }) {
    final policy = FeaturePolicy.fromProfile(profile);
    final enabled = <FeatureKey>[];
    final disabled = <FeatureKey>[];
    for (final k in FeatureKey.values) {
      if (k.isCore) continue; // cores are always on — uninteresting in previews
      (policy.flag(k) ? enabled : disabled).add(k);
    }
    return BusinessProfileMeta._(
      profile: profile,
      arabicName: arabicName,
      arabicDescription: arabicDescription,
      enabledByDefault: List.unmodifiable(enabled),
      disabledByDefault: List.unmodifiable(disabled),
    );
  }
}

class BusinessProfileCatalog {
  const BusinessProfileCatalog._();

  static final List<BusinessProfileMeta> _all = [
    // ترتيب القايمة = ترتيب الاختيار في الويزارد. `lite` الأول لأنه الأبسط
    // والافتراضي لـ PicPos.
    BusinessProfileMeta.build(
      profile: BusinessProfile.lite,
      arabicName: 'لايت — نقطة بيع ومخازن',
      arabicDescription:
          'نقطة بيع + مخازن + صناديق + تقارير (ومعها المشتريات) — بدون طاولات '
          'أو كيتشن أو فروع أو موظفين أو محاسبة موسّعة.',
    ),
    BusinessProfileMeta.build(
      profile: BusinessProfile.restaurant,
      arabicName: 'مطعم',
      arabicDescription:
          'نقطة بيع بالطاولات والكيتشن والتوصيل والحجوزات — بدون باركود أو ميزان.',
    ),
    BusinessProfileMeta.build(
      profile: BusinessProfile.cafe,
      arabicName: 'كافيه',
      arabicDescription:
          'مثل المطعم مع التعديلات (Modifiers) — قهوة وحلويات وتوصيل.',
    ),
    BusinessProfileMeta.build(
      profile: BusinessProfile.supermarket,
      arabicName: 'تجزئة / سوبر ماركت',
      arabicDescription:
          'نقطة بيع بالباركود والميزان والعروض — بدون طاولات أو كيتشن.',
    ),
    BusinessProfileMeta.build(
      profile: BusinessProfile.supermarketPro,
      arabicName: 'سوبر ماركت Pro',
      arabicDescription: 'إضافة إدارة الموظفين (HR) على ملف السوبر ماركت.',
    ),
    BusinessProfileMeta.build(
      profile: BusinessProfile.supermarketPlus,
      arabicName: 'سوبر ماركت Plus',
      arabicDescription:
          'سوبر ماركت + خدمات مطعم/كافيه (طاولات، كيتشن، توصيل).',
    ),
    BusinessProfileMeta.build(
      profile: BusinessProfile.commercial,
      arabicName: 'تجارى / جملة وتوزيع',
      arabicDescription:
          'فواتير B2B + فروع + HR + تصنيع + أوراق تجارية — بدون نقطة بيع.',
    ),
    BusinessProfileMeta.build(
      profile: BusinessProfile.unified,
      arabicName: 'موحّد — كل الميزات',
      arabicDescription:
          'ملف شامل يُشغّل كل الميزات، مناسب للعملاء المركبين أو البيئات التجريبية.',
    ),
  ];

  /// Lookup by profile. Returns a stub meta for the catch-all case if
  /// someone adds a new enum value and forgets to register it (defensive).
  static BusinessProfileMeta metaFor(BusinessProfile p) {
    for (final m in _all) {
      if (m.profile == p) return m;
    }
    return BusinessProfileMeta.build(
      profile: p,
      arabicName: p.name,
      arabicDescription: 'ملف غير مسجّل فى الدليل.',
    );
  }

  /// All profiles in the order they should appear in the wizard dropdown.
  static List<BusinessProfileMeta> all() => List.unmodifiable(_all);
}
