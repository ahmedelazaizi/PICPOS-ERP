// شاشةٌ **تُمنَح صلاحيّتُها وتدخل النطاقَ** لا بدّ أن تقدر على الرسم.
//
// ═══ 🔴 العقدُ وما يكسره ═══
//
// `screenPermissionMap` يجعل الشاشةَ **قابلةً للمنح**: مديرٌ يفتح مصفوفةَ
// الصلاحيات فيراها ويمنحها لدور. و`ScreenRegistry` يجعلها **داخلَ نطاق**
// الملفّ فتُعَدُّ من شاشاته. ومع ذلك قد لا يكون لها `AppScreen` ولا
// `ScreenConfig` — أي **لا شيءَ يبنيها**.
//
// والنتيجةُ صلاحيّةٌ تُمنَح لشاشةٍ لا تُفتَح: المديرُ يمنحها ويظنُّ أنّه
// أعطى شيئاً، والموظّفُ لا يجد باباً. ولا يُكشَف ذلك بتشغيلٍ ولا باختبارِ
// ودجت — فما لا يُرسَم لا يُختبَر.
//
// ⚠️ **وقع فعلاً**: `ScreenId.bankReconciliation(53)` في خريطة الصلاحيات
// وفي نطاق `unified` منذ 2026-09-01، **وبلا `AppScreen` إطلاقاً** — لا
// تُبلَغ إلّا من تبويبٍ داخلَ حاوية «الحسابات». فحذفُ الحاوية كان يُسقط
// الشاشةَ من الوجود وصلاحيّتُها باقيةٌ تُمنَح.
//
// ⚠️ **ولا خطَّ أساسٍ هنا عمداً.** قِيست الحالةُ يومَ كُتب هذا الحارس:
// ثلاثةَ عشرَ معرِّفاً بلا `AppScreen`، و**واحدٌ** منها في الخريطة
// والنطاق معاً. فالبقيّةُ (`users` · `payroll` · `attendance` …) ليست
// شاشاتٍ من الدرجة الأولى أصلاً — تُفتَح تبويباتٍ داخلَ غيرها ولا
// تُمنَح وحدَها. وخطُّ أساسٍ كان سيُخفي العطبَ الوحيدَ بين اثني عشرَ
// مشروعاً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_source.dart';

/// أعضاءُ enum بصيغة `name(index),` — الاسمُ إلى فهرسه.
Map<String, int> _enumMembers(String path) {
  final src = File(path).readAsStringSync();
  return {
    for (final m in RegExp(
      r'^\s{2}([a-z][A-Za-z0-9_]*)\((\d+)\)',
      multiLine: true,
    ).allMatches(src))
      m.group(1)!: int.parse(m.group(2)!),
  };
}

Set<String> _enumNames(String path) => _enumMembers(path).keys.toSet();

/// مفاتيحُ `screenPermissionMap` — `ScreenId.x: 'code',`.
Set<String> _grantable() {
  final src = File('lib/data/providers/auth_providers.dart').readAsStringSync();
  return {
    for (final m in RegExp(r"ScreenId\.([A-Za-z0-9_]+):\s*'").allMatches(src))
      m.group(1)!,
  };
}

/// أعضاءُ نطاقٍ بعينه في `ScreenRegistry`.
Set<String> _scope(String name) {
  final src = File(
    'lib/core/navigation/screen_registry.dart',
  ).readAsStringSync();
  final m = RegExp(
    'static const List<ScreenId> $name = \\[(.*?)\\n  \\];',
    dotAll: true,
  ).firstMatch(src);
  if (m == null) return {};
  return {
    for (final x in RegExp(
      r'ScreenId\.([A-Za-z0-9_]+)',
    ).allMatches(m.group(1)!))
      x.group(1)!,
  };
}

/// أسماءُ الشاشات التي لها `ScreenConfig` فعلاً.
Set<String> _configured() {
  final src = readLibrarySource('lib/app_main_screen.dart');
  return {
    for (final m in RegExp(
      r'appScreen: AppScreen\.([A-Za-z0-9_]+),',
    ).allMatches(src))
      m.group(1)!,
  };
}

