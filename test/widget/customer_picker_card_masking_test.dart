// RPT-006 (audit 2026-10-23): the customer picker card must not leak the
// balance / credit-limit hint to users without the customers view code.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/customer_picker_providers.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/shared_widgets/customer_picker/customer_picker_card.dart';

Party _party() => Party(
      id: 1,
      code: 'C-1',
      name: 'سارة أحمد',
      phone: '01011112222',
      address: 'المعادي',
      isCustomer: true,
      isSupplier: false,
      isDeliveryCompany: false,
      isFavorite: false,
      balance: 1234.5,
      creditLimit: 100,
      paymentTermsDays: 0,
      earlyPaymentDiscountPct: 0,
      earlyPaymentDiscountDays: 0,
      fixedDiscount: 0,
      priceLevel: 'default',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      isGlobal: true,
      isSystemDefault: false,
      rowVersion: 0,
    );

Future<void> _pump(WidgetTester tester, List<String> perms) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserPermissionsProvider.overrideWith((ref) async => perms),
      customerPickerPartyProvider.overrideWith((ref, id) async => _party()),
      customerReservationCountProvider.overrideWith((ref, id) async => 0),
      partyReservationsProvider.overrideWith((ref, id) async => const []),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: CustomerPickerCard(
          partyId: 1,
          snapshotName: 'سارة أحمد',
          onClear: () {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without customers_view: balance and debt chip are masked',
      (tester) async {
    await _pump(tester, const ['customers_add']);
    expect(find.textContaining('1234'), findsNothing);
    expect(find.text('عليه دين'), findsNothing);
    expect(find.textContaining('تجاوز الحد الائتماني'), findsNothing);
  });

  testWidgets('with customers_view: balance and debt chip are shown',
      (tester) async {
    await _pump(tester, const ['customers_view']);
    expect(find.textContaining('1234'), findsOneWidget);
    expect(find.text('عليه دين'), findsOneWidget);
  });
}
