// WH-002: the «استلامات المخازن» button on the purchases screen is shown only
// to a user holding purchases_create and opens the inbox dialog.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';

import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/providers/wh_receipts_inbox_provider.dart';
import 'package:picpos_erp/presentation/purchases_picpos/screens/purchases_picpos_screen.dart';
import 'package:picpos_erp/presentation/screens/purchases/purchase_invoices_controller.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_receipts_source.dart';

class _EmptyController extends PurchaseInvoicesController {
  @override
  PurchaseInvoicesScreenState build() => PurchaseInvoicesScreenState(
        isLoading: false,
        allInvoices: [],
        filteredInvoices: [],
        filteredDocs: [],
        postedInvoiceIds: {},
      );
}

class _NoReceipts implements WhReceiptsSource {
  @override
  Future<List<Map<String, Object?>>> list(int userId) async => const [];
  @override
  Future<Map<String, Object?>> convert(String gid, int userId) async => {};
}

Future<void> _pump(WidgetTester tester, AppDatabase db, {required bool canCreate, required TextDirection dir}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      purchaseInvoicesControllerProvider.overrideWith(_EmptyController.new),
      hasPermissionProvider(PermissionCodes.purchasesCreate).overrideWith((ref) async => canCreate),
      hasPermissionProvider(PermissionCodes.purchasesEdit).overrideWith((ref) async => true),
      allBranchesProvider.overrideWith((ref) => Stream.value(const [])),
      allWarehousesProvider.overrideWith((ref) => Stream.value(const [])),
      allCostCentersProvider.overrideWith((ref) => Stream.value(const [])),
      whReceiptsInboxProvider.overrideWithValue(_NoReceipts()),
    ],
    child: MaterialApp(home: Directionality(textDirection: dir, child: const PurchasesPicposScreen())),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  for (final dir in [TextDirection.rtl, TextDirection.ltr]) {
    testWidgets('${dir.name}: shown with purchases_create and opens the inbox dialog', (tester) async {
      final db = AppDatabase.forTesting();
      await _pump(tester, db, canCreate: true, dir: dir);
      expect(find.byKey(const Key('purchases.whReceipts')), findsOneWidget);
      await tester.tap(find.byKey(const Key('purchases.whReceipts')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Dialog), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('${dir.name}: hidden without purchases_create', (tester) async {
      final db = AppDatabase.forTesting();
      await _pump(tester, db, canCreate: false, dir: dir);
      expect(find.byKey(const Key('purchases.whReceipts')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}