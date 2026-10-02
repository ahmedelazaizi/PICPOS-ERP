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
import 'package:ural_erp/core/config/brand.dart';
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

  // ═══ المرحلة هـ / E1 (قرارُ المالك) ═══
  //
  // «المالية والمحاسبة» انقسمت رأسَين: «الإدارة المالية» (‏`accounting`) =
  // سند قبض · سند صرف · إدارة الشيكات · الخزينة · إغلاق الوردية؛
  // و«إدارة الحسابات» (‏`accounts`) = كلُّ شاشات المحاسبة الباقية، ومنها ما
  // كان تحت «اليومية العامة» — فرأسُ `journal` دُمج ولم يبقَ.
  //
  // ⚠️ E-fix ٣ — الفصلُ لـPicPos وحدَه: المجموعتان ١ و٢ تُقاسان ببناء PicPos
  //    (`--dart-define=APP_BRAND=picpos`)، وUralCash يُقاس بمجموعة ١ب.
  group('١ · الرأسان', skip: !Brand.isPicPos, () {
    test('«إدارة الحسابات» رأسُ مجموعةٍ — لا مدخلَ شاشة', () {
      final meta = kNavGroupDefs.firstWhere((g) => g.key == 'accounts',
          orElse: () => throw StateError('لا مجموعةَ باسم accounts'));
      expect(meta.label, 'إدارة الحسابات');

      // 🔴 ولا مدخلَ بتسميةِ الرأس في القائمة: الرأسُ تعريفٌ، والمدخلُ
      //    ينتقل إلى شاشة. ووجودُهما معاً يعطي رأساً واسماً مكرَّراً تحته.
      for (final label in const ['الحسابات', 'إدارة الحسابات']) {
        expect(kAllNavItemDefs.where((i) => i.label == label), isEmpty,
            reason: '«$label» مدخلُ شاشةٍ — والرأسُ لا ينتقل');
      }
    });

    test('و«الإدارة المالية» رأسُ السندات والخزينة', () {
      final meta = kNavGroupDefs.firstWhere((g) => g.key == 'accounting');
      expect(meta.label, 'الإدارة المالية');
    });

    test('و«اليومية العامة» دُمجت — لا رأسَ ولا مدخلَ يشير إليها', () {
      expect(kNavGroupDefs.where((g) => g.key == 'journal'), isEmpty);
      expect(_indexesOf('journal'), isEmpty);
    });

    test('وترتيبُهما: الإدارة المالية ثمّ إدارة الحسابات', () {
      final order = _groupOrder();
      expect(order.indexOf('accounts'), order.indexOf('accounting') + 1);
    });
  });

  group('١ب · UralCash — رؤوسُ ما قبل المرحلة هـ حرفاً بحرف', skip: Brand.isPicPos,
      () {
    test('الرؤوسُ الثلاثةُ بتسمياتها القديمة وبترتيبها', () {
      String label(String key) =>
          kNavGroupDefs.firstWhere((g) => g.key == key).label;
      expect(label('accounting'), 'المالية والمحاسبة');
      expect(label('accounts'), 'الحسابات');
      expect(label('journal'), 'اليومية العامة');
      final order = _groupOrder();
      expect(order.indexOf('accounts'), order.indexOf('accounting') + 1);
      expect(order.indexOf('journal'), order.indexOf('accounts') + 1);
    });

    test('🔴 المداخلُ في مجموعاتها القديمة وبترتيبها وأقسامِها', () {
      expect(_indexesOf('accounting'), [
        ScreenId.receiptVoucher.navigationIndex,
        ScreenId.paymentVoucher.navigationIndex,
        ScreenId.commercialPapers.navigationIndex,
        ScreenId.journalVoucher.navigationIndex,
        ScreenId.assetCategories.navigationIndex,
        ScreenId.assetLocations.navigationIndex,
        ScreenId.chequeBooks.navigationIndex,
        ScreenId.treasury.navigationIndex,
        ScreenId.shiftClose.navigationIndex,
        ScreenId.fixedAssets.navigationIndex,
        ScreenId.eInvoice.navigationIndex,
        ScreenId.fiscalYear.navigationIndex,
        ScreenId.operationalExpenses.navigationIndex,
      ]);
      expect(_indexesOf('accounts'), [
        ScreenId.chartOfAccounts.navigationIndex,
        ScreenId.costCenters.navigationIndex,
        ScreenId.generalLedger.navigationIndex,
        ScreenId.trialBalance.navigationIndex,
      ]);
      expect(_indexesOf('journal'), [
        ScreenId.journalEntries.navigationIndex,
        ScreenId.journalTemplates.navigationIndex,
        ScreenId.bankReconciliation.navigationIndex,
      ]);
      expect(_itemAt(ScreenId.receiptVoucher.navigationIndex)!.section,
          'المالية والمحاسبة');
      expect(_itemAt(ScreenId.chartOfAccounts.navigationIndex)!.section,
          'الحسابات');
      expect(_itemAt(ScreenId.journalEntries.navigationIndex)!.section,
          'اليومية العامة');
    });
  });

  group('٢ · محتوى المجموعتَين', skip: !Brand.isPicPos, () {
    test('🔴 «الإدارة المالية» خمسٌ بعينها وبترتيبها (+ دفتر الشيكات لـUralCash)',
        () {
      expect(_indexesOf('accounting'), [
        ScreenId.receiptVoucher.navigationIndex,
        ScreenId.paymentVoucher.navigationIndex,
        ScreenId.commercialPapers.navigationIndex,
        ScreenId.chequeBooks.navigationIndex,
        ScreenId.treasury.navigationIndex,
        ScreenId.shiftClose.navigationIndex,
      ]);
      // في PicPos صار دفترُ الشيكات تبويباً داخل «إدارة الشيكات».
      expect(kPicPosReplacedNavIndexes,
          contains(ScreenId.chequeBooks.navigationIndex));
    });

    test('🔴 «إدارة الحسابات» كلُّ شاشات المحاسبة الباقية وبترتيبها', () {
      expect(_indexesOf('accounts'), [
        ScreenId.chartOfAccounts.navigationIndex,
        ScreenId.costCenters.navigationIndex,
        ScreenId.generalLedger.navigationIndex,
        ScreenId.trialBalance.navigationIndex,
        ScreenId.journalEntries.navigationIndex,
        ScreenId.journalTemplates.navigationIndex,
        ScreenId.bankReconciliation.navigationIndex,
        ScreenId.journalVoucher.navigationIndex,
        ScreenId.assetCategories.navigationIndex,
        ScreenId.assetLocations.navigationIndex,
        ScreenId.fixedAssets.navigationIndex,
        ScreenId.eInvoice.navigationIndex,
        ScreenId.fiscalYear.navigationIndex,
        ScreenId.operationalExpenses.navigationIndex,
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
