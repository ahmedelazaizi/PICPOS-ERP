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
