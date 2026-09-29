import 'package:ural_erp/core/i18n/tr.dart';
/// Business profile describes the operational behavior of the application.
/// Unlike [AppFlavor], this layer is intended to drive modules and policies.
enum BusinessProfile {
  unified,
  restaurant,
  cafe,
  supermarket,
  supermarketPro,
  supermarketPlus,
  commercial,

  /// أصغر بروفايل: نقطة بيع + مخازن + صناديق + تقارير (والمشتريات اللي
  /// بتغذّي المخزون). البروفايل الافتراضي لـ PicPos — شوف
  /// [Brand.defaultProfileCode].
  ///
  /// **بيخفي شاشات فقط.** نفس الـ binary ونفس الـ schema — «لايت» نطاق
  /// واجهة، مش نسخة أخف.
  lite,
}

extension BusinessProfileX on BusinessProfile {
  String get code => switch (this) {
        BusinessProfile.unified => 'unified',
        BusinessProfile.restaurant => 'restaurant',
        BusinessProfile.cafe => 'cafe',
        BusinessProfile.supermarket => 'supermarket',
        BusinessProfile.supermarketPro => 'supermarket_pro',
        BusinessProfile.supermarketPlus => 'supermarket_plus',
        BusinessProfile.commercial => 'commercial',
        BusinessProfile.lite => 'lite',
      };

  String get displayName => switch (this) {
        BusinessProfile.unified => tr('النظام الموحد'),
        BusinessProfile.restaurant => tr('المطاعم'),
        BusinessProfile.cafe => tr('الكافيهات'),
        BusinessProfile.supermarket => tr('السوبرماركت'),
        BusinessProfile.supermarketPro => tr('السوبرماركت برو'),
        BusinessProfile.supermarketPlus => tr('السوبرماركت بلس'),
        BusinessProfile.commercial => tr('التجاري'),
        BusinessProfile.lite => tr('لايت'),
      };

  String get defaultBusinessType => switch (this) {
        BusinessProfile.unified => 'retail',
        BusinessProfile.restaurant => 'restaurant',
        BusinessProfile.cafe => 'cafe',
        BusinessProfile.supermarket => 'supermarket',
        BusinessProfile.supermarketPro => 'supermarket',
        BusinessProfile.supermarketPlus => 'supermarket',
        BusinessProfile.commercial => 'commercial',
        BusinessProfile.lite => 'retail',
      };
}
