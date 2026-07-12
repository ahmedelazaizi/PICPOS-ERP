part of '../purchase_invoices_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PURCHASE INVOICE DETAILS — View, Print, Detail Row helper
// ═══════════════════════════════════════════════════════════════════════════

mixin _PurchaseInvoiceDetailsMixin
    on ConsumerState<PurchaseInvoicesScreen> {

  void showInvoiceDetails(InvoiceEntity invoice) async {
    final controller = ref.read(purchaseInvoicesControllerProvider.notifier);
    final items = await controller.getInvoiceItems(invoice.id!);
    final supplier = await controller.getSupplierById(invoice.partyId!);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.receipt, color: AppColors.warning),
              const SizedBox(width: 8),
              Text('فاتورة شراء #${invoice.invoiceNumber}'),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  detailRow('المورد', supplier?.name ?? 'غير محدد'),
                  detailRow(
                    'التاريخ',
                    invoice.invoiceDate.toString().substring(0, 10),
                  ),
                  detailRow(
                    'الإجمالي',
                    '${invoice.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  ),
                  detailRow(
                    'المدفوع',
                    '${invoice.paid.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  ),
                  detailRow(
                    'المتبقي',
                    '${(invoice.total - invoice.paid).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  ),
                  const Divider(height: 24),
                  const Text(
                    'الأصناف:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DataTable(
                    columnSpacing: 20,
                    columns: const [
                      DataColumn(label: Text('الصنف')),
                      DataColumn(label: Text('الوحدة')),
                      DataColumn(label: Text('الكمية')),
                      DataColumn(label: Text('السعر')),
                      DataColumn(label: Text('الإجمالي')),
                    ],
                    rows: items
                        .map(
                          (item) => DataRow(
                            cells: [
                              DataCell(Text(item.product.name)),
                              DataCell(Text(item.item.unitName ?? 'قطعة')),
                              DataCell(
                                Text(item.item.quantity.toStringAsFixed(2)),
                              ),
                              DataCell(
                                Text(
                                  '${item.item.unitCost.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${(item.item.quantity * item.item.unitCost).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void printInvoice(InvoiceEntity invoice) async {
    try {
      final controller = ref.read(purchaseInvoicesControllerProvider.notifier);
      final supplier = await controller.getSupplierById(invoice.partyId!);
      final items = await controller.getInvoiceItems(invoice.id!);
      final String? companyName = await controller.getCompanyName();

      await InvoiceGenerator.printPurchaseInvoice(
        invoiceNumber: invoice.invoiceNumber,
        date: invoice.invoiceDate,
        supplierName: supplier?.name ?? 'غير محدد',
        items: items
            .map(
              (item) => InvoiceItem(
                name: item.product.name,
                quantity: item.item.quantity,
                price: item.item.unitCost,
                total: item.item.quantity * item.item.unitCost,
              ),
            )
            .toList(),
        total: invoice.total,
        paid: invoice.paid,
        companyName: companyName,
        db: ref.read(databaseProvider),
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
      }
    }
  }
}
