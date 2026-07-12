/// Distribution flavor used for packaging, branding, and default profile
/// selection.
enum AppFlavor {
  unified,
  restaurant,
  cafe,
  supermarket,
  supermarketPro,
  supermarketPlus,
  commercial,
}

extension AppFlavorX on AppFlavor {
  String get code => switch (this) {
        AppFlavor.unified => 'unified',
        AppFlavor.restaurant => 'restaurant',
        AppFlavor.cafe => 'cafe',
        AppFlavor.supermarket => 'supermarket',
        AppFlavor.supermarketPro => 'supermarket_pro',
        AppFlavor.supermarketPlus => 'supermarket_plus',
        AppFlavor.commercial => 'commercial',
      };

  String get appName => switch (this) {
        AppFlavor.unified => 'UralCash',
        AppFlavor.restaurant => 'UralCash Restaurant',
        AppFlavor.cafe => 'UralCash Cafe',
        AppFlavor.supermarket => 'UralCash Market',
        AppFlavor.supermarketPro => 'UralCash Market Pro',
        AppFlavor.supermarketPlus => 'UralCash Market Plus',
        AppFlavor.commercial => 'UralCash Commercial',
      };

  String get appNameAr => switch (this) {
        AppFlavor.unified => 'يورال كاش',
        AppFlavor.restaurant => 'يورال كاش - المطاعم',
        AppFlavor.cafe => 'يورال كاش - الكافيهات',
        AppFlavor.supermarket => 'يورال كاش - السوبرماركت',
        AppFlavor.supermarketPro => 'يورال كاش - السوبرماركت برو',
        AppFlavor.supermarketPlus => 'يورال كاش - السوبرماركت بلس',
        AppFlavor.commercial => 'يورال كاش - التجاري',
      };
}
