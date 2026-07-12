// ignore_for_file: library_private_types_in_public_api
// =======================================================================
// SALES INVOICE SAVE, EDIT & DELETE
// Extracted from sales_invoice_dialogs.dart - Sprint 13 God File Splitting
// =======================================================================
part of '../../sales_invoices_screen.dart';

extension SalesInvoiceSaveEditExt on _SalesInvoicesScreenState {
  /// Unified save logic for generating a Quotation
  Future<void> _saveQuotation({
    required BuildContext context,
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
    if (invoiceItems.isEmpty) {
      AppToast.show(
        context,
        'يرجى إضافة صنف واحد على الأقل',
        type: ToastType.error,
      );
      return;
    }

    // Cluster 034 / Issue 2 pattern — capture a ProviderContainer up-front
    // so this async chain survives State disposal (e.g. the parent screen
    // unmounts while a dialog stays visible). Using `this.ref` directly
    // would throw "Bad state: Using 'ref' when a widget is about to or
    // has been unmounted is unsafe" as soon as we hit any await boundary.
    final container = ProviderScope.containerOf(context, listen: false);

    try {
      final authState = container.read(authProvider);
      final userId = authState.user?.id ?? 1;

      final quotationNumber =
          existingNumber ??
          'Q-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';



      final cartItems = invoiceItems.map((item) => CartItemEntity(
        productId: item['productId'] as int,
        productName: item['productName'] as String,
        productCode: '', // Not needed for saving
        quantity: item['quantity'] as double,
        unitPrice: item['unitPrice'] as double,
        taxRate: item['taxRate'] as double,
        taxAmount: item['taxAmount'] as double,
        selectedUnitName: item['selectedUnitName'] as String?,
        quantityInBase: (item['quantityInBase'] as double?) ?? 1.0,
      )).toList();

      final repo = container.read(quotationsRepositoryProvider);
      final quotationId = existingId != null
          ? await (repo.updateFullQuotation(
              id: existingId,
              items: cartItems,
              customerId: customerId,
              userId: userId,
              subtotal: subtotal,
              discount: discount,
              tax: tax,
              total: total,
              notes: notes,
              status: 'draft',
            ).then((_) => existingId))
          : await repo.saveQuotation(
              items: cartItems,
              customerId: customerId,
              userId: userId,
              subtotal: subtotal,
              discount: discount,
              tax: tax,
              total: total,
              notes: notes,
            );

      try {
        final activityLogRepo = container.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: userId,
          userName: authState.originalUser?.displayName ?? 'Unknown',
          action: existingId != null ? 'update_quotation' : 'create_quotation',
          entityType: 'quotation',
          entityId: quotationId,
          description: existingId != null
              ? 'تعديل عرض سعر #$quotationNumber'
              : 'إنشاء عرض سعر #$quotationNumber',
          amount: total,
        );
      } catch (_) {}

      if (context.mounted) {
        Navigator.pop(context);
        container
            .read(quotationsControllerProvider.notifier)
            .loadQuotations(); // Refresh list if needed
        AppToast.show(
          context,
          'تم حفظ عرض السعر بنجاح #$quotationNumber',
          type: ToastType.success,
        );
      }
    } catch (e, stack) {
      if (!context.mounted) return;
      AppErrorHandler.handle(context, e, stack);
    }
  }

