// حارسُ فورك متحكّم بحث الباركود — نسخةُ PicPos.
//
// ═══ لماذا نسخةٌ أصلاً ═══
//
// «سؤال عن الكمية قبل الإضافة» (§٤ `askqty`) يحتاج التدخّلَ **قبل** الإضافة
// للسلّة — أي داخلَ المتحكّم. والأصلُ يخدم شاشةَ UralCash وشاشةَ الطاولات،
// والعملُ على UralCash موقوفٌ منذ 2026-08-22. فالنسخُ قرارُ مالكٍ 2026-08-29:
// «استنساخ الملف ووضعه على picpos ولا يرتبط بـ uralcash».
//
// ═══ ما يحرسه هذا الملفّ ═══
//
// ثلاثةُ أشياءَ يسقط كلٌّ منها بلا صوت:
//
//   ١. **الانفصال**: أن يعود PicPos للمتحكّم المشترك فيرتدَّ تعديلُه على
//      شاشتَين مجمّدتَين — أو أسوأ: أن يعود الأصلُ فيفقد PicPos خطّافَه.
//   ٢. **حارسُ الطبقات**: الأصلُ يستورد `data/database/sync_interceptor.dart`
//      وهو في القائمة البيضاء، والنسخةُ **جديدةٌ** فلا تُسمح لها.
//      (‏نفسُ ما سقط عليه فوركُ حوار إضافة طرف — انظر
//      `picpos_add_party_dialog_fork_test.dart`.)
//   ٣. **الخطّافُ نفسُه**: أن يبقى مسارُ المسح يستشير الكميةَ قبل الإضافة.
//
// ⚠️ **ولماذا يقرأ هذا الحارسُ المصدرَ نصّاً**: البديلُ ضخُّ شاشةِ الكاشير
// كاملةً بقاعدةِ بيانات. والمقصودُ هنا عقدُ الملفّ لا سلوكُ الشاشة — والسلوكُ
// مُقاسٌ في `test/widget`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _forkPath =
    'lib/presentation/pos_picpos/providers/picpos_search_controller.dart';
const _originPath = 'lib/presentation/pos/providers/pos_search_controller.dart';
const _opsPath =
    'lib/presentation/pos_picpos/screens/picpos_pos_operations.dart';

String _read(String path) {
  final f = File(path);
  expect(f.existsSync(), isTrue, reason: 'الملفُّ «$path» اختفى');
  return f.readAsStringSync();
}

