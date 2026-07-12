// Spec 103 — sales invoice cost-center dropdown + client-mode warehouse filter.
//
// Tests:
//   1. SalesInvoiceForm shows cost-center dropdown when costCenters is non-empty.
//   2. SalesInvoiceForm hides cost-center dropdown when costCenters is empty.
//   3. _selectedCostCenterId defaults to default warehouse's costCenterId on init.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart'
    show WarehouseData;
import 'package:ural_erp/presentation/screens/widgets/sales_invoices/sales_invoice_form.dart';

CostCenter _costCenter(int id, String name) => CostCenter(
      id: id,
      code: 'CC$id',
      name: name,
      parentId: null,
      isActive: true,
      createdAt: DateTime(2024),
      rowVersion: 1,
    );

WarehouseData _warehouse({
  required int id,
  required String name,
  int? costCenterId,
  bool isDefault = false,
}) =>
    WarehouseData(
      id: id,
      name: name,
      isDefault: isDefault,
      branchId: 1,
      costCenterId: costCenterId,
    );

Widget _buildForm({
  required List<CostCenter> costCenters,
  List<WarehouseData>? warehouses,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SalesInvoiceForm(
          customers: const [],
          initialProducts: const [],
          categories: const [],
          warehouses: warehouses ??
              [_warehouse(id: 1, name: 'مخزن 1', isDefault: true)],
          costCenters: costCenters,
          systemTaxRate: 0.14,
          onSaveQuotation: ({
            required dialogContext,
            required existingId,
            required existingNumber,
            required customerId,
            required notes,
            required invoiceItems,
            required subtotal,
            required discount,
            required tax,
            required total,
          }) async {},
          onSaveInvoice: ({
            required dialogContext,
            required customerId,
            required paymentMethod,
            required notes,
            required invoiceItems,
            required subtotal,
            required discount,
            required tax,
            required total,
            required paid,
            required isReturnMode,
            required printAfterSave,
            required taxEnabled,
            convertingQuotationId,
            required products,
            warehouseId,
            costCenterId,
          }) async {},
        ),
      ),
    ),
  );
}

void main() {
  group('Spec 103 — SalesInvoiceForm cost-center dropdown', () {
    testWidgets('shows dropdown when costCenters is non-empty', (tester) async {
      await tester.pumpWidget(_buildForm(
        costCenters: [_costCenter(1, 'مركز الإنتاج')],
      ));
      await tester.pumpAndSettle();
      // Closed state: the dropdown label/button is shown. The option list is
      // only built once the DropdownButton is OPENED (the closed button shows
      // only the selected item, which is 'بدون' here since this warehouse has
      // no costCenterId).
      expect(find.text('مركز التكلفة'), findsOneWidget);

      // Open the dropdown so its menu items get built, then assert the option.
      await tester.tap(find.text('مركز التكلفة'));
      await tester.pumpAndSettle();
      // findsWidgets: the opened menu may retain the closed-state item too.
      expect(find.text('مركز الإنتاج'), findsWidgets);
    });

    testWidgets('hides dropdown when costCenters is empty', (tester) async {
      await tester.pumpWidget(_buildForm(costCenters: const []));
      await tester.pumpAndSettle();
      expect(find.text('مركز التكلفة'), findsNothing);
    });

    testWidgets('defaults cost center to default warehouse costCenterId',
        (tester) async {
      final warehouses = [
        _warehouse(id: 1, name: 'مخزن 1', isDefault: true, costCenterId: 7),
      ];
      final costCenters = [_costCenter(7, 'مركز المبيعات')];

      await tester.pumpWidget(_buildForm(
        costCenters: costCenters,
        warehouses: warehouses,
      ));
      await tester.pumpAndSettle();

      // The selected item text appears in the dropdown button.
      expect(find.text('مركز المبيعات'), findsWidgets);
    });
  });
}
