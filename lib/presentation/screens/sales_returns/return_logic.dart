part of '../sales_returns_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// RETURN LOGIC — Process, Print Receipt, History, Cancel
// ═══════════════════════════════════════════════════════════════════════════

/// زرار «إلغاء المرتجع» في سجل المرتجعات — `sales_return_delete`.
///
/// دي عملية عكسية حقيقية (بترجّع الفلوس للكاش وبتخصم الأصناف من المخزون
/// تاني)، فتجاوز المدير هو الشكل الصح: المنع النهائي بيسيب مرتجع غلط قايم.
/// `onGranted` صريح (درس f8d3fa9).
@visibleForTesting
Widget buildSalesReturnDeleteButtonGuarded({
  required VoidCallback onCancel,
}) {
  return PermissionGuard(
    permission: PermissionCodes.salesReturnDelete,
    allowManagerOverride: true,
    actionName: 'إلغاء مرتجع مبيعات',
    onGranted: onCancel,
    child: IconButton(
      icon: const Icon(PhosphorIconsBold.x, color: Colors.red, size: 18),
      tooltip: 'إلغاء المرتجع',
      onPressed: onCancel,
    ),
  );
}

/// زرار «طباعة المرتجع» (إعادة طباعة إيصال مرتجع قديم) — `sales_return_print`.
@visibleForTesting
Widget buildSalesReturnPrintButtonGuarded({required VoidCallback onPrint}) {
  return PermissionGuard(
    permission: PermissionCodes.salesReturnPrint,
    allowManagerOverride: true,
    actionName: 'طباعة مرتجع مبيعات',
    onGranted: onPrint,
    child: IconButton(
      icon: const Icon(PhosphorIconsBold.printer, color: AppColors.info),
      tooltip: 'طباعة المرتجع',
      onPressed: onPrint,
    ),
  );
}

