part of '../party_statement_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARTY STATEMENT — Dialogs & Export: Document View, Print, Excel Export
// ═══════════════════════════════════════════════════════════════════════════

mixin _PartyStatementDialogsMixin on ConsumerState<PartyStatementScreen> {
  // Abstract — provided by the shell
  Party? get party;
  List<PartyStatementEntry> get entries;
  DateTime? get fromDate;
  DateTime? get toDate;
  DateFormat get dateFormat;
  bool get isLoading;
  set isLoading(bool val);
  double get totalDebit;
  double get totalCredit;
  double get finalBalance;

  Future<void> viewDocument(PartyStatementEntry entry) async {
    if (entry.referenceId == null || entry.referenceType == null) return;

    setState(() => isLoading = true);
    try {
      if (entry.referenceType == 'purchase_invoice') {
        final purchasesRepo = ref.read(purchasesRepositoryProvider);
        final invoice = await purchasesRepo.getRawInvoiceById(entry.referenceId!);
        if (invoice != null) {
          final items = (await purchasesRepo.getInvoiceItemsWithProduct(invoice.id)).cast<PurchaseInvoiceItemWithProduct>();
          if (mounted) _showPurchaseInvoiceDialog(invoice, items);
        }
      } else if (entry.referenceType == 'sales_invoice') {
        final salesRepo = ref.read(salesRepositoryProvider);
        final invoice = await salesRepo.getRawInvoiceById(entry.referenceId!);
        if (invoice != null) {
          final items = await salesRepo.getSalesInvoiceItems(invoice.id);
          if (mounted) _showSalesInvoiceDialog(invoice, items);
        }
      } else {
        // Safe transactions: payments, receipts, PADJ balance adjustments, return settlements
        if (mounted) _showTransactionDialog(entry);
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showTransactionDialog(PartyStatementEntry entry) {
    final amount = entry.debit > 0 ? entry.debit : entry.credit;
    final isDebit = entry.debit > 0;
    final color = isDebit ? AppColors.error : AppColors.success;

    final typeLabel = switch (entry.referenceType) {
      'purchase_return_balance' => 'تسوية رصيد مرتجع مشتريات',
      'sales_return_balance'    => 'تسوية رصيد مرتجع مبيعات',
      'receipt'                 => 'سند قبض',
      'payment'                 => 'سند صرف',
      _                         => 'معاملة مالية',
    };

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(PhosphorIconsBold.receipt, color: color),
            const SizedBox(width: 8),
            Text(typeLabel),
          ]),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInvoiceHeader(entry.date, widget.isSupplier ? 'المورد: ${widget.partyName}' : 'العميل: ${widget.partyName}'),
                const Divider(),
                if (entry.invoiceNumber != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _buildSummaryRow('رقم السند', entry.invoiceNumber!),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _buildSummaryRow('البيان', entry.description),
                ),
                const Divider(),
                _buildSummaryRow(
                  isDebit ? 'مبلغ مدين' : 'مبلغ دائن',
                  '${amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  bold: true,
                  color: color,
                ),
                const SizedBox(height: 4),
                _buildSummaryRow(
                  'الرصيد بعد العملية',
                  '${entry.balance.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  color: entry.balance > 0 ? AppColors.error : AppColors.success,
                ),
              ],
            ),
          ),
          actions: [
            // Field-report 2026-05-14: voucher preview was view-only;
            // operators routinely need a paper copy at the counter.
            // Receipt/payment vouchers print via VouchersPdfGenerator;
            // return-balance memos reuse the same template (operator just
            // gets a signed proof of the balance adjustment).
            TextButton.icon(
              icon: const Icon(PhosphorIconsBold.printer),
              label: const Text('طباعة'),
              onPressed: () async {
                try {
                  final isReceipt = entry.referenceType == 'receipt' ||
                      entry.referenceType == 'sales_return_balance';
                  await VouchersPdfGenerator.printVoucher(
                    voucherNumber: entry.invoiceNumber ?? '',
                    voucherType: isReceipt ? 'receipt' : 'payment',
                    date: entry.date,
                    amount: amount,
                    partyName: widget.partyName,
                    description: '$typeLabel — ${entry.description}',
                  );
                } catch (e) {
                  if (mounted) {
                    AppToast.show(context, 'خطأ في الطباعة: $e',
                        type: ToastType.error);
                  }
                }
              },
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          ],
        ),
      ),
    );
  }

  void _showPurchaseInvoiceDialog(PurchaseInvoiceData inv, List<PurchaseInvoiceItemWithProduct> items) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(PhosphorIconsBold.receipt, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('تفاصيل فاتورة شراء #${inv.invoiceNumber}'),
          ]),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInvoiceHeader(inv.invoiceDate, 'المورد: ${widget.partyName}'),
                if (inv.supplierInvoiceNumber != null && inv.supplierInvoiceNumber!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text('رقم وثيقة المورد: ${inv.supplierInvoiceNumber!}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                if (inv.notes != null && inv.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text('ملاحظات: ${inv.notes!}'),
                    ),
                  ),
                const Divider(),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Table(
                      columnWidths: const {0: FlexColumnWidth(3), 1: FixedColumnWidth(80), 2: FixedColumnWidth(80), 3: FixedColumnWidth(100)},
                      children: [
                        const TableRow(
                          decoration: BoxDecoration(color: AppColors.surface),
                          children: [
                            Padding(padding: EdgeInsets.all(8), child: Text('الصنف', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.all(8), child: Text('الكمية', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.all(8), child: Text('السعر', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.all(8), child: Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                        ),
                        ...items.map((item) => TableRow(children: [
                          Padding(padding: const EdgeInsets.all(8), child: Text(item.product.name)),
                          Padding(padding: const EdgeInsets.all(8), child: Text(item.item.quantity.toString())),
                          Padding(padding: const EdgeInsets.all(8), child: Text(item.item.unitCost.toStringAsFixed(AppConstants.decimalPlaces))),
                          Padding(padding: const EdgeInsets.all(8), child: Text((item.item.quantity * item.item.unitCost).toStringAsFixed(AppConstants.decimalPlaces))),
                        ])),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                _buildInvoiceSummary(inv.total, inv.paid),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(PhosphorIconsBold.printer),
              label: const Text('طباعة'),
              onPressed: () async {
                try {
                  await ref
                      .read(printingServiceProvider)
                      .printPurchaseInvoiceA4(inv.id);
                } catch (e) {
                  if (mounted) {
                    AppToast.show(context, 'خطأ في الطباعة: $e',
                        type: ToastType.error);
                  }
                }
              },
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
          ],
        ),
      ),
    );
  }

  void _showSalesInvoiceDialog(SalesInvoiceData inv, List<SalesInvoiceItem> items) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(PhosphorIconsBold.receipt, color: AppColors.success),
            const SizedBox(width: 8),
            Text('تفاصيل فاتورة مبيعات #${inv.invoiceNumber}'),
          ]),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInvoiceHeader(inv.invoiceDate, 'العميل: ${widget.partyName}'),
                const Divider(),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Table(
                      columnWidths: const {0: FlexColumnWidth(3), 1: FixedColumnWidth(80), 2: FixedColumnWidth(80), 3: FixedColumnWidth(100)},
                      children: [
                        const TableRow(
                          decoration: BoxDecoration(color: AppColors.surface),
                          children: [
                            Padding(padding: EdgeInsets.all(8), child: Text('الصنف', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.all(8), child: Text('الكمية', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.all(8), child: Text('السعر', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.all(8), child: Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                        ),
                        ...items.map((item) => TableRow(children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: FutureBuilder<ProductEntity?>(
                              future: ref.read(productRepositoryProvider).getProductById(item.productId),
                              builder: (context, snap) => Text(snap.data?.name ?? '...'),
                            ),
                          ),
                          Padding(padding: const EdgeInsets.all(8), child: Text(item.quantity.toString())),
                          Padding(padding: const EdgeInsets.all(8), child: Text(item.unitPrice.toStringAsFixed(AppConstants.decimalPlaces))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(item.total.toStringAsFixed(AppConstants.decimalPlaces))),
                        ])),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                _buildInvoiceSummary(inv.total, inv.paid),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(PhosphorIconsBold.printer),
              label: const Text('طباعة'),
              onPressed: () async {
                try {
                  await ref
                      .read(printingServiceProvider)
                      .printSalesInvoiceA4(inv.id);
                } catch (e) {
                  if (mounted) {
                    AppToast.show(context, 'خطأ في الطباعة: $e',
                        type: ToastType.error);
                  }
                }
              },
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceHeader(DateTime date, String partyInfo) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(partyInfo, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('التاريخ: ${dateFormat.format(date)}'),
        ],
      ),
    );
  }

  Widget _buildInvoiceSummary(double total, double paid) {
    final remaining = total - paid;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        _buildSummaryRow('الإجمالي النهائي', '${total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}', bold: true),
        _buildSummaryRow('المبلغ المدفوع', '${paid.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}'),
        _buildSummaryRow('المبلغ المتبقي', '${remaining.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}', color: remaining > 0 ? AppColors.error : AppColors.success),
      ]),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color, fontSize: bold ? 16 : 14)),
        ],
      ),
    );
  }

  Future<void> printStatement() async {
    try {
      final statementItems = entries.map((e) => StatementItem(
        date: e.date,
        description: '${e.description}${e.invoiceNumber != null ? ' - ${e.invoiceNumber}' : ''}',
        debit: e.debit, credit: e.credit, balance: e.balance,
      )).toList();

      await InvoiceGenerator.printPartyStatement(
        partyName: widget.partyName,
        partyType: widget.isSupplier ? 'supplier' : 'customer',
        currentBalance: party?.balance ?? 0,
        transactions: statementItems,
        fromDate: fromDate, toDate: toDate,
      );
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
    }
  }

  Future<void> exportToExcel() async {
    try {
      final excel = Excel.createExcel();
      const sheetName = 'كشف حساب';
      excel.rename('Sheet1', sheetName);
      final sheet = excel[sheetName];

      sheet.appendRow([TextCellValue('كشف حساب: ${widget.partyName}')]);
      sheet.appendRow([TextCellValue(widget.isSupplier ? 'مورد' : 'عميل')]);
      if (fromDate != null && toDate != null) {
        sheet.appendRow([TextCellValue('الفترة: ${dateFormat.format(fromDate!)} - ${dateFormat.format(toDate!)}')]);
      }
      sheet.appendRow([TextCellValue('الرصيد الحالي: ${party?.balance.toStringAsFixed(AppConstants.decimalPlaces) ?? 0} ${AppConstants.currencySymbolEn}')]);
      sheet.appendRow([TextCellValue('')]);

      sheet.appendRow([
        TextCellValue('التاريخ'), TextCellValue('البيان'), TextCellValue('رقم المستند'),
        TextCellValue('مدين'), TextCellValue('دائن'), TextCellValue('الرصيد'),
      ]);

      for (final entry in entries) {
        sheet.appendRow([
          TextCellValue(dateFormat.format(entry.date)),
          TextCellValue(entry.description),
          TextCellValue(entry.invoiceNumber ?? '-'),
          DoubleCellValue(entry.debit),
          DoubleCellValue(entry.credit),
          DoubleCellValue(entry.balance),
        ]);
      }

      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([
        TextCellValue(''), TextCellValue('الإجمالي'), TextCellValue(''),
        DoubleCellValue(totalDebit), DoubleCellValue(totalCredit), DoubleCellValue(finalBalance),
      ]);

      final fileName = 'PartyStatement_${widget.partyName}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final bytes = Uint8List.fromList(fileBytes);
        await fileUtils.saveFile(fileName, bytes);
        if (mounted) AppToast.show(context, 'تم تصدير الكشف إلى: $fileName', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ في التصدير: $e', type: ToastType.error);
    }
  }
}
