// مفتاحُ «نوع النشاط» لا بدّ أن يكون في التحميل المسبق.
//
// ── العطبُ الصامتُ الذي يحرسه هذا الملفّ (مقيسٌ 2026-08-15) ────────────────
// `featureFlagsProvider` يقرأ `industry_mode` قراءةً **متزامنة** من
// `SettingsRepositoryCached.get`. وتلك الدالّةُ:
//
//     String? get(String key) {
//       if (_cache.containsKey(key)) return _cache[key];
//       return null; // miss
//     }
//
// ترجع `null` عند **إخفاق الكاش** بنفس ما ترجعه عند غياب المفتاح من القاعدة.
// والكاشُ لا يمتلئ إلا بـ`preload(preloadKeys)` في `main.dart`.
//
// فمفتاحٌ خارجَ تلك القائمة يُقرأ `null` **دائماً** ⇒ «نوع النشاط» لا يُشعل
// الطاولاتِ أبداً مهما اختار المالك. بلا خطأٍ، بلا تحذير، وبلا اختبارٍ أحمر —
// عطبٌ صامتٌ تامّ من الفئة التي كلّفت هذا المستودعَ جلساتٍ.
//
// والقراءةُ المتزامنةُ مقصودةٌ ولا تُستبدل: `industryModeProvider` يبني
// حالتَه بـ`supermarket` ثم يحمّل من القاعدة لاحقاً، فمراقبتُه كانت ستعرض
// التنقّلَ بلا طاولاتٍ لحظةً ثم يقفز — ووميضٌ في شريط التنقّل يُقرأ عطباً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/config/industry_tables_policy.dart';

void main() {
  test('`industry_mode` مُحمَّلٌ مسبقاً في `main.dart`', () {
    final src = File('lib/main.dart').readAsStringSync();

    // نقيس داخل قائمةِ التحميل نفسِها لا في الملفّ كلِّه: ذكرٌ عابرٌ في
    // تعليقٍ أو في سطرٍ آخرَ كان سيُخضِر الحارسَ بلا أن يُحمَّل شيء.
    final start = src.indexOf('final preloadKeys = <String>[');
    expect(start, isNot(-1),
        reason: 'قائمةُ التحميل المسبق تغيّر شكلُها — حدِّث الحارس');
    final end = src.indexOf('];', start);
    expect(end, greaterThan(start));
    final list = src.substring(start, end);

    // بالثابتِ المُسمّى أو بالنصّ الحرفيّ — المقيسُ **وصولُ المفتاح** لا
    // صياغتُه. والثابتُ أفضلُ (مصدرٌ واحد) فيُقبل أوّلاً.
    expect(
      list.contains('industryModeSettingKey') ||
          list.contains("'$industryModeSettingKey'"),
      isTrue,
      reason: 'المفتاحُ خارجَ التحميل المسبق ⇒ `get()` يرجع null دائماً '
          '⇒ «مطعم (طاولات وصالات)» لا يُظهر شيئاً، بلا أيّ أثرٍ يكشفه',
    );
  });

  test('واسمُ المفتاح واحدٌ في الكتابة والقراءة', () {
    // `IndustryModeNotifier.setMode` يكتب بنصٍّ حرفيّ؛ فلو انحرف أحدُهما
    // لَكتب أحدُهما في مكانٍ ويقرأ الآخرُ من آخر — وكلاهما يمرّ أخضر.
    final notifier =
        File('lib/data/providers/settings_providers.dart').readAsStringSync();
    expect(notifier.contains("'$industryModeSettingKey'"), isTrue);
  });
}
