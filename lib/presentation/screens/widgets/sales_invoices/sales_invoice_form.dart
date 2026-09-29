import 'package:ural_erp/core/i18n/tr.dart';
// Spec 090 — sales invoice form extraction.
//
// Ports the working PurchaseInvoiceForm pattern to sales:
//   showGeneralDialog + Scaffold + ConsumerStatefulWidget
//   (no StatefulBuilder / setDialogState / PopScope / 800x650 AlertDialog).
//
// What MUST be preserved (see project_spec_090_planned.md):
//   - Tax toggle + system default rate
//   - isReturnMode segmented button
//   - isConvert + editQuotation flows (delete vs update quotation)
//   - 4 save buttons (draft quote / save edits / save+print / save F12)
//   - Delivery-company credit default — handled by orchestrator, NOT here
//   - Allow-negative-sale — handled by orchestrator, NOT here
//   - 15s pre-load timeout — handled by caller before showing the form
//   - Unsaved-changes guard — explicit on Cancel, NOT via PopScope
//
// The form does NOT pop the dialog on save success; the
// _saveInvoice / _saveQuotation handlers (in sales_invoice_save_edit.dart)
// already call Navigator.pop themselves, mirroring the existing flow so
// no behavior changes for the save path.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/constants/app_constants.dart' hide InvoiceStatus;
import '../../../../core/logging/diagnostic_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/financial_utils.dart';
import '../../../../core/widgets/unsaved_changes_dialog.dart';
import '../../../../data/providers/providers.dart';
import '../../../../domain/entities/quotation_entity.dart';
import '../../../../domain/repositories/inventory_repository.dart' show WarehouseData;
import '../../../widgets/dialogs/add_product_dialog.dart';
import '../../../widgets/searchable_unit_selection_dialog.dart';
import '../../sales_invoices_controller.dart';

typedef SalesInvoiceSaveQuotationCallback = Future<void> Function({
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
});

typedef SalesInvoiceSaveInvoiceCallback = Future<void> Function({
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
});

class SalesInvoiceForm extends ConsumerStatefulWidget {
  final List<Party> customers;
  final List<Product> initialProducts;
  final List<Category> categories;
  final List<WarehouseData> warehouses;
  final List<CostCenter> costCenters;

  /// System default tax rate as a decimal (e.g. 0.14 for 14%).
  final double systemTaxRate;

  /// When non-null AND [isConvert] is false → edit-quotation mode.
  /// When non-null AND [isConvert] is true → convert-quotation-to-invoice mode.
  final QuotationEntity? editQuotation;
  final bool isConvert;

  final SalesInvoiceSaveQuotationCallback onSaveQuotation;
  final SalesInvoiceSaveInvoiceCallback onSaveInvoice;

  const SalesInvoiceForm({
    super.key,
    required this.customers,
    required this.initialProducts,
    required this.categories,
    required this.warehouses,
    required this.costCenters,
    required this.systemTaxRate,
    required this.onSaveQuotation,
    required this.onSaveInvoice,
    this.editQuotation,
    this.isConvert = false,
  });

  @override
  ConsumerState<SalesInvoiceForm> createState() => _SalesInvoiceFormState();
}

class _SalesInvoiceFormState extends ConsumerState<SalesInvoiceForm> {
  // Mutable product list — extended when the user creates a new product
  // mid-invoice via AddProductDialog.
  late List<Product> _products;

  int? _selectedCustomerId;
  String? _selectedCustomerName;
  int? _selectedWarehouseId;
  int? _selectedCostCenterId;
  String _paymentMethod = 'cash';
  String _notes = '';
  double _subtotal = 0;
  double _discount = 0;
  double _tax = 0;
  double _total = 0;
  double _paid = 0;
  bool _isReturnMode = false;
  // Tax toggle: enabled by default if the source quotation already had tax.
  late bool _taxEnabled;
  bool _isLoading = false;

  final List<Map<String, dynamic>> _invoiceItems = [];

