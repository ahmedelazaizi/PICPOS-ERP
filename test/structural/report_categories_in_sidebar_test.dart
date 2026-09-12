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

const _navPath = 'lib/presentation/shell/nav_widgets.dart';
const _screenPath =
    'lib/presentation/reports_picpos/screens/reports_picpos_screen.dart';

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

  test('والمستمِعُ يُنزَع عند التخلّص', () {
    expect(screen.contains('pendingPicposReport.removeListener'), isTrue,
        reason: 'مستمِعٌ باقٍ على شاشةٍ متخلَّصٍ منها — `setState` بعد الموت');
  });
}
