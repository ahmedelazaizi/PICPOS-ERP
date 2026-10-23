// شاشةُ ميزان التسعير PLU يجب أن تكون قابلةً للوصول في **كلّ** تشكيلةِ
// PicPos — لا في بعضها.
//
// ═══ العطبُ الميدانيّ ═══
//
// بلاغُ المالك 2026-08-22: «شاشةُ ميزان التسعير PLU لا تظهر، وبالتالي مديرُ
// PLU كذلك». والقياسُ على التنصيبة الحيّة:
// `settings.business_profile = restaurant`، و`restaurant` كانت **التشكيلةَ
// الوحيدةَ** الخاليةَ من [ScreenId.scalePlu] من بين السبع.
//
// وكلُّ ما عداها كان سليماً وفُحص قبل التعديل: صفُّ الصلاحية موجود، والدورُ
// يملكها، ومدخلُ التنقّل موجود، والبانيةُ موصولة، والفهارسُ متطابقة.
//
// ═══ ولماذا الاختبارُ على الثوابت المُسمّاة لا على `forProfile` ═══
//
// `Brand.isPicPos` **ثابتُ ترجمةٍ** افتراضُه `uralcash`، فالبوّابةُ كلُّها
// تُشغَّل على فرع UralCash ولن تدخل فرعَ PicPos في `forProfile` أبداً.
// فحصُ `forProfile` هنا كان سيمرّ أخضرَ وهو لا يقيس شيئاً — وهي نفسُ
// المصيدةِ المكتوبةِ فوق `ScreenRegistry.litePicpos`. فتُقاس الثوابتُ
// المُسمّاةُ مباشرةً.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';
import 'package:picpos_erp/core/navigation/screen_registry.dart';

void main() {
  group('كلُّ تشكيلاتِ PicPos تصل إلى شاشة الميزان', () {
    // الخريطةُ صريحةٌ: أيُّ تشكيلةٍ تُضاف مستقبلاً بلا ميزانٍ يجب أن تُضاف
    // هنا عمداً — لا أن تمرَّ صامتة.
    final profiles = <String, List<ScreenId>>{
      'supermarket': ScreenRegistry.supermarket,
      'supermarketPro': ScreenRegistry.supermarketPro,
      'supermarketPlus': ScreenRegistry.supermarketPlus,
      'commercial': ScreenRegistry.commercial,
      'unified': ScreenRegistry.unified,
      'litePicpos': ScreenRegistry.litePicpos,
      'restaurantPicpos': ScreenRegistry.restaurantPicpos,
    };

    for (final entry in profiles.entries) {
      test('${entry.key} تحمل ScreenId.scalePlu', () {
        expect(
          entry.value.contains(ScreenId.scalePlu),
          isTrue,
          reason:
              'تشكيلةُ ${entry.key} بلا شاشة الميزان — وهو العطبُ الذي وقع على '
              '`restaurant` وأخفى الشاشةَ عن تنصيبةٍ حيّة',
        );
      });
    }
  });

  group('عقدُ عدم المساس بـUralCash', () {
    // قرارُ المالك 2026-08-22: لا تُشارَك تعديلاتُ PicPos مع UralCash.
    // فتشكيلاتُ UralCash الأساسيّةُ تبقى كما هي، والإضافةُ في ثابتٍ منفصل.
    test('`restaurant` الأصليّةُ تبقى بلا شاشة الميزان', () {
      expect(ScreenRegistry.restaurant.contains(ScreenId.scalePlu), isFalse);
    });

    test('`lite` الأصليّةُ تبقى بلا شاشة الميزان', () {
      expect(ScreenRegistry.lite.contains(ScreenId.scalePlu), isFalse);
    });

    test('نسخةُ PicPos إضافةٌ لا استبدال — تحوي كلَّ شاشات الأصل', () {
      for (final s in ScreenRegistry.restaurant) {
        expect(ScreenRegistry.restaurantPicpos.contains(s), isTrue,
            reason: 'شاشةُ $s سقطت من نسخة PicPos');
      }
      expect(
        ScreenRegistry.restaurantPicpos.length,
        ScreenRegistry.restaurant.length + 1,
        reason: 'الإضافةُ شاشةٌ واحدةٌ بالضبط',
      );
    });

    test('`cafe` اسمٌ آخرُ لـ`restaurant` فيتبعها', () {
      expect(ScreenRegistry.cafe, same(ScreenRegistry.restaurant));
    });
  });

  group('الجسرُ بين دليلَي الشاشات', () {
    // لو انفصل رقمُ `ScreenId` عن رقم `AppScreen` لاختفت الشاشةُ من التنقّل
    // بلا أيّ خطأ — فالمطابقةُ تُقاس.
    test('scalePlu وpluManager اسمان لنفس الفهرس', () {
      expect(ScreenId.scalePlu.navigationIndex,
          ScreenId.pluManager.navigationIndex);
    });

    test('fromIndex ترجع scalePlu لفهرسها', () {
      expect(ScreenId.fromIndex(ScreenId.scalePlu.navigationIndex),
          ScreenId.scalePlu);
    });
  });
}
