// حارسُ العقد: بحثُ الشريط الجانبيّ يقرأ **المسموحَ** لا القائمةَ الكاملة.
//
// ═══ فئةُ العطب ═══
//
// `kAllNavItemDefs` هي كلُّ شاشةٍ في النظام بلا ترشيح. والمداخلُ التي يعرضها
// الشريطُ فعلاً (`userNavItemsProvider`) نجت من ثلاث بوّابات: نطاقُ الملفّ
// الشخصيّ، وصلاحيّاتُ المستخدم، وسياجُ العلامة (‏`navItemVisibleForBrand`).
//
// فبحثٌ يقرأ القائمةَ الكاملة يعرض للكاشير «دليلَ الحسابات» و«الموظفين»
// و«الفوترة الإلكترونية». وأخفُّ ضررِه إفشاءُ خريطةِ النظام لمن لا يملكها؛
// وأثقلُه أن `onNavigate` تنقّلٌ **بالفهرس** لا يمرّ بحارسِ صلاحيةٍ ثانٍ.
//
// ⚠️ **والإغراءُ حقيقيٌّ لا نظريّ**: أوّلُ ما يخطر لمن يجد البحثَ لا يعطي
// نتيجةً أن يوسّعه إلى القائمة الكاملة — وهو «إصلاحٌ» يمرّ خضراءَ في كلّ
// اختبارٍ قائمٍ لأن اختباراتِ الوحدة تعمل بمدخلاتٍ تُمرَّر إليها يدوياً.
//
// ولا اختبارَ ودجت لـ`AppShell` في المستودع: بناؤها يحتاج رسمَ بيانٍ كاملاً
// من المزوّدات (‏مصادقةٌ وقاعدةٌ وشبكةٌ وسلّة). فالمقياسُ هنا بنيويّ.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _shellPath = 'lib/presentation/shell/app_shell.dart';

/// جسمُ الدالّة المسمّاة — بموازنة الأقواس المعقوفة.
///
/// ⚠️ ويبدأ العدُّ من **أوّلِ `{` بعد قائمة المعاملات**: بدؤه من أوّلِ `{`
/// في السطر يلتقط قوسَ معاملٍ مُسمّى فينتهي الجسمُ عند أوّلِ `}` تافه.
String _body(String src, String signature) {
  final at = src.indexOf(signature);
  expect(at, greaterThanOrEqualTo(0), reason: 'لم أجد «$signature»');

  var i = at + signature.length;
  // تجاوزُ قائمة المعاملات كاملةً.
  var parens = 0;
  for (; i < src.length; i++) {
    if (src[i] == '(') parens++;
    if (src[i] == ')') {
      parens--;
      if (parens == 0) {
        i++;
        break;
      }
    }
  }

  final open = src.indexOf('{', i);
  expect(open, greaterThanOrEqualTo(0), reason: 'لا جسمَ لـ«$signature»');

  var depth = 0;
  for (var j = open; j < src.length; j++) {
    if (src[j] == '{') depth++;
    if (src[j] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, j + 1);
    }
  }
  fail('جسمُ «$signature» غيرُ مغلق');
}

void main() {
  late String shell;

  setUpAll(() {
    final file = File(_shellPath);
    expect(file.existsSync(), isTrue, reason: 'الشريطُ غائب: $_shellPath');
    shell = file.readAsStringSync();
  });

  test('بانيةُ النتائج لا تلمس القائمةَ الكاملة', () {
    final body = _body(shell, 'Widget _navSearchResults');
    expect(body.contains('kAllNavItemDefs'), isFalse,
        reason: 'البحثُ يقرأ كلَّ شاشات النظام — بما فيها الممنوعةُ عن المستخدم');
    expect(body.contains('navEntriesFromNavItems(items)'), isTrue,
        reason: 'المصدرُ الصحيحُ هو المداخلُ المُرشَّحةُ المُمرَّرة');
  });

  test('ولا يبنيها المستدعي من القائمة الكاملة', () {
    // حتّى لو بقيت البانيةُ نظيفةً، منادٍ يمرّر `kAllNavItemDefs` يهدمها.
    expect(shell.contains('_navSearchResults(kAllNavItemDefs'), isFalse,
        reason: 'المنادي يُمرِّر القائمةَ الكاملة');
    expect(shell.contains('_navSearchResults(items)'), isTrue,
        reason: 'لا منادِيَ للبانية أصلاً — البحثُ غيرُ موصول');
  });

  test('والحقلُ يُصفَّر بعد التنقّل', () {
    // شريطٌ عالقٌ على نتيجةٍ بينما المحتوى على شاشةٍ أخرى — ولا سبيلَ
    // للعودة إلى المجموعات إلّا بمسحٍ يدويّ.
    final body = _body(shell, 'Widget _navSearchResults');
    expect(body.contains("_navQuery = ''"), isTrue,
        reason: 'النقرُ على نتيجةٍ لا يُصفِّر البحث');
  });
}