  @override
  void initState() {
    super.initState();
    unawaited(DiagnosticLogger.log('SPEC-090-FORM',
        'initState — editQuotation=${widget.editQuotation?.id} '
        'isConvert=${widget.isConvert} '
        'customers=${widget.customers.length} '
        'products=${widget.initialProducts.length} '
        'warehouses=${widget.warehouses.length}'));
    _products = List<Product>.from(widget.initialProducts);

    // Default warehouse = isDefault row, else first.
    _selectedWarehouseId = widget.warehouses
            .where((w) => w.isDefault)
            .firstOrNull
            ?.id ??
        widget.warehouses.firstOrNull?.id;

    // Default cost center from the default warehouse (if any).
    _selectedCostCenterId = widget.warehouses
        .where((w) => w.id == _selectedWarehouseId)
        .firstOrNull
        ?.costCenterId;

    final q = widget.editQuotation;
    if (q != null) {
      _selectedCustomerId = q.customerId;
      _selectedCustomerName = q.customerName;
      _notes = q.notes ?? '';
      _subtotal = q.subtotal;
      _discount = q.discount;
      _tax = q.tax;
      _total = q.total;
      _taxEnabled = q.tax > 0;
      for (final e in q.items) {
        _invoiceItems.add({
          'productId': e.productId,
          'productName': e.productName ?? '',
          'categoryId': null,
          'taxRate': e.taxRate,
          'quantity': e.quantity,
          'unitPrice': e.unitPrice,
          'lineTotal': e.total,
          'taxAmount': e.taxAmount,
        });
      }
    } else {
      // Spec 135 BUG-B — tax ON by default for new invoices. Previously
      // false, so a new invoice's displayed total excluded the system tax
      // even though the sales-transaction orchestrator persists per-line
      // taxAmount unconditionally (it uses item.taxAmount when > 0, and only
      // falls back to the taxEnabled-gated system rate for zero-rate lines).
      // The default-off therefore (a) hid tax from the cashier on configured-
      // tax products while still saving it, and (b) skipped the system rate
      // on zero-rate products. Defaulting ON makes the form total match what
      // is persisted and applies the system rate as intended. No double-count:
      // the orchestrator picks per-line taxAmount OR the system rate, never both.
      _taxEnabled = true;
    }
  }

  @override
  void dispose() {
    unawaited(DiagnosticLogger.log('SPEC-090-FORM',
        'dispose — form unmounted (route popped). '
        'items=${_invoiceItems.length} isLoading=$_isLoading'));
    super.dispose();
  }

  String _getCategoryName(int? categoryId) {
    if (categoryId == null) return '-';
    return widget.categories.where((c) => c.id == categoryId).firstOrNull?.name ?? '-';
  }

  void _recalculate() {
    final effectiveTaxRate = _taxEnabled ? (widget.systemTaxRate * 100) : 0.0;
    final totals = FinancialUtils.calculateInvoiceTotals(
      items: _invoiceItems.map((item) {
        final itemTax = item['taxRate'] as double;
        final appliedTax =
            _taxEnabled ? (itemTax > 0 ? itemTax : effectiveTaxRate) : 0.0;
        return (
          quantity: item['quantity'] as double,
          unitPrice: item['unitPrice'] as double,
          taxRatePercent: appliedTax,
        );
      }).toList(),
      globalDiscountAmount: _discount,
    );
    _subtotal = totals.subtotal;
    _tax = totals.totalTax;
    _total = totals.grandTotal;
    if (_paymentMethod == 'cash') {
      _paid = _total;
    }
    setState(() {});
  }

  void _addProductToInvoice(Product product) {
    setState(() {
      const qty = 1.0;
      final lineTotal = FinancialUtils.calculateLineSubtotal(qty, product.salePrice);
      final taxAmount =
          FinancialUtils.calculateTaxAmount(lineTotal, product.taxRate);
      _invoiceItems.add({
        'productId': product.id,
        'productName': product.name,
        'categoryId': product.categoryId,
        'taxRate': product.taxRate,
        'quantity': qty,
        'unitPrice': product.salePrice,
        'lineTotal': lineTotal,
        'taxAmount': taxAmount,
      });
    });
    _recalculate();
  }