void main() {
  late Set<String> screenIds;
  late Set<String> appScreens;
  late Set<String> grantable;
  late Set<String> unified;
  late Set<String> configured;

  setUpAll(() {
    screenIds = _enumNames('lib/core/navigation/screen_id.dart');
    appScreens = _enumNames('lib/core/enums/app_screen.dart');
    grantable = _grantable();
    unified = _scope('unified');
    configured = _configured();
  });

  group('حراسةُ الحارس', () {
    test('المصادرُ الخمسةُ قُرئت غيرَ فارغة', () {
      expect(screenIds.length, greaterThan(60));
      expect(appScreens.length, greaterThan(60));
      expect(grantable.length, greaterThan(40));
      expect(unified.length, greaterThan(40));
      expect(configured.length, greaterThan(40));
    });

    test('🔴 ومراسٍ موجبة — معرِّفٌ معروفٌ يُكتشَف في الأربعة', () {
      // بلا هذه لكان «لا مخالفَ» صحيحاً حتّى لو قرأنا ملفّاتٍ خاطئة.
      for (final anchor in const ['chartOfAccounts', 'journalEntries']) {
        expect(screenIds, contains(anchor));
        expect(appScreens, contains(anchor));
        expect(grantable, contains(anchor));
        expect(unified, contains(anchor));
      }
    });

    test('والاشتقاقُ يميّز المُعرَّفَ من غيرِه', () {
      // `financialStatements` مُعرَّفٌ في الاثنين، و`attendance` في
      // `ScreenId` وحدَه — فلو تساوى الطرفان فالقارئُ يقرأ ملفّاً واحداً.
      expect(appScreens, contains('financialStatements'));
      expect(screenIds.difference(appScreens), isNotEmpty);
    });
  });

  test('🔴 كلُّ شاشةٍ تُمنَح وتدخل النطاقَ لها `AppScreen` تُبنى به', () {
    final offenders = (grantable.intersection(
      unified,
    )).difference(appScreens).intersection(screenIds).toList()..sort();

    expect(
      offenders,
      isEmpty,
      reason:
          'صلاحيّةٌ تُمنَح لشاشةٍ **لا شيءَ يبنيها**: المديرُ يمنحها '
          'ويظنُّ أنّه أعطى باباً، والموظّفُ لا يجده.\n'
          'والعلاجُ عضوٌ في `AppScreen` بنفس الفهرس و`ScreenConfig` له:\n'
          '  ${offenders.join('\n  ')}',
    );
  });

  test('🔴 ولها `ScreenConfig` يبنيها — لا عضوَ enum وحدَه', () {
    // ⚠️ عضوٌ في `AppScreen` بلا `ScreenConfig` يعطي **نفسَ العطب**:
    //    الصلاحيّةُ تُمنَح ولا شيءَ يُرسَم. وقُيس يومَ كُتب هذا:
    //    ستّةٌ وخمسون شاشةً تُمنَح وتدخل النطاقَ — **وللستّ والخمسين
    //    إعداد**. فلا خطَّ أساسٍ هنا أيضاً.
    final offenders = (grantable.intersection(
      unified,
    )).difference(configured).intersection(screenIds).toList()..sort();

    expect(
      offenders,
      isEmpty,
      reason:
          'عضوٌ في `AppScreen` بلا `ScreenConfig` — الموجّهُ لا يجد '
          'ما يبنيه فيرتدّ إلى شاشةٍ أخرى أو يقع:\n'
          '  ${offenders.join('\n  ')}',
    );
  });

  test('وكلُّ `AppScreen` له `ScreenId` بنفس الاسم — لا توأمَ يتيم', () {
    final orphan = appScreens.difference(screenIds).toList()..sort();
    expect(
      orphan,
      isEmpty,
      reason:
          '`AppScreen` بلا `ScreenId` ⇒ شاشةٌ تُبنى ولا تُمنَح ولا '
          'تدخل نطاقاً: ${orphan.join(' · ')}',
    );
  });

  test('🔴 والتوأمان يحملان **نفسَ الفهرس** — لا اسماً فقط', () {
    // 🔴 الفهرسُ هو ما يسافر: `navigationIndex` هو ما يُخزَّن في تفضيلات
    //    المستخدم ويُمرَّر إلى `screenNavigationProvider.open(...)`. فاسمان
    //    متطابقان بفهرسَين مختلفَين يفتحان **شاشتَين مختلفتَين** بنفس
    //    الاسم — والبلاغُ حينها «الشاشةُ الخطأ تُفتَح»، وهو آخرُ ما يُشَكّ
    //    فيه.
    final ids = _enumMembers('lib/core/navigation/screen_id.dart');
    final apps = _enumMembers('lib/core/enums/app_screen.dart');
    final mismatched = <String>[
      for (final e in apps.entries)
        if (ids.containsKey(e.key) && ids[e.key] != e.value)
          '${e.key}: ScreenId=${ids[e.key]} ≠ AppScreen=${e.value}',
    ]..sort();

    expect(
      mismatched,
      isEmpty,
      reason: 'توأمان بفهرسَين مختلفَين:\n  ${mismatched.join('\n  ')}',
    );
  });
}
