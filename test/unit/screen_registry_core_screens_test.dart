// نطاقاتُ الشاشات — **حارسُ الشاشة الغائبة من القائمة الجانبية**.
//
// ═══ 🔴 بلاغُ المالك 2026-08-22 ═══
//
// «شاشةُ إغلاق الوردية لا تظهر في القائمة الجانبية». وأثبته السجلُّ بلا
// تخمين: `allowedIndices=[0…45, 60]` — الرقمُ ٦٠ (`regions`) حاضرٌ و٥٦
// (`shiftClose`) غائب، وهما جارَان في `unified`.
//
// والسببُ: `shiftClose` كانت في **ستّة** نطاقاتٍ وساقطةً من `unified` وحدَها.
// ولا يكفي وجودُها في `screenPermissionMap`: حلقةُ `userAllowedScreensProvider`
// تُرشِّح بنطاق الملفّ **قبل** فحصِ الصلاحية، فما ليس في النطاق يسقط حتى مع
// تجاوزِ مدير النظام.
//
// ⚠️ **ولماذا لا يُقاس «unified ⊇ lite»:** قِيست الخاصّيّةُ قبل كتابة الحارس
// فسقطت — `lite` تحمل `users` و`fieldAudit` ولا تحملهما `unified`، وذلك
// **قرارٌ قائمٌ** لا سهو. فحارسٌ يفرض الاحتواءَ كان سيَحمرّ على تصميمٍ مقصود.
// والمقيسُ هنا أضيقُ وأصدق: شاشاتٌ جوهريّةٌ بعينها لا يجوز أن تغيب.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/navigation/screen_registry.dart';

void main() {
  /// النطاقاتُ التي تُشحن، باسمها كما تُقرأ في الفشل.
  const profiles = <String, List<ScreenId>>{
    'restaurant': ScreenRegistry.restaurant,
    'cafe': ScreenRegistry.cafe,
    'supermarket': ScreenRegistry.supermarket,
    'supermarketPro': ScreenRegistry.supermarketPro,
    'supermarketPlus': ScreenRegistry.supermarketPlus,
    'commercial': ScreenRegistry.commercial,
    'unified': ScreenRegistry.unified,
    'lite': ScreenRegistry.lite,
    'litePicpos': ScreenRegistry.litePicpos,
    'restaurantPicpos': ScreenRegistry.restaurantPicpos,
  };

  /// شاشاتٌ **لا يعمل النظامُ بدونها** — غيابُها من أيّ نطاقٍ عطبٌ لا خيار.
  ///
  /// وكلُّ واحدةٍ لها سببٌ يُقال، لا «احتياطاً»:
  ///   • `shiftClose` — بلا إغلاقِ ورديّةٍ لا يُقفل درجٌ ولا تُسلَّم عهدة.
  ///   • `treasury` — الصناديقُ والأرصدة.
  ///   • `settings` — بلا إعداداتٍ لا يُضبَط شيءٌ ولا يُخرَج من خطأ.
  ///
  /// ⚠️ **و`pos` ليست منها — قِيست فسقطت.** نطاقُ `commercial` لا يحملها
  /// عمداً: تدفّقُ جملةٍ يقوده **فاتورةُ مبيعاتٍ** لا درجُ كاشير. فحارسٌ
  /// يفرضها كان سيَحمرّ على قرارٍ صحيح — وهو نفسُ سببِ إسقاطِ قياسِ
  /// «unified ⊇ lite» أعلاه. **قِس قبل أن تحرس.**
  const core = <ScreenId>[
    ScreenId.shiftClose,
    ScreenId.treasury,
    ScreenId.settings,
  ];

  group('الشاشاتُ الجوهريّةُ في كلّ نطاق', () {
    profiles.forEach((name, screens) {
      for (final id in core) {
        test('$name يحمل ${id.name}', () {
          expect(
            screens,
            contains(id),
            reason: 'نطاقُ «$name» بلا ${id.name} — وحلقةُ '
                '`userAllowedScreensProvider` تُرشِّح بالنطاق **قبل** '
                'الصلاحية، فتغيب الشاشةُ حتى عن مدير النظام',
          );
        });
      }
    });
  });

  group('سلامةُ النطاقات', () {
    // نطاقٌ فارغٌ يوقع المستخدمَ في واجهةٍ بلا مخرج.
    profiles.forEach((name, screens) {
      test('$name ليس فارغاً', () {
        expect(screens, isNotEmpty);
      });
    });

    // ⚠️ تكرارُ شاشةٍ في نطاقٍ يعني مدخلَين في القائمة الجانبية لنفس الشاشة.
    profiles.forEach((name, screens) {
      test('$name بلا تكرار', () {
        expect(screens.toSet().length, screens.length,
            reason: 'شاشةٌ مكرَّرةٌ تُنتج مدخلَين في القائمة');
      });
    });

    // `restaurantPicpos` إضافةٌ على `restaurant` لا استبدال — عقدٌ مكتوبٌ في
    // تعليقها، ويُقاس كي لا يُكسَر بإعادةِ كتابةِ القائمة يدوياً.
    test('restaurantPicpos يحتوي restaurant كاملةً ويزيد الميزان', () {
      expect(ScreenRegistry.restaurantPicpos,
          containsAll(ScreenRegistry.restaurant));
      expect(ScreenRegistry.restaurantPicpos, contains(ScreenId.scalePlu));
    });

    test('litePicpos يحتوي lite كاملةً ويزيد الميزان', () {
      expect(ScreenRegistry.litePicpos, containsAll(ScreenRegistry.lite));
      expect(ScreenRegistry.litePicpos, contains(ScreenId.scalePlu));
    });
  });
}