  Future<void> _handleAddNewProduct() async {
    final result = await AddProductDialog.show(context);
    if (result == null) return;
    final controller = ref.read(salesInvoicesControllerProvider.notifier);
    final updatedProducts = await controller.getProducts();
    final newProduct =
        updatedProducts.where((p) => p.id == result.productId).firstOrNull;
    if (!mounted) return;
    setState(() {
      _products = updatedProducts;
    });
    if (newProduct != null) {
      _addProductToInvoice(newProduct);
    }
  }

  Future<void> _handleCancel() async {
    unawaited(DiagnosticLogger.log('SPEC-090-FORM',
        '_handleCancel pressed — items=${_invoiceItems.length} '
        'isLoading=$_isLoading'));
    if (_invoiceItems.isNotEmpty) {
      final discard = await UnsavedChangesDialog.show(context);
      if (!discard) {
        unawaited(DiagnosticLogger.log('SPEC-090-FORM',
            '_handleCancel — user chose to stay; not popping'));
        return;
      }
      if (!mounted) {
        unawaited(DiagnosticLogger.log('SPEC-090-FORM',
            '_handleCancel — form unmounted after discard dialog; skipping pop'));
        return;
      }
    }
    unawaited(DiagnosticLogger.log('SPEC-090-FORM',
        '_handleCancel — calling Navigator.pop'));
    Navigator.of(context).pop();
    unawaited(DiagnosticLogger.log('SPEC-090-FORM',
        '_handleCancel — Navigator.pop returned (sync)'));
  }

  Future<void> _runSaveQuotation() async {
    if (_isLoading) return;
    unawaited(DiagnosticLogger.log('SPEC-090-FORM',
        '_runSaveQuotation entered — items=${_invoiceItems.length}'));
    setState(() => _isLoading = true);
    try {
      await widget.onSaveQuotation(
        dialogContext: context,
        existingId: widget.editQuotation?.id,
        existingNumber: widget.editQuotation?.quotationNumber,
        customerId: _selectedCustomerId,
        notes: _notes,
        invoiceItems: _invoiceItems,
        subtotal: _subtotal,
        discount: _discount,
        tax: _tax,
        total: _total,
      );
      unawaited(DiagnosticLogger.log('SPEC-090-FORM',
          '_runSaveQuotation — onSaveQuotation returned; mounted=$mounted'));
    } finally {
      if (mounted) {
        unawaited(DiagnosticLogger.log('SPEC-090-FORM',
            '_runSaveQuotation finally — form still mounted at this microtask; '
                'resetting _isLoading. Pop may still be pending for next frame.'));
        setState(() => _isLoading = false);
      } else {
        unawaited(DiagnosticLogger.log('SPEC-090-FORM',
            '_runSaveQuotation finally — form unmounted (expected pop happened)'));
      }
    }
  }

