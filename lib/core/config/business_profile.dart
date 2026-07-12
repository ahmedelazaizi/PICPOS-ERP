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
      };

  String get displayName => switch (this) {
        BusinessProfile.unified => 'النظام الموحد',
        BusinessProfile.restaurant => 'المطاعم',
        BusinessProfile.cafe => 'الكافيهات',
        BusinessProfile.supermarket => 'السوبرماركت',
        BusinessProfile.supermarketPro => 'السوبرماركت برو',
        BusinessProfile.supermarketPlus => 'السوبرماركت بلس',
        BusinessProfile.commercial => 'التجاري',
      };

  String get defaultBusinessType => switch (this) {
        BusinessProfile.unified => 'retail',
        BusinessProfile.restaurant => 'restaurant',
        BusinessProfile.cafe => 'cafe',
        BusinessProfile.supermarket => 'supermarket',
        BusinessProfile.supermarketPro => 'supermarket',
        BusinessProfile.supermarketPlus => 'supermarket',
        BusinessProfile.commercial => 'commercial',
      };
}
