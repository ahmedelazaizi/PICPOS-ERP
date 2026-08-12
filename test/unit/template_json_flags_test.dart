// أعلامُ إعدادات جدول الأصناف تُقرأ متسامحةً — وقيمةٌ واحدةٌ شاذّةٌ لا
// تُسقط بقيّةَ الإعدادات.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// إعداداتُ الجدول تُخزَّن JSON في `columnWidths`: عروضُ الأعمدة أرقاماً،
// ومعها أعلامٌ (`_showHeader` · `_headerBold` · `_bodyBold`) ورقمُ
// `_decimalPlaces`. وثلاثةُ قرّاءٍ يفكّونها — المصمّم والمعاينة والطابعة —
// وكلُّهم كان يكتب `value as bool?`.
//
// وهذه رميةٌ لا قراءة: قيمةٌ مخزَّنةٌ `1` أو `"true"` (وهو ما يحدث حين
// تمرّ الإعداداتُ بمزامنةٍ أو تصديرٍ يفقد النوع) ترمي `TypeError`. وفي
// المعاينة والطابعة الـ`try` يلفّ **الحلقةَ كلَّها**، فتُبتلع الرميةُ
// وتضيع معها **عروضُ الأعمدة والدقّةُ وكلُّ الأعلام** دفعةً واحدة —
// والمستخدمُ يرى تصميمَه مسطَّحاً بلا رسالةِ خطأٍ واحدة.
//
// نفسُ فئة عطب الصباح (`double` تُقرأ `bool?` في شاشة الإعدادات) — وهي
// الثالثةُ في هذا المستودع، فالعلاجُ مِقبضٌ واحدٌ لا رقعةٌ ثالثة.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/utils/template_json_flags.dart';

void main() {
  group('readJsonFlag — متسامحةٌ مع ما يصل فعلاً', () {
    test('المنطقيُّ الصريح يُقرأ كما هو', () {
      expect(readJsonFlag(true, defaultValue: false), isTrue);
      expect(readJsonFlag(false, defaultValue: true), isFalse);
    });

    test('الأرقام: صفرٌ كاذبٌ وما عداه صادق', () {
      expect(readJsonFlag(1, defaultValue: false), isTrue);
      expect(readJsonFlag(1.0, defaultValue: false), isTrue);
      expect(readJsonFlag(0, defaultValue: true), isFalse);
      expect(readJsonFlag(0.0, defaultValue: true), isFalse);
    });

    test('النصوص المعروفة', () {
      expect(readJsonFlag('true', defaultValue: false), isTrue);
      expect(readJsonFlag('false', defaultValue: true), isFalse);
      expect(readJsonFlag('1', defaultValue: false), isTrue);
      expect(readJsonFlag('0', defaultValue: true), isFalse);
    });

    test('الغائبُ والمجهولُ يرجعان للافتراضي — لا يرميان', () {
      expect(readJsonFlag(null, defaultValue: true), isTrue);
      expect(readJsonFlag(null, defaultValue: false), isFalse);
      expect(readJsonFlag(const {}, defaultValue: true), isTrue);
      expect(readJsonFlag('ربما', defaultValue: false), isFalse);
    });
  });

  group('parseTableFlags — عزلُ المفاتيح', () {
    test('قيمةٌ شاذّةٌ لا تُسقط جارتَها', () {
      final f = parseTableFlags(
        '{"product":3.5,"_showHeader":1,"_decimalPlaces":"ليس رقماً",'
        '"_headerBold":false,"quantity":2.0}',
      );
      // العرضان سليمان رغم مفتاحٍ فاسدٍ بينهما.
      expect(f.columnWidths['product'], 3.5);
      expect(f.columnWidths['quantity'], 2.0);
      // والعلمُ المخزَّن رقماً يُقرأ صحيحاً.
      expect(f.showHeader, isTrue);
      expect(f.headerBold, isFalse);
      // والفاسدُ وحدَه يسقط للافتراضي.
      expect(f.decimalPlaces, isNull);
    });

    test('JSON فاسدٌ كلياً ⇒ لا شيءَ ولا رمية', () {
      final f = parseTableFlags('{ليس JSON');
      expect(f.columnWidths, isEmpty);
      expect(f.showHeader, isNull);
    });

    test('فارغٌ أو null ⇒ لا شيء', () {
      expect(parseTableFlags(null).columnWidths, isEmpty);
      expect(parseTableFlags('').showHeader, isNull);
    });

    test('الأعلامُ لا تتسرّب إلى عروض الأعمدة', () {
      final f = parseTableFlags('{"_showHeader":1,"total":1.5}');
      expect(f.columnWidths.keys, ['total']);
    });
  });
}
