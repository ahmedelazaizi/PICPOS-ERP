// PicPos-lite يفتح المطبخَ والإضافات؛ UralCash-lite لا يتغيّر.
//
// ── لماذا ثابتان مُسمّيان لا فرعٌ داخل `fromProfile` وحدَه ──────────────────
// `Brand.isPicPos` ثابتُ ترجمةٍ من `--dart-define=APP_BRAND`، وافتراضُه
// `uralcash`. فالبوابةُ كلُّها تشتغل على فرع UralCash، وفرعُ PicPos ما كان
// ليُقاس أصلاً. نفسُ المسألة حُلَّت في `ScreenRegistry.litePicpos` بثابتٍ
// عامٍّ يُقاس مباشرةً — وهذا الملفُّ يقيسه بنفس النمط
// (`test/widget/picpos_scale_plu_test.dart`).
//
// ── لماذا المطبخُ مع الإضافات معاً ─────────────────────────────────────────
// مقيسٌ من الملفات الشخصية الأربعة التي تفتح المطبخ (restaurant · cafe ·
// supermarketPlus · unified): كلُّها بلا استثناء تفتح `modifiersEnabled`
// معه. و`FeatureDependencyGraph.requires` يفرض `restaurantModifiers →
// posKitchen`، و`implies` يقترح العكس. ففتحُ المطبخ وحدَه كان يترك اقتراحاً
// معلَّقاً في الڤاليديتور، وفتحُ الإضافات وحدَه كان يُشعل قاعدةً صلبة.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/config/brand.dart';
import 'package:ural_erp/core/config/business_profile.dart';
import 'package:ural_erp/core/config/feature_policy.dart';
import 'package:ural_erp/core/config/feature_validator.dart';

void main() {
  test('PicPos-lite يفتح المطبخ والإضافات', () {
    expect(FeaturePolicy.litePicpos.kitchenEnabled, isTrue);
    expect(FeaturePolicy.litePicpos.modifiersEnabled, isTrue);
  });

  test('UralCash-lite لم تتغيّر — المطروحُ لا يُمسّ', () {
    expect(FeaturePolicy.lite.kitchenEnabled, isFalse);
    expect(FeaturePolicy.lite.modifiersEnabled, isFalse);
  });

  test('الفرقُ محصورٌ في العلمَين — لا شيءَ آخرَ انزلق', () {
    expect(
      FeaturePolicy.lite.copyWith(kitchenEnabled: true, modifiersEnabled: true),
      FeaturePolicy.litePicpos,
    );
  });

  test('`fromProfile` تتبع الماركة', () {
    final resolved = FeaturePolicy.fromProfile(BusinessProfile.lite);
    expect(
      resolved,
      Brand.isPicPos ? FeaturePolicy.litePicpos : FeaturePolicy.lite,
    );
    // البوابةُ تشتغل على الافتراضي، فهذا هو الفرعُ المقيس فعلاً هنا.
    expect(Brand.isPicPos, isFalse,
        reason: 'شغّل الملفَّ بلا --dart-define — وإلا فالتأكيدُ التالي مقلوب');
    expect(resolved.kitchenEnabled, isFalse);
  });

  test('litePicpos تمرّ الڤاليديتور بلا قاعدةٍ مطبَّقةٍ ولا رفض', () {
    final result = FeatureValidator.validate(FeaturePolicy.litePicpos, const {});
    expect(result.appliedRules, isEmpty);
    expect(result.rejectedOverrides, isEmpty);
    expect(result.policy, FeaturePolicy.litePicpos);
  });
}
