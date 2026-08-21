import 'package:flutter/widgets.dart' show FontWeight;

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
    required this.searchFieldHeight,
    required this.barcodeContentPaddingV,
    required this.barcodeRowPaddingV,
    required this.categoryLabelWeight,
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

  /// ارتفاعُ خانة البحث عن المنتج.
  final double searchFieldHeight;

  /// الحشوُ الرأسيُّ **داخلَ** حقل الباركود.
  ///
  /// هو المتحكّمُ الأكبرُ في ارتفاعه: ١٦ مع خطٍّ قياسُه ١٦ يعطي ~٥٦ بكسل.
  final double barcodeContentPaddingV;

  /// الحشوُ الرأسيُّ للشريط الحاوي للباركود (وللبحث بجانبه).
  final double barcodeRowPaddingV;

  /// وزنُ اسم التصنيف غيرِ المختار تحت أيقونته.
  ///
  /// المختارُ يبقى `w900` في الودجت المشترك — التمييزُ بالوزن مقصود.
  final FontWeight categoryLabelWeight;

  /// الوجهةُ القائمة: الباركودُ سطراً كاملاً، والبحثُ داخلَ شبكة الأصناف.
  ///
  /// قيمُها هي **الحاليةُ حرفاً بحرف** — فلا يتغيّر شيءٌ لغير PicPos.
  static const PosLayoutPolicy stacked = PosLayoutPolicy(
    searchBesideBarcode: false,
    barcodeFlex: 1,
    searchFlex: 1,
    searchFieldHeight: 48,
    barcodeContentPaddingV: 16,
    barcodeRowPaddingV: 12,
    categoryLabelWeight: FontWeight.w600,
  );

  /// وجهةُ PicPos: الاثنان في صفٍّ واحد، والباركودُ أصغر وأقصر.
  ///
  /// ⚠️ والارتفاعُ غيرُ العرض: «تصغيرُ حجم خانة الباركود» في الطلب الأصليّ
  /// فُهم عرضاً أوّلَ مرّة، وصحّحه المالكُ بعد الاختبار الميدانيّ إلى
  /// **الارتفاع** — «تقليل ارتفاع خانتى البحث قليلاً». فالعرضُ نسبةٌ
  /// (‏٥ مقابل ٦) والارتفاعُ يُقلَّل هنا: الحشوُ الداخليُّ ١٦→١٠ والشريطُ
  /// ١٢→٦ والبحثُ ٤٨→٤٤ — أي ~٢٠ بكسلاً أقلَّ للصفّ كلِّه.
  static const PosLayoutPolicy picpos = PosLayoutPolicy(
    searchBesideBarcode: true,
    barcodeFlex: 5,
    searchFlex: 6,
    searchFieldHeight: 44,
    barcodeContentPaddingV: 10,
    barcodeRowPaddingV: 6,
    categoryLabelWeight: FontWeight.w800,
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