/// يزيل تعليقاتِ السطر كي لا يُحسَب ذكرٌ في شرحٍ استعمالاً.
///
/// ⚠️ بلا هذا يمرُّ الحارسُ على ترويسة الفورك نفسِها: هي تذكر مسارَ الأصل
/// شرحاً لسببِ النسخ، وفحصُ «لا يذكر الأصل» كان سيسقط عليها.
String _stripLineComments(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('فوركُ متحكّم بحث الباركود', () {
    test('الأصلُ باقٍ ومستقلٌّ — النسخُ لم يمسّ UralCash', () {
      final origin = _read(_originPath);
      // مرساةٌ: الأصلُ ما زال يحمل رموزَه هو.
      expect(origin, contains('class PosSearchController'),
          reason: 'الأصلُ فقد اسمَه — أُعيدت تسميتُه بدل نسخِه');
      expect(origin, contains('final posSearchControllerProvider'),
          reason: 'مزوِّدُ الأصل اختفى — شاشتا UralCash بلا متحكّم');
      expect(origin, isNot(contains('askQuantity')),
          reason: 'خطّافُ PicPos تسرّب إلى الأصل — وهذا عينُ ما جاء '
              'النسخُ يمنعه');
    });

    test('والنسخةُ لا تشارك الأصلَ رمزاً واحداً', () {
      final fork = _stripLineComments(_read(_forkPath));

      expect(fork, contains('class PicposSearchController'));
      expect(fork, contains('final picposSearchControllerProvider'));
      expect(fork, contains('enum PicposBarcodeSearchErrorKind'),
          reason: 'حتّى التعدادُ مستقلٌّ: نوعٌ مشترَكٌ واحدٌ يكفي ليجعل '
              'تعديلاً في PicPos يرتدَّ على UralCash');

      // ⚠️ الفحصُ على الاستيراد لا على الاسم: `picposSearchControllerProvider`
      // **يحتوي** `posSearchControllerProvider` كسلسلةٍ فرعيّة، ففحصُ الاسم
      // وحدَه كان يقرأ نفسَه مخالفةً ويحمرُّ على نسخةٍ سليمة.
      expect(fork, isNot(contains("pos/providers/pos_search_controller.dart")),
          reason: 'النسخةُ تستورد الأصلَ — فلا انفصال');
    });

    test('وشاشةُ PicPos تستعمل النسخةَ لا الأصل', () {
      final screen = _read('lib/presentation/pos_picpos/screens/'
          'picpos_pos_screen.dart');
      expect(screen, contains("../providers/picpos_search_controller.dart"),
          reason: 'الشاشةُ لا تستورد النسخة');
      expect(
        screen,
        isNot(contains("import '../../pos/providers/pos_search_controller.dart'")),
        reason: 'الشاشةُ ما زالت تستورد الأصلَ المشترك',
      );
    });

    test('ولا تستورد `data/database` — حارسُ الطبقات', () {
      final fork = _stripLineComments(_read(_forkPath));
      expect(fork, isNot(contains('data/database/sync_interceptor.dart')),
          reason: 'ملفُّ عرضٍ **جديدٌ** لا يستورد `data/database`؛ '
              'والأصلُ وحدَه في القائمة البيضاء');
      expect(fork, contains('isClientModeProvider'),
          reason: 'بوّابةُ وضع العميل يجب أن تبقى — عبر المزوِّد. وحذفُها '
              'بدل تحويلِها يفتح كتابةً على عميلٍ لا يملكها');
    });

    test('والخطّافُ موصولٌ: المسحُ يستشير الكميةَ قبل الإضافة', () {
      final fork = _stripLineComments(_read(_forkPath));

      // ⚠️ **المقياسُ الاستشارةُ لا التصريح.** حقلٌ اسمُه `askQuantity` موجودٌ
      // ولا يُنادى يمرُّ على فحصِ `contains('askQuantity')` وحدَه — وهو بعينه
      // «إعدادٌ يُحفَظ ولا يُقرأ».
      expect(fork, contains('Future<double?> _resolveScanQuantity('),
          reason: 'دالّةُ حسمِ الكمية غائبة');
      final consults = '_resolveScanQuantity(product)'.allMatches(fork).length;
      expect(consults, greaterThanOrEqualTo(3),
          reason: 'مواضعُ إضافةِ الصنف العاديّ ثلاثةٌ، واستشارةُ بعضِها '
              'تترك بابَ إضافةٍ بلا سؤال — وهو أسوأُ من ألّا يُوصَّل: '
              'المِزلاجُ يبدو عاملاً ولا يعمل حيث يهمّ. (‏وُجد $consults)');

      // الموزونُ مستثنىً: وزنُه في الباركود، وسؤالُه «كم عدداً» يهدم القراءة.
      expect(fork, contains('if (product.isSoldByWeight) return 1;'),
          reason: 'الصنفُ الموزونُ يجب ألّا يُسأل عن عددٍ');
    });

    test('والشاشةُ تحقن الخطّافَ عند كلّ مسحة', () {
      final ops = _stripLineComments(_read(_opsPath));
      expect(ops, contains('search.askQuantity = _askLineQuantity;'),
          reason: 'الخطّافُ غيرُ محقونٍ — فمسارُ المسح لا يسأل أبداً');
    });
  });
}
