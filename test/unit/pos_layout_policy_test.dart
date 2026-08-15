// ═══════════════════════════════════════════════════════════════════════════
// §٢ — تخطيطُ رأس لوحة الأصناف مقيَّدٌ بالعلامة، ومقيسٌ تحت النكهة الافتراضية
// ═══════════════════════════════════════════════════════════════════════════
//
// طلبُ المالك: «تصغيرُ حجم خانة الباركود قليلاً ورفعُ خانة البحث عن المنتج
// بجانب الباركود وتكون متناسقة» — **لـPicPos وحدَه** (قرارُه الصريح، والملفّان
// مشتركان مع UralCash).
//
// ── ولماذا سياسةٌ مُسمّاةٌ لا `if (Brand.isPicPos)` ─────────────────────────
// `Brand.isPicPos` ثابتُ ترجمة، والبوابةُ كلُّها تشتغل على الافتراضيّ
// `uralcash`. فأيُّ فرعٍ مطويٍّ خلفه **لا يقيسه اختبارٌ واحد**: يمرّ أخضرَ
// وهو ميّت. وهذا الملفُّ يقيس الوجهتَين معاً لأن العلامةَ تُمرَّر معاملاً
// صريحاً — نفسُ علاج `ScreenRegistry.litePicpos` و`FeaturePolicy.litePicpos`.

import 'package:flutter/widgets.dart' show FontWeight;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/config/pos_layout_policy.dart';

void main() {
  group('الوجهتان مقيستان بالاسم', () {
    test('PicPos يرفع البحثَ بجانب الباركود', () {
      expect(PosLayoutPolicy.picpos.searchBesideBarcode, isTrue);
    });

    test('والافتراضيُّ يُبقيه داخلَ الشبكة كما كان', () {
      expect(PosLayoutPolicy.stacked.searchBesideBarcode, isFalse);
    });

    test('وخاناتُ البحث أقصرُ في وجهة PicPos', () {
      // بلاغُ المالك بعد الاختبار الميدانيّ: «تقليل ارتفاع خانتى البحث قليلاً
      // لم يتم كما اتفقنا». والطلبُ الأصليُّ «تصغيرُ حجم خانة الباركود» فُهم
      // عرضاً، ومقصودُه الارتفاع. فالثلاثةُ تنزل معاً — وإلا بقي الصفُّ
      // بارتفاعه لأن أطولَ عنصرٍ يحكمه.
      expect(
        PosLayoutPolicy.picpos.barcodeContentPaddingV,
        lessThan(PosLayoutPolicy.stacked.barcodeContentPaddingV),
      );
      expect(
        PosLayoutPolicy.picpos.barcodeRowPaddingV,
        lessThan(PosLayoutPolicy.stacked.barcodeRowPaddingV),
      );
      expect(
        PosLayoutPolicy.picpos.searchFieldHeight,
        lessThan(PosLayoutPolicy.stacked.searchFieldHeight),
      );
    });

    test('واسمُ التصنيف أثقلُ في وجهة PicPos', () {
      expect(
        PosLayoutPolicy.picpos.categoryLabelWeight.index,
        greaterThan(PosLayoutPolicy.stacked.categoryLabelWeight.index),
      );
    });

    test('والوجهةُ الافتراضيةُ تحمل القيمَ الحاليةَ حرفاً بحرف', () {
      // ⚠️ الضابطُ الحاكم: لا يتسرّب قرارُ فوركٍ إلى الآخر. لو تغيّر أيٌّ من
      // هذه الأرقام فقد تغيّر شكلُ UralCash بلا أن يطلبه أحد.
      expect(PosLayoutPolicy.stacked.searchFieldHeight, 48);
      expect(PosLayoutPolicy.stacked.barcodeContentPaddingV, 16);
      expect(PosLayoutPolicy.stacked.barcodeRowPaddingV, 12);
      expect(PosLayoutPolicy.stacked.categoryLabelWeight, FontWeight.w600);
    });

    test('الباركودُ أصغرُ من البحث في وجهة PicPos', () {
      // «تصغيرُ خانة الباركود قليلاً» — والقياسُ نسبةٌ لا بكسل، فالصفُّ يتمدّد
      // بعرض اللوحة.
      expect(
        PosLayoutPolicy.picpos.barcodeFlex,
        lessThan(PosLayoutPolicy.picpos.searchFlex),
      );
    });
  });

  group('الاختيارُ بالعلامة', () {
    test('picpos → وجهةُ PicPos', () {
      expect(PosLayoutPolicy.forBrand('picpos'), same(PosLayoutPolicy.picpos));
    });

    test('uralcash → الوجهةُ الافتراضية', () {
      expect(
        PosLayoutPolicy.forBrand('uralcash'),
        same(PosLayoutPolicy.stacked),
      );
    });

    test('وأيُّ علامةٍ مجهولةٍ تقع على الافتراضيّ لا على PicPos', () {
      // ⚠️ الاتّجاهُ مقصود: علامةٌ جديدةٌ ترث السلوكَ القائمَ لا سلوكَ فورك
      // بعينه. `Brand.isKnown` يحرس المعرّفاتِ نفسَها في مكانٍ آخر.
      expect(PosLayoutPolicy.forBrand('nope'), same(PosLayoutPolicy.stacked));
    });
  });
}