  Future<void> _saveInvoice({
    required BuildContext context,
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
    bool taxEnabled = true,
    int? convertingQuotationId,
    required List<Product> products,
    int? warehouseId,
    int? costCenterId,
  }) async {
    if (invoiceItems.isEmpty) {
      AppToast.show(
        context,
        'يرجى إضافة صنف واحد على الأقل',
        type: ToastType.error,
      );
      return;
    }

    // Cluster 034 / Issue 2 fix — read providers via ProviderScope on the
    // dialog's BuildContext, NOT via `this.ref`. The screen's State can
    // be disposed (route navigation, provider-driven rebuild) while the
    // dialog stays visible because dialogs run in their own Navigator.
    // `this.ref` would then throw `Bad state: Using "ref" when a widget
    // is about to or has been unmounted is unsafe` — the exception the
    // operator saw as "حالة غير متوقعة". ProviderScope is anchored to
    // the widget tree, not the State, so it survives State disposal.
    final container = ProviderScope.containerOf(context, listen: false);

    // Cluster 034 / Issue 2 diag — trace where _saveInvoice hangs.
    // The previous fix (ProviderScope.containerOf) removed the
    // StateError, but the user reports the dialog still hangs after
    // pressing save. These checkpoints let us see the last reached
    // step before the freeze.
    unawaited(DiagnosticLogger.log('SALES-INVOICE-SAVE',
        'enter _saveInvoice items=${invoiceItems.length} '
        'printAfterSave=$printAfterSave isReturn=$isReturnMode'));

    try {
      final authState = container.read(authProvider);
      final userId = authState.user?.id ?? 1;

      final validItems = <CartItemEntity>[];
      for (final item in invoiceItems) {
        final pId = item['productId'] as int;
        final productFound = products.where((p) => p.id == pId).firstOrNull;
        if (productFound == null) {
          throw Exception('الصنف ${item['productName']} غير متوفر أو تم حذفه');
        }
        validItems.add(
          CartItemEntity(
            productId: productFound.id,
            productName: productFound.name,
            productCode: productFound.code,
            barcode: productFound.barcode,
            quantity: item['quantity'] as double,
            unitPrice: item['unitPrice'] as double,
            taxRate: item['taxRate'] as double,
            taxAmount: item['taxAmount'] as double,
            isSoldByWeight: productFound.isSoldByWeight,
            selectedUnitName: item['selectedUnitName'] as String?,
            quantityInBase: (item['quantityInBase'] as double?) ?? 1.0,
          ),
        );
      }
      unawaited(DiagnosticLogger.log('SALES-INVOICE-SAVE',
          'validated ${validItems.length} items, userId=$userId'));

      // Spec 137 P1: the form's global discount is an ABSOLUTE amount shown in
      // the displayed total, but SaleRequest takes a PERCENT. Convert at full
      // precision (no rounding) so the orchestrator recovers the exact discount
      // amount (round(subtotal * percent/100) == discount) and the SAVED total
      // matches what the cashier saw. Without this the discount was dropped and
      // the customer was charged the undiscounted total.
      final invoiceDiscountPercent =
          subtotal > 0 ? (discount / subtotal * 100) : 0.0;

      // Spec 151 E-06: thread the configured system VAT rate into the request.
      // A taxable line whose per-product taxRate is 0 falls back to
      // request.taxPercent in the orchestrator's two-pass; this path never set
      // it, so SaleRequest's default (formerly a hardcoded 14) applied a 14%
      // rate regardless of jurisdiction. Read the seeded `tax_rate` setting and
      // fall back to the NAMED default only when it is unset/unparseable.
      final systemTaxRate = double.tryParse(
            await container.read(databaseProvider).getSettingValue('tax_rate') ??
                '',
          ) ??
          SaleRequest.kDefaultTaxPercent;

      final request = SaleRequest(
        customerId: customerId,
        userId: userId,
        warehouseId: warehouseId ?? 1,
        paidAmount: paid,
        paymentMethod: paymentMethod,
        isReturn: isReturnMode,
        items: validItems,
        taxEnabled: taxEnabled,
        taxPercent: systemTaxRate,
        discountPercent: invoiceDiscountPercent,
        costCenterId: costCenterId,
      );

      final useCase = container.read(completeSaleUseCaseProvider);
      unawaited(DiagnosticLogger.log('SALES-INVOICE-SAVE',
          'calling useCase.execute (warehouseId=${request.warehouseId} '
          'paymentMethod=${request.paymentMethod})'));
      final result = await useCase.execute(request);
      unawaited(DiagnosticLogger.log('SALES-INVOICE-SAVE',
          'useCase.execute returned success=${result.isSuccess} '
          'invoiceId=${result.invoiceId} err=${result.errorMessage}'));

      if (!result.isSuccess) {
        if (context.mounted) {
          AppToast.show(
            context,
            'خطأ: ${result.errorMessage}',
            type: ToastType.error,
          );
        }
        return;
      }

      final invoiceId = result.invoiceId ?? 0;

      // Print if requested — sales invoices screen prints A4 (the full
      // invoice document), distinct from POS which always prints 80mm
      // thermal via `printReceipt`.
      //
      // Feature 042 (Bug 4) — wrap the call in a timeout + try/catch.
      // The previous bare `await printSalesInvoiceA4(invoiceId)` froze
      // the UI on the mirror device: `Printing.layoutPdf()` on Windows
      // opens the native print-preview dialog and, when the dialog is
      // dismissed without printing (or never opens because no printer
      // is configured), the underlying Future never resolves. The
      // invoice IS already persisted at this point, so a print failure
      // must not block dialog dismissal — we surface a non-blocking
      // toast and proceed. 30s is generous enough for a real print
      // setup and short enough that a hung dialog is recoverable
      // without Task Manager.
      if (printAfterSave) {
        unawaited(DiagnosticLogger.log('SALES-INVOICE-SAVE',
            'calling printSalesInvoiceA4 invoiceId=$invoiceId'));
        final printingService = container.read(printingServiceProvider);
        try {
          await printingService
              .printSalesInvoiceA4(invoiceId)
              .timeout(const Duration(seconds: 30));
        } on TimeoutException catch (e) {
          unawaited(DiagnosticLogger.log('SALES-INVOICE-SAVE',
              'printSalesInvoiceA4 TIMED OUT after 30s invoiceId=$invoiceId err=$e — '
              'invoice already saved, continuing to close dialog'));
          if (context.mounted) {
            AppToast.show(
              context,
              'انتهت مهلة طباعة الفاتورة — الفاتورة محفوظة، يمكنك إعادة الطباعة لاحقاً',
              type: ToastType.warning,
            );
          }
        } catch (e) {
          unawaited(DiagnosticLogger.log('SALES-INVOICE-SAVE',
              'printSalesInvoiceA4 FAILED invoiceId=$invoiceId err=$e — '
              'invoice already saved, continuing to close dialog'));
          if (context.mounted) {
            AppToast.show(
              context,
              'فشلت طباعة الفاتورة: $e — الفاتورة محفوظة',
              type: ToastType.warning,
            );
          }
        }
      }

        if (context.mounted) {
          if (convertingQuotationId != null) {
            // Bound the server round-trip. A hanging ClientWriteInterceptor
            // queue or a dead server used to block this call indefinitely
            // and the silent `catch (_) {}` swallowed the error, so the
            // outer dialog never reached the `Navigator.pop` below — the
            // screen just sat on its loading spinner until the user
            // force-closed it. The invoice itself is already saved at this
            // point; the quotation-status flip is best-effort bookkeeping
            // and must never block dismissal.
            try {
              await container
                  .read(quotationsRepositoryProvider)
                  .updateQuotationStatus(
                    convertingQuotationId,
                    'converted',
                    convertedInvoiceId: invoiceId,
                  )
                  .timeout(const Duration(seconds: 5));
              container.read(quotationsControllerProvider.notifier).loadQuotations();
            } catch (e) {
              debugPrint('[QuotationConvert] status flip failed (non-blocking): $e');
            }
          }

        if (context.mounted) {
          Navigator.pop(context);
          AppToast.show(
            context,
            isReturnMode
                ? 'تم ${printAfterSave ? 'حفظ وطباعة' : 'إنشاء'} إشعار المرتجع بنجاح #$invoiceId'
                : 'تم ${printAfterSave ? 'حفظ وطباعة' : 'إنشاء'} الفاتورة بنجاح #$invoiceId',
            type: ToastType.success,
          );
        }
      }
    } catch (e, stack) {
      if (!context.mounted) return;
      AppErrorHandler.handle(context, e, stack);
    }
  }

