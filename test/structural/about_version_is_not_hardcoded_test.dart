// رقمُ الإصدار في «عن البرنامج» يُقرأ ولا يُحفَر.
//
// ═══ العطبُ الميدانيّ ═══
//
// بلاغُ المالك 2026-08-22: «رقمُ الإصدار لا يظهر تحديثُه في إعدادات النظام».
//
// والسببُ **لم يكن** أن القيمةَ غيرُ متاحة: `AppVersionService.initialize()`
// تُنادى في `main.dart` قبل `runApp` وتملأ `AppConstants.appVersion` من
// `pubspec` عبر `package_info_plus`. كارتُ «عن البرنامج» وحدَه كان يطبع
// نصّاً محفوراً `'الإصدار 1.0.0'` — فيقرأ المشغّلُ نسخةً غيرَ التي يشغّلها،
// وهو أسوأُ من ألّا يُعرض رقمٌ أصلاً.
//
// ═══ ولماذا حارسٌ بنيويّ ═══
//
// تركيبُ شاشة الإعدادات في اختبارِ ودجت يجرّ `AppDatabase` حقيقيّةً ونصفَ
// المزوّدات. والعطبُ نصّيٌّ محضٌ يُقرأ من المصدر — فالقراءةُ أرخصُ وأوثق.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const path =
      'lib/presentation/settings_picpos/screens/settings_picpos_screen.dart';

  late String src;

  /// المصدرُ **بلا تعليقات**.
  ///
  /// ⚠️ لزم هذا فوراً: التعليقُ الذي يشرح الإصلاح يقتبس النصَّ المحفورَ
  /// القديم (`'الإصدار 1.0.0'`) ليوثّقه، فطابقه الحارسُ وسقط على إصلاحٍ
  /// صحيح. حارسٌ يقرأ الشرحَ بدل الكود يُنذر كذباً — ويُدرَّب المطوّرُ على
  /// تجاهله.
  late String code;

  setUpAll(() {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: 'حدِّث المسار: $path');
    src = f.readAsStringSync();
    code = src
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
  });

  test('لا رقمَ إصدارٍ محفورٌ في كود الشاشة', () {
    // أيُّ `الإصدار` يتبعه رقمٌ حرفيٌّ = حفر. الصيغةُ الصحيحةُ تستبدل قيمةً.
    final hardcoded = RegExp(r"'الإصدار\s+\d+\.\d+");
    expect(
      hardcoded.hasMatch(code),
      isFalse,
      reason: 'رقمُ الإصدار محفورٌ — يجب أن يُقرأ من AppConstants.appVersion',
    );
  });

  test('الكارتُ يقرأ appVersion فعلاً', () {
    expect(src, contains('AppConstants.appVersion'),
        reason: 'لا مصدرَ حقيقيّاً للنسخة في الشاشة');
  });

  test('ورقمُ البناء يُعرض معه', () {
    // نسختان بنفس الرقم وبناءَين مختلفَين تقعان بين إصدارَين تجريبيَّين،
    // والرقمُ وحدَه لا يفرّقهما.
    expect(src, contains('AppConstants.appBuildNumber'));
  });

  test('الخدمةُ التي تملأ القيمةَ ما زالت تُنادى عند الإقلاع', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('AppVersionService.initialize()'),
        reason: 'بدونها تبقى القيمةُ الافتراضيّةَ 1.0.0 وتعود الشكوى نفسُها');
  });
}
