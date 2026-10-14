// حارسُ العقد: **«فئات الأصول» و«التوزيع والمواقع» شاشتان تكتبان وموصولتان.**
//
// ═══ ما يُحرَس هنا ولماذا ═══
//
// ‏١) 🔴 **PicPos بلا كاتبٍ لفئة الأصول.** الحواران الوحيدان في المستودع
//    (`showCreateAssetCategoryDialog` وأختُها) **`part`** من شاشة UralCash
//    `fixed_assets_screen.dart`، والفوركُ لا يبلغهما ولا يستطيع: الملفُّ
//    جزءٌ من ملفٍّ آخرَ لا مكتبةٌ تُستورَد. و`createFixedAsset` تشترط
//    `categoryId` — فشاشةُ الأصول كلُّها لا تُستعمَل على تنصيبةٍ جديدة.
//
//    **وقِيس أحمرَ قبل أن يُكتَب**: `grep` على المستودع كلِّه لم يجد لهاتَين
//    الدالّتَين منادياً واحداً في أيّ ملفِّ PicPos.
//
// ‏٢) 🔴 **وحساباتُ الفئة تفصيليّةٌ نشطةٌ وحدَها.** `accounting_dao_writes`
//    يرفض الترحيلَ على حسابٍ طبيعتُه `view`، وقيدُ الاقتناء يُرحَّل على
//    حساب الفئة. فحسابٌ رئيسيٌّ فيها = فئةٌ لا يُسجَّل تحتها أصلٌ أبداً،
//    والرفضُ يقع في آخر نموذجِ الأصل الطويل.
//
// ‏٣) 🔴 **وإعادةُ تسميةِ الموقع تُخطَّط خالصةً ثمّ تُكتَب على كلّ أصل.**
//    العمودُ نصٌّ حرّ، والتسميةُ كتابةٌ على صفوفٍ متعدّدةٍ لا رجعةَ فيها.
//
// ‏٤) **والتوصيلُ ستّةُ مواضع** — وحارسٌ يقيس خمسةً من ستّةٍ يُعطي طمأنينةً
//    كاذبة (وقع مع الحجوزات مرّتين).
//
// ‏٥) **والتبويبتان لا تبقيان في مكانَين**: شاشةُ الأصول كانت خمسةَ
//    تبويباتٍ فصارت ثلاثة، و`_tabNotes` تُفهرَس بـ`_tabs.index` — فسطرٌ
//    زائدٌ يُظهر شرحَ الفئات تحت الاستبعاد.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_source.dart';
import 'package:ural_erp/core/config/brand.dart';
import 'package:ural_erp/core/enums/app_screen.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/navigation/screen_registry.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r`.
///
/// ⚠️ **والتعليقُ يُسقَط قبل العدّ**: هذه الملفّاتُ تذكر أنماطَها في شرحها
/// فوقَ تنفيذها حرفيّاً.
String _code(String path) => [
  for (final line in readLibrarySource(path).split('\n'))
    if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
].join('\n');

int _count(String haystack, String needle) {
  var n = 0;
  var i = haystack.indexOf(needle);
  while (i != -1) {
    n++;
    i = haystack.indexOf(needle, i + needle.length);
  }
  return n;
}

const _cats =
    'lib/presentation/fixed_assets_picpos/screens/asset_categories_picpos_screen.dart';
const _locs =
    'lib/presentation/fixed_assets_picpos/screens/asset_locations_picpos_screen.dart';
const _plan = 'lib/domain/models/asset_location_plan.dart';
const _screen =
    'lib/presentation/fixed_assets_picpos/screens/fixed_assets_picpos_screen.dart';
const _writes = 'lib/data/database/daos/accounting_dao_writes.dart';