  // ══════════════════════════════════════════════════════
  // EDIT INVOICE (Payment Update)
  // ══════════════════════════════════════════════════════

  void _editInvoice(InvoiceEntity invoice) async {
    // Cluster 034 / Issue 2 pattern — capture a ProviderContainer instead
    // of using `this.ref` so subsequent async work (DB reads, dialog
    // builders that fire after navigations) doesn't trip the "ref after
    // unmount" assertion. The edit flow opens its own modal dialog and
    // can outlive the parent State.
    final container = ProviderScope.containerOf(context, listen: false);
    final salesRepo = container.read(salesRepositoryProvider);
    final branchRepo = container.read(branchRepositoryProvider);
    final accountingRepo = container.read(accountingRepositoryProvider);
    final controller = container.read(salesInvoicesControllerProvider.notifier);
    final database = container.read(databaseProvider);

    // Load data
    final customers = await controller.getCustomers();
    final products = await controller.getProducts();
    final warehousesList = await branchRepo.getWarehouses();
    final costCentersList = await accountingRepo.getActiveCostCenters();
    final existingItems = await salesRepo.getInvoiceItemsWithProduct(invoice.id!);

    // Read actual invoice data from DB to get correct warehouseId/costCenterId
    final dbInvoice = await database.getSalesInvoiceById(invoice.id!);

    // Pre-populate
    int? selectedCustomerId = invoice.partyId;
    String? selectedCustomerName = customers
        .where((c) => c.id == invoice.partyId)
        .firstOrNull?.name ?? 'عميل نقدي';
    // Use DB values for warehouse and cost center (more reliable than entity)
    final invoiceWhId = dbInvoice?.warehouseId ?? invoice.warehouseId;
    int? selectedWarehouseId = (invoiceWhId != null && warehousesList.any((w) => w.id == invoiceWhId))
        ? invoiceWhId
        : (warehousesList.isNotEmpty ? warehousesList.first.id : null);
    int? selectedCostCenterId = dbInvoice?.costCenterId ?? invoice.costCenterId;
    String notes = invoice.notes ?? '';
    double subtotal = invoice.subtotal;
    double tax = invoice.taxAmount;
    double total = invoice.total;
    double paid = invoice.paid;
    String paymentMethod = invoice.paymentMethod ?? 'cash';

    final List<Map<String, dynamic>> invoiceItems = existingItems.map((e) {
      final lineTotal = e.item.quantity * e.item.unitPrice;
      return {
        'productId': e.item.productId,
        'productName': e.product.name,
        'quantity': e.item.quantity,
        'unitPrice': e.item.unitPrice,
        'taxRate': e.item.taxRate,
        'taxAmount': e.item.taxAmount,
        'lineTotal': lineTotal,
        'selectedUnitName': e.item.unitName,
        'quantityInBase': e.item.quantityInBase,
      };
    }).toList();

    void recalculate(StateSetter setDialogState) {
      subtotal = 0;
      tax = 0;
      for (final item in invoiceItems) {
        final line = (item['quantity'] as double) * (item['unitPrice'] as double);
        item['lineTotal'] = line;
        item['taxAmount'] = line * (item['taxRate'] as double) / 100;
        subtotal += line;
        tax += item['taxAmount'] as double;
      }
      total = subtotal + tax;
      setDialogState(() {});
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            if (context.mounted) Navigator.pop(context, result);
          },
          child: Directionality(
            textDirection: ui.TextDirection.rtl,
            child: AlertDialog(
              title: Row(
                children: [
                  const Icon(PhosphorIconsBold.pencilSimple, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Text('تعديل فاتورة #${invoice.invoiceNumber}'),
                ],
              ),
              content: SizedBox(
                width: 800,
                height: 600,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Customer & Warehouse Row
                      Row(
                        children: [
                          Expanded(
                            child: Autocomplete<Party>(
                              initialValue: TextEditingValue(text: selectedCustomerName ?? ''),
                              optionsBuilder: (textValue) {
                                if (textValue.text.isEmpty) return customers;
                                return customers.where(
                                  (c) => c.name.toLowerCase().contains(textValue.text.toLowerCase()),
                                );
                              },
                              displayStringForOption: (c) => c.name,
                              fieldViewBuilder: (context, tc, fn, onSub) {
                                return TextField(
                                  controller: tc,
                                  focusNode: fn,
                                  decoration: InputDecoration(
                                    labelText: 'العميل',
                                    prefixIcon: const Icon(PhosphorIconsBold.user),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: selectedCustomerName != null
                                        ? IconButton(
                                            icon: const Icon(PhosphorIconsBold.x, size: 16),
                                            onPressed: () {
                                              tc.clear();
                                              setDialogState(() {
                                                selectedCustomerId = null;
                                                selectedCustomerName = null;
                                              });
                                            },
                                          )
                                        : null,
                                  ),
                                );
                              },
                              onSelected: (c) {
                                setDialogState(() {
                                  selectedCustomerId = c.id;
                                  selectedCustomerName = c.name;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (warehousesList.length > 1)
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                initialValue: selectedWarehouseId,
                                decoration: const InputDecoration(
                                  labelText: 'المخزن',
                                  prefixIcon: Icon(PhosphorIconsBold.warehouse, size: 20),
                                  border: OutlineInputBorder(),
                                ),
                                items: warehousesList.map((w) {
                                  return DropdownMenuItem<int>(value: w.id, child: Text(w.name));
                                }).toList(),
                                onChanged: (val) => setDialogState(() => selectedWarehouseId = val),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Cost Center Row
                      if (costCentersList.isNotEmpty)
                        DropdownButtonFormField<int?>(
                          initialValue: selectedCostCenterId,
                          decoration: const InputDecoration(
                            labelText: 'مركز التكلفة',
                            prefixIcon: Icon(PhosphorIconsBold.buildings, size: 20),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('بدون')),
                            ...costCentersList.map((cc) {
                              return DropdownMenuItem<int?>(value: cc.id, child: Text(cc.name));
                            }),
                          ],
                          onChanged: (val) => setDialogState(() => selectedCostCenterId = val),
                        ),
                      const SizedBox(height: 12),

                      // Product Search
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('إضافة صنف:', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Builder(builder: (context) {
                              TextEditingController? acCtrl;
                              return Autocomplete<Product>(
                                optionsBuilder: (textValue) {
                                  if (textValue.text.isEmpty) return const [];
                                  return products.where(
                                    (p) => p.name.toLowerCase().contains(textValue.text.toLowerCase()) ||
                                        (p.code.toLowerCase().contains(textValue.text.toLowerCase())) ||
                                        (p.barcode?.contains(textValue.text) ?? false),
                                  );
                                },
                                displayStringForOption: (p) => '${p.name} (${p.code})',
                                fieldViewBuilder: (context, tc, fn, onSub) {
                                  acCtrl = tc;
                                  return TextField(
                                    controller: tc,
                                    focusNode: fn,
                                    decoration: const InputDecoration(
                                      hintText: 'ابحث بالاسم أو الكود...',
                                      prefixIcon: Icon(PhosphorIconsBold.magnifyingGlass),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  );
                                },
                                onSelected: (product) {
                                  const qty = 1.0;
                                  final lineTotal = qty * product.salePrice;
                                  final taxAmount = lineTotal * product.taxRate / 100;
                                  setDialogState(() {
                                    invoiceItems.add({
                                      'productId': product.id,
                                      'productName': product.name,
                                      'quantity': qty,
                                      'unitPrice': product.salePrice,
                                      'taxRate': product.taxRate,
                                      'taxAmount': taxAmount,
                                      'lineTotal': lineTotal,
                                    });
                                    recalculate(setDialogState);
                                  });
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    acCtrl?.clear();
                                  });
                                },
                              );
                              }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Items Table
                      if (invoiceItems.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: SingleChildScrollView(
                            child: DataTable(
                              columnSpacing: 12,
                              headingRowHeight: 36,
                              dataRowMinHeight: 32,
                              dataRowMaxHeight: 42,
                              columns: const [
                                DataColumn(label: Text('الصنف', style: TextStyle(fontSize: 12))),
                                DataColumn(label: Text('الوحدة', style: TextStyle(fontSize: 12))),
                                DataColumn(label: Text('الكمية', style: TextStyle(fontSize: 12))),
                                DataColumn(label: Text('السعر', style: TextStyle(fontSize: 12))),
                                DataColumn(label: Text('الضريبة', style: TextStyle(fontSize: 12))),
                                DataColumn(label: Text('الإجمالي', style: TextStyle(fontSize: 12))),
                                DataColumn(label: Text('', style: TextStyle(fontSize: 12))),
                              ],
                              rows: invoiceItems.asMap().entries.map((entry) {
                                final i = entry.key;
                                final item = entry.value;
                                final lineTotal = item['lineTotal'] as double;
                                final itemTotal = lineTotal + (item['taxAmount'] as double);
                                return DataRow(
                                  cells: [
                                    DataCell(Text(item['productName'] as String, style: const TextStyle(fontSize: 12))),
                                    DataCell(
                                      InkWell(
                                        onTap: () async {
                                          // Reuse the captured container
                                          // (declared at the top of
                                          // _editInvoice) — `this.ref` would
                                          // be unsafe here because the dialog
                                          // can outlive the parent State.
                                          final productRepo = container.read(productRepositoryProvider);
                                          final units = await productRepo.getProductUnits(item['productId'] as int);
                                          if (units.isEmpty) return;

                                          if (context.mounted) {
                                            final selectedUnit = await showDialog<ProductUnit>(
                                              context: context,
                                              builder: (context) => SearchableUnitSelectionDialog(
                                                units: units,
                                                currentUnitName: item['selectedUnitName'] as String?,
                                              ),
                                            );

                                            if (selectedUnit != null) {
                                              setDialogState(() {
                                                invoiceItems[i]['selectedUnitName'] = selectedUnit.unitName;
                                                invoiceItems[i]['quantityInBase'] = selectedUnit.quantityInBase;
                                                recalculate(setDialogState);
                                              });
                                            }
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.info.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                (item['selectedUnitName'] as String?) ?? 'قطعة',
                                                style: const TextStyle(color: AppColors.info, fontWeight: FontWeight.bold, fontSize: 10),
                                              ),
                                              const Icon(PhosphorIconsBold.caretDown, size: 8, color: AppColors.info),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      SizedBox(
                                        width: 60,
                                        child: TextFormField(
                                          initialValue: (item['quantity'] as double).toString(),
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: const TextStyle(fontSize: 12),
                                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                                          onChanged: (val) {
                                            item['quantity'] = double.tryParse(val) ?? 0;
                                            recalculate(setDialogState);
                                          },
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      SizedBox(
                                        width: 70,
                                        child: TextFormField(
                                          initialValue: (item['unitPrice'] as double).toStringAsFixed(AppConstants.decimalPlaces),
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: const TextStyle(fontSize: 12),
                                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                                          onChanged: (val) {
                                            item['unitPrice'] = double.tryParse(val) ?? 0;
                                            recalculate(setDialogState);
                                          },
                                        ),
                                      ),
                                    ),
                                    DataCell(Text((item['taxAmount'] as double).toStringAsFixed(AppConstants.decimalPlaces), style: const TextStyle(fontSize: 11))),
                                    DataCell(Text(itemTotal.toStringAsFixed(AppConstants.decimalPlaces), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                    DataCell(
                                      IconButton(
                                        icon: const Icon(PhosphorIconsBold.trash, size: 16, color: AppColors.error),
                                        onPressed: () {
                                          setDialogState(() {
                                            invoiceItems.removeAt(i);
                                            recalculate(setDialogState);
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),

                      const SizedBox(height: 12),

                      // Totals
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            _detailRow('المجموع الفرعي', subtotal.toStringAsFixed(AppConstants.decimalPlaces)),
                            _detailRow('الضريبة', tax.toStringAsFixed(AppConstants.decimalPlaces)),
                            const Divider(),
                            _detailRow('الإجمالي', total.toStringAsFixed(AppConstants.decimalPlaces)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Payment
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: paid.toString(),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'المبلغ المدفوع',
                                prefixIcon: Icon(PhosphorIconsBold.wallet),
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (val) => paid = double.tryParse(val) ?? 0,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: paymentMethod,
                              decoration: const InputDecoration(
                                labelText: 'وسيلة الدفع',
                                prefixIcon: Icon(PhosphorIconsBold.creditCard),
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                                DropdownMenuItem(value: 'card', child: Text('بطاقة')),
                                DropdownMenuItem(value: 'bank', child: Text('تحويل بنكي')),
                                DropdownMenuItem(value: 'click', child: Text('كليك')),
                                DropdownMenuItem(value: 'multiple', child: Text('متعدد')),
                                DropdownMenuItem(value: 'credit', child: Text('آجل')),
                              ],
                              onChanged: (val) => setDialogState(() => paymentMethod = val ?? 'cash'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Notes
                      TextFormField(
                        initialValue: notes,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظات',
                          prefixIcon: Icon(PhosphorIconsBold.notepad),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => notes = val,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    if (invoiceItems.isEmpty) {
                      AppToast.show(context, 'يرجى إضافة صنف واحد على الأقل', type: ToastType.error);
                      return;
                    }
                    try {
                      final items = invoiceItems.asMap().entries.map((entry) {
                        final item = entry.value;
                        return CartItemEntity(
                          productId: item['productId'] as int,
                          productName: item['productName'] as String,
                          productCode: '',
                          quantity: item['quantity'] as double,
                          unitPrice: item['unitPrice'] as double,
                          taxRate: item['taxRate'] as double,
                          taxAmount: item['taxAmount'] as double,
                          selectedUnitName: item['selectedUnitName'] as String?,
                          quantityInBase: (item['quantityInBase'] as double?) ?? 1.0,
                        );
                      }).toList();

                      await salesRepo.updateFullSalesInvoice(
                        invoiceId: invoice.id!,
                        customerId: selectedCustomerId,
                        warehouseId: selectedWarehouseId ?? 1,
                        paid: paid,
                        paymentMethod: paymentMethod,
                        notes: notes.isEmpty ? null : notes,
                        items: items,
                        costCenterId: selectedCostCenterId,
                      );

                      if (context.mounted) {
                        Navigator.pop(context);
                        AppToast.show(context, 'تم تعديل الفاتورة بنجاح', type: ToastType.success);
                      }
                    } catch (e, stack) {
                      if (!context.mounted) return;
                      AppErrorHandler.handle(context, e, stack);
                    }
                  },
                  icon: const Icon(PhosphorIconsBold.floppyDisk),
                  label: const Text('حفظ التعديلات'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  // DELETE INVOICE
  // ══════════════════════════════════════════════════════

  void _deleteInvoice(InvoiceEntity invoice) async {
    final passwordController = TextEditingController();

    if (!mounted) return;

    // Cluster 034 / Issue 2 pattern — the dialog's confirm button runs an
    // async delete and refresh chain that can outlive the parent State.
    // Capture a container so the chain doesn't trip the post-unmount
    // "ref" assertion if the user navigates away before the await
    // resolves.
    final container = ProviderScope.containerOf(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.trash, color: AppColors.error),
              SizedBox(width: 8),
              Text('تأكيد الحذف'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'هل أنت متأكد من حذف فاتورة رقم ${invoice.invoiceNumber}؟',
                ),
                const SizedBox(height: 8),
                const Text(
                  'هذا الإجراء لا يمكن التراجع عنه',
                  style: TextStyle(color: AppColors.error, fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة سر المدير',
                    prefixIcon: Icon(PhosphorIconsBold.lock),
                    border: OutlineInputBorder(),
                    hintText: 'أدخل كلمة السر للتأكيد',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final controller = container.read(
                  salesInvoicesControllerProvider.notifier,
                );
                final isVerified = controller.verifyAdminPassword(
                  passwordController.text,
                );

                if (isVerified) {
                  try {
                    await controller.deleteInvoice(
                      invoice.id!,
                      invoice.invoiceNumber,
                      invoice.total,
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                      AppToast.show(
                        context,
                        'تم حذف الفاتورة بنجاح',
                        type: ToastType.success,
                      );
                    }
                  } catch (e, stack) {
                    if (!context.mounted) return;
                    AppErrorHandler.handle(context, e, stack);
                  }
                } else {
                  if (!context.mounted) return;
                  AppToast.show(
                    context,
                    'كلمة السر غير صحيحة',
                    type: ToastType.error,
                  );
                }
              },
              icon: const Icon(PhosphorIconsBold.trash),
              label: const Text('حذف'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            ),
          ],
        ),
      ),
    );
  }
}
