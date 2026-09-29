// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: library_private_types_in_public_api
part of '../../sales_invoices_screen.dart';

extension SalesInvoiceDialogsExt on _SalesInvoicesScreenState {
  // DETAILS DIALOG
  // ══════════════════════════════════════════════════════

  /// غلافٌ يُظهر الإخفاقَ بدل أن يبتلعه.
  ///
  /// بلاغٌ ميدانيّ (2026-08-20): «زرُّ عرض التفاصيل لا يفتح شيئاً». والجسمُ
  /// كان `void … async` — وهي صيغةٌ **لا يُمسَك استثناؤها في أيّ موضع**:
  /// يُرمى في حلقة الأحداث فلا حوارَ يُفتح ولا رسالةَ تظهر، فيبدو الزرُّ
  /// معطوباً وهو يعمل. وقبل `showDialog` انتظاران يجلبان من القاعدة، وأيُّ
  /// إخفاقٍ فيهما كان يختفي بلا أثر.
  ///
  /// ولا يُغيَّر الجسمُ نفسُه هنا: `Future<void>` وحدَها تجعله قابلاً
  /// للانتظار، فيصير استثناؤه ممسوكاً.
  void _showInvoiceDetails(InvoiceEntity invoice) async {
    try {
      await _showInvoiceDetailsInner(invoice);
    } catch (e, st) {
      debugPrint('[SalesDetails] تعذّر فتح تفاصيل ${invoice.invoiceNumber}: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 8),
          content: Text(tr('تعذّر فتح تفاصيل الفاتورة: {e}', {'e': e})),
        ),
      );
    }
  }

  Future<void> _showInvoiceDetailsInner(InvoiceEntity invoice) async {
    final controller = ref.read(salesInvoicesControllerProvider.notifier);
    final items = await controller.getInvoiceItems(invoice.id!);
    final customer = invoice.partyId != null
        ? await controller.getCustomerById(invoice.partyId!)
        : null;
    final customerName = customer?.name ?? tr('عميل نقدي');

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.receipt, color: AppColors.info),
              const SizedBox(width: 8),
              Text(tr('فاتورة بيع #{p0}', {'p0': invoice.invoiceNumber})),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow(tr('العميل'), customerName),
                  _detailRow(
                    tr('التاريخ'),
                    (invoice.createdAt ?? invoice.invoiceDate).toString().substring(0, 10),
                  ),
                  _detailRow(
                    tr('المجموع الفرعي'),
                    invoice.subtotal.toStringAsFixed(AppConstants.decimalPlaces),
                  ),
                  _detailRow(tr('الخصم'), invoice.discountAmount.toStringAsFixed(AppConstants.decimalPlaces)),
                  _detailRow(tr('الضريبة'), invoice.taxAmount.toStringAsFixed(AppConstants.decimalPlaces)),
                  _detailRow(tr('الإجمالي'), invoice.total.toStringAsFixed(AppConstants.decimalPlaces)),
                  _detailRow(tr('المدفوع'), invoice.paid.toStringAsFixed(AppConstants.decimalPlaces)),
                  _detailRow(
                    tr('المتبقي'),
                    (invoice.total - invoice.paid).toStringAsFixed(AppConstants.decimalPlaces),
                  ),
                  _detailRow(tr('الحالة'), invoice.status.name),
                  // Branch / Warehouse / Cost center context — resolves
                  // branch via warehouse FK so admin viewing a server-side
                  // invoice can immediately see its origin.
                  Builder(builder: (_) {
                    final state = ref.read(salesInvoicesControllerProvider);
                    final whId = invoice.warehouseId;
                    final whName = whId != null ? state.warehouseNames[whId] : null;
                    // Prefer direct branchId on the invoice (L3) with
                    // backward-compat fallback to warehouse → branch lookup.
                    final brId = invoice.branchId ??
                        (whId != null ? state.warehouseBranchId[whId] : null);
                    final brName = brId != null ? state.branchNames[brId] : null;
                    final ccName = invoice.costCenterId != null
                        ? state.costCenterNames[invoice.costCenterId]
                        : null;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (brName != null) _detailRow(tr('الفرع'), brName),
                        if (whName != null) _detailRow(tr('المخزن'), whName),
                        if (ccName != null) _detailRow(tr('مركز التكلفة'), ccName),
                      ],
                    );
                  }),
                  if (invoice.originClientId != null && invoice.originClientId!.isNotEmpty)
                    _detailRow(tr('الجهاز'), invoice.originClientId!),
                  if (invoice.notes != null && invoice.notes!.isNotEmpty)
                    _detailRow(tr('ملاحظات'), invoice.notes!),
                  const Divider(height: 24),
                  
                  // Margin Analysis
                  Consumer(
                    builder: (context, ref, child) {
                      final analysisStream = ref.watch(invoiceProfitAnalysisStreamProvider(invoice.id!));
                      return analysisStream.when(
                        data: (InvoiceProfitAnalysis? analysis) {
                          if (analysis == null) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ProfitMarginAnalysisWidget(analysis: analysis),
                              const Divider(height: 24),
                            ],
                          );
                        },
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (_, _) => const SizedBox.shrink(),
                      );
                    },
                  ),

                   Text(
                    tr('الأصناف:'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                     Text(
                      tr('لا توجد أصناف'),
                      style: const TextStyle(color: AppColors.textMuted),
                    )
                  else
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
                                DataCell(Text(item.displayName)),
                                DataCell(Text(item.item.unitName ?? tr('قطعة'))),
                                DataCell(
                                  Text(item.item.quantity.toStringAsFixed(AppConstants.decimalPlaces)),
                                ),
                                DataCell(
                                  Text(item.item.unitPrice.toStringAsFixed(AppConstants.decimalPlaces)),
                                ),
                                DataCell(
                                  Text(item.item.total.toStringAsFixed(AppConstants.decimalPlaces)),
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
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
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

  // ══════════════════════════════════════════════════════
  // PRINT INVOICE
  // ══════════════════════════════════════════════════════

  void _printInvoice(InvoiceEntity invoice) async {
    try {
      // Use PrintingService.printReceipt — the same unified path as POS.
      // This ensures the user's custom thermal/receipt template is applied
      // (falls back to default layout if no template exists).
      final printingService = ref.read(printingServiceProvider);
      await printingService.printReceipt(invoice.id!);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ في الطباعة: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  // ══════════════════════════════════════════════════════
  // CREATE NEW INVOICE
  // ══════════════════════════════════════════════════════

  void _createNewInvoice({
    QuotationEntity? editQuotation,
    bool isConvert = false,
  }) async {
    final controller = ref.read(salesInvoicesControllerProvider.notifier);

    unawaited(DiagnosticLogger.log('SPEC-090-DIALOG',
        '_createNewInvoice entered — '
        'editQuotation=${editQuotation?.id} isConvert=$isConvert'));

    // Show a modal progress spinner while we pre-load customers/products/
    // categories/warehouses. getCustomers() and getActiveWarehouses() are
    // Stream.first calls that can hang indefinitely on a slow client→server
    // link — without this indicator the user just sees the previous screen
    // frozen (the "convert draft" freeze the user reported).
    //
    // Spec 090 hotfix +160: await the spinner's mount via a Completer
    // before kicking off the preload. The previous +159 attempt captured
    // spinnerCtx in the builder but didn't WAIT for the builder to run.
    // On fast preload paths (e.g. a warm local cache resolving in <16ms,
    // before Flutter scheduled a frame), the futures completed before the
    // spinner widget was mounted: closeLoading saw ctx=null and skipped,
    // then the spinner finally mounted with no one to close it. After the
    // form popped on save, the orphan spinner was revealed and froze the
    // screen. Field-reproduced on +159 startup, log line
    // "closeLoading — spinner ctx null or unmounted (ctx=null)".
    final spinnerCtxCompleter = Completer<BuildContext>();
    final spinnerRouteFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        if (!spinnerCtxCompleter.isCompleted) {
          spinnerCtxCompleter.complete(ctx);
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
    // Yield control until the dialog's builder has actually executed.
    // Bounded with a small timeout so a Navigator that never schedules
    // the dialog (defensive — shouldn't happen) can't hang the caller.
    BuildContext? spinnerCtx;
    try {
      spinnerCtx = await spinnerCtxCompleter.future
          .timeout(const Duration(milliseconds: 500));
    } on TimeoutException {
      unawaited(DiagnosticLogger.log('SPEC-090-DIALOG',
          'spinner mount await TIMED OUT after 500ms — proceeding without spinner handle'));
    }
    if (!mounted) return;

    var loadingClosed = false;
    void closeLoading() {
      if (loadingClosed) return;
      loadingClosed = true;
      final ctx = spinnerCtx;
      if (ctx != null && ctx.mounted) {
        unawaited(DiagnosticLogger.log(
            'SPEC-090-DIALOG', 'closeLoading — popping preload spinner'));
        Navigator.of(ctx).pop();
      } else {
        // Fall back to popping the topmost route from the screen context
        // so we never leave an orphan spinner on screen. If ctx is null
        // here the spinner mount timed out — popping a route is the only
        // way to guarantee no stuck overlay.
        unawaited(DiagnosticLogger.log('SPEC-090-DIALOG',
            'closeLoading — spinner ctx unavailable (ctx=$ctx); falling back to root navigator pop'));
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    }
    // Silence: the dialog future may complete after this scope; we don't
    // need to await it ourselves but the variable suppresses the unused-future
    // lint and lets us log dismissal for diagnostics.
    unawaited(spinnerRouteFuture);

    final List<Party> customersList;
    final List<Product> products;
    final List<Category> categories;
    final List<dynamic> warehousesList;
    final List<CostCenter> costCentersList;
    try {
      final loadedCustomers = controller.getCustomers();
      final loadedProducts = controller.getProducts();
      final loadedCategories = controller.getCategories();
      final loadedWarehouses = controller.getActiveWarehouses();
      final loadedCostCenters =
          ref.read(accountingRepositoryProvider).getActiveCostCenters();
      await Future.wait([
        loadedCustomers,
        loadedProducts,
        loadedCategories,
        loadedWarehouses,
        loadedCostCenters,
      ]).timeout(const Duration(seconds: 15));
      customersList = await loadedCustomers;
      products = await loadedProducts;
      categories = await loadedCategories;
      warehousesList = await loadedWarehouses;
      costCentersList = await loadedCostCenters;
    } on TimeoutException {
      closeLoading();
      if (mounted) {
        AppToast.show(
          context,
          tr('انتهت مهلة تحميل البيانات — تأكد من الاتصال بالسيرفر'),
          type: ToastType.error,
        );
      }
      return;
    } catch (e) {
      closeLoading();
      if (mounted) {
        AppToast.show(
          context,
          tr('فشل تحميل بيانات الفاتورة: {e}', {'e': e}),
          type: ToastType.error,
        );
      }
      return;
    }

    closeLoading();
    if (!mounted) return;

    // Spec 090: open the extracted SalesInvoiceForm via showGeneralDialog +
    // Scaffold (mirrors the working PurchaseInvoiceForm pattern). The
    // form drives its own state via setState (no StatefulBuilder), exposes
    // explicit Cancel handling (no PopScope), and delegates persistence
    // back to _saveQuotation / _saveInvoice — the same handlers as before,
    // which already call Navigator.pop on success.
    //
    // Spec 090 hotfix +159: yield one frame between popping the preload
    // spinner and pushing the form so the navigator's animation queue
    // doesn't end up with both routes overlapping. Field report on +158
    // showed the form popping correctly on Save but a stray loading
    // spinner remained visible — consistent with the preload spinner not
    // being fully removed before the form was pushed on top of it.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final systemTaxRate = ref.read(posDefaultTaxRateProvider).value ?? 0;
    final activeWarehouses =
        warehousesList.whereType<WarehouseData>().toList();

    // Spec 103: in client mode restrict warehouses to the current branch so
    // the saved invoice's warehouseId resolves to the correct branchId and
    // appears in the branch's invoice list. القاعدةُ نفسُها في
    // `narrowWarehousesToClientBranch` — كانت منسوخةً هنا وفي توأم PicPos،
    // وبقيت نافذةُ فاتورة المشتريات بلا حصر.
    List<WarehouseData> filteredWarehouses = activeWarehouses;
    if (SyncInterceptor.isClientMode) {
      final prefs = await SharedPreferences.getInstance();
      filteredWarehouses = narrowWarehousesToClientBranch<WarehouseData>(
        warehouses: activeWarehouses,
        clientBranchId: prefs.getInt('client_branch_id'),
        branchIdOf: (w) => w.branchId,
      );
    }

    unawaited(DiagnosticLogger.log('SPEC-103-DIALOG',
        '_createNewInvoice preload done — '
        'costCenters=${costCentersList.length} '
        'warehousesAll=${activeWarehouses.length} '
        'warehousesFiltered=${filteredWarehouses.length} '
        'isClientMode=${SyncInterceptor.isClientMode}'));
    unawaited(DiagnosticLogger.log('SPEC-090-DIALOG',
        'about to showGeneralDialog — customers=${customersList.length} '
        'products=${products.length} categories=${categories.length} '
        'warehouses=${filteredWarehouses.length}'));

    if (!mounted) return;
    final dialogFuture = showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Sales Invoice',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, _) => Scaffold(
        body: SalesInvoiceForm(
          customers: customersList,
          initialProducts: products,
          categories: categories,
          warehouses: filteredWarehouses,
          costCenters: costCentersList,
          systemTaxRate: systemTaxRate,
          editQuotation: editQuotation,
          isConvert: isConvert,
          onSaveQuotation: ({
            required BuildContext dialogContext,
            required int? existingId,
            required String? existingNumber,
            required int? customerId,
            required String notes,
            required List<Map<String, dynamic>> invoiceItems,
            required double subtotal,
            required double discount,
            required double tax,
            required double total,
          }) async {
            await _saveQuotation(
              context: dialogContext,
              existingId: existingId,
              existingNumber: existingNumber,
              customerId: customerId,
              notes: notes,
              invoiceItems: invoiceItems,
              subtotal: subtotal,
              discount: discount,
              tax: tax,
              total: total,
            );
          },
          onSaveInvoice: ({
            required BuildContext dialogContext,
            required int? customerId,
            required String paymentMethod,
            required String notes,
            required List<Map<String, dynamic>> invoiceItems,
            required double subtotal,
            required double discount,
            required double tax,
            required double total,
            required double paid,
            required bool isReturnMode,
            required bool printAfterSave,
            required bool taxEnabled,
            int? convertingQuotationId,
            required List<Product> products,
            int? warehouseId,
            int? costCenterId,
          }) async {
            await _saveInvoice(
              context: dialogContext,
              customerId: customerId,
              paymentMethod: paymentMethod,
              notes: notes,
              invoiceItems: invoiceItems,
              subtotal: subtotal,
              discount: discount,
              tax: tax,
              total: total,
              paid: paid,
              isReturnMode: isReturnMode,
              printAfterSave: printAfterSave,
              taxEnabled: taxEnabled,
              convertingQuotationId: convertingQuotationId,
              products: products,
              warehouseId: warehouseId,
              costCenterId: costCenterId,
            );
          },
        ),
      ),
    );

    unawaited(dialogFuture.then((_) {
      unawaited(DiagnosticLogger.log('SPEC-090-DIALOG',
          'showGeneralDialog Future completed — sales-invoice form route popped'));
    }));
  }

  // ======================================================
  // SAVE, EDIT & DELETE -- See sales_invoice_save_edit.dart
  // ======================================================
}