mixin _ReturnLogicMixin on ConsumerState<SalesReturnsScreen> {
  // Abstract — provided by main State class
  TextEditingController get returnReasonController;

  bool _savingReturn = false;

  Future<void> processReturn() async {
    if (_savingReturn) return;
    final state = ref.read(salesReturnProvider);
    final notifier = ref.read(salesReturnProvider.notifier);

    if (state.selectedInvoice == null) return;

    final hasReturns = state.returnQuantities.values.any((q) => q > 0);
    if (!hasReturns) {
      AppToast.show(
        context,
        'يرجى تحديد كمية للإرجاع',
        type: ToastType.warning,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.warning, color: AppColors.warning),
              SizedBox(width: 8),
              Text('تأكيد المرتجع'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('فاتورة: ${state.selectedInvoice!.invoiceNumber}'),
              const SizedBox(height: 8),
              Text(
                'عدد الأصناف للإرجاع: ${state.returnQuantities.values.where((q) => q > 0).length}',
              ),
              const SizedBox(height: 8),
              Text(
                'إجمالي الإرجاع: ${notifier.calculateReturnTotal().toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
              ),
              child: const Text('تأكيد الإرجاع'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final reason = returnReasonController.text.trim();
    final returnTotal = notifier.calculateReturnTotal();
    final invoiceNumber = state.selectedInvoice!.invoiceNumber;

    // B5: Manager approval for high-value returns
    try {
      final thresholdStr = await ref.read(databaseProvider).getSettingValue('return_approval_threshold');
      final threshold = double.tryParse(thresholdStr ?? '0') ?? 0;
      if (threshold > 0 && returnTotal > threshold && mounted) {
        final approved = await requestManagerApproval(
          context,
          actionName: 'اعتماد مرتجع بقيمة ${returnTotal.toStringAsFixed(AppConstants.decimalPlaces)}',
        );
        if (!approved) return;
      }
    } catch (_) {
      // Settings not available — proceed without threshold check
    }

    // Capture print data BEFORE processReturn() clears state
    final capturedInvoice = state.selectedInvoice;
    final capturedItems = List<SalesInvoiceItem>.from(state.invoiceItems);
    final capturedQtys = Map<int, double>.from(state.returnQuantities);
    final capturedCache = Map<int, ProductEntity>.from(state.productCache);

    setState(() => _savingReturn = true);
    bool success = false;
    try {
      // ح‑١ (مواصفة 2026-08-18): مرتجعٌ يصرف نقداً بلا ورديّةٍ مفتوحة يُرفَض
      // كاملاً. المساعدُ يترجم الرفضَ إلى عرضِ فتحِ ورديّةٍ ثمّ يعيد المحاولةَ
      // مرّةً — والتوأمُ في `sales_returns_picpos_logic` يستدعي نفسَه.
      final outcome = await runRefundWithShiftPrompt(
        context: context,
        ref: ref,
        attempt: () async => success = await notifier.processReturn(reason),
      );
      if (outcome != RefundShiftOutcome.completed) {
        if (mounted) {
          AppToast.show(
            context,
            outcome == RefundShiftOutcome.cancelledByUser
                ? 'أُلغي المرتجع — لم تُفتَح وردية'
                : 'تعذّر فتح الوردية، فلم يُنفَّذ المرتجع',
            type: ToastType.warning,
          );
        }
        return;
      }
    } finally {
      if (mounted) setState(() => _savingReturn = false);
    }

    if (success && mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    PhosphorIconsBold.checkCircle,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 12),
                const Text('تم المرتجع بنجاح!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'مرتجع فاتورة: $invoiceNumber',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'قيمة المرتجع: ${returnTotal.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(height: 24),
                const Text('هل تريد طباعة إيصال المرتجع؟'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('لا'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _printReturnReceipt(
                    invoiceNumber: invoiceNumber,
                    returnTotal: returnTotal,
                    selectedInvoice: capturedInvoice,
                    invoiceItems: capturedItems,
                    productCache: capturedCache,
                    returnQuantities: capturedQtys,
                  );
                },
                icon: const Icon(PhosphorIconsBold.printer),
                label: const Text('طباعة'),
              ),
            ],
          ),
        ),
      );

      returnReasonController.clear();
      await ref.read(salesReturnProvider.notifier).loadInvoices();
    }
  }

  Future<void> _printReturnReceipt({
    required String invoiceNumber,
    required double returnTotal,
    SalesInvoiceData? selectedInvoice,
    List<SalesInvoiceItem>? invoiceItems,
    Map<int, ProductEntity>? productCache,
    Map<int, double>? returnQuantities,
  }) async {
    try {
      final repository = ref.read(returnsRepositoryProvider);

      final printData = await repository.getSalesReturnPrintData(
        invoiceNumber: invoiceNumber,
        returnTotal: returnTotal,
        selectedInvoice: selectedInvoice,
        invoiceItems: invoiceItems,
        productCache: productCache,
        returnQuantities: returnQuantities,
      );

      if (printData == null) return;

      final authState = ref.read(authProvider);
      final employeeName = authState.user?.displayName;
      final returnReason = returnReasonController.text;

      // القالبُ أوّلاً (`thermal`/`sales_return`)، والمولّدُ المكتوبُ في الكود
      // احتياطاً داخل الخدمة — انظر توأمَه في `sales_returns_picpos_logic`.
      await InvoiceGenerator.printSalesReturnReceipt(
        db: ref.read(databaseProvider),
        // Prefer the real SRET-N voucher produced during processSalesReturn;
        // fall back to a legible placeholder if the lookup failed for any
        // reason. Previously the printout used `'RET-<originalInvoice>'`
        // which silently duplicated the original number and left the
        // customer without a distinct return reference.
        returnVoucherNumber:
            printData.returnVoucherNumber ?? 'SRET-$invoiceNumber',
        originalInvoiceNumber: invoiceNumber,
        date: DateTime.now(),
        items: printData.items,
        returnTotal: returnTotal,
        paymentMethod: printData.paymentMethod,
        cashRefund: printData.cashRefund,
        bankRefund: printData.bankRefund,
        returnReason: returnReason.isNotEmpty ? returnReason : null,
        customerName: printData.customerName,
        companyName: printData.receiptSettings.companyName,
        companyPhone: printData.receiptSettings.companyPhone,
        companyAddress: printData.receiptSettings.companyAddress,
        employeeName: employeeName,
      );

      if (mounted) {
        AppToast.show(
          context,
          'تم طباعة إيصال مرتجع فاتورة $invoiceNumber',
          type: ToastType.success,
        );
      }
    } catch (e, stack) {
      if (mounted) {
        AppErrorHandler.handle(context, e, stack);
      }
    }
  }

  /// «سجل المرتجعات» — mirrors the purchase-returns history dialog.
  ///
  /// Feeds off [IReturnsRepository.getSalesReturnHistoryEntries], NOT
  /// `getSalesReturnHistory`. The latter matches only `sale_type='return'`
  /// invoice rows, and THIS screen's own standalone path never writes one —
  /// it flips the ORIGINAL invoice to 'returned'/'partial_return' and records
  /// the refund in `safe_transactions`, exactly like the purchases side. So
  /// the old query left this dialog permanently empty on a standalone/server
  /// install while «سجل مرتجعات المشتريات» listed everything. The entry list
  /// normalises both storage shapes and carries the ACTUAL refunded amount
  /// (not the original invoice's total) plus the original row that
  /// cancel/reprint must act on.
  void showReturnsHistoryDialog() {
    final repository = ref.read(returnsRepositoryProvider);
    // Use a 1-year lookback so recently processed returns always appear.
    final historyFrom = DateTime.now().subtract(const Duration(days: 365));
    final historyTo = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(
                  PhosphorIconsBold.clockCounterClockwise,
                  color: AppColors.info,
                ),
                SizedBox(width: 8),
                Text('سجل مرتجعات المبيعات'),
              ],
            ),
            content: SizedBox(
              width: 600,
              height: 450,
              child: FutureBuilder<List<SalesReturnHistoryEntry>>(
                future: repository.getSalesReturnHistoryEntries(
                  fromDate: historyFrom,
                  toDate: historyTo,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: ShimmerLoading.list(itemCount: 6),
                    );
                  }

                  final entries = snapshot.data ?? [];

                  if (entries.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            PhosphorIconsBold.arrowUDownLeft,
                            size: 48,
                            color: AppColors.textMuted,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'لا توجد مرتجعات خلال آخر سنة',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      // The row to act on for cancel/reprint is always the
                      // ORIGINAL invoice (see SalesReturnHistoryEntry docs);
                      // fall back to the displayed row when unresolvable.
                      final invoice = entry.originalInvoice ?? entry.invoice;
                      final isFullReturn = entry.isFullReturn;

                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isFullReturn
                                ? AppColors.error.withValues(alpha: 0.1)
                                : AppColors.warning.withValues(alpha: 0.1),
                            child: Icon(
                              isFullReturn
                                  ? PhosphorIconsBold.arrowUDownLeft
                                  : PhosphorIconsBold.arrowsClockwise,
                              size: 18,
                              color: isFullReturn
                                  ? AppColors.error
                                  : AppColors.warning,
                            ),
                          ),
                          title: Text('فاتورة #${entry.originalInvoiceNumber}'),
                          // Show the ACTUAL returned amount next to the
                          // original's total — same shape as the purchase
                          // returns history, where showing the original total
                          // alone made a 100 د.أ return on a 5000 د.أ invoice
                          // read as 5000.
                          subtitle: FutureBuilder<String?>(
                            future: invoice.customerId != null
                                ? ref
                                    .read(partiesRepositoryProvider)
                                    .getPartyById(invoice.customerId!)
                                    .then((p) => p?.name)
                                : Future.value(null),
                            builder: (ctx, partySnap) {
                              final customerName =
                                  partySnap.data ?? 'عميل نقدي';
                              final d = entry.invoice.invoiceDate;
                              final ret = entry.returnAmount.toStringAsFixed(
                                  AppConstants.decimalPlaces);
                              final orig = entry.originalInvoiceTotal
                                  .toStringAsFixed(
                                      AppConstants.decimalPlaces);
                              final cur = AppConstants.currencySymbolAr;
                              return Text(
                                '$customerName • ${d.day}/${d.month}/${d.year} • '
                                'قيمة المرتجع: $ret $cur '
                                '(الفاتورة الأصلية: $orig $cur)',
                              );
                            },
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isFullReturn
                                      ? AppColors.error.withValues(alpha: 0.1)
                                      : AppColors.warning.withValues(
                                          alpha: 0.1,
                                        ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isFullReturn ? 'مرتجع كامل' : 'مرتجع جزئي',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isFullReturn
                                        ? AppColors.error
                                        : AppColors.warning,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(
                                  PhosphorIconsBold.eye,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                                tooltip: 'عرض أصناف المرتجع',
                                onPressed: () async {
                                  // ISS-06: Acceptable — one-shot read in button callback
                                  final db = ref.read(databaseProvider);
                                  // Keyed on the ORIGINAL id: that is what
                                  // stock_movements.reference_id holds.
                                  final items = await db
                                      .getSalesReturnItemDetails(
                                          entry.originalInvoiceId);
                                  if (!ctx.mounted) return;
                                  showDialog(
                                    context: ctx,
                                    builder: (itemCtx) => Directionality(
                                      textDirection: TextDirection.rtl,
                                      child: AlertDialog(
                                        title: Row(
                                          children: [
                                            const Icon(
                                              PhosphorIconsBold.package,
                                              color: AppColors.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'أصناف المرتجع - ${entry.originalInvoiceNumber}',
                                            ),
                                          ],
                                        ),
                                        content: SizedBox(
                                          width: 460,
                                          height: 320,
                                          child: items.isEmpty
                                            ? const Center(child: Text('لا توجد بيانات مرتجع'))
                                            : ListView.builder(
                                            itemCount: items.length,
                                            itemBuilder: (_, i) {
                                              final item = items[i];
                                              final name = (item['product_name'] as String?) ?? 'صنف #${item['product_id']}';
                                              final qty = (item['returned_qty'] as num?)?.toDouble() ?? 0;
                                              final total = (item['total_amount'] as num?)?.toDouble() ?? 0;
                                              return ListTile(
                                                dense: true,
                                                leading: const Icon(
                                                  PhosphorIconsBold.package,
                                                  size: 18,
                                                ),
                                                title: Text(
                                                  name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  'الكمية المرتجعة: ${qty.toStringAsFixed(AppConstants.decimalPlaces)}',
                                                ),
                                                trailing: Text(
                                                  '${total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(itemCtx),
                                            child: const Text('إغلاق'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 4),
                              buildSalesReturnDeleteButtonGuarded(
                                onCancel: () => _confirmAndCancelReturn(
                                  ctx,
                                  entry,
                                  invoice,
                                ),
                              ),
                              buildSalesReturnPrintButtonGuarded(
                                onPrint: () => _printReturnReceipt(
                                  invoiceNumber: entry.originalInvoiceNumber,
                                  returnTotal: entry.returnAmount,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _cancellingReturn = false;

  /// ديالوج التأكيد بتاع «إلغاء المرتجع» ثم التنفيذ.
  ///
  /// اتنقلت من جوه `onPressed` عشان الحارس (`onGranted`) والزرار ينادوا نفس
  /// الكود بالظبط — لو فضلت closure مكرّرة، مسار موافقة المدير كان هيبقى
  /// نسخة تانية ممكن تنحرف.
  Future<void> _confirmAndCancelReturn(
    BuildContext ctx,
    SalesReturnHistoryEntry entry,
    SalesInvoiceData invoice,
  ) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (confirmCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.warning, color: Colors.red),
              SizedBox(width: 8),
              Text('تأكيد إلغاء المرتجع'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('فاتورة: ${entry.originalInvoiceNumber}'),
              const SizedBox(height: 8),
              Text(
                'المبلغ: ${entry.returnAmount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'سيتم إرجاع المبلغ للكاش وخصم الأصناف مرة أخرى من المخزون',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(confirmCtx, false),
              child: const Text('تراجع'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(confirmCtx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                'إلغاء المرتجع',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && ctx.mounted) {
      await _cancelReturn(invoice);
      if (ctx.mounted) {
        Navigator.pop(ctx);
        showReturnsHistoryDialog();
      }
    }
  }

  Future<void> _cancelReturn(SalesInvoiceData invoice) async {
    if (_cancellingReturn) return;
    setState(() => _cancellingReturn = true);
    try {
      final repository = ref.read(returnsRepositoryProvider);
      final auth = ref.read(authProvider);

      await repository.cancelSalesReturn(
        invoice: invoice,
        userId: auth.user?.id ?? 1,
        userName: auth.user?.displayName ?? 'مجهول',
      );

      if (mounted) {
        AppToast.show(
          context,
          '✅ تم إلغاء مرتجع فاتورة ${invoice.invoiceNumber} بنجاح',
          type: ToastType.success,
        );
        setState(() {});
      }
    } catch (e, stack) {
      if (mounted) {
        AppErrorHandler.handle(context, e, stack);
      }
    } finally {
      if (mounted) setState(() => _cancellingReturn = false);
    }
  }
}
