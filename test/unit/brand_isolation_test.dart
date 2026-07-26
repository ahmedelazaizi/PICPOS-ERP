// ═══════════════════════════════════════════════════════════════════════════
// Brand — عزل الهوية والبيانات بين المنتجات المستقلة
// ═══════════════════════════════════════════════════════════════════════════
//
// الاختبارات دي بتتنفّذ من غير `--dart-define=APP_BRAND`, يعني على العلامة
// الافتراضية `uralcash`. الغرض الأساسي منها **مش** اختبار PicPos — ده
// اختبار انحدار على UralCash:
//
//   أسماء ملفات الداتابيز الـ ٧ لازم تفضل حرف بحرف زي ما كانت قبل إدخال
//   طبقة العلامات. أي تغيير في السلاسل دي معناه إن كل تركيب قائم عند عميل
//   هيدوّر على ملف مش موجود ويبدأ بداتابيز فاضية — فقد بيانات صامت.
//
// السلاسل المتوقعة اتاخدت من `getDatabaseFileName()` قبل الـ refactor.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/config/app_config.dart';
import 'package:ural_erp/core/config/brand.dart';
import 'package:ural_erp/data/database/connection_io.dart';

void main() {
  group('Brand — العلامة الافتراضية', () {
    test('البناء من غير APP_BRAND بيقع على uralcash', () {
      expect(Brand.id, 'uralcash');
      expect(Brand.isUralCash, isTrue);
      expect(Brand.isPicPos, isFalse);
      expect(Brand.isKnown, isTrue);
    });

    test('الأسماء والأصول والمسارات بتاعت UralCash ما اتغيرتش', () {
      expect(Brand.name, 'UralCash');
      expect(Brand.nameAr, 'يورال كاش');
      expect(Brand.logoAsset, 'logo.PNG');
      expect(Brand.dbPrefix, 'uralcash');
      expect(Brand.dataFolderName, 'UralCash');
      // افتراضي PostgreSQL للتنصيبات الجديدة — لو اتغيّر، معالج تنصيب جديد
      // هيجهّز قاعدة باسم مختلف عن كل التركيبات القائمة.
      expect(Brand.pgIdentifier, 'uralcash');
      expect(Brand.backupFolderName, 'UralCash_Backups');
      expect(Brand.documentCompanyFallback, 'UralCash Market');
    });

    test('assertKnownBrand ما بترميش على علامة معروفة', () {
      expect(Brand.assertKnownBrand, returnsNormally);
    });
  });

  group('الأسماء الظاهرة — انحدار', () {
    // السلاسل الحرفية زي ما كانت مكتوبة في app_flavor.dart قبل ربطها بـ
    // Brand. الاشتقاق لازم يدّي نفس الناتج بالظبط لـ UralCash.
    const expectedEn = <AppFlavor, String>{
      AppFlavor.unified: 'UralCash',
      AppFlavor.restaurant: 'UralCash Restaurant',
      AppFlavor.cafe: 'UralCash Cafe',
      AppFlavor.supermarket: 'UralCash Market',
      AppFlavor.supermarketPro: 'UralCash Market Pro',
      AppFlavor.supermarketPlus: 'UralCash Market Plus',
      AppFlavor.commercial: 'UralCash Commercial',
    };

    const expectedAr = <AppFlavor, String>{
      AppFlavor.unified: 'يورال كاش',
      AppFlavor.restaurant: 'يورال كاش - المطاعم',
      AppFlavor.cafe: 'يورال كاش - الكافيهات',
      AppFlavor.supermarket: 'يورال كاش - السوبرماركت',
      AppFlavor.supermarketPro: 'يورال كاش - السوبرماركت برو',
      AppFlavor.supermarketPlus: 'يورال كاش - السوبرماركت بلس',
      AppFlavor.commercial: 'يورال كاش - التجاري',
    };

    test('الاسم الإنجليزي لكل flavor ما اتغيرش', () {
      for (final e in expectedEn.entries) {
        expect(e.key.appName, e.value);
      }
      expect(expectedEn.keys.toSet(), AppFlavor.values.toSet());
    });

    test('الاسم العربي لكل flavor ما اتغيرش', () {
      for (final e in expectedAr.entries) {
        expect(e.key.appNameAr, e.value);
      }
      expect(expectedAr.keys.toSet(), AppFlavor.values.toSet());
    });

    test('AppConfig بيعرض اسم الـ flavor الحالي', () {
      expect(AppConfig.appName, expectedEn[AppConfig.flavor]);
      expect(AppConfig.appNameAr, expectedAr[AppConfig.flavor]);
    });
  });

  group('عزل ملف الداتابيز — انحدار حرج', () {
    // كل flavor واسم ملفه الحرفي قبل الـ refactor. القايمة دي عقد مع كل
    // تركيب قائم — متعدّلهاش إلا مع ترحيل مقصود ينقل الملف القديم.
    const expected = <AppFlavor, String>{
      AppFlavor.unified: 'uralcash_unified.db',
      AppFlavor.restaurant: 'uralcash_restaurant.db',
      AppFlavor.cafe: 'uralcash_cafe.db',
      AppFlavor.supermarket: 'uralcash_supermarket.db',
      AppFlavor.supermarketPro: 'uralcash_supermarket_pro.db',
      AppFlavor.supermarketPlus: 'uralcash_supermarket_plus.db',
      AppFlavor.commercial: 'uralcash_commercial.db',
    };

    test('كل flavor لسه بيدّي نفس اسم الملف بالظبط', () {
      for (final entry in expected.entries) {
        expect(
          databaseFileNameFor(entry.key),
          entry.value,
          reason: 'تغيير اسم ملف ${entry.key} = فقد بيانات عند العملاء',
        );
      }
    });

    test('القايمة بتغطي كل flavor — flavor جديد لازم ياخد قرار صريح', () {
      expect(expected.keys.toSet(), AppFlavor.values.toSet());
    });

    test('الدالة الحية بتوافق الـ flavor الحالي', () {
      expect(getDatabaseFileName(), expected[AppConfig.flavor]);
    });

    test('كل الأسماء فريدة — منتجان ما بيشاركوش ملف', () {
      expect(expected.values.toSet(), hasLength(expected.length));
    });
  });
}
