// منسوخ من lib/presentation/screens/sales_returns/return_logic.dart
// (mixin `_ReturnLogicMixin` في شاشة UralCash). الملف الأصل `part of` خاص
// فما ينفعش يتعمله import، فبينتقل بنسخ حرفي هنا — نفس الأسلوب المعتمد في
// purchases_picpos_crud.dart. التغيير الوحيد: السطر الأول واسم الـ mixin/قيد
// `on`. جسم الدوال بدون أي تعديل — أي إصلاح منطقي يتصلّح في المصدر أولاً ثم
// patch (مصيدة النسخ §٥.٨).
part of 'sales_returns_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// RETURN LOGIC — Process, Print Receipt, History, Cancel
// ═══════════════════════════════════════════════════════════════════════════

/// زرار «إلغاء المرتجع» — `sales_return_delete`. نسخة مطابقة لنسخة فورك
/// UralCash (`screens/sales_returns/return_logic.dart`)؛ الملفين مكتبتين
/// منفصلتين فما ينفعش يتشاركوا دالة top-level.
@visibleForTesting
Widget buildSalesReturnDeleteButtonGuarded({
  required VoidCallback onCancel,
}) {
  return PermissionGuard(
    permission: PermissionCodes.salesReturnDelete,
    allowManagerOverride: true,
    actionName: tr('إلغاء مرتجع مبيعات'),
    onGranted: onCancel,
    child: IconButton(
      icon: const Icon(PhosphorIconsBold.x, color: AppColors.error, size: 18),
      tooltip: tr('إلغاء المرتجع'),
      onPressed: onCancel,
    ),
  );
}

/// زرار «طباعة المرتجع» — `sales_return_print`. نفس ملاحظة النسخ فوق.
@visibleForTesting
Widget buildSalesReturnPrintButtonGuarded({required VoidCallback onPrint}) {
  return PermissionGuard(
    permission: PermissionCodes.salesReturnPrint,
    allowManagerOverride: true,
    actionName: tr('طباعة مرتجع مبيعات'),
    onGranted: onPrint,
    child: IconButton(
      icon: const Icon(PhosphorIconsBold.printer, color: AppColors.info),
      tooltip: tr('طباعة المرتجع'),
      onPressed: onPrint,
    ),
  );
}

