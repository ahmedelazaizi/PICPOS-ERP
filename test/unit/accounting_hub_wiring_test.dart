// test/unit/accounting_hub_wiring_test.dart
//
// حارسُ حاويةِ «الحسابات» — التوصيلُ الستّةُ **والطيُّ معاً**.
//
// ⚠️ الطيُّ خطرُه غيرُ خطرِ الإضافة: إضافةُ شاشةٍ تفشل ظاهرةً (لا شيء يُفتَح)،
// أمّا الطيُّ فيفشل **صامتاً** — المدخلُ يختفي والشاشةُ تبقى مبنيّةً موصولةً
// فلا يحمرّ حارسٌ واحد، والمستخدمُ وحدَه يكتشف أنّها لم تعد تُبلَغ. فهذا
// الملفُّ يقيس البلوغَ لا التسجيل: كلُّ مدخلٍ طُوي **له تبويبٌ يفتحه**.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/enums/app_screen.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/navigation/screen_registry.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/presentation/accounting_picpos/accounting_hub_picpos_screen.dart';

void main() {
  group('الحاويةُ موصولةٌ في المواضع الستّة', () {
    test('١) لها معرِّفُ شاشة', () {
      expect(ScreenId.accountingHub.navigationIndex, 63);
    });

    test('٢) و`AppScreen` يحمل نفسَ الرقم', () {
      expect(AppScreen.accountingHub.value,
          ScreenId.accountingHub.navigationIndex,
          reason: 'رقمان يفترقان = شاشةٌ تُفتَح غيرَ التي أُذن بها');
    });

    test('٣) ولها صلاحيةٌ في `screenPermissionMap`', () {
      expect(screenPermissionMap[ScreenId.accountingHub], 'settings_view');
    });

    test('٤) وهي في نطاق `unified`', () {
      expect(ScreenRegistry.unified, contains(ScreenId.accountingHub),
          reason: 'النطاقُ يُرشِّح **قبل** فحصِ الصلاحية');
    });

    test('٥) ولها مدخلٌ واحدٌ في القائمة الجانبيّة بنفس كود الصلاحية', () {
      final item = kAllNavItemDefs
          .where((n) => n.index == ScreenId.accountingHub.navigationIndex)
          .toList();
      expect(item, hasLength(1),
          reason: 'المصدرُ السادسُ المستقلُّ — هو الذي غاب عن الحجوزات');
      expect(item.single.permission, screenPermissionMap[ScreenId.accountingHub]);
      expect(item.single.group, 'accounting');
    });

    test('٦) ورقمُها لا يصطدم برقمٍ آخر', () {
      final same = ScreenId.values
          .where((s) =>
              s.navigationIndex == ScreenId.accountingHub.navigationIndex)
          .toList();
      expect(same, hasLength(1));
    });
  });

  group('التبويباتُ على التصميم — سبعةٌ لا ثمانية', () {
    // ⚠️ مقيسٌ من `TABS` في PicPos-Accounting-remote-2026-08-22.dc.html،
    //    ومن `screen` في `data-props` (‏نفسُ السبعةِ حرفاً بحرف)، ومن
    //    `hint-placeholder-count="7"` على شريط التبويبات. و«الحسابات» اسمُ
    //    المدخل في `NAV` لا تبويبٌ ثامن.
    test('عددُها وترتيبُها كالتصميم', () {
      expect(AccountingTab.values.map((t) => t.name).toList(),
          ['coa', 'cc', 'je', 'gl', 'tb', 'tpl', 'map']);
    });

    test('وأسماؤها كالتصميم', () {
      expect(AccountingTab.values.map((t) => t.label).toList(), [
        'دليل الحسابات',
        'مراكز التكلفة',
        'قيود اليومية',
        'دفتر الأستاذ',
        'ميزان المراجعة',
        'قوالب القيود',
        'ربط الحسابات',
      ]);
    });

    test('وصلاحيةُ كلِّ تبويبٍ هي صلاحيةُ شاشتِه — لا توسيعَ ولا تضييق', () {
      for (final tab in AccountingTab.values) {
        final id = tab.screenId;
        if (id == null) continue; // tpl — لا شاشةَ مسجَّلةً له
        expect(tab.permission, screenPermissionMap[id],
            reason: 'تبويبُ ${tab.label} يحرسه كودٌ يخالف شاشتَه = ثغرةٌ '
                'أو رابطٌ ميت');
      }
    });
  });

  group('الطيُّ لم يُسقط بلوغَ شاشة', () {
    test('كلُّ مدخلٍ مطويٍّ له تبويبٌ يفتحه', () {
      final reachable = AccountingTab.values
          .map((t) => t.screenId?.navigationIndex)
          .whereType<int>()
          .toSet();

      for (final folded in kPicPosFoldedIntoAccountingHub) {
        expect(reachable, contains(folded),
            reason: 'المدخلُ $folded طُوي من القائمة ولا تبويبَ يفتحه — '
                'شاشةٌ صارت غيرَ مبلوغة');
      }
    });

    test('والمطويُّ ستّةٌ — والسابعُ (قوالبُ القيود) لم يكن له مدخلٌ أصلاً', () {
      expect(kPicPosFoldedIntoAccountingHub, hasLength(6));
      expect(AccountingTab.tpl.screenId, isNull);
    });

    test('وكلُّ مطويٍّ ما زال مسجَّلاً: نطاقٌ وصلاحيةٌ ومعرِّف', () {
      for (final folded in kPicPosFoldedIntoAccountingHub) {
        final id = ScreenId.fromIndex(folded);
        expect(id, isNotNull, reason: 'رقمٌ مطويٌّ بلا معرِّف: $folded');
        expect(ScreenRegistry.unified, contains(id),
            reason: 'الطيُّ يمسّ المدخلَ لا المسار — و$id سقط من النطاق');
        expect(screenPermissionMap[id], isNotNull,
            reason: 'شاشةٌ بلا صلاحيةٍ بعد الطيّ = بابٌ مفتوحٌ أو مقفولٌ بلا قصد');
      }
    });

    test('و«الخزينة» **لم** تُطوَ — مدخلٌ مستقلٌّ في تصميم `NAV`', () {
      expect(kPicPosFoldedIntoAccountingHub,
          isNot(contains(ScreenId.treasury.navigationIndex)),
          reason: 'التصميمُ يضعها مدخلاً أعلى المستوى بجانب «الحسابات»');
      expect(
          kAllNavItemDefs
              .where((n) => n.index == ScreenId.treasury.navigationIndex),
          hasLength(1));
    });

    test('وما لا يذكره التصميمُ لم يُطوَ', () {
      // الشيكات · الأصول الثابتة · الفوترة الإلكترونية · السنوات المالية ·
      // المصروفات التشغيلية · إغلاق الوردية — لا ذكرَ لها في التصميم،
      // فتبقى كما هي. «وما لا يذكره التصميمُ لا يقرّره.»
      for (final index in [56, 34, 35, 22, 28, 26]) {
        expect(kPicPosFoldedIntoAccountingHub, isNot(contains(index)),
            reason: 'المدخلُ $index طُوي بلا سندٍ من التصميم');
      }
    });
  });
}