  Future<void> _runSaveInvoice({required bool printAfterSave}) async {
    if (_isLoading) return;
    unawaited(DiagnosticLogger.log('SPEC-090-FORM',
        '_runSaveInvoice entered — printAfterSave=$printAfterSave '
        'items=${_invoiceItems.length} isReturn=$_isReturnMode '
        'isConvert=${widget.isConvert}'));
    setState(() => _isLoading = true);
    try {
      await widget.onSaveInvoice(
        dialogContext: context,
        customerId: _selectedCustomerId,
        paymentMethod: _paymentMethod,
        notes: _notes,
        invoiceItems: _invoiceItems,
        subtotal: _subtotal,
        discount: _discount,
        tax: _tax,
        total: _total,
        paid: _paid,
        isReturnMode: _isReturnMode,
        printAfterSave: printAfterSave,
        taxEnabled: _taxEnabled,
        convertingQuotationId:
            widget.isConvert ? widget.editQuotation?.id : null,
        products: _products,
        warehouseId: _selectedWarehouseId,
        costCenterId: _selectedCostCenterId,
      );
      unawaited(DiagnosticLogger.log('SPEC-090-FORM',
          '_runSaveInvoice — onSaveInvoice returned; mounted=$mounted'));
    } finally {
      if (mounted) {
        unawaited(DiagnosticLogger.log('SPEC-090-FORM',
            '_runSaveInvoice finally — form still mounted at this microtask; '
            'resetting _isLoading. Pop may still be pending for next frame.'));
        setState(() => _isLoading = false);
      } else {
        unawaited(DiagnosticLogger.log('SPEC-090-FORM',
            '_runSaveInvoice finally — form unmounted (pop happened as expected)'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editQ = widget.editQuotation;
    final isEditQuotation = editQ != null && !widget.isConvert;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(isEditQuotation: isEditQuotation),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isEditQuotation && !widget.isConvert)
                      _buildReturnToggle(),
                    _buildCustomerAndDateRow(),
                    const SizedBox(height: 12),
                    if (widget.warehouses.length > 1) _buildWarehouseDropdown(),
                    _buildCostCenterDropdown(),
                    _buildAddProductCard(),
                    const SizedBox(height: 16),
                    _buildItemsSection(),
                    const SizedBox(height: 16),
                    _buildTotalsCard(),
                    const SizedBox(height: 16),
                    _buildNotesField(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildActions(isEditQuotation: isEditQuotation),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader({required bool isEditQuotation}) {
    final editQ = widget.editQuotation;
    final iconData = isEditQuotation
        ? PhosphorIconsBold.pencilSimple
        : widget.isConvert
            ? PhosphorIconsBold.shoppingCart
            : _isReturnMode
                ? PhosphorIconsBold.arrowCounterClockwise
                : PhosphorIconsBold.plus;
    final color = isEditQuotation
        ? AppColors.info
        : _isReturnMode
            ? AppColors.error
            : AppColors.success;
    final title = isEditQuotation
        ? tr('تعديل عرض سعر #{p0}', {'p0': editQ?.quotationNumber ?? ''})
        : widget.isConvert
            ? tr('تحويل عرض سعر #{p0} لفاتورة', {'p0': editQ?.quotationNumber ?? ''})
            : _isReturnMode
                ? tr('مرتجع مبيعات')
                : tr('فاتورة مبيعات جديدة');
    return Row(
      children: [
        Icon(iconData, color: color, size: 28),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
        IconButton(
          tooltip: tr('إغلاق'),
          icon: const Icon(PhosphorIconsBold.x),
          onPressed: _isLoading ? null : _handleCancel,
        ),
      ],
    );
  }

  Widget _buildReturnToggle() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      child: SegmentedButton<bool>(
        segments:  [
          ButtonSegment<bool>(
            value: false,
            icon: const Icon(PhosphorIconsBold.receipt),
            label: Text(tr('فاتورة بيع')),
          ),
          ButtonSegment<bool>(
            value: true,
            icon: const Icon(PhosphorIconsBold.arrowCounterClockwise),
            label: Text(tr('مرتجع مبيعات')),
          ),
        ],
        selected: {_isReturnMode},
        onSelectionChanged: (sel) =>
            setState(() => _isReturnMode = sel.first),
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: _isReturnMode
              ? AppColors.error.withValues(alpha: 0.15)
              : AppColors.success.withValues(alpha: 0.15),
          selectedForegroundColor:
              _isReturnMode ? AppColors.error : AppColors.success,
        ),
      ),
    );
  }

  Widget _buildCustomerAndDateRow() {
    return Row(
      children: [
        Expanded(
          child: Autocomplete<Party>(
            initialValue: _selectedCustomerName != null
                ? TextEditingValue(text: _selectedCustomerName!)
                : null,
            optionsBuilder: (textValue) {
              if (textValue.text.isEmpty) return widget.customers;
              return widget.customers.where(
                (c) =>
                    c.name.toLowerCase().contains(textValue.text.toLowerCase()) ||
                    (c.phone?.contains(textValue.text) ?? false),
              );
            },
            displayStringForOption: (c) => c.name,
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  labelText: tr('العميل'),
                  prefixIcon: const Icon(PhosphorIconsBold.user),
                  border: const OutlineInputBorder(),
                  hintText: tr('ابحث عن العميل (اتركه فارغاً للنقدي)...'),
                  suffixIcon: _selectedCustomerName != null
                      ? IconButton(
                          icon: const Icon(PhosphorIconsBold.x, size: 16),
                          onPressed: () {
                            controller.clear();
                            setState(() {
                              _selectedCustomerId = null;
                              _selectedCustomerName = null;
                            });
                          },
                        )
                      : null,
                ),
              );
            },
            onSelected: (customer) {
              setState(() {
                _selectedCustomerId = customer.id;
                _selectedCustomerName = customer.name;
              });
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TextFormField(
            readOnly: true,
            decoration: InputDecoration(
              labelText: tr('التاريخ'),
              prefixIcon: const Icon(PhosphorIconsBold.calendar),
              border: const OutlineInputBorder(),
              hintText: DateTime.now().toString().substring(0, 10),
            ),
            initialValue: DateTime.now().toString().substring(0, 10),
          ),
        ),
      ],
    );
  }

  Widget _buildWarehouseDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int>(
        initialValue: _selectedWarehouseId,
        decoration:  InputDecoration(
          labelText: tr('المخزن'),
          prefixIcon: const Icon(PhosphorIconsBold.warehouse, size: 20),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: widget.warehouses
            .map((w) => DropdownMenuItem<int>(
                  value: w.id,
                  child: Text(w.name, style: const TextStyle(fontSize: 13)),
                ))
            .toList(),
        onChanged: (val) => setState(() {
          _selectedWarehouseId = val;
          _selectedCostCenterId = widget.warehouses
              .where((w) => w.id == val)
              .firstOrNull
              ?.costCenterId;
        }),
      ),
    );
  }