// J2: القيدُ عامٌّ (`ConsumerState<W>`) كي يركّبه سجلُّ المرتجعات أيضاً
// (`SalesReturnRecordActionsState`) لإعادة الطباعة والإلغاء من صفوفه.
mixin _SalesReturnsPicposLogic<W extends ConsumerStatefulWidget>
    on ConsumerState<W> {
  // Abstract — provided by main State class
  TextEditingController get returnReasonController;

  bool _savingReturn = false;

  /// [beforePost] (J2) يقع بعد التأكيد وموافقة المدير وقبل الترحيل — فيه
  /// تُحفَظ المسوّدة؛ `false` منه يوقف الترحيل. والنتيجةُ `true` متى رُحِّل.
  Future<bool> processReturn({Future<bool> Function()? beforePost}) async {
    if (_savingReturn) return false;
    final state = ref.read(salesReturnProvider);
    final notifier = ref.read(salesReturnProvider.notifier);

    if (state.selectedInvoice == null) return false;

    final hasReturns = state.returnQuantities.values.any((q) => q > 0);
    if (!hasReturns) {
      AppToast.show(
        context,
        tr('يرجى تحديد كمية للإرجاع'),
        type: ToastType.warning,
      );
      return false;
    }
    final canSeeFigures = await ref.read(
      screenFiguresVisibilityProvider(ScreenId.salesReturns).future,
    );
    final returnTotalLabel = canSeeFigures
        ? notifier.calculateReturnTotal().toStringAsFixed(AppConstants.decimalPlaces)
        : maskedFinancialFigure;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.warning, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(tr('تأكيد المرتجع')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('فاتورة: {p0}', {'p0': state.selectedInvoice!.invoiceNumber})),
              const SizedBox(height: 8),
              Text(
                'عدد الأصناف للإرجاع: ${state.returnQuantities.values.where((q) => q > 0).length}',
              ),
              const SizedBox(height: 8),
              Text(
                tr('إجمالي الإرجاع: {p0} {p1}', {'p0': returnTotalLabel, 'p1': AppConstants.currencySymbolAr}),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
              ),
              child:  Text(tr('تأكيد الإرجاع')),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return false;

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
          actionName: tr('اعتماد مرتجع بقيمة {p0}', {
            'p0': canSeeFigures
                ? returnTotal.toStringAsFixed(AppConstants.decimalPlaces)
                : maskedFinancialFigure,
          }),
        );
        if (!approved) return false;
      }
    } catch (_) {
      // Settings not available — proceed without threshold check
    }

    if (beforePost != null && !await beforePost()) return false;
    if (!mounted) return false;

    // Capture print data BEFORE processReturn() clears state
    final capturedInvoice = state.selectedInvoice;
    final capturedItems = List<SalesInvoiceItem>.from(state.invoiceItems);
    final capturedQtys = Map<int, double>.from(state.returnQuantities);
    final capturedCache = Map<int, ProductEntity>.from(state.productCache);

    setState(() => _savingReturn = true);
    bool success = false;
    try {
      if (!mounted) return false;
      // ح‑١ (مواصفة 2026-08-18) — نسخةُ المنطقِ واحدةٌ في
      // `runWithOpenShiftPrompt`، والتوأمُ في `screens/sales_returns` يستدعي
      // نفسَه. لا تنسخ هنا (مصيدةُ النسخ §٥.٥).
      final outcome = await runWithOpenShiftPrompt(
        context: context,
        ref: ref,
        attempt: () async => success = await notifier.processReturn(reason),
      );
      if (outcome != ShiftPromptOutcome.completed) {
        if (mounted) {
          AppToast.show(
            context,
            outcome == ShiftPromptOutcome.cancelledByUser
                ? tr('أُلغي المرتجع — لم تُفتَح وردية')
                : tr('تعذّر فتح الوردية، فلم يُنفَّذ المرتجع'),
            type: ToastType.warning,
          );
        }
        return false;
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
                 Text(tr('تم المرتجع بنجاح!')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('مرتجع فاتورة: {invoiceNumber}', {'invoiceNumber': invoiceNumber}),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('قيمة المرتجع: {p0} {p1}', {
                     'p0': canSeeFigures
                         ? returnTotal.toStringAsFixed(AppConstants.decimalPlaces)
                         : maskedFinancialFigure,
                     'p1': AppConstants.currencySymbolAr,
                   }),
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(height: 24),
                 Text(tr('هل تريد طباعة إيصال المرتجع؟')),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:  Text(tr('لا')),
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
                label:  Text(tr('طباعة')),
              ),
            ],
          ),
        ),
      );

      returnReasonController.clear();
      await ref.read(salesReturnProvider.notifier).loadInvoices();
    }
    return success;
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
      // احتياطاً داخل الخدمة. كان النداءُ يذهب إلى المولّد مباشرةً فلا يُسأل
      // عن قالبٍ أصلاً — ومرتجعُ المبيعات له قالبٌ مبذورٌ قابلٌ للتصميم.
      final printed = await InvoiceGenerator.printSalesReturnReceipt(
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
          printed
              ? tr('تم طباعة إيصال مرتجع فاتورة {invoiceNumber}', {'invoiceNumber': invoiceNumber})
              : tr('أُلغيت طباعة إيصال مرتجع فاتورة {invoiceNumber}', {'invoiceNumber': invoiceNumber}),
          type: printed ? ToastType.success : ToastType.warning,
        );
      }
    } catch (e, stack) {
      if (mounted) {
        AppErrorHandler.handle(context, e, stack);
      }
    }
  }

  // J2 — حوارُ «سجل مرتجعات المبيعات» حُذف: حلّت محلَّه شاشةُ السجلّ
  // (`sales_return_records_picpos_screen.dart`) بأفعال صفوفها — عرضٌ
  // وطباعةٌ وإلغاءٌ بنفس الحرّاس (`buildSalesReturn*ButtonGuarded`) ونفس
  // المعالجات أدناه.

  bool _cancellingReturn = false;

  /// ديالوج تأكيد «إلغاء المرتجع» ثم التنفيذ — اتنقلت من جوه `onPressed`
  /// عشان الحارس (`onGranted`) والزرار ينادوا نفس الكود بالظبط.
  /// `true` = أُلغي فعلاً (J2: السجلُّ يختم مسوّداته «ملغى» ويُحدِّث).
  Future<bool> _confirmAndCancelReturn(
    BuildContext ctx, {
    required String originalInvoiceNumber,
    required double returnAmount,
    required SalesInvoiceData invoice,
  }) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (confirmCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.warning, color: AppColors.error),
              const SizedBox(width: 8),
              Text(tr('تأكيد إلغاء المرتجع')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('فاتورة: {p0}', {'p0': originalInvoiceNumber})),
              const SizedBox(height: 8),
              Text(
                tr('المبلغ: {p0} {p1}', {'p0': returnAmount.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolAr}),
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
                child:  Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('سيتم إرجاع المبلغ للكاش وخصم الأصناف مرة أخرى من المخزون'),
                        style: const TextStyle(fontSize: 12, color: Colors.orange),
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
              child:  Text(tr('تراجع')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(confirmCtx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child:  Text(
                tr('إلغاء المرتجع'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && ctx.mounted) {
      return _cancelReturn(invoice);
    }
    return false;
  }

  Future<bool> _cancelReturn(SalesInvoiceData invoice) async {
    if (_cancellingReturn) return false;
    setState(() => _cancellingReturn = true);
    try {
      final repository = ref.read(returnsRepositoryProvider);
      final auth = ref.read(authProvider);

      await repository.cancelSalesReturn(
        invoice: invoice,
        userId: auth.user?.id ?? 1,
        userName: auth.user?.displayName ?? tr('مجهول'),
      );

      if (mounted) {
        AppToast.show(
          context,
          tr('✅ تم إلغاء مرتجع فاتورة {p0} بنجاح', {'p0': invoice.invoiceNumber}),
          type: ToastType.success,
        );
        setState(() {});
      }
      return true;
    } catch (e, stack) {
      if (mounted) {
        AppErrorHandler.handle(context, e, stack);
      }
      return false;
    } finally {
      if (mounted) setState(() => _cancellingReturn = false);
    }
  }
}
