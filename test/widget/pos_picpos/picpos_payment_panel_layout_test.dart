import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/pos_picpos/widgets/picpos_one_time_customer.dart';
import 'package:ural_erp/presentation/pos_picpos/widgets/picpos_payment_panel.dart';

void main() {
  for (final showCustomer in [true, false]) {
    for (final showOrderType in [true, false]) {
      testWidgets(
        'quick-sale panel lays out at 662px with customer $showCustomer and order type $showOrderType',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                showAddCustomerInPOSProvider.overrideWith(
                  (ref) async => showCustomer,
                ),
                showOrderTypeInPOSProvider.overrideWith(
                  (ref) async => showOrderType,
                ),
                posDefaultTaxRateProvider.overrideWith((ref) async => 0.16),
                posBottomPanelScaleProvider.overrideWith((ref) async => 1.0),
                posButtonHeightProvider.overrideWith((ref) async => 32.0),
                posButtonFontSizeProvider.overrideWith((ref) async => 12.0),
                showSubtotalInPOSProvider.overrideWith((ref) async => true),
                showTaxButtonInPOSProvider.overrideWith((ref) async => true),
                showDiscountButtonInPOSProvider.overrideWith(
                  (ref) async => true,
                ),
                showDrawerButtonInPOSProvider.overrideWith((ref) async => true),
                showExpenseButtonInPOSProvider.overrideWith(
                  (ref) async => true,
                ),
                showSaveOnlyInPOSProvider.overrideWith((ref) async => true),
                showHoldButtonInPOSProvider.overrideWith((ref) async => true),
                branchCashSafesProvider.overrideWith((ref) async => []),
                branchBankSafesProvider.overrideWith((ref) async => []),
                posCashCustomerIdProvider.overrideWith((ref) async => null),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 662,
                      child: PicPosPaymentPanel(
                        onCheckout: () {},
                        onSave: () {},
                        onLastInvoice: () {},
                        onEditDiscount: () {},
                        onPickCustomer: () {},
                        onPreviousInvoices: () {},
                        onOpenDrawer: () {},
                        onExpense: () {},
                        onHold: () {},
                        onHeldOrders: () {},
                        onQuickReturn: () {},
                        onExchange: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();

          expect(
            find.byType(PicPosOneTimeCustomerButton),
            showCustomer ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('داخلي'),
            showOrderType ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
