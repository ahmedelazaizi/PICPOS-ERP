// منسوخ من lib/presentation/screens/purchase_returns/return_logic.dart
// (mixin `_PurchaseReturnLogicMixin` في شاشة UralCash). الملف الأصل `part of`
// خاص فما ينفعش يتعمله import، فبينتقل بنسخ حرفي هنا — نفس الأسلوب المعتمد في
// sales_returns_picpos_logic.dart. التغيير الوحيد: السطر الأول واسم الـ
// mixin/قيد `on`. جسم الدوال بدون أي تعديل — أي إصلاح منطقي يتصلّح في المصدر
// أولاً ثم patch (مصيدة النسخ §٥.٨).
part of 'purchase_returns_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PURCHASE RETURN LOGIC — Process, History, Print
// ═══════════════════════════════════════════════════════════════════════════

// J2: القيدُ عامٌّ (`ConsumerState<W>`) كي يركّبه سجلُّ المردودات أيضاً
// (`PurchaseReturnRecordActionsState`) لإعادة الطباعة والعرض والتعديل.
mixin _PurchaseReturnsPicposLogic<W extends ConsumerStatefulWidget>
    on ConsumerState<W> {

  /// الحفظُ جارٍ — خطؤه يُعرَض في حواره، فلا يكرّره مستمعُ الشاشة.
  bool _savingReturn = false;

  /// [beforePost] (J2) يقع بعد التأكيد وموافقة المدير وقبل الترحيل — فيه
  /// تُحفَظ المسوّدة؛ `false` منه يوقف الترحيل. والنتيجةُ `true` متى رُحِّل.
  Future<bool> processReturn({Future<bool> Function()? beforePost}) async {
    final state = ref.read(purchaseReturnProvider);
    final notifier = ref.read(purchaseReturnProvider.notifier);

    if (state.selectedInvoice == null) return false;

    final hasReturns = state.returnQuantities.values.any((q) => q > 0);
    if (!hasReturns) {
      AppToast.show(context, tr('يرجى تحديد كميات المرتجع'), type: ToastType.info);
      return false;
    }

    // Capture print data BEFORE state is cleared by processReturn()
    final invoice      = state.selectedInvoice!;
    final invoiceItems = state.invoiceItems;
    final returnQtys   = Map<int, double>.from(state.returnQuantities);
    final returnTotal  = notifier.calculateReturnTotal();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.warning, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(tr('تأكيد مرتجع المشتريات')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('فاتورة: {p0}', {'p0': invoice.invoiceNumber})),
              const SizedBox(height: 8),
              Text(
                tr('إجمالي المرتجع: {p0} {p1}', {'p0': returnTotal.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolAr}),
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
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child:  Text(tr('تأكيد المرتجع'), style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return false;

    // B5: Manager approval for high-value returns
    try {
      final thresholdStr = await ref.read(databaseProvider).getSettingValue('return_approval_threshold');
      final threshold = double.tryParse(thresholdStr ?? '0') ?? 0;
      if (threshold > 0 && returnTotal > threshold && mounted) {
        final approved = await requestManagerApproval(
          context,
          actionName: tr('اعتماد مرتجع مشتريات بقيمة {p0}', {'p0': returnTotal.toStringAsFixed(AppConstants.decimalPlaces)}),
        );
        if (!approved) return false;
      }
    } catch (_) {
      // Settings not available — proceed without threshold check
    }

    if (beforePost != null && !await beforePost()) return false;
    if (!mounted) return false;
    // 🔴 بلاغُ المالك: الإخفاقُ كان صامتاً — راجع رأس `purchase_return_save.dart`.
    // والعلَمُ يُسكت مستمعَ الأخطاء العامّ في الشاشة: الحفظُ يعرض خطأه بنفسه.
    _savingReturn = true;
    final bool success;
    try {
      success =
          await savePurchaseReturnWithFeedback(context: context, ref: ref);
    } finally {
      _savingReturn = false;
    }

    if (success && mounted) {
      // Show success dialog with print option
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
                  child: const Icon(PhosphorIconsBold.checkCircle, color: AppColors.success),
                ),
                const SizedBox(width: 12),
                 Text(tr('تم مرتجع المشتريات بنجاح!')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('مرتجع فاتورة: {p0}', {'p0': invoice.invoiceNumber}),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('قيمة المرتجع: {p0} {p1}', {'p0': returnTotal.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolAr}),
                  style: const TextStyle(fontSize: 15, color: AppColors.warning),
                ),
                const SizedBox(height: 20),
                 Text(tr('هل تريد طباعة فاتورة المرتجع A4؟')),
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
                  _printReturnInvoice(
                    invoice: invoice,
                    invoiceItems: invoiceItems,
                    returnQuantities: returnQtys,
                    returnTotal: returnTotal,
                  );
                },
                icon: const Icon(PhosphorIconsBold.printer),
                label:  Text(tr('طباعة A4')),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],
          ),
        ),
      );
    }
    return success;
  }

  /// طباعة فاتورة مرتجع المشتريات A4
  Future<void> _printReturnInvoice({
    required PurchaseInvoiceData invoice,
    required List<PurchaseInvoiceItemWithProduct> invoiceItems,
    required Map<int, double> returnQuantities,
    required double returnTotal,
  }) async {
    try {
      // ISS-06: Route party lookup through partiesRepositoryProvider
      final partiesRepo = ref.read(partiesRepositoryProvider);
      final supplier = await partiesRepo.getPartyById(invoice.supplierId);
      final supplierName = supplier?.name ?? tr('مورد غير محدد');

      // Get company name from settings
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final companyName = await settingsRepo.getSetting('company_name');

      // Build return items list (only items with returnQty > 0)
      final printItems = invoiceItems
          .where((i) => (returnQuantities[i.item.id] ?? 0) > 0)
          .map((i) {
            final qty  = returnQuantities[i.item.id]!;
            final cost = i.item.unitCost;
            // الخصمُ والضريبةُ مقسَّطان بنسبة المرتجَع — نظيرُ التوأم في
            // `screens/purchase_returns/return_logic.dart`.
            final ratio =
                i.item.quantity > 0 ? qty / i.item.quantity : 0.0;
            return InvoiceItem(
              name: i.product.name,
              quantity: qty,
              price: cost,
              total: qty * cost,
              note: i.item.unitName,
              barcode: i.product.barcode,
              code: i.product.code,
              unit: i.item.unitName,
              discount: i.item.discount * ratio,
              tax: i.item.taxAmount * ratio,
            );
          })
          .toList();

      final printed = await InvoiceGenerator.printPurchaseInvoice(
        invoiceNumber: 'PRET-${invoice.invoiceNumber}',
        date: DateTime.now(),
        supplierName: supplierName,
        items: printItems,
        total: returnTotal,
        paid: returnTotal, // Return = fully settled
        companyName: companyName,
        // ISS-06: Raw DB access retained — printing utilities require the
        // database instance to resolve printer settings and receipt templates.
        db: ref.read(databaseProvider),
        isReturn: true,
      );

      if (mounted) {
        AppToast.show(
          context,
          printed
              ? tr('تم طباعة فاتورة مرتجع {p0}', {'p0': invoice.invoiceNumber})
              : tr('أُلغيت طباعة فاتورة مرتجع {p0}', {'p0': invoice.invoiceNumber}),
          type: printed ? ToastType.success : ToastType.warning,
        );
      }
    } catch (e, stack) {
      if (mounted) {
        AppErrorHandler.handle(context, e, stack);
      }
    }
  }

  /// P5 (Issue #3): Reprint a historical purchase return from the history
  /// dialog. Fetches the items that were actually returned (from
  /// stock_movements with reference_type='purchase_return') and routes them
  /// through the same printer used by the just-after-return print flow.
  Future<void> _reprintHistoricalReturn(PurchaseInvoiceData invoice) async {
    try {
      final db = ref.read(databaseProvider);
      final partiesRepo = ref.read(partiesRepositoryProvider);
      final settingsRepo = ref.read(settingsRepositoryProvider);

      final returnedItems = await db.getPurchaseReturnItemDetails(invoice.id);
      if (returnedItems.isEmpty) {
        if (mounted) {
          AppToast.show(
            context,
            tr('لا يوجد تفاصيل أصناف لمرتجع هذه الفاتورة'),
            type: ToastType.warning,
          );
        }
        return;
      }

      final supplier = await partiesRepo.getPartyById(invoice.supplierId);
      final supplierName = supplier?.name ?? tr('مورد غير محدد');
      final companyName = await settingsRepo.getSetting('company_name');

      double returnTotal = 0;
      final printItems = <InvoiceItem>[];
      for (final r in returnedItems) {
        final qty = (r['returned_qty'] as num?)?.toDouble() ?? 0;
        final cost = (r['unit_cost'] as num?)?.toDouble() ?? 0;
        final total = qty * cost;
        returnTotal += total;
        printItems.add(InvoiceItem(
          name: r['product_name'] as String? ?? '#${r['product_id']}',
          quantity: qty,
          price: cost,
          total: total,
          note: r['unit_name'] as String? ?? '',
          // الأعمدةُ من الاستعلام نفسِه — والتقسيطُ وقع هناك بـSQL.
          code: r['product_code'] as String?,
          barcode: r['product_barcode'] as String?,
          unit: r['unit_name'] as String?,
          discount: (r['line_discount'] as num?)?.toDouble() ?? 0,
          tax: (r['line_tax'] as num?)?.toDouble() ?? 0,
        ));
      }

      final printed = await InvoiceGenerator.printPurchaseInvoice(
        invoiceNumber: 'PRET-${invoice.invoiceNumber}',
        date: invoice.invoiceDate,
        supplierName: supplierName,
        items: printItems,
        total: returnTotal,
        paid: returnTotal,
        companyName: companyName,
        db: db,
        isReturn: true,
      );

      if (mounted) {
        AppToast.show(
          context,
          printed
              ? tr('تم طباعة مرتجع الفاتورة {p0}', {'p0': invoice.invoiceNumber})
              : tr('أُلغيت طباعة مرتجع الفاتورة {p0}', {'p0': invoice.invoiceNumber}),
          type: printed ? ToastType.success : ToastType.warning,
        );
      }
    } catch (e, stack) {
      if (mounted) {
        AppErrorHandler.handle(context, e, stack);
      }
    }
  }

  // J2 — حوارُ «طباعة أو تعديل مرتجعٍ سابق» حُذف: إعادةُ الطباعة
  // (`purchases_return_print`) وعرضُ الأصناف وتعديلُ المرتجع المرحَّل
  // (`purchases_return_edit`، ميزة ٠١٥) صارت أفعالَ صفوفٍ في سجلّ المردودات
  // (`purchase_return_records_picpos_screen.dart`) تنادي المعالجاتِ نفسَها
  // أدناه بنفس الحرّاس.

  Future<void> _showReturnDetails(PurchaseInvoiceData invoice) async {
    // ISS-06: Acceptable — one-shot read in button callback, provider exists
    // (purchaseReturnItemDetailsProvider) for future refactor to reactive pattern.
    final db = ref.read(databaseProvider);
    final items = await db.getPurchaseReturnItemDetails(invoice.id);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(tr('تفاصيل مرتجع #{p0}', {'p0': invoice.invoiceNumber})),
          content: SizedBox(
            width: 480,
            height: 350,
            child: items.isEmpty
                ?  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        tr('تفاصيل المرتجع غير متاحة محلياً.\nقد يكون هذا مرتجع جزئي تم قبل تحديث النسخة — انتظر المزامنة التالية أو نفّذ مزامنة يدوية لتحديث البيانات من السيرفر.'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        child:  Row(
                          children: [
                            Expanded(flex: 3, child: Text(tr('الصنف'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            Expanded(flex: 2, child: Text(tr('الكمية المرتجعة'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                            Expanded(flex: 2, child: Text(tr('سعر الوحدة'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.end)),
                            Expanded(flex: 2, child: Text(tr('الإجمالي'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.end)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final name = (item['product_name'] as String?) ?? tr('صنف #{p0}', {'p0': item['product_id']});
                            final qty = (item['returned_qty'] as num?)?.toDouble() ?? 0;
                            final unit = (item['unit_name'] as String?) ?? '';
                            final cost = (item['unit_cost'] as num?)?.toDouble() ?? 0;
                            final total = (item['total_amount'] as num?)?.toDouble() ?? 0;
                            return ListTile(
                              dense: true,
                              title: Row(
                                children: [
                                  Expanded(flex: 3, child: Text(name, style: const TextStyle(fontSize: 13))),
                                  Expanded(flex: 2, child: Text(
                                    '${qty.toStringAsFixed(AppConstants.decimalPlaces)}${unit.isNotEmpty ? ' $unit' : ''}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 13),
                                  )),
                                  Expanded(flex: 2, child: Text(
                                    cost.toStringAsFixed(AppConstants.decimalPlaces),
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(fontSize: 13),
                                  )),
                                  Expanded(flex: 2, child: Text(
                                    '${total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  )),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      // Total footer
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        color: Theme.of(context).colorScheme.surfaceContainerLowest,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                             Text(tr('إجمالي المرتجع:'), style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(
                              '${items.fold<double>(0, (s, i) => s + ((i['total_amount'] as num?)?.toDouble() ?? 0)).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child:  Text(tr('إغلاق'))),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Feature 015 — Edit a posted purchase return
  // ═══════════════════════════════════════════════════════════════════════

  /// Opens an editor dialog for [invoice]'s currently-posted return.
  /// The user revises per-item return quantities; saving triggers an
  /// atomic reverse + recreate via `purchasesRepository.editPurchaseReturn`.
  ///
  /// Period-lock is checked locally as a UI affordance (the orchestrator
  /// and server enforce it independently — UI is just the friendly path).
  Future<void> _editPurchaseReturn(PurchaseInvoiceData invoice) async {
    final db = ref.read(databaseProvider);

    // Period gate (UI affordance; orchestrator + server enforce too).
    final closed = await db.isDateInClosedPeriod(invoice.invoiceDate);
    if (!mounted) return;
    if (closed) {
      AppToast.show(
        context,
        tr('لا يمكن تعديل المرتجع — الفترة المحاسبية مقفلة. افتح الفترة من شاشة السنوات المالية أولاً.'),
        type: ToastType.error,
      );
      return;
    }

    // Pre-fill: original invoice items + the qty currently returned per
    // product (from the stock_movements ledger).
    final invoiceItems = await db.getPurchaseInvoiceItemsWithProduct(invoice.id);
    final returnedDetails = await db.getPurchaseReturnItemDetails(invoice.id);
    if (!mounted) return;

    final currentByPid = <int, double>{};
    for (final r in returnedDetails) {
      final pid = (r['product_id'] as num?)?.toInt() ?? 0;
      final qty = (r['returned_qty'] as num?)?.toDouble() ?? 0;
      if (pid > 0) currentByPid[pid] = qty;
    }

    final qtyControllers = <int, TextEditingController>{
      for (final pi in invoiceItems)
        pi.item.id: TextEditingController(
          text: (currentByPid[pi.item.productId] ?? 0)
              .toStringAsFixed(AppConstants.decimalPlaces),
        ),
    };

    // R2: declare `saving` OUTSIDE StatefulBuilder so the guard survives
    //     rebuilds. Inside-builder declarations reset on every rebuild
    //     and the double-submission guard becomes useless.
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(PhosphorIconsBold.pencilSimple, color: AppColors.warning),
                const SizedBox(width: 8),
                Text(tr('تعديل مرتجع فاتورة #{p0}', {'p0': invoice.invoiceNumber})),
              ],
            ),
            content: SizedBox(
              width: 600,
              height: 400,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child:  Row(
                      children: [
                        Expanded(flex: 3, child: Text(tr('الصنف'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Expanded(flex: 2, child: Text(tr('الكمية الأصلية'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Expanded(flex: 2, child: Text(tr('كمية المرتجع'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Expanded(flex: 2, child: Text(tr('سعر الوحدة'), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: invoiceItems.length,
                      itemBuilder: (ctx, index) {
                        final pi = invoiceItems[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              Expanded(flex: 3, child: Text(pi.product.name, style: const TextStyle(fontSize: 13))),
                              Expanded(flex: 2, child: Text(pi.item.quantity.toStringAsFixed(AppConstants.decimalPlaces), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: qtyControllers[pi.item.id],
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textAlign: TextAlign.center,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                                    border: OutlineInputBorder(),
                                  ),
                                  enabled: !saving,
                                ),
                              ),
                              Expanded(flex: 2, child: Text(pi.item.unitCost.toStringAsFixed(AppConstants.decimalPlaces), textAlign: TextAlign.end, style: const TextStyle(fontSize: 13))),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        setState(() => saving = true);
                        try {
                          final newItems = <PurchaseReturnItem>[];
                          for (final pi in invoiceItems) {
                            final qtyText =
                                qtyControllers[pi.item.id]?.text.trim() ?? '0';
                            final qty = double.tryParse(qtyText) ?? 0;
                            newItems.add(PurchaseReturnItem(
                              itemId: pi.item.id,
                              productId: pi.item.productId,
                              returnQuantity: qty,
                              unitCost: pi.item.unitCost,
                              taxAmount: pi.item.taxAmount,
                              originalQuantity: pi.item.quantity,
                              quantityInBase: 1.0,
                            ));
                          }

                          final repo = ref.read(purchasesRepositoryProvider);
                          await repo.editPurchaseReturn(
                            invoice: invoice,
                            newReturnItems: newItems,
                          );
                           if (!ctx.mounted || !mounted) return;
                           Navigator.pop(ctx);
                          AppToast.show(
                            context,
                            tr('تم تعديل المرتجع بنجاح'),
                            type: ToastType.success,
                          );
                          // Refresh the invoice list so status badges update.
                          await ref
                              .read(purchaseReturnProvider.notifier)
                              .loadInvoices();
                        } catch (e, stack) {
                          if (mounted) {
                            AppErrorHandler.handle(context, e, stack);
                          }
                        } finally {
                          if (mounted) setState(() => saving = false);
                        }
                      },
                icon: saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(PhosphorIconsBold.checkCircle, size: 18),
                label:  Text(tr('حفظ التعديل'), style: const TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
              ),
            ],
          ),
        ),
      ),
    );

    for (final c in qtyControllers.values) {
      c.dispose();
    }
  }
}
