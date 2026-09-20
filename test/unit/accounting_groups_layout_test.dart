// عقدُ مجموعتَي «الحسابات» و«اليومية العامة» — أمرُ المالك 2026-09-20.
//
// ═══ ما طُلب ═══
//
// حاويةُ «الحسابات» كانت **مدخلَ شاشةٍ** يفتح تسعةَ تبويبات. صارت التبويباتُ
// شاشاتٍ مستقلّةً لها مداخلُها، و«الحسابات» **رأسَ مجموعةٍ لا مدخلاً** —
// والرأسُ في هذا الشريط يطوي ويبسط ولا ينتقل إلى شاشة.
//
//   ▸ الحسابات        دليل الحسابات · مراكز التكلفة · دفتر الأستاذ ·
//                     ميزان المراجعة
//   ▸ اليومية العامة  قيود اليومية · قوالب القيود · المطابقة البنكية
//
// و«ربط الحسابات» انتقل إلى الإعدادات، و«القوائم المالية» صارت **باباً
// واحداً** في التقارير.
//
// ⚠️ **ولماذا اختبارٌ لا نظرةٌ إلى الشاشة**: `kAllNavItemDefs` مصدرُ توصيلٍ
// مستقلٌّ لا يُشتقّ من `ScreenId` ولا من خريطة الصلاحيات — فمدخلٌ في مجموعةٍ
// بلا رأسٍ يظهر تحت المفتاح الإنجليزيّ الخام بلا خطأٍ ولا تحذير.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';

/// نصٌّ بلا أسطر التعليق — فذكرُ اسمٍ في شرحٍ ليس باباً يُفتَح.
String _stripComments(String raw) => [
      for (final line in raw.split('\n'))
        if (!line.trimLeft().startsWith('//')) line,
    ].join('\n');

NavItemDef? _itemAt(int index) {
  for (final i in kAllNavItemDefs) {
    if (i.index == index) return i;
  }
  return null;
}

/// فهارسُ مجموعةٍ بترتيب ظهورها.
List<int> _indexesOf(String group) =>
    [for (final i in kAllNavItemDefs) if (i.group == group) i.index];

/// ترتيبُ الرؤوس كما يبنيه الشريط: أوّلُ ظهورٍ لكلّ مفتاح.
List<String> _groupOrder() {
  final seen = <String>[];
  for (final i in kAllNavItemDefs) {
    final g = i.group ?? 'other';
    if (!seen.contains(g)) seen.add(g);
  }
  return seen;
}

