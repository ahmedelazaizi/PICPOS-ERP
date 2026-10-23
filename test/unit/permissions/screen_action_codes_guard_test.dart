// B-8 + B-1/B-2: حدودُ قاعدة «أيُّ كودِ فعلٍ يفتح الشاشة».
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/permissions/financial_figures_access.dart';
import 'package:ural_erp/core/permissions/screen_access_resolver.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/screen_access_selectors.dart';

void main() {
  group('B-8: screenActionCodes لا تمسّ الشاشاتِ الحسّاسة', () {
    // كودٌ أوّليٌّ حسّاسٌ: توسيعُ القاعدة لاحقاً يجب ألّا يكشف شاشتَه بكودٍ آخر.
    const sensitivePrimary = {
      'settings_view',
      'treasury_view',
      'reports_view',
      'users',
      'rolesAndPermissions',
    };

    test('لا شاشةَ كودُها الأوّليّ حسّاسٌ في screenActionCodes', () {
      for (final id in screenActionCodes.keys) {
        expect(sensitivePrimary.contains(screenPermissionMap[id]), isFalse,
            reason: '$id كودُها الأوّليّ ${screenPermissionMap[id]} حسّاسٌ '
                'ولا يجوز أن تفتحها أكوادُ أفعال');
      }
    });

    test('ولا أكوادٌ حسّاسةٌ بين أكواد الأفعال نفسِها', () {
      for (final e in screenActionCodes.entries) {
        for (final c in e.value) {
          expect(sensitivePrimary.contains(c), isFalse,
              reason: '${e.key} تحوي الكودَ الحسّاس $c');
        }
      }
    });

    test('الشاشاتُ الصارمة ليست في screenActionCodes أصلاً', () {
      for (final id in strictPermissionScreens) {
        expect(screenActionCodes.containsKey(id), isFalse, reason: '$id');
      }
    });

    test('سلوكيّاً: كودُ فعلٍ لا يفتح الإعداداتِ ولا الخزينةَ ولا التقارير', () {
      final everyActionCode = {
        for (final l in screenActionCodes.values) ...l,
      };
      for (final id in [
        ScreenId.settings,
        ScreenId.treasury,
        ScreenId.reports,
      ]) {
        // (users/rolesAndPermissions بلا مدخلٍ في screenPermissionMap؛
        //  تُحرَس داخل الإعدادات — يغطّيها فحصُ strictPermissionScreens أعلاه.)
        final primary = screenPermissionMap[id];
        expect(primary, isNotNull, reason: '$id بلا كود');
        // الكودُ الأوّليُّ نفسُه خارج المجموعة المفتوحة بأكواد الأفعال.
        final withoutPrimary = everyActionCode.difference({?primary});
        expect(
          canOpenScreen(withoutPrimary, id,
              primaryCode: primary, bypass: false),
          isFalse,
          reason: '$id تُفتح بأكواد أفعالٍ فقط',
        );
      }
    });
  });

  group('B-1/B-2 (قرارُ مالك F.2 — يوثّق السلوكَ القائمَ لا يغيّره)', () {
    // ⚠️ هذا الاختبارُ يوثّق قراراً: «أيُّ كودِ فعلٍ يفتح شاشةَ القائمة».
    //    إن تغيّر القرارُ فليُعدَّل هذا الاختبارُ عمداً مع قرار المالك.
    List<int> allowedFor(Set<String> perms) => selectAllowedScreenIndexes(
          navItems: kAllNavItemDefs,
          permissions: perms,
          bypass: false,
          eInvoicePlatform: null,
          flavorAllowed: ScreenId.values.toSet(),
        );

    test('دورٌ {pos_access, sales_create} يفتح فواتيرَ البيع (بلا sales_view)',
        () {
      final allowed = allowedFor({'pos_access', 'sales_create'});
      expect(allowed, contains(ScreenId.salesInvoices.navigationIndex));
      expect(allowed, contains(ScreenId.pos.navigationIndex));
      expect(
        canSeeScreenFigures({'pos_access', 'sales_create'}, ScreenId.salesInvoices),
        isFalse,
      );
      // AUTHZ-004: sales_view وحدَه لا يكشف أرقامَ الفواتير — يلزم معه
      // sales_amounts_view.
      expect(
        canSeeScreenFigures({'pos_access', 'sales_view'}, ScreenId.salesInvoices),
        isFalse,
      );
      expect(
        canSeeScreenFigures(
            {'pos_access', 'sales_view', 'sales_amounts_view'}, ScreenId.salesInvoices),
        isTrue,
      );
    });

    test('دورٌ {customers_add} يفتح العملاء والأطراف (بلا customers_view)', () {
      final allowed = allowedFor({'customers_add'});
      expect(allowed, contains(ScreenId.customers.navigationIndex));
      expect(allowed, contains(ScreenId.parties.navigationIndex));
    });

    test('ولا يفتح بها الإعداداتِ ولا الخزينةَ ولا التقارير', () {
      final allowed = allowedFor({'pos_access', 'sales_create', 'customers_add'});
      for (final id in [ScreenId.settings, ScreenId.treasury, ScreenId.reports]) {
        expect(allowed, isNot(contains(id.navigationIndex)), reason: '$id');
      }
    });
  });
}
