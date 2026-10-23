// عروض الأسعار — شاشةٌ مستقلّةٌ تحت «فواتير المبيعات» (طلبُ المالك).
//
// كانت تبويباً ثانياً داخل شاشة فواتير البيع في PicPos. صارت شاشةً لها
// معرِّفٌ ومدخلٌ جانبيٌّ ومسارٌ وصلاحيّةٌ — والمواضعُ الستّةُ نفسُها التي
// يحرسها `bookings_screen_wiring_test` يجب أن تتّفق هنا أيضاً.
//
// شغّله بـ `--dart-define=APP_BRAND=picpos` ليُقاس نطاقُ PicPos الفعليّ.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/config/brand.dart';
import 'package:picpos_erp/core/config/business_profile.dart';
import 'package:picpos_erp/core/enums/app_screen.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';
import 'package:picpos_erp/core/navigation/screen_registry.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/presentation/shell/screen_breadcrumbs.dart';

void main() {
  group('عروض الأسعار موصولةٌ في كلّ موضع', () {
    test('المعرِّفُ و`AppScreen` يحملان الرقمَ نفسَه', () {
      expect(ScreenId.quotations.navigationIndex, 75);
      expect(AppScreen.quotations.value, ScreenId.quotations.navigationIndex);
    });

    test('صلاحيّتُها `quotes_view` في الخريطة وفي المدخل الجانبيّ', () {
      expect(screenPermissionMap[ScreenId.quotations],
          PermissionCodes.quotesView);
      final item = kAllNavItemDefs
          .where((n) => n.index == ScreenId.quotations.navigationIndex)
          .toList();
      expect(item, hasLength(1));
      expect(item.single.label, 'عروض الأسعار');
      expect(item.single.group, 'sales');
      expect(item.single.permission, screenPermissionMap[ScreenId.quotations]);
    });

    test('المدخلُ الجانبيُّ مباشرةً تحت «فواتير المبيعات»', () {
      final salesItems =
          kAllNavItemDefs.where((n) => n.group == 'sales').toList();
      final invoices = salesItems.indexWhere(
          (n) => n.index == ScreenId.salesInvoices.navigationIndex);
      expect(invoices, isNonNegative);
      expect(salesItems[invoices + 1].index,
          ScreenId.quotations.navigationIndex);
    });

    test('ومسارُها «المبيعات ‹ عروض الأسعار»', () {
      final path = resolveScreenPath(ScreenId.quotations.navigationIndex);
      expect(path, isNotNull);
      expect(path!.label, 'عروض الأسعار');
      expect(path.groupLabel, isNotNull);
    });

    test('وفي نطاق PicPos تأتي بعد فواتير المبيعات مباشرةً', () {
      final withQuotes = ScreenRegistry.withPicposQuotations(
          [ScreenId.pos, ScreenId.salesInvoices, ScreenId.purchases]);
      expect(withQuotes, [
        ScreenId.pos,
        ScreenId.salesInvoices,
        ScreenId.quotations,
        ScreenId.purchases,
      ]);
      if (Brand.isPicPos) {
        final unified = ScreenRegistry.forProfile(BusinessProfile.unified);
        final invoices = unified.indexOf(ScreenId.salesInvoices);
        expect(invoices, isNonNegative);
        expect(unified[invoices + 1], ScreenId.quotations);
        expect(navItemVisibleForBrand(ScreenId.quotations.navigationIndex),
            isTrue);
      } else {
        expect(navItemVisibleForBrand(ScreenId.quotations.navigationIndex),
            isFalse,
            reason: 'UralCash ما زال يعرض عروض الأسعار داخل شاشته الأصليّة');
      }
    });
  });

  group('شاشة فواتير البيع في PicPos', () {
    final source = File(
      'lib/presentation/sales_invoices_picpos/screens/'
      'sales_invoices_picpos_screen.dart',
    ).readAsStringSync();

    test('بلا زرّ «طلبات البيع»', () {
      expect(source, isNot(contains("tr('طلبات البيع')")));
      expect(source, isNot(contains('SalesOrdersScreen')));
    });

    test('بلا تبويب عروض الأسعار — والتحويلُ لفاتورة ما زال موصولاً', () {
      expect(source, isNot(contains('TabBar(')));
      expect(source, isNot(contains('TabBarView(')));
      expect(source, contains('onConvertQuotation:'));
      expect(source, contains('isConvert: true'));
    });
  });
}
