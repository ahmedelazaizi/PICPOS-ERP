// ═══════════════════════════════════════════════════════════════════════════
// حارسُ دخانٍ لكلّ شاشةِ تقرير — تُفتَح فتُرسَم، بلا استثناءٍ وبلا فيضان.
// ═══════════════════════════════════════════════════════════════════════════
//
// لم يكن في المستودع اختبارٌ **يفتح** شاشةَ تقريرٍ أصلاً: تغطيةُ الواجهات
// كلُّها على الصلاحيات والورديات. فعطلُ التخطيط أو استثناءُ البناء لا يظهر
// إلا للمستخدم — ومقيسٌ أن الفئة حقيقية، فقد ظهر فيضانٌ أفقيّ في رأس
// `report_builder_screen` بالمصادفة حين فتحه اختبارٌ لأوّل مرة.
//
// ── ما يفحصه ─────────────────────────────────────────────────────────────
// أن الشاشة **تُرسَم**: لا استثناءَ في البناء ولا `RenderFlex overflow`.
// لا يفحص صحّةَ الأرقام — لذلك سويّاتُ الوحدات.
//
// وتفاصيلُ التجهيزة وسببُ التعليق الذي كان يمنع هذا الملفَّ كلَّه:
// `_support/screen_smoke.dart`.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/screens/reports/ar_aging_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/category_profit_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/consumption_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/delivery_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/expenses_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/inventory_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/purchase_returns_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/purchases_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/sales_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/sales_returns_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/shifts_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/tax_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/top_products_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/treasury_report_screen.dart';
import 'package:ural_erp/presentation/screens/reports/vat_reconciliation_screen.dart';

import '_support/screen_smoke.dart';

/// كلُّ شاشةِ تقريرٍ ذاتِ مُنشئٍ بلا معاملاتٍ مطلوبة.
///
/// ⚠️ القائمةُ يدويةٌ لأن Dart لا يعدّد الأصناف وقت التشغيل — ويحرسها
/// `test/structural/report_screens_all_smoked_test.dart` فيفشل لأيّ شاشةٍ
/// تُضاف تحت `screens/reports/` ولا تُدرَج هنا.
final Map<String, Widget Function()> reportScreens = {
  'ArAgingReportScreen': () => const ArAgingReportScreen(),
  'CategoryProfitReportScreen': () => const CategoryProfitReportScreen(),
  'ConsumptionReportScreen': () => const ConsumptionReportScreen(),
  'DeliveryReportScreen': () => const DeliveryReportScreen(),
  'ExpensesReportScreen': () => const ExpensesReportScreen(),
  'InventoryReportScreen': () => const InventoryReportScreen(),
  'PurchaseReturnsReportScreen': () => const PurchaseReturnsReportScreen(),
  'PurchasesReportScreen': () => const PurchasesReportScreen(),
  'SalesReportScreen': () => const SalesReportScreen(),
  'SalesReturnsReportScreen': () => const SalesReturnsReportScreen(),
  'ShiftsReportScreen': () => const ShiftsReportScreen(),
  'TaxReportScreen': () => const TaxReportScreen(),
  'TopProductsReportScreen': () => const TopProductsReportScreen(),
  'TreasuryReportScreen': () => const TreasuryReportScreen(),
  'VatReconciliationScreen': () => const VatReconciliationScreen(),
};

void main() {
  for (final entry in reportScreens.entries) {
    testWidgets('${entry.key} تُرسَم بلا استثناءٍ ولا فيضان',
        timeout: const Timeout(Duration(seconds: 45)), (tester) async {
      final error = await pumpScreen(tester, entry.value);
      expect(error, isNull,
          reason: 'الشاشةُ رمت أو فاضت أثناء البناء — يراها المستخدمُ '
              'شاشةً حمراء أو عموداً مقصوصاً');
    });
  }
}
