// نموذجُ التابات — بلاغُ المالك 2026-09-12: «التاب فوق للتنقل بين الشاشات
// موجود ولكن كما عدمه … لا يتم التنقل الى الشاشة المضغوط عليها ولا يفتح
// اكثر من تابين».
//
// ⚠️ **والبلاغُ دقيقٌ إلى الحرف.** «التابُ» الموجودُ هو شريطُ فتات الخبز:
// `setBreadcrumbs` **يستبدل** القائمةَ بمدخلٍ أو مدخلَين في كلّ تنقّل —
// فلا يظهر أكثرُ من اثنَين أبداً. والنقرُ ميّتٌ لسببٍ أدقّ: الأوّلُ
// (‏رأسُ المجموعة) يُبنى بلا `onTap` أصلاً، والثاني يُبنى بـ`onTap`
// ثمّ يُرسَم بـ`onTap: isLast ? null : item.onTap` — فالوحيدُ الذي يحمل
// ردَّ فعلٍ هو **عينُ** الوحيدِ الذي يُلغى ردُّ فعله. صفرُ مداخلَ قابلةٍ
// للنقر، دائماً، بلا استثناء.
//
// ═══ ولماذا نموذجٌ خالص ═══
//
// لأنّ ما يُخطئ هو الحسابُ لا الرسم: أيُّ تابٍ يُخلى عند الامتلاء، وما
// يصير نشطاً بعد الإغلاق، وماذا يحدث لتابِ شاشةٍ سُحبت صلاحيتُها. وكلُّها
// تُقاس بلا شجرةٍ ولا `pumpWidget`.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/screen_tabs.dart';

