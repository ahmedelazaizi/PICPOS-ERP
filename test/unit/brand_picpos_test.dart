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
import 'package:ural_erp/core/config/app_config.dart';
import 'package:ural_erp/core/config/brand.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/core/theme/app_theme.dart';
import 'package:ural_erp/data/database/connection_io.dart';

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
        ScreenId.parties,
      ]) {
        expect(screens, contains(inScope),
            reason: '$inScope جوّه نطاق lite المعلن');
      }
      for (final outOfScope in [
        ScreenId.tables,
        ScreenId.kitchen,
        ScreenId.hr,
        ScreenId.branches,
        ScreenId.regions,
        ScreenId.manufacturing,
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
  }, skip: skipReason);
}
