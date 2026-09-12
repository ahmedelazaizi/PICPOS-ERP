// حارسُ العقد: فئاتُ التقارير في الشريط — مصدرٌ واحدٌ ومسارُ فتحٍ محروس.
//
// ═══ فئتا العطب ═══
//
// **١ — مصدرٌ ثانٍ للكتالوج.** الشريطُ يعرض عناوينَ الفئات وتقاريرَها، وأسهلُ
// طريقةٍ لكتابته نسخُ العناوين في قائمةٍ جديدة. والملفُّ يحمل أصلاً تحذيراً
// من ازدواجٍ قائمٍ بين هويّتَي الشاشة («الكتالوجُ وحدَه مفروك، فالبطاقةُ
// تُضاف في الاثنين معاً وإلّا ظهر التقريرُ في هويّةٍ وغاب عن الأخرى») —
// فثالثٌ يضاعف الانحراف: تقريرٌ يُضاف في الشاشة ولا يظهر في الشريط، أو
// عنوانٌ يُصحَّح في موضعٍ ويبقى خطأً في الآخر.
//
// **٢ — تخطّي حارس الصلاحية.** بطاقاتُ التقارير في الشاشة ملفوفةٌ بـ
// `PermissionGuard` مع `allowManagerOverride`، فمن لا يملك الصلاحيةَ يُسأل
// كلمةَ مرورِ المسؤول. و`PicposReportEntry.action` **دالّةٌ عاريةٌ** تفتح
// الشاشةَ بلا سؤال؛ فنقرةٌ في الشريط تستدعيها مباشرةً تفتح تقريراً محجوباً
// بلا كلمةِ مرورٍ ولا أثر. والإغراءُ قائمٌ لأنّ `action` في متناول اليد:
// الكتالوجُ الذي يقرأه الشريطُ يحملها.
//
// ولذلك يُستدعى الكتالوجُ بـ`PicposReportActions.inert` — أفعالٌ فارغةٌ —
// فحتى استدعاءٌ سهواً لا يفتح شيئاً. والفتحُ يمرّ بطلبٍ تستهلكه الشاشةُ بعد
// `ensurePermission`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ⚠️ **كان `nav_widgets.dart`.** أُخرِجَت الودجتُ إلى ملفٍّ عامٍّ لتصير
/// قابلةَ اختبارِ الودجت، ومرساةُ «يقرأ الكتالوج» أمسكت النقلَ فوراً —
/// ولولاها لقرأ الحارسُ ملفّاً لا يذكر الكتالوجَ فصار الفحصان الأوّلان
/// يمرّان على نصٍّ غائبٍ إلى الأبد.
const _navPath = 'lib/presentation/shell/report_category_nav.dart';
const _screenPath =
    'lib/presentation/reports_picpos/screens/reports_picpos_screen.dart';

/// جسمُ الدالّة المسمّاة — بموازنة الأقواس.
///
/// ⚠️ **ولا يكفي «إلى أوّلِ `\n  }`».** توقيعُ `_openReport` متعدّدُ الأسطر
/// ينتهي بـ`\n  }) {`، وهو يطابق النمطَ — فينتهي «الجسمُ» عند قائمة
/// المعاملات بلا سطرِ شيفرةٍ واحد، ويسقط الفحصُ على نصٍّ غائبٍ لا على عطب.
/// وهذا ما حدث في أوّل تشغيل.
String _body(String src, String signature) {
  final at = src.indexOf(signature);
  expect(at, greaterThanOrEqualTo(0), reason: 'لم أجد «$signature»');

  // تجاوزُ قائمة المعاملات كاملةً بموازنة الأقواس الهلاليّة.
  var i = at + signature.length;
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
  late String nav;
  late String screen;

  setUpAll(() {
    nav = File(_navPath).readAsStringSync();
    screen = File(_screenPath).readAsStringSync();
  });

  test('الشريطُ يقرأ الكتالوجَ من مصدره ولا ينسخه', () {
    expect(nav.contains('buildPicposReportCatalog('), isTrue,
        reason: 'الشريطُ لا يقرأ الكتالوجَ — عناوينُه منسوخةٌ غالباً');
    expect(nav.contains("title: 'تقارير المبيعات'"), isFalse,
        reason: 'عنوانُ فئةٍ مكتوبٌ في الشريط — مصدرٌ ثانٍ ينحرف');
  });

  test('ويستدعيه بأفعالٍ خاملةٍ لا بأفعالٍ حقيقيّة', () {
    expect(nav.contains('PicposReportActions.inert'), isTrue,
        reason: 'الشريطُ يبني الكتالوجَ بأفعالٍ تفتح — و`action` في متناوله');
  });

  test('ولا يستدعي `action` بحال', () {
    expect(RegExp(r'\.action\(\)').hasMatch(nav), isFalse,
        reason: 'فتحٌ مباشرٌ من الشريط يتخطّى `PermissionGuard` كاملاً');
  });

  test('والشاشةُ تفتح الطلبَ بعد فحصِ الصلاحية لا قبله', () {
    final at = screen.indexOf('Future<void> _consumePending()');
    expect(at, greaterThan(0), reason: 'لا مستهلِكَ للطلب — الفتحُ غيرُ موصول');

    final ensureAt = screen.indexOf('ensurePermission(', at);
    final actionAt = screen.indexOf('entry.action()', at);
    expect(ensureAt, greaterThan(0),
        reason: 'المستهلِكُ لا يفحص صلاحيةً — تقريرٌ محجوبٌ يُفتح من الشريط');
    expect(actionAt, greaterThan(ensureAt),
        reason: 'الفتحُ يسبق الفحص — والفحصُ بعده زينةٌ لا حارس');
  });

  test('والطلبُ يُستهلَك لا يُقرأ', () {
    final at = screen.indexOf('Future<void> _consumePending()');
    final body = screen.substring(at, at + 1200);
    expect(body.contains('pendingPicposReport.take()'), isTrue,
        reason: 'قراءةٌ بلا استهلاكٍ تُعيد فتحَ التقرير في كلّ إعادة بناء');
  });

  test('والتنقّلُ يسبق تسجيلَ الطلب — وإلّا فُتح التقريرُ ثمّ مُسِح', () {
    // ⚠️ **ومع التابات صارت شاشةُ التقارير قد تكون مبنيّةً في تابٍ خلفيّ.**
    // فتسجيلُ الطلب أوّلاً يُوقظ مستمِعَها فيدفع مسارَ التقرير في الحال،
    // ثمّ يأتي التنقّلُ فيمسحه بـ`popUntil` — تقريرٌ يُفتَح ويُغلَق في
    // إطارٍ واحد، ونقرةٌ عاملةٌ تبدو ميّتة.
    final shell =
        File('lib/presentation/shell/app_shell.dart').readAsStringSync();
    final body = _body(shell, 'void _openReport');

    final navAt = body.indexOf('_onNavItemTap(');
    final reqAt = body.indexOf('pendingPicposReport.request(');
    expect(navAt, greaterThan(0), reason: 'الفتحُ لا ينتقل إلى الشاشة');
    expect(reqAt, greaterThan(0), reason: 'الفتحُ لا يسجّل طلباً');
    expect(navAt, lessThan(reqAt),
        reason: 'الطلبُ سبق التنقّل — والتقريرُ يُمسَح قبل أن يُرى');
  });

  test('والمستمِعُ يُنزَع عند التخلّص', () {
    expect(screen.contains('pendingPicposReport.removeListener'), isTrue,
        reason: 'مستمِعٌ باقٍ على شاشةٍ متخلَّصٍ منها — `setState` بعد الموت');
  });
}
