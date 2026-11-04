import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/presentation/treasury_picpos/screens/treasury_picpos_screen.dart';

void main() {
  test('cash-flow categories are translated, unknown categories keep raw names', () {
    I18nCatalog.setLocale(const Locale('en'));
    I18nCatalog.setCatalog({
      'مرتجع': 'Return',
      'عملاء': 'Customers',
      'موردين': 'Suppliers',
    });
    expect(cashFlowCategoryLabel('return'), 'Return');
    expect(cashFlowCategoryLabel('customer_payment'), 'Customers');
    expect(cashFlowCategoryLabel('supplier_payment'), 'Suppliers');
    expect(cashFlowCategoryLabel('sales'), 'مبيعات');
    expect(cashFlowCategoryLabel('unmapped_category'), 'unmapped_category');
  });
}
