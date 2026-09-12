// test/unit/nav_search_test.dart
//
// بحثُ الشريط الجانبيّ — «خانة بحث عن الشاشات او ما داخلها» (‏أمرُ المالك
// 2026-09-12).
//
// ⚠️ **ولماذا تسويةٌ عربيّةٌ لا `contains` مباشرة**: تسمياتُ الشاشات في
// `kAllNavItemDefs` مكتوبةٌ كما كُتبت — «الأصناف» بهمزةٍ و«الاصناف» بدونها
// في نفس الملفّ (‏رأسُ المجموعة بلا همزةٍ والمدخلُ بها). فمن يكتب ما يراه
// على الرأس لا يجد المدخل. ونفسُه في «ى/ي» و«ة/ه» — وكلُّها محارفُ مختلفةٌ
// بايتاً لا شكلاً.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/domain/models/nav_search.dart';

void main() {
  group('تسويةُ النصّ العربيّ', () {
    test('الهمزاتُ كلُّها ألفٌ واحدة', () {
      for (final v in ['أصناف', 'إصناف', 'آصناف', 'اصناف']) {
        expect(normalizeArabicForSearch(v), 'اصناف', reason: v);
      }
    });

    test('الألفُ المقصورةُ ياءٌ والتاءُ المربوطةُ هاء', () {
      expect(normalizeArabicForSearch('علي'), normalizeArabicForSearch('على'));
      expect(normalizeArabicForSearch('فاتورة'), normalizeArabicForSearch('فاتوره'));
    });

    test('والتشكيلُ والتطويلُ يسقطان', () {
      expect(normalizeArabicForSearch('الفَوَاتِير'), 'الفواتير');
      expect(normalizeArabicForSearch('الفـــواتير'), 'الفواتير');
    });

    test('واللاتينيُّ يُخفَّض', () {
      expect(normalizeArabicForSearch('Dashboard'), 'dashboard');
    });

    test('والمسافاتُ الزائدةُ تُطوى', () {
      expect(normalizeArabicForSearch('  سند   تحويل  '), 'سند تحويل');
    });
  });

  group('مطابقةُ المداخل', () {
    List<NavSearchHit> hits(String q) =>
        searchNavEntries(q, navEntriesFromNavItems(kAllNavItemDefs));

    test('استعلامٌ فارغٌ لا يعطي شيئاً — الشريطُ يعرض مجموعاتِه', () {
      expect(hits(''), isEmpty);
      expect(hits('   '), isEmpty);
    });

    test('يجد المدخلَ بجزءٍ من تسميته', () {
      expect(hits('طاول').map((h) => h.label), contains('الطاولات'));
    });

    test('ويجده بهمزةٍ مخالفةٍ لما كُتب', () {
      // المكتوبُ «الأصناف» بهمزة؛ والمستخدمُ يكتب ما يراه على الرأس.
      final found = hits('الاصناف').map((h) => h.label);
      expect(found, contains('الأصناف'));
    });

    test('ويجده بكلمةٍ **داخله** لا في اسمه', () {
      // «ما داخلها» في أمر المالك: الكاشيرُ ليس اسمَ شاشةٍ وهو داخلَ البيع
      // السريع، والباركودُ داخلَ الأصناف.
      expect(hits('كاشير').map((h) => h.label), contains('البيع السريع'));
      expect(hits('باركود').map((h) => h.label), contains('الأصناف'));
    });

    test('وكلماتُ الاستعلام تتجمّع — كلُّها لازمة', () {
      final both = hits('سند تحويل');
      expect(both.map((h) => h.label), contains('سند تحويل اصناف'));

      // كلمةٌ لا تنتمي للمدخل تُسقطه ولو طابقت الأخرى.
      final none = hits('سند مطبخ');
      expect(none.map((h) => h.label), isNot(contains('سند تحويل اصناف')));
    });

    test('والمطابقةُ في التسمية تسبق المطابقةَ في الكلمات المفتاحيّة', () {
      final found = hits('تقارير');
      expect(found, isNotEmpty);
      expect(found.first.label, contains('التقارير'),
          reason: 'من يكتب «تقارير» يقصد الشاشةَ لا ما يذكرها');
    });

    test('ولا تكرارَ لمدخلٍ طابق باسمه وبكلمته معاً', () {
      final found = hits('مخزون');
      final labels = found.map((h) => h.label).toList();
      expect(labels.toSet(), hasLength(labels.length));
    });

    test('واستعلامٌ لا يطابق شيئاً يعود فارغاً لا بكلِّ شيء', () {
      expect(hits('زقنبوت'), isEmpty);
    });
  });

  group('سلامةُ فهرس الكلمات', () {
    test('كلُّ فهرسٍ في الخريطة له مدخلٌ في القائمة', () {
      final known = {for (final i in kAllNavItemDefs) i.index};
      for (final index in kNavSearchKeywords.keys) {
        expect(known, contains(index),
            reason: 'كلماتٌ مفتاحيّةٌ لفهرسٍ $index بلا مدخل — سطرٌ ميّت');
      }
    });

    test('ولا كلمةَ مفتاحيّةٍ فارغة', () {
      for (final entry in kNavSearchKeywords.entries) {
        for (final w in entry.value) {
          expect(w.trim(), isNotEmpty, reason: 'فراغٌ في ${entry.key}');
        }
      }
    });
  });
}