void main() {
  group('حراسةُ الحارس', () {
    test('القائمةُ والرؤوسُ قُرئت غيرَ فارغة', () {
      expect(kAllNavItemDefs.length, greaterThan(40));
      expect(kNavGroupDefs.length, greaterThan(8));
    });

    test('ومرساةٌ موجبة — مجموعةٌ معروفةٌ ما زالت قائمة', () {
      // لو انكسر الكشفُ لصارت كلُّ المجموعات فارغةً و«لا مخالفَ» صحيحاً.
      expect(_indexesOf('sales'), isNotEmpty);
      expect(_indexesOf('accounting'), isNotEmpty);
    });
  });

  group('١ · الرأسان', () {
    test('«الحسابات» رأسُ مجموعةٍ — لا مدخلَ شاشة', () {
      final meta = kNavGroupDefs.firstWhere((g) => g.key == 'accounts',
          orElse: () => throw StateError('لا مجموعةَ باسم accounts'));
      expect(meta.label, 'الحسابات');

      // 🔴 ولا مدخلَ بتسميةِ «الحسابات» في القائمة: الرأسُ تعريفٌ، والمدخلُ
      //    ينتقل إلى شاشة. ووجودُهما معاً يعطي رأساً واسماً مكرَّراً تحته.
      final asItem =
          kAllNavItemDefs.where((i) => i.label == 'الحسابات').toList();
      expect(asItem, isEmpty,
          reason: '«الحسابات» ما زالت مدخلَ شاشةٍ — الحاويةُ لم تُحذَف');
    });

    test('و«اليومية العامة» رأسٌ جديد', () {
      final meta = kNavGroupDefs.firstWhere((g) => g.key == 'journal',
          orElse: () => throw StateError('لا مجموعةَ باسم journal'));
      expect(meta.label, 'اليومية العامة');
    });

    test('وترتيبُهما: المالية والمحاسبة ثمّ الحسابات ثمّ اليومية', () {
      final order = _groupOrder();
      expect(order.indexOf('accounts'), order.indexOf('accounting') + 1);
      expect(order.indexOf('journal'), order.indexOf('accounts') + 1);
    });
  });

  group('٢ · محتوى المجموعتَين', () {
    test('🔴 «الحسابات» أربعُ شاشاتٍ بعينها وبترتيبها', () {
      expect(_indexesOf('accounts'), [
        ScreenId.chartOfAccounts.navigationIndex,
        ScreenId.costCenters.navigationIndex,
        ScreenId.generalLedger.navigationIndex,
        ScreenId.trialBalance.navigationIndex,
      ]);
    });

    test('🔴 و«اليومية العامة» ثلاثٌ بعينها وبترتيبها', () {
      expect(_indexesOf('journal'), [
        ScreenId.journalEntries.navigationIndex,
        ScreenId.journalTemplates.navigationIndex,
        ScreenId.bankReconciliation.navigationIndex,
      ]);
    });
  });

  group('٣ · الخارجون من الشريط', () {
    test('«ربط الحسابات» لا مدخلَ له — انتقل إلى الإعدادات', () {
      expect(_itemAt(ScreenId.accountMapping.navigationIndex), isNull,
          reason: 'ما زال في الشريط، والقرارُ نقلُه إلى الإعدادات');
    });

    test('🔴 وهو موصولٌ في الإعدادات فعلاً — لا يُحذَف بلا بديل', () {
      // 🔴 **بلا نزعِ التعليقات نجت طفرةُ إغلاق الباب**: الملفُّ
      //    يذكر `AccountMappingPicPosScreen` في شرحٍ في رأسِه، فمطابقةُ
      //    النصّ الخام تمرّ خضراءَ والبابُ مغلقٌ.
      final settings = _stripComments(File(
              'lib/presentation/settings_picpos/screens/settings_picpos_screen.dart')
          .readAsStringSync());
      expect(settings, contains('AccountMappingPicPosScreen('),
          reason: 'سُحب من الشريط ولم يُوصَل في الإعدادات ⇒ شاشةٌ فقدت '
              'بابَها الوحيد');
    });

    test('«القوائم المالية» لا مدخلَ لها — بابُها التقارير', () {
      expect(_itemAt(ScreenId.financialStatements.navigationIndex), isNull);
    });
  });

  test('🔴 والطيُّ مرفوعٌ — ولا يعود بسطر', () {
    // ⚠️ **ويُقاس هنا لا في `brand_picpos_test` وحدَه**: ذاك مُخطّىً
    //    بالكامل بلا `--dart-define=APP_BRAND=picpos`، فطفرةٌ تُعيد
    //    ملءَ الطيّ **تنجو من السويّة كلِّها** — وقد نجت فعلاً.
    expect(kPicPosFoldedIntoAccountingHub, isEmpty,
        reason: 'عاد طيُّ الحاوية — والقرارُ شاشاتٌ مستقلّةٌ تحت رأسَين');
  });

  group('٤ · القوائمُ الماليةُ بابُها التقارير', () {
    // كانت **ثلاثةَ أبوابٍ** لشاشةٍ واحدة: مدخلُ الشريط · تبويبُ الحاوية ·
    // تقريرُ التحليلات. وكلُّ بابٍ يمرّر مُعامِلاتٍ غيرَ مُعامِلات أخيه
    // (`view` و`initialTabIndex`) — فيرى المستخدمُ شاشتَين مختلفتَين باسمٍ
    // واحدٍ ويظنُّ إحداهما معطوبة.
    //
    // ⚠️ **ولا يُقاس ذلك بعدِّ المُنشئات في كلّ الشجرة**: `ScreenConfig`
    //    للقوائم المالية **يبقى** (الشاشةُ ممنوحةٌ وفي النطاق، و
    //    `allowed_screens_can_render_test` يشترط لها بنّاءً)، وميزانُ
    //    المراجعة يبني نفسَ الصنف بـ`view` آخر. فالمقياسُ **بابُ
    //    المستخدم** لا عددُ الأسطر.

    test('بابُ التقارير موجودٌ وواحد', () {
      final reports = File(
              'lib/presentation/reports_picpos/screens/reports_picpos_screen.dart')
          .readAsStringSync();
      expect('FinancialStatementsPicPosScreen('.allMatches(reports).length, 1,
          reason: 'بابُ التقارير غاب أو تعدّد');
    });

    test('🔴 وميزانُ المراجعة يُثبّت `view` — لا يفتح الشاشةَ عامّةً', () {
      final main = File('lib/app_main_screen.dart').readAsStringSync();
      final at = main.indexOf('appScreen: AppScreen.trialBalance,');
      expect(at, greaterThan(0), reason: 'لا إعدادَ لميزان المراجعة');
      final body = main.substring(at, main.indexOf('label:', at));
      expect(body, contains('FinancialStatementsView.trialBalance'),
          reason: 'الميزانُ يفتح الشاشةَ بلا `view` ⇒ يعرض قائمةَ الدخل '
              'تحت اسم «ميزان المراجعة»');
    });
  });

  test('٥ · ولا أثرَ للحاوية في الشجرة', () {
    final left = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final code = [
        for (final line in f.readAsStringSync().split('\n'))
          if (!line.trimLeft().startsWith('//')) line,
      ].join('\n');
      if (code.contains('AccountingHubPicPosScreen') ||
          code.contains('accountingHub') ||
          code.contains('AccountingTab')) {
        left.add(f.path.replaceAll(r'\', '/'));
      }
    }
    expect(left, isEmpty,
        reason: 'بقايا حاويةٍ محذوفةٍ تُقرأ غداً على أنّها الطريق:\n  '
            '${left.join('\n  ')}');
  });
}
