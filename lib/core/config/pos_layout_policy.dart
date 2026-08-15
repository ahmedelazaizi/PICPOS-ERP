import 'brand.dart';

/// تخطيطُ رأس لوحة اختيار الأصناف في شاشة البيع — وجهةٌ لكلّ علامة.
///
/// ── لماذا سياسةٌ مُسمّاةٌ لا `if (Brand.isPicPos)` في موضع الرسم ───────────
/// `Brand.isPicPos` **ثابتُ ترجمة**، والبوابةُ كلُّها تشتغل على الافتراضيّ
/// `uralcash`. فأيُّ فرعٍ مطويٍّ خلفه لا يقيسه اختبارٌ واحد: يمرّ أخضرَ وهو
/// ميّت، ويُكتشف عطبُه في الميدان. وحصرُ الفرع في [forBrand] — دالّةٍ تأخذ
/// العلامةَ **معاملاً صريحاً** — يجعل الوجهتَين مقيستَين معاً تحت أيّ نكهة.
///
/// وهو نفسُ علاج `ScreenRegistry.litePicpos` و`FeaturePolicy.litePicpos`
/// و`withIndustryTablesOverride` في هذا المستودع.
///
/// ── ولماذا التقييدُ بالعلامة أصلاً ─────────────────────────────────────────
/// `pos_product_selection_panel.dart` و`product_grid.dart` يخدمان **العلامتَين**
/// معاً. والمالكُ حسم أن هذا التغييرَ البصريَّ لـPicPos وحدَه، فلا يُمسّ تخطيطُ
/// UralCash.
class PosLayoutPolicy {
  const PosLayoutPolicy({
    required this.searchBesideBarcode,
    required this.barcodeFlex,
    required this.searchFlex,
  });

  /// هل يُرفع حقلُ البحث عن المنتج من داخل شبكة الأصناف إلى صفٍّ واحدٍ مع
  /// خانة الباركود؟
  ///
  /// حين تكون `true` تتوقّف `ProductGrid` عن رسم حقلها الداخليّ — وإلا ظهر
  /// حقلا بحثٍ اثنان يكتبان في نفس الحالة.
  final bool searchBesideBarcode;

  /// نصيبُ خانة الباركود من عرض الصفّ.
  final int barcodeFlex;

  /// نصيبُ خانة البحث من عرض الصفّ.
  ///
  /// أكبرُ من [barcodeFlex] عن قصد: «تصغيرُ خانة الباركود قليلاً» في طلب
  /// المالك. والنسبةُ لا البكسل، فالصفُّ يتمدّد بعرض اللوحة على أيّ شاشة.
  final int searchFlex;

  /// الوجهةُ القائمة: الباركودُ سطراً كاملاً، والبحثُ داخلَ شبكة الأصناف.
  static const PosLayoutPolicy stacked = PosLayoutPolicy(
    searchBesideBarcode: false,
    barcodeFlex: 1,
    searchFlex: 1,
  );

  /// وجهةُ PicPos: الاثنان في صفٍّ واحد، والباركودُ أصغر.
  static const PosLayoutPolicy picpos = PosLayoutPolicy(
    searchBesideBarcode: true,
    barcodeFlex: 5,
    searchFlex: 6,
  );

  /// الفرعُ الوحيدُ على العلامة في هذا الملفّ.
  ///
  /// وعلامةٌ مجهولةٌ تقع على [stacked] لا على [picpos]: علامةٌ جديدةٌ ترث
  /// السلوكَ القائمَ لا سلوكَ فورك بعينه.
  static PosLayoutPolicy forBrand(String brandId) =>
      brandId == 'picpos' ? picpos : stacked;

  /// وجهةُ العلامة المبنيّة — يُستدعى من مواضع الرسم.
  static PosLayoutPolicy get current => forBrand(Brand.id);
}