  Widget _buildCostCenterDropdown() {
    if (widget.costCenters.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int?>(
        value: _selectedCostCenterId,
        decoration:  InputDecoration(
          labelText: tr('مركز التكلفة'),
          prefixIcon: const Icon(PhosphorIconsBold.buildings, size: 20),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
           DropdownMenuItem<int?>(value: null, child: Text(tr('بدون'))),
          ...widget.costCenters.map((cc) => DropdownMenuItem<int?>(
                value: cc.id,
                child: Text(cc.name),
              )),
        ],
        onChanged: (v) => setState(() => _selectedCostCenterId = v),
      ),
    );
  }

  Widget _buildAddProductCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                 Text(
                  tr('إضافة صنف:'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _handleAddNewProduct,
                  icon: const Icon(PhosphorIconsBold.plusCircle, size: 16),
                  label:  Text(tr('إضافة صنف جديد')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.success,
                    side: const BorderSide(color: AppColors.success),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              TextEditingController? acCtrl;
              return Autocomplete<Product>(
                optionsBuilder: (textValue) {
                  if (textValue.text.isEmpty) {
                    return const Iterable<Product>.empty();
                  }
                  return _products.where(
                    (p) =>
                        p.name.toLowerCase().contains(textValue.text.toLowerCase()) ||
                        p.code.contains(textValue.text),
                  );
                },
                displayStringForOption: (p) => p.name,
                fieldViewBuilder: (context, acController, focusNode, onFieldSubmitted) {
                  acCtrl = acController;
                  return TextField(
                    controller: acController,
                    focusNode: focusNode,
                    decoration:  InputDecoration(
                      hintText: tr('ابحث عن صنف بالاسم أو الباركود...'),
                      prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                      border: const OutlineInputBorder(),
                    ),
                  );
                },
                onSelected: (product) {
                  _addProductToInvoice(product);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    acCtrl?.clear();
                  });
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Text(tr('الأصناف:'), style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_invoiceItems.isEmpty)
          Container(
            height: 100,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child:  Center(
              child: Text(
                tr('لم يتم إضافة أصناف بعد'),
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
          )
        else
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 12,
                columns:  [
                  DataColumn(label: Text(tr('الصنف'))),
                  DataColumn(label: Text(tr('الوحدة'))),
                  DataColumn(label: Text(tr('التصنيف'))),
                  DataColumn(label: Text(tr('الكمية'))),
                  DataColumn(label: Text(tr('سعر البيع'))),
                  DataColumn(label: Text(tr('الضريبة %'))),
                  DataColumn(label: Text(tr('قيمة الضريبة'))),
                  DataColumn(label: Text(tr('الإجمالي'))),
                  const DataColumn(label: Text('')),
                ],
                rows: _invoiceItems.asMap().entries.map(_buildItemRow).toList(),
              ),
            ),
          ),
      ],
    );
  }

  DataRow _buildItemRow(MapEntry<int, Map<String, dynamic>> entry) {
    final index = entry.key;
    final item = entry.value;
    final taxRate = item['taxRate'] as double;
    final taxAmount = item['taxAmount'] as double;
    final lineTotal = item['lineTotal'] as double;
    return DataRow(
      cells: [
        DataCell(Text(item['productName'] as String)),
        DataCell(
          InkWell(
            onTap: () async {
              final productRepo = ref.read(productRepositoryProvider);
              final units =
                  await productRepo.getProductUnits(item['productId'] as int);
              if (units.isEmpty) return;
              if (!mounted) return;
              final selectedUnit = await showDialog<ProductUnit>(
                context: context,
                builder: (context) => SearchableUnitSelectionDialog(
                  units: units,
                  currentUnitName: item['selectedUnitName'] as String?,
                ),
              );
              if (selectedUnit != null) {
                setState(() {
                  _invoiceItems[index]['selectedUnitName'] = selectedUnit.unitName;
                  _invoiceItems[index]['quantityInBase'] =
                      selectedUnit.quantityInBase;
                });
                _recalculate();
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
                    (item['selectedUnitName'] as String?) ?? tr('قطعة'),
                    style: const TextStyle(
                      color: AppColors.info,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  const Icon(PhosphorIconsBold.caretDown, size: 10, color: AppColors.info),
                ],
              ),
            ),
          ),
        ),
        DataCell(Text(_getCategoryName(item['categoryId'] as int?))),
        DataCell(
          SizedBox(
            width: 60,
            child: TextFormField(
              key: ValueKey('inv_qty_${index}_${item['productId']}'),
              initialValue: (item['quantity'] as double).toStringAsFixed(0),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (val) {
                final qty = double.tryParse(val) ?? 1;
                final unitPrice = item['unitPrice'] as double;
                final newLineTotal =
                    FinancialUtils.calculateLineSubtotal(qty, unitPrice);
                final newTaxAmount =
                    FinancialUtils.calculateTaxAmount(newLineTotal, taxRate);
                _invoiceItems[index]['quantity'] = qty;
                _invoiceItems[index]['lineTotal'] = newLineTotal;
                _invoiceItems[index]['taxAmount'] = newTaxAmount;
                _recalculate();
              },
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 80,
            child: TextFormField(
              key: ValueKey('inv_price_${index}_${item['productId']}'),
              initialValue: (item['unitPrice'] as double)
                  .toStringAsFixed(AppConstants.decimalPlaces),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (val) {
                final price = double.tryParse(val) ?? 0;
                final qty = item['quantity'] as double;
                final newLineTotal =
                    FinancialUtils.calculateLineSubtotal(qty, price);
                final newTaxAmount =
                    FinancialUtils.calculateTaxAmount(newLineTotal, taxRate);
                _invoiceItems[index]['unitPrice'] = price;
                _invoiceItems[index]['lineTotal'] = newLineTotal;
                _invoiceItems[index]['taxAmount'] = newTaxAmount;
                _recalculate();
              },
            ),
          ),
        ),
        DataCell(Text('${taxRate.toStringAsFixed(0)}%')),
        DataCell(Text(taxAmount.toStringAsFixed(AppConstants.decimalPlaces))),
        DataCell(Text(lineTotal.toStringAsFixed(AppConstants.decimalPlaces))),
        DataCell(
          IconButton(
            icon: const Icon(PhosphorIconsBold.trash, color: AppColors.error, size: 18),
            onPressed: () {
              setState(() => _invoiceItems.removeAt(index));
              _recalculate();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTotalsCard() {
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                 Text(tr('المجموع الفرعي:')),
                Text(_subtotal.toStringAsFixed(AppConstants.decimalPlaces)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                 Text(tr('الخصم:')),
                const SizedBox(width: 16),
                SizedBox(
                  width: 100,
                  child: TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (val) {
                      _discount = double.tryParse(val) ?? 0;
                      _recalculate();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  tr('الضريبة ({p0}%):', {'p0': (widget.systemTaxRate * 100).toStringAsFixed(0)}),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 28,
                  child: Switch(
                    value: _taxEnabled,
                    activeColor: AppColors.primary,
                    onChanged: (val) {
                      _taxEnabled = val;
                      _recalculate();
                    },
                  ),
                ),
                const Spacer(),
                Text(
                  _tax.toStringAsFixed(AppConstants.decimalPlaces),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _taxEnabled ? AppColors.primary : Colors.grey,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                 Text(
                  tr('الإجمالي:'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(
                  _total.toStringAsFixed(AppConstants.decimalPlaces),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                 Text(tr('المدفوع:')),
                const SizedBox(width: 16),
                SizedBox(
                  width: 120,
                  child: TextField(
                    key: ValueKey('paid_${_paymentMethod}_$_total'),
                    controller: TextEditingController(
                      text: _paymentMethod != 'credit'
                          ? _total.toStringAsFixed(AppConstants.decimalPlaces)
                          : '0',
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    enabled: _paymentMethod != 'credit',
                    onChanged: (val) =>
                        setState(() => _paid = double.tryParse(val) ?? 0),
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _paymentMethod,
                  items:  [
                    DropdownMenuItem(value: 'cash', child: Text(tr('نقدي'))),
                    DropdownMenuItem(value: 'credit', child: Text(tr('آجل'))),
                    DropdownMenuItem(value: 'bank', child: Text(tr('تحويل'))),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _paymentMethod = val ?? 'cash';
                      _paid = _paymentMethod == 'credit' ? 0 : _total;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      initialValue: _notes,
      decoration:  InputDecoration(
        labelText: tr('ملاحظات'),
        prefixIcon: const Icon(PhosphorIconsBold.note),
        border: const OutlineInputBorder(),
      ),
      maxLines: 2,
      onChanged: (val) => _notes = val,
    );
  }

  Widget _buildActions({required bool isEditQuotation}) {
    final loadingSpinner = _isLoading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : null;

    if (isEditQuotation) {
      // Edit-quotation mode: Cancel + Save edits.
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton.icon(
            onPressed: _isLoading ? null : _handleCancel,
            icon: const Icon(PhosphorIconsBold.x),
            label:  Text(tr('إلغاء')),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _runSaveQuotation,
            icon: loadingSpinner ?? const Icon(PhosphorIconsBold.floppyDisk),
            label:  Text(tr('حفظ التعديلات')),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
          ),
        ],
      );
    }

    // Normal invoice / convert mode.
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (!_isReturnMode && !widget.isConvert)
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _runSaveQuotation,
            icon: const Icon(PhosphorIconsBold.fileText),
            label:  Text(tr('حفظ مسودة عرض أسعار')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple.shade50,
              foregroundColor: Colors.purple.shade700,
              elevation: 0,
              side: BorderSide(color: Colors.purple.shade200),
            ),
          ),
        TextButton.icon(
          onPressed: _isLoading ? null : _handleCancel,
          icon: const Icon(PhosphorIconsBold.x),
          label:  Text(tr('إلغاء')),
        ),
        ElevatedButton.icon(
          onPressed:
              _isLoading ? null : () => _runSaveInvoice(printAfterSave: true),
          icon: loadingSpinner ?? const Icon(PhosphorIconsBold.printer),
          label: Text(widget.isConvert ? tr('تأكيد التحويل وطباعة') : tr('حفظ وطباعة')),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
        ),
        ElevatedButton.icon(
          onPressed:
              _isLoading ? null : () => _runSaveInvoice(printAfterSave: false),
          icon: loadingSpinner ?? const Icon(PhosphorIconsBold.floppyDisk),
          label:  Text(tr('حفظ الفاتورة (F12)')),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
        ),
      ],
    );
  }
}

