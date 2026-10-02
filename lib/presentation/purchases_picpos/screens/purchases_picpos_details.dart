part of 'purchases_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PURCHASE INVOICE DETAILS — View, Print, Detail Row helper
//
// نسخة حرفية من lib/presentation/screens/purchase_invoices/purchase_invoice_details.dart
// (mixin `_PurchaseInvoiceDetailsMixin` في شاشة UralCash). نفس أسلوب النسخ
// المعتمد في picpos_pos_operations.dart — التغيير الوحيد: السطر الأول واسم
// الـ mixin/قيد `on`. جسم الدوال بدون أي تعديل.
// ═══════════════════════════════════════════════════════════════════════════

mixin _PurchasesPicposDetails on ConsumerState<PurchasesPicposScreen> {

  void showInvoiceDetails(InvoiceEntity invoice) async {
    final controller = ref.read(purchaseInvoicesControllerProvider.notifier);
    final items = await controller.getInvoiceItems(invoice.id!);
    final supplier = await controller.getSupplierById(invoice.partyId!);
    // J1b — «حساب المشتريات» المخزَّن؛ `null` ⇒ الحسابُ المربوطُ (لا يُعرَض).
    final db = ref.read(databaseProvider);
    final purchaseAccountId =
        await db.getPurchaseInvoicePurchaseAccountId(invoice.id!);
    final purchaseAccount = purchaseAccountId == null
        ? null
        : await db.getAccountById(purchaseAccountId);

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
              Text(tr('فاتورة شراء #{p0}', {'p0': invoice.invoiceNumber})),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  detailRow(tr('المورد'), supplier?.name ?? tr('غير محدد')),
                  if (purchaseAccount != null)
                    detailRow(
                      tr('حساب المشتريات'),
                      '${purchaseAccount.code} — ${trData(purchaseAccount.name)}',
                    ),
                  detailRow(
                    tr('التاريخ'),
                    invoice.invoiceDate.toString().substring(0, 10),
                  ),
                  detailRow(
                    tr('الإجمالي'),
                    '${invoice.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  ),
                  detailRow(
                    tr('المدفوع'),
                    '${invoice.paid.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  ),
                  detailRow(
                    tr('المتبقي'),
                    '${(invoice.total - invoice.paid).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  ),
                  const Divider(height: 24),
                   Text(
                    tr('الأصناف:'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DataTable(
                    columnSpacing: 20,
                    columns:  [
                      DataColumn(label: Text(tr('الصنف'))),
                      DataColumn(label: Text(tr('الوحدة'))),
                      DataColumn(label: Text(tr('الكمية'))),
                      DataColumn(label: Text(tr('السعر'))),
                      DataColumn(label: Text(tr('الإجمالي'))),
                    ],
                    rows: items
                        .map(
                          (item) => DataRow(
                            cells: [
                              DataCell(Text(item.product.name)),
                              DataCell(Text(item.item.unitName ?? tr('قطعة'))),
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
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  // v176 / §٨ — أوراقُ الفاتورة (البيانُ الجمركيُّ والعقدُ
                  // وإذنُ التسليم). واللوحُ يحلّ هُويّةَ الفاتورة بنفسه.
                  PicPosAttachmentsPanel(
                    entityType: 'purchase_invoice',
                    entityId: invoice.id,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إغلاق')),
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
        supplierName: supplier?.name ?? tr('غير محدد'),
        items: items
            .map(
              // فاتورةٌ كاملةٌ لا مرتجعٌ جزئيّ ⇒ الخصمُ والضريبةُ بلا تقسيط.
              (item) => InvoiceItem(
                name: item.product.name,
                quantity: item.item.quantity,
                price: item.item.unitCost,
                total: item.item.quantity * item.item.unitCost,
                code: item.product.code,
                barcode: item.product.barcode,
                unit: item.item.unitName,
                discount: item.item.discount,
                tax: item.item.taxAmount,
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
        AppToast.show(context, tr('خطأ في الطباعة: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }
}