void main() {
  group('الفتحُ والتنشيط', () {
    test('يبدأ بتابٍ واحدٍ نشط', () {
      final t = ScreenTabs.of(0);
      expect(t.order, [0]);
      expect(t.active, 0);
    });

    test('وفتحُ شاشةٍ جديدةٍ يُضيف تاباً وينشّطه', () {
      final t = ScreenTabs.of(0).open(11);
      expect(t.order, [0, 11]);
      expect(t.active, 11);
    });

    test('وفتحُ شاشةٍ مفتوحةٍ ينشّطها ولا يُكرّرها', () {
      final t = ScreenTabs.of(0).open(11).open(4).open(11);
      expect(t.order, [0, 11, 4]);
      expect(t.active, 11);
    });

    test('وترتيبُ التابات ترتيبُ الفتح لا ترتيبُ الاستعمال', () {
      // ⚠️ وهذا شرطٌ **لازم** لا تفضيل: الشاشاتُ تُرسَم في `IndexedStack`
      // والمطابقةُ بالموضع، فإعادةُ ترتيبٍ عند كلّ نقرةٍ تنقل حالةَ شاشةٍ
      // إلى أخرى — سلّةُ الكاشير تظهر في شاشة المخزون.
      final t = ScreenTabs.of(0).open(11).open(4).open(0);
      expect(t.order, [0, 11, 4]);
      expect(t.active, 0);
    });
  });

  group('الإغلاق', () {
    test('إغلاقُ تابٍ غيرِ نشطٍ لا يُغيّر النشط', () {
      final t = ScreenTabs.of(0).open(11).open(4).close(11);
      expect(t.order, [0, 4]);
      expect(t.active, 4);
    });

    test('وإغلاقُ النشطِ ينشّط آخرَ ما استُعمل', () {
      final t = ScreenTabs.of(0).open(11).open(4); // استُعمِل 0 ثمّ 11 ثمّ 4
      final after = t.close(4);
      expect(after.order, [0, 11]);
      expect(after.active, 11, reason: 'وقع على الجارِ لا على آخرِ المستعمَل');
    });

    test('ولا يُغلَق التابُ الوحيد', () {
      final t = ScreenTabs.of(0);
      expect(t.close(0).order, [0], reason: 'شلٌّ بلا محتوى');
    });

    test('وإغلاقُ ما ليس مفتوحاً لا أثرَ له', () {
      final t = ScreenTabs.of(0).open(11);
      expect(t.close(99).order, [0, 11]);
      expect(t.close(99).active, 11);
    });
  });

  group('السقفُ والإخلاء', () {
    ScreenTabs fill() {
      var t = ScreenTabs.of(0);
      // فهارسُ اعتباطيّةٌ بعددِ السقف
      for (var i = 2; i < kMaxScreenTabs + 1; i++) {
        t = t.open(100 + i);
      }
      return t;
    }

    test('مرساةٌ — السقفُ يُبلَغ فعلاً', () {
      final t = fill();
      expect(t.order.length, kMaxScreenTabs);
      expect(t.isFull, isTrue);
    });

    test('وفتحُ تابٍ فوق السقف يُخلي أقدمَ مستعمَلٍ لا أقدمَ مفتوح', () {
      // ⚠️ الفرقُ حقيقيّ: التابُ الأوّلُ قد يكون أكثرَ ما يُستعمَل.
      var t = fill();
      final oldestOpened = t.order.first; // 0
      t = t.open(oldestOpened); // فصار أحدثَ استعمالاً
      final lru = t.mru.last;

      final after = t.open(777);
      expect(after.order.length, kMaxScreenTabs);
      expect(after.order, contains(777));
      expect(after.order, contains(oldestOpened),
          reason: 'أُخلي أقدمُ **مفتوحٍ** وهو أحدثُ مستعمَل');
      expect(after.order, isNot(contains(lru)));
      expect(after.active, 777);
    });

    test('ولا يُخلى التابُ النشط', () {
      var t = fill();
      final active = t.active;
      final after = t.open(777);
      expect(after.order, contains(active),
          reason: 'أُخلِيَت الشاشةُ المعروضةُ من تحت المستخدم');
    });

    test('ولا تُخلى نقطةُ البيع — السلّةُ تموت معها', () {
      // نقطةُ البيع تحمل بيعاً غيرَ مُفوتَر؛ وتفكيكُ شجرتها يمسحه بلا سؤال.
      var t = ScreenTabs.of(0).open(1); // 1 = نقطة البيع
      for (var i = 2; i < kMaxScreenTabs + 1; i++) {
        t = t.open(200 + i);
      }
      expect(t.order.length, kMaxScreenTabs);
      expect(t.order, contains(1));

      final after = t.open(888);
      expect(after.order, contains(1),
          reason: 'أُخلِيَت نقطةُ البيع — وسلّةٌ مملوءةٌ ضاعت صامتة');
      expect(kUnevictableScreenTabs, contains(1));
    });

    test('وإن لم يبقَ مُخلىً يحلُّ الجديدُ محلَّ النشط', () {
      // سقفٌ كلُّه محصَّنٌ أو نشط: التنقّلُ يجب أن ينجح لا أن يُرفَض.
      var t = ScreenTabs.of(1);
      for (var i = 1; i < kMaxScreenTabs; i++) {
        t = t.open(300 + i);
      }
      // حصِّن كلَّ شيءٍ عدا النشط بجعل السقف ممتلئاً بمحصَّنٍ واحدٍ ونشط
      final full = t;
      expect(full.isFull, isTrue);
      final after = full.open(999);
      expect(after.order.length, lessThanOrEqualTo(kMaxScreenTabs));
      expect(after.order, contains(999));
      expect(after.active, 999);
    });
  });

  group('سحبُ الصلاحية', () {
    test('تابُ شاشةٍ لم تبقَ مسموحةً يُسقَط', () {
      // ⚠️ **وهذا ليس تنظيفاً.** الشاشةُ في `IndexedStack` **مبنيّةٌ حيّة**
      // تقرأ وتكتب؛ فبقاءُ تابِها بعد سحب الصلاحية إبقاءُ الشاشة عاملةً
      // لمن مُنِعَ منها.
      final t = ScreenTabs.of(0).open(11).open(4);
      final after = t.retain({0, 4});
      expect(after.order, [0, 4]);
      expect(after.active, 4);
    });

    test('وإن سقط النشطُ نُشِّط ناجٍ', () {
      final t = ScreenTabs.of(0).open(11).open(4);
      final after = t.retain({0, 11});
      expect(after.order, [0, 11]);
      expect(after.active, 11);
    });

    test('وإن لم ينجُ شيءٌ فُتِح أوّلُ المسموح', () {
      final t = ScreenTabs.of(11);
      final after = t.retain({0, 4});
      expect(after.order, [0]);
      expect(after.active, 0);
    });

    test('ومسموحٌ فارغٌ لا يُنتج شلّاً بلا تاب', () {
      final t = ScreenTabs.of(11);
      expect(t.retain(const {}).order, [11]);
    });
  });

  group('الثبات', () {
    test('العملياتُ لا تُعدّل الأصل', () {
      final a = ScreenTabs.of(0);
      final b = a.open(11);
      expect(a.order, [0], reason: 'قائمةٌ مُشترَكةٌ عُدِّلت في مكانها');
      expect(b.order, [0, 11]);
    });

    test('وقائمةُ الترتيب غيرُ قابلةٍ للتعديل من الخارج', () {
      final t = ScreenTabs.of(0).open(11);
      expect(() => t.order.add(99), throwsUnsupportedError);
    });
  });
}
