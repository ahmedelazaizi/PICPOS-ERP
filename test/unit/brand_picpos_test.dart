// ═══════════════════════════════════════════════════════════════════════════
// PicPos — التحقق من فرع العلامة الثانية
// ═══════════════════════════════════════════════════════════════════════════
//
// الملف ده **بيتخطّى** في التشغيل العادي، وبيشتغل بس مع:
//
//   flutter test --dart-define=APP_BRAND=picpos test/unit/brand_picpos_test.dart
//
// وده أمر مدمج في سكربت بناء PicPos، فأي بناء للعلامة بيتحقق من هويتها قبل
// ما يطلع. الغرض إثبات إن الـ dart-define بيوصل فعلاً وإن كل قيمة هوية
// بتتبدّل — مش بس الاسم.
//
// اختبارات UralCash في `brand_isolation_test.dart`.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/config/app_config.dart';
// `BusinessProfile` و`FeaturePolicy` يصلان عبر `app_config.dart` المستورد
// فوق — استيرادُهما صراحةً يرفع خطَّ أساس analyze بلا فائدة.
import 'package:picpos_erp/core/config/brand.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';
import 'package:picpos_erp/core/navigation/screen_registry.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/data/database/connection_io.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';

void main() {
  // مفيش `skip` على مستوى الملف في flutter_test، فالبوابة على مستوى الجروب.
  const skipReason =
      Brand.isPicPos ? null : 'يشتغل فقط مع --dart-define=APP_BRAND=picpos';

  group('PicPos', () {
    test('الـ dart-define وصل والعلامة معروفة', () {
      expect(Brand.id, 'picpos');
      expect(Brand.isPicPos, isTrue);
      expect(Brand.isUralCash, isFalse);
      expect(Brand.isKnown, isTrue);
      expect(Brand.assertKnownBrand, returnsNormally);
    });

    test('الاسم اتبدّل في كل المصادر — مفيش UralCash متسرّب', () {
      expect(Brand.name, 'PicPos');
      expect(Brand.nameAr, 'بيك بوس');
      expect(AppConstants.appName, 'PicPos');
      expect(AppConfig.appName, isNot(contains('UralCash')));
      expect(AppConfig.appNameAr, isNot(contains('يورال')));
    });

    test('اللوجو من مجلد العلامة، مش لوجو UralCash', () {
      expect(Brand.logoAsset, 'assets/brand/picpos/logo.png');
      expect(Brand.logoAsset, isNot('logo.PNG'));
    });

    test('لوحة الألوان اتبدّلت للأزرق ومفيش تركواز متبقّي', () {
      // مسحوبة من ملف اللوجو نفسه.
      expect(AppColors.primary, const Color(0xFF0250D3));
      expect(AppColors.primaryDark, const Color(0xFF012258));

      // ألوان UralCash التركوازية ما تظهرش في أي فتحة مرتبطة بالعلامة.
      const uralTeal = [
        Color(0xFF2B737F),
        Color(0xFF134657),
        Color(0xFF469CA5),
        Color(0xFF1E4A5A),
      ];
      const brandSlots = [
        AppColors.primary,
        AppColors.primaryDark,
        AppColors.primaryLight,
        AppColors.info,
        AppColors.surfaceDark,
        AppColors.cardDark,
        AppColors.borderDark,
      ];
      for (final slot in brandSlots) {
        expect(uralTeal, isNot(contains(slot)),
            reason: 'لون تركواز من UralCash متسرّب في هوية PicPos');
      }
    });

    test('البيانات معزولة — مفيش ملف داتابيز مشترك مع UralCash', () {
      expect(Brand.dbPrefix, 'picpos');
      expect(Brand.dataFolderName, 'PicPos');
      // قاعدة PostgreSQL منفصلة — سيرفران على نفس نسخة PG كانوا هيتصادموا
      // على قاعدة اسمها `uralcash`.
      expect(Brand.pgIdentifier, 'picpos');
      // المستندات المطبوعة: أخطر تسريب — عميل مسجّلش اسم شركته كان بيطبع
      // فواتيره وعليها اسم منتج مش بتاعه.
      expect(Brand.documentCompanyFallback, 'PicPos');
      expect(Brand.documentCompanyFallback, isNot(contains('UralCash')));
      // النسخ الاحتياطي: مجلد مشترك = استعادة تكتب داتابيز منتج فوق التاني.
      expect(Brand.backupFolderName, 'PicPos_Backups');
      expect(Brand.backupFolderName, isNot(contains('UralCash')));
      expect(Brand.pgIdentifier, isNot(contains('uralcash')));
      // lowercase إجباري: PostgreSQL بيحوّل المُعرّفات غير المقتبسة لحروف صغيرة.
      expect(Brand.pgIdentifier, Brand.pgIdentifier.toLowerCase());
      for (final flavor in AppFlavor.values) {
        final name = databaseFileNameFor(flavor);
        expect(name, startsWith('picpos_'),
            reason: 'كل flavor لازم يكتب في ملف خاص بـ PicPos');
        expect(name, isNot(startsWith('uralcash')),
            reason: 'تصادم مع بيانات UralCash على نفس الجهاز');
      }
    });

    test('نطاق المنتج — بيقلع lite من غير ما يلمس اسم ملف الداتابيز', () {
      expect(Brand.defaultProfileCode, 'lite');
      expect(AppConfig.profile, BusinessProfile.lite);

      // ── التأكيدان دول هما سبب وجود `Brand.defaultProfileCode` أصلاً ──
      // البديل اللي اترفض كان `AppFlavor.lite` + بناء بـ `APP_FLAVOR=lite`.
      // اسم الملف مركّب `'${Brand.dbPrefix}_${flavor.code}.db'`، فده كان
      // هيحوّل PicPos من `picpos_unified.db` لـ `picpos_lite.db` — أي تركيب
      // قائم يدوّر على ملف مش موجود ويبدأ بداتابيز فاضية (فقد بيانات صامت).
      // لو التأكيدان دول فشلوا، يبقى حد ربط نطاق المنتج بالـ flavor تاني.
      expect(AppConfig.flavor, AppFlavor.unified);
      expect(getDatabaseFileName(), 'picpos_unified.db');

      final screens = AppConfig.allowedScreenIds;
      for (final inScope in [
        ScreenId.pos,
        ScreenId.inventory,
        ScreenId.treasury,
        ScreenId.reports,
        ScreenId.purchases,
        ScreenId.customers,
        ScreenId.suppliers,
        // قرار المالك 2026-09-28: التصنيع ظاهر في كل النطاقات ومحكوم بالصلاحية.
        ScreenId.manufacturing,
      ]) {
        expect(screens, contains(inScope),
            reason: '$inScope جوّه نطاق lite المعلن');
      }
      for (final outOfScope in [
        ScreenId.parties,
        ScreenId.tables,
        ScreenId.kitchen,
        ScreenId.hr,
        ScreenId.branches,
        ScreenId.regions,
        ScreenId.chartOfAccounts,
        ScreenId.offers,
      ]) {
        expect(screens, isNot(contains(outOfScope)),
            reason: '$outOfScope برّه نطاق lite — نقطة بيع + مخازن + صناديق + تقارير');
      }
    });

    test('الثيم — الشاشات المشتركة بتاخد لغة تصميم PicPos', () {
      // الشاشات الـ٣٠ (١٨٥٠٠ سطر) ما اتنسختش ولا اتعدّلت — شكلها كله بييجي
      // من `ThemeData` واحدة، والفرع ده هو اللي بيدّي PicPos شكله المستقل.
      //
      // بنتحقق من الفرع مش من `ThemeData` نفسها — بناؤها بيستدعي
      // `GoogleFonts` لأوزان مش مضمّنة في الـ assets فبيرمي في الاختبار.
      expect(AppTheme.designLanguage, 'picpos');
    });

    test('الملفُّ الشخصيُّ lite يفتح المطبخَ والإضافات لـPicPos', () {
      // `picpos_lite_kitchen_policy_test` يقيس الثابتَين نفسَيهما، لكنّ سطرَ
      // الاختيار `Brand.isPicPos ? litePicpos : lite` لا تقيسه البوابةُ
      // إطلاقاً — تشتغل على الافتراضي `uralcash`. فهذا هو الموضعُ الوحيدُ
      // الذي يُنفَّذ فيه الفرعُ، ومعه يتحقّق كلُّ بناءِ PicPos من أن
      // «إدارة الإضافات والمعدلات» ستُعرض فعلاً وأن حوارَ سطر السلّة سيظهر.
      final policy = FeaturePolicy.fromProfile(BusinessProfile.lite);
      expect(policy, FeaturePolicy.litePicpos);
      expect(policy.kitchenEnabled, isTrue);
      expect(policy.modifiersEnabled, isTrue);

      // ⚠️ وشاشةُ المطبخ تبقى خارجَ التنقّل — مؤكَّدٌ فوق في اختبار نطاق
      // الشاشات. العلَمُ يفتح الإعداداتِ وحوارَ السلّة لا شاشةَ KDS.
    });

    test('✅ طيُّ «الحسابات» **رُفِع** — ولا يعود بلا قرار', () {
      // ⚠️ هذا هو الموضعُ الوحيدُ الذي يُنفَّذ فيه فرعُ PicPos من
      // `navItemVisibleForBrand`: البوّابةُ تشتغل على `uralcash`، فطيٌّ
      // يعود سهواً يمرّ خضراءَ عندها ويختفي للمستخدم وحدَه.
      //
      // حُذفت الحاويةُ 2026-09-20 وصارت تبويباتُها شاشاتٍ تحت رأسَين.
      // والثابتةُ باقيةٌ **فارغةً** لا محذوفةً: أوّلُ من يملؤها يُعيد
      // السلوكَ كلَّه بسطر، وهذا يمنعه.
      expect(kPicPosFoldedIntoAccountingHub, isEmpty,
          reason: 'عاد الطيُّ — والقرارُ شاشاتٌ مستقلّةٌ تحت رأسَين');

      // والمداخلُ التي كانت مطويّةً تُرى الآن في PicPos.
      for (final idx in const [27, 32, 33, 36]) {
        expect(navItemVisibleForBrand(idx), isTrue,
            reason: 'المدخلُ $idx ما زال مطويّاً بعد رفع الطيّ');
      }

      // «الخزينة» مدخلٌ مستقلٌّ في التصميم ولم تُطوَ قطّ.
      expect(navItemVisibleForBrand(ScreenId.treasury.navigationIndex), isTrue);
    });

    // E-fix ٣ — الفصلُ («الإدارة المالية» / «إدارة الحسابات») لـPicPos وحدَه.
    test('رأسا المالية مفصولان في PicPos، ولا رأسَ «اليومية العامة»', () {
      final labels = {for (final g in kNavGroupDefs) g.key: g.label};
      expect(labels['accounting'], 'الإدارة المالية');
      expect(labels['accounts'], 'إدارة الحسابات');
      expect(labels.containsKey('journal'), isFalse);
      expect(kAllNavItemDefs.where((i) => i.group == 'journal'), isEmpty);
      expect(
          [for (final i in kAllNavItemDefs) if (i.group == 'accounting') i.index],
          [68, 69, 34, 70, 10, 56]);
    });

    // E-fix ٤ب — «التوزيع» القديمة (٢٤) تُخفى وتحلّ محلَّها ٧٨.
    test('«إدارة المناديب والتوزيع» تحلّ محلَّ «التوزيع» القديمة', () {
      expect(navItemVisibleForBrand(ScreenId.distribution.navigationIndex),
          isFalse);
      expect(navItemVisibleForBrand(ScreenId.repDistribution.navigationIndex),
          isTrue);
      final scope = ScreenRegistry.forProfile(BusinessProfile.unified);
      expect(scope, isNot(contains(ScreenId.distribution)));
      expect(scope, contains(ScreenId.repDistribution));
      expect(screenPermissionMap[ScreenId.distribution], 'distribution_view',
          reason: 'الصلاحيةُ باقية');
    });

    test('يستبدل مدخل الأطراف بمدخلي العملاء والموردين', () {
      expect(navItemVisibleForBrand(ScreenId.parties.navigationIndex), isFalse);
      expect(navItemVisibleForBrand(ScreenId.customers.navigationIndex), isTrue);
      expect(navItemVisibleForBrand(ScreenId.suppliers.navigationIndex), isTrue);

      final scope = ScreenRegistry.forProfile(BusinessProfile.unified);
      expect(scope, isNot(contains(ScreenId.parties)));
      expect(scope, containsAll(<ScreenId>[
        ScreenId.customers,
        ScreenId.suppliers,
      ]));
    });

    test('والشاشاتُ الثلاثُ المتقاعدةُ تختفي من قائمة PicPos', () {
      // أمرُ المالك 2026-09-12. وهذا — كسابقِه — الموضعُ **الوحيدُ** الذي
      // يُنفَّذ فيه فرعُ PicPos من `navItemVisibleForBrand`: سجلُّ التقاعد
      // قد يُكتَب صحيحاً ولا يُوصَل بالبوّابة، فيمرّ كلُّ شيءٍ أخضرَ
      // والمداخلُ الثلاثةُ ما زالت في الشريط.
      for (final retired in kPicPosRetiredNavIndexes) {
        expect(navItemVisibleForBrand(retired), isFalse,
            reason: 'المدخلُ $retired ما زال يظهر — التقاعدُ غيرُ موصول');
      }

      // وجارتُها في نفس المجموعة تبقى: `حركة المخزون` (29).
      expect(navItemVisibleForBrand(ScreenId.stockMovements.navigationIndex),
          isTrue);

      // والنطاقُ يُسقط **اثنتَين منها** — الشريطُ وحدَه لا يمنع البلوغَ
      // بالفهرس.
      //
      // 🔴 **و«التكاليف المحملة» (41) ليست منها — عن قصدٍ مكتوب.** سطرُها
      //    في [kPicPosRetiredNavIndexes] يقول حرفاً: «مخفيّةٌ من القائمة،
      //    **مبلوغةٌ** من شاشة الاستيراد». فإسقاطُها من النطاق يقطع بابَها
      //    الوحيدَ الباقي.
      //
      // ⚠️ **وكان هذا التوكيدُ أحمرَ قبل 2026-09-20 ولم يره أحد**: الملفُّ
      //    كلُّه `skip` بلا `--dart-define=APP_BRAND=picpos`، فلا تُشغّله
      //    سويّةُ `unit` إطلاقاً — يشغّله سكربتُ بناء PicPos وحدَه. وهو
      //    عينُ الخطر الذي يحرسه هذا الملفّ: فرعٌ لا يُنفَّذ في البوّابة.
      final scope = ScreenRegistry.forProfile(BusinessProfile.unified)
          .map((s) => s.navigationIndex);
      const reachableElsewhere = {41}; // التكاليف المحملة ← شاشةُ الاستيراد
      for (final retired in kPicPosRetiredNavIndexes) {
        if (reachableElsewhere.contains(retired)) {
          expect(scope, contains(retired),
              reason: 'الشاشةُ $retired مخفيّةٌ من الشريط و**مبلوغةٌ** من '
                  'شاشة الاستيراد — إسقاطُها من النطاق يقطع بابَها');
          continue;
        }
        expect(scope, isNot(contains(retired)),
            reason: 'الشاشةُ $retired ما زالت في نطاق PicPos');
      }
    });
  }, skip: skipReason);
}
