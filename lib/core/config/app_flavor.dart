import 'brand.dart';

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

  /// الاسم الظاهر = اسم العلامة + لاحقة الـ flavor.
  ///
  /// الاسم نفسه بيجي من [Brand] عشان المنتجات المستقلة (UralCash / PicPos)
  /// تطلع من نفس الكود. لـ `Brand.name == 'UralCash'` الناتج مطابق حرف بحرف
  /// للسلاسل اللي كانت مكتوبة صراحةً هنا — مثبَّت في
  /// `test/unit/brand_isolation_test.dart`.
  String get appName => switch (this) {
        AppFlavor.unified => Brand.name,
        AppFlavor.restaurant => '${Brand.name} Restaurant',
        AppFlavor.cafe => '${Brand.name} Cafe',
        AppFlavor.supermarket => '${Brand.name} Market',
        AppFlavor.supermarketPro => '${Brand.name} Market Pro',
        AppFlavor.supermarketPlus => '${Brand.name} Market Plus',
        AppFlavor.commercial => '${Brand.name} Commercial',
      };

  String get appNameAr => switch (this) {
        AppFlavor.unified => Brand.nameAr,
        AppFlavor.restaurant => '${Brand.nameAr} - المطاعم',
        AppFlavor.cafe => '${Brand.nameAr} - الكافيهات',
        AppFlavor.supermarket => '${Brand.nameAr} - السوبرماركت',
        AppFlavor.supermarketPro => '${Brand.nameAr} - السوبرماركت برو',
        AppFlavor.supermarketPlus => '${Brand.nameAr} - السوبرماركت بلس',
        AppFlavor.commercial => '${Brand.nameAr} - التجاري',
      };
}