void main() {
  test('🔴 لفئةِ الأصول كاتبٌ في PicPos — إنشاءً وتعديلاً', () {
    final code = _code(_cats);
    expect(
      code.contains('createAssetCategory('),
      isTrue,
      reason:
          '🔴 لا فئةَ تُنشأ في PicPos — و`createFixedAsset` تشترط '
          '`categoryId`، فشاشةُ الأصول كلُّها لا تُستعمَل على تنصيبةٍ '
          'جديدة',
    );
    expect(
      code.contains('updateAssetCategoryById('),
      isTrue,
      reason: 'فئةٌ ناقصةُ الربط لا سبيلَ لإصلاحها',
    );
  });

  test('🔴 وحساباتُها تفصيليّةٌ نشطةٌ وحدَها', () {
    final code = _code(_cats);
    // ⚠️ **يُقرأ جسمُ الشرط لا وجودُ اسمِ الدالّة**: أوّلُ صيغةٍ كانت
    //    `contains('isPostableAccount')` — واسمُ الدالّة يبقى مكتوباً مهما
    //    صار جسمُها `=> true`، فتعرض القائمةُ كلَّ حسابٍ في الدليل ولا شيءَ
    //    يبدو معطوباً حتى يُرفَض قيدُ الاقتناء.
    final at = code.indexOf('bool isPostableAccount(');
    expect(at, greaterThan(0), reason: 'شرطُ صلاحيةِ الحساب اختفى');
    final body = code.substring(at, code.indexOf(';', at));
    expect(
      body.contains("!= 'view'"),
      isTrue,
      reason:
          '🔴 حسابٌ رئيسيٌّ في الفئة = فئةٌ لا يُسجَّل تحتها أصلٌ '
          'أبداً — والمحرّكُ يرفض الترحيلَ عليه',
    );
    expect(
      body.contains('isActive'),
      isTrue,
      reason: 'حسابٌ موقوفٌ يُختار اليومَ ويُرفَض غداً',
    );
    expect(
      code.contains('isPostableAccount(a.accountNature, a.isActive)'),
      isTrue,
      reason: 'الشرطُ معرَّفٌ ولا يُنادى — فالقائمةُ غيرُ مرشَّحة',
    );

    // ومرساةٌ: المحرّكُ **يرفض** فعلاً، وإلّا صار الترشيحُ بلا معنى.
    expect(
      _code(_writes).contains('حساب رئيسي'),
      isTrue,
      reason:
          'رفضُ الترحيل على الحساب الرئيسيِّ اختفى من المحرّك — '
          'فالفحصُ أعلاه صار بلا سند',
    );
  });

  test('🔴 والعمرُ بالشهور بلا ×١٢ بيدها', () {
    for (final f in [_cats, _locs]) {
      final code = _code(f);
      expect(
        code.contains('* 12'),
        isFalse,
        reason: '🔴 حسابُ شهورٍ بيده في $f — والرقمُ يعود إلى حقل سنوات',
      );
      expect(code.contains('/ 12'), isFalse, reason: 'قسمةٌ بيدها في $f');
    }
    expect(
      _code(_cats).contains('usefulLifeYearsFromMonths('),
      isTrue,
      reason:
          'اللوحُ يعطي شهوراً والعمودُ سنوات — والتمريرُ كما هو يجعل '
          '٣٠ شهراً ثلاثين سنة',
    );
  });

  test('🔴 وإعادةُ التسمية تُخطَّط خالصةً وتُكتَب على كلّ أصل', () {
    expect(
      _code(_plan).contains('AssetLocationRenamePlan planAssetLocationRename('),
      isTrue,
    );
    final code = _code(_locs);
    expect(
      code.contains('planAssetLocationRename('),
      isTrue,
      reason: 'الشاشةُ تخطّط بيدها — والخطّةُ الخالصةُ هي ما يُقاس',
    );
    // 🔴 **حلقةٌ على `plan.assetIds` لا كتابةٌ واحدة**: الموقعُ صفُّ جدولٍ
    //    مشتقٌّ لا صفُّ قاعدة، فكتابةٌ واحدةٌ لا تنقل شيئاً.
    expect(
      code.contains('for (final id in plan.assetIds)'),
      isTrue,
      reason: '🔴 الموقعُ ليس صفّاً يُحدَّث — هو نصٌّ على كلّ أصل',
    );
    expect(code.contains('location: plan.target'), isTrue);
  });

  test('والتبويبتان خرجتا من شاشة الأصول ولم تبقيا في مكانَين', () {
    final code = _code(_screen);
    expect(
      code.contains('_categoriesTab('),
      isFalse,
      reason: 'جدولُ الفئات في موضعَين يفترقان عند أوّل تعديل',
    );
    expect(code.contains('_distributionTab('), isFalse);
    expect(
      code.contains('TabController(length: 3'),
      isTrue,
      reason: 'عددُ التبويبات خالف ما يُبنى — و`TabBarView` ترمي',
    );
    // ⚠️ `_tabNotes` تُفهرَس بـ`_tabs.index` — وطولُها يجب أن يساويه.
    expect(_count(code, "    '"), greaterThan(0));
    final tabNotes = RegExp(
      r'static (?:final _tabNotes =|List<String> get _tabNotes =>) \[',
    ).firstMatch(code);
    expect(tabNotes, isNotNull);
    final notes = code.substring(
      tabNotes!.start,
      code.indexOf('];', tabNotes.start),
    );
    expect(
      _count(notes, "'),"),
      3,
      reason: 'سطرٌ زائدٌ يُظهر شرحَ تبويبةٍ خرجت تحت تبويبةٍ باقية',
    );
  });

  group('والتوصيلُ ستّةُ مواضعَ لكلٍّ منهما', () {
    const expected = <ScreenId, ({int index, String label, AppScreen screen})>{
      ScreenId.assetCategories: (
        index: 65,
        label: 'فئات الأصول',
        screen: AppScreen.assetCategories,
      ),
      ScreenId.assetLocations: (
        index: 66,
        label: 'التوزيع والمواقع',
        screen: AppScreen.assetLocations,
      ),
    };

    expected.forEach((id, e) {
      test('«${e.label}»', () {
        // ‏١) معرِّفُ الشاشة.
        expect(id.navigationIndex, e.index);
        // ‏٢) و`AppScreen` بنفس الرقم.
        expect(
          e.screen.value,
          id.navigationIndex,
          reason:
              'الرقمان مصدرُ حقيقةٍ في نظامَين — وانحرافُهما يفتح '
              'شاشةً غيرَ التي أذنت بها الصلاحية',
        );
        // ‏٣) وصلاحيّةٌ في الخريطة — وهي صلاحيةُ شاشة الأصول نفسُها.
        expect(
          screenPermissionMap[id],
          'assets_view',
          reason:
              'كودٌ جديدٌ يترك كلَّ دورٍ قائمٍ بلا الشاشة حتى يُمنح '
              'يدويّاً، ويمسّ سجلَّ التكافؤ',
        );
        // ‏٤) والنطاقُ نطاقُ شاشة الأصول بالضبط.
        expect(
          ScreenRegistry.unified,
          contains(id),
          reason:
              'الحلقةُ ترشّح بالنطاق **قبل** الصلاحية — فالنقصانُ '
              'يُسقطها حتى عن مدير النظام',
        );
        expect(
          ScreenRegistry.lite.contains(id),
          isFalse,
          reason: 'ملفٌّ بلا شاشةِ أصولٍ لا يحتاج فئاتِها',
        );
        // ‏٥) و`ScreenConfig` تبنيها.
        expect(
          _code(
            'lib/app_main_screen.dart',
          ).contains('appScreen: AppScreen.${e.screen.name},'),
          isTrue,
          reason: 'شاشةٌ بلا بانٍ تفتح فراغاً',
        );
        // ‏٦) ومدخلٌ في القائمة الجانبيّة — المصدرُ السادسُ المستقلّ.
        final item = kAllNavItemDefs.where((n) => n.index == e.index).toList();
        expect(
          item,
          hasLength(1),
          reason: 'بلا مدخلٍ هنا لا يراها المستخدمُ مهما صحّ الباقي',
        );
        expect(item.single.label, e.label);
        // E1 — شاشاتُ الأصول تحت «إدارة الحسابات» (‏`accounts`).
        // E-fix ٣ — في PicPos وحدَه؛ UralCash على «المالية والمحاسبة».
        expect(item.single.group, Brand.isPicPos ? 'accounts' : 'accounting');
        expect(
          item.single.permission,
          screenPermissionMap[id],
          reason:
              'صلاحيّةٌ في القائمة تخالف الخريطةَ تُظهر مدخلاً يفتح '
              'شاشةً ممنوعة',
        );
      });
    });

    // ⚠️ **الترتيبُ أمرُ مالكٍ 2026-09-18** — والشريطُ يبنيه من موضع
    //    المداخل في `kAllNavItemDefs` لا من `kNavGroupDefs`.
    test('وترتيبُ صدرِ المجموعة كما طلب المالك', () {
      final accounting = [
        for (final n in kAllNavItemDefs)
          if (n.group == 'accounting') n.label,
      ];
      // ⚠️ **وصدرُ المجموعة بدأ بـ«سند قبض» منذ 2026-09-20**: كان
      //    `journalEntriesScreenLabel` أوّلَه، ونُقلت «اليومية العامة» إلى
      //    رأسِ مجموعةٍ خاصٍّ بها بأمر المالك. والترتيبُ النسبيُّ للستّة
      //    الباقية **كما طلبه المالكُ حرفاً** — النقلُ أزاح ولم يُرتّب.
      //
      // E1 (قرارُ المالك): «الإدارة المالية» صارت السنداتِ والشيكاتِ
      // والخزينةَ والوردية وحدَها، وانتقل «سند قيد» والأصولُ إلى «إدارة
      // الحسابات» — والترتيبُ النسبيُّ للمنقولة بقي كما طلبه المالك.
      expect(accounting.take(3).toList(), [
        'سند قبض',
        'سند صرف',
        chequesScreenLabel,
      ]);
      // E-fix ٣ — UralCash على ترتيبه قبل المرحلة هـ: صدرُ «المالية
      // والمحاسبة» السبعةُ كما طلبها المالك 2026-09-18.
      if (!Brand.isPicPos) {
        expect(accounting.take(7).toList(), [
          'سند قبض',
          'سند صرف',
          chequesScreenLabel,
          'سند قيد',
          'فئات الأصول',
          'التوزيع والمواقع',
          'دفتر الشيكات',
        ]);
        return;
      }
      expect(accounting, isNot(contains('سند قيد')));

      final accounts = [
        for (final n in kAllNavItemDefs)
          if (n.group == 'accounts') n.label,
      ];
      final at = accounts.indexOf('سند قيد');
      expect(at, greaterThanOrEqualTo(0));
      expect(accounts.sublist(at, at + 3), [
        'سند قيد',
        'فئات الأصول',
        'التوزيع والمواقع',
      ]);

      // و«اليومية العامة» صدرُ ما دُمج منها في «إدارة الحسابات».
      expect(accounts, contains(journalEntriesScreenLabel));
      expect(accounts.indexOf(journalEntriesScreenLabel), lessThan(at));
    });
  });
}
