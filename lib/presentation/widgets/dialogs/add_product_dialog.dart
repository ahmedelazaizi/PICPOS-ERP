import 'package:ural_erp/core/i18n/tr.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/utils/number_utils.dart';
import '../../../domain/entities/product_entity.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../core/theme/app_colors.dart';
import 'product_form_helpers.dart';
// دفعة ٨ — نفس حرّاس `products_expiry`/`products_image` بتوع ديالوج التعديل.
// ديالوج «إضافة صنف» ده موقع تاني حيّ لنفس الحقول (شاشة الأصناف للبراندين،
// وفورم فاتورة المبيعات، وفورم المشتريات كلهم بيفتحوه) وكان فايت من الفرز.
import '../../screens/products/widgets/product_edit_dialog.dart'
    show buildProductExpirySectionGuarded, buildProductImageActionsGuarded;

import '../../../core/config/app_config.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../services/license_service.dart';
import '../../../data/providers/providers.dart';
import '../../../services/client_write_interceptor.dart';
import '../../../core/utils/uuid_v7.dart';

/// Result returned when a product is successfully added
class AddProductResult {
  final int productId;
  final String productName;
  final double salePrice;
  final double costPrice;

  AddProductResult({
    required this.productId,
    required this.productName,
    required this.salePrice,
    required this.costPrice,
  });
}

/// Reusable dialog for adding new products
/// Used in: Products screen, Sales Invoices, Purchase Invoices
class AddProductDialog extends ConsumerStatefulWidget {
  /// Optional callback when product is successfully added
  final void Function(AddProductResult)? onProductAdded;

  /// Whether to show simplified form (for quick add in invoices)
  final bool simplified;

  const AddProductDialog({
    super.key,
    this.onProductAdded,
    this.simplified = false,
  });

  /// Show the dialog and return the result
  static Future<AddProductResult?> show(
    BuildContext context, {
    bool simplified = false,
  }) async {
    return showDialog<AddProductResult>(
      context: context,
      builder: (context) => AddProductDialog(simplified: simplified),
    );
  }

  @override
  ConsumerState<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends ConsumerState<AddProductDialog> {
  // Controllers
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _salePriceController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _minStockController = TextEditingController(text: '0');
  final _shelfDaysController = TextEditingController(text: '90');
  final _alertDaysController = TextEditingController(text: '30');
  final _pricePerUnitController = TextEditingController();
  final _taxRateController = TextEditingController(text: '0');
  final _priceTalabatController = TextEditingController(text: '0');
  final _priceCareemController = TextEditingController(text: '0');
  final _priceAshyaeController = TextEditingController(text: '0');
  final _wholesalePriceController = TextEditingController(text: '0');
  final _scalePluNumberController = TextEditingController();
  // Cluster 023 / Issue 7 — opening stock balance for the product's
  // default warehouse. When > 0, the post-create flow calls the
  // canonical adjustStock(type='opening_stock') so stock_movements +
  // inventory_balances + products.current_stock are populated atomically.
  final _openingBalanceController = TextEditingController(text: '0');

  // State
  bool _trackExpiry = false;
  String _scaleType = 'count'; // count, weight, weightByPiece, display
  bool _allowNegativeSale = false;
  Uint8List? _selectedImage;
  int? _selectedCategoryId;
  int? _selectedSupplierId;
  int? _selectedWarehouseId;
  String _productType = 'general';
  bool _isLoading = false;
  bool _showWarehousePrices = false;
  final List<_WarehousePriceRow> _warehousePriceRows = [];

  // Built ONCE, not inside build(). A Future created inline makes its
  // `FutureBuilder` restart on every setState, which empties the option list
  // and (combined with `Autocomplete`'s one-shot `initialValue`) blanks the
  // field. Harmless here because add mode starts with no selection, but the
  // same shape is what broke the edit dialog — fixed in both to keep it fixed.
  Future<List<Category>>? _categoriesFuture;
  Future<List<Party>>? _suppliersFuture;

  // Multi-unit packaging rows (up to 5 units)
  bool _showPackagingUnits = false;
  final List<_ProductUnitRow> _unitRows = [];
  int _defaultUnitIndex = 0; // which unit is the default

  // Cluster 023 / Issue 11 — BOM (composite raw materials) inline in the
  // create dialog. When the user fills any rows, the post-create flow
  // calls manufacturingRepo.createBOM with autoDepleteOnSale=true and
  // depletionPolicy='always_auto_deplete' so a sale of this finished
  // product automatically deducts the raw materials at sale time
  // (Feature 009 / US1 contract).
  bool _showBomComponents = false;
  final List<_BomComponentRow> _bomRows = [];

  bool get _isSoldByWeight =>
      _scaleType == 'weight' || _scaleType == 'weightByPiece';

  @override
  void initState() {
    super.initState();
    _loadNextCode();
  }

  Future<void> _loadNextCode() async {
    final productRepo = ref.read(productRepositoryProvider);
    final nextCode = await productRepo.getNextProductCode();
    if (mounted) {
      setState(() {
        _codeController.text = nextCode;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _barcodeController.dispose();
    _salePriceController.dispose();
    _costPriceController.dispose();
    _minStockController.dispose();
    _shelfDaysController.dispose();
    _alertDaysController.dispose();
    _pricePerUnitController.dispose();
    _taxRateController.dispose();
    _priceTalabatController.dispose();
    _priceCareemController.dispose();
    _priceAshyaeController.dispose();
    _wholesalePriceController.dispose();
    _scalePluNumberController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                PhosphorIconsBold.plusCircle,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
             Text(tr('إضافة صنف جديد'), style: const TextStyle(fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Basic Data Section
                _buildSectionHeader(
                  tr('البيانات الأساسية'),
                  PhosphorIconsBold.package,
                  AppColors.primary,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildCompactTextField(
                        _nameController,
                        tr('اسم الصنف *'),
                        icon: PhosphorIconsBold.tag,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildCompactTextField(_codeController, tr('الكود')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildCompactTextField(
                        _barcodeController,
                        tr('الباركود'),
                        icon: PhosphorIconsBold.barcode,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildCompactTextField(
                        _salePriceController,
                        tr('سعر البيع *'),
                        isNumber: true,
                        icon: PhosphorIconsBold.currencyDollar,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildCompactTextField(
                        _costPriceController,
                        tr('سعر التكلفة'),
                        isNumber: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      // البند 4: كان حقلاً نصياً حراً يقبل أي رقم.
                      child: ProductFormHelpers.buildTaxRateDropdown(
                        _taxRateController,
                        icon: PhosphorIconsBold.percent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildCompactTextField(
                        _minStockController,
                        tr('الحد الأدنى'),
                        isNumber: true,
                        icon: PhosphorIconsBold.warning,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Cluster 023 / Issue 7 — opening balance field. Routed
                    // through inventoryRepo.adjustStock(type='opening_stock')
                    // after the product is created (see _save). Requires a
                    // warehouse pick — the helper validates that.
                    Expanded(
                      child: _buildCompactTextField(
                        _openingBalanceController,
                        tr('الرصيد الافتتاحى'),
                        isNumber: true,
                        icon: PhosphorIconsBold.stack,
                      ),
                    ),
                  ],
                ),

                // Platform Prices (hidden in simplified mode)
                if (!widget.simplified) ...[
                  const SizedBox(height: 8),
                   Text(
                    tr('أسعار المنصات'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildCompactTextField(
                          _priceTalabatController,
                          tr('سعر طلبات'),
                          isNumber: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildCompactTextField(
                          _priceCareemController,
                          tr('سعر كريم'),
                          isNumber: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildCompactTextField(
                          _priceAshyaeController,
                          tr('سعر أشيائي'),
                          isNumber: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildCompactTextField(
                          _wholesalePriceController,
                          tr('سعر الجملة'),
                          isNumber: true,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),

                // Category Dropdown
                FutureBuilder<List<Category>>(
                  future: _categoriesFuture ??=
                      ref.read(productRepositoryProvider).getCategories(),
                  builder: (context, snapshot) {
                    final categories = snapshot.data ?? [];
                    return SizedBox(
                      height: 44,
                      child: Autocomplete<Category>(
                        key: ValueKey(
                            'category-${categories.length}-$_selectedCategoryId'),
                        initialValue: TextEditingValue(
                          text: _selectedCategoryId != null
                              ? (categories.where((c) => c.id == _selectedCategoryId).firstOrNull?.name ?? '')
                              : '',
                        ),
                        optionsBuilder: (textValue) {
                          final q = textValue.text.toLowerCase().trim();
                          if (q.isEmpty) return categories;
                          return categories.where((c) => c.name.toLowerCase().contains(q));
                        },
                        displayStringForOption: (c) => c.name,
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: tr('التصنيف *'),
                              hintText: tr('ابحث عن التصنيف...'),
                              prefixIcon: const Icon(PhosphorIconsBold.squaresFour, size: 18),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                          );
                        },
                        onSelected: (cat) {
                          setState(() => _selectedCategoryId = cat.id);
                        },
                      ),
                    );
                  },
                ),

                const SizedBox(height: 8),

                // Product Type + Warehouse Row
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: DropdownButtonFormField<String>(
                          initialValue: _productType,
                          decoration: InputDecoration(
                            labelText: tr('نوع الصنف'),
                            prefixIcon: const Icon(PhosphorIconsBold.factory, size: 18),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                          items:  [
                            DropdownMenuItem(value: 'general', child: Text(tr('عام'), style: const TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'raw_material', child: Text(tr('خامة'), style: const TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'finished_goods', child: Text(tr('منتج تام'), style: const TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'service', child: Text(tr('خدمة'), style: const TextStyle(fontSize: 13))),
                          ],
                          onChanged: (v) => setState(() => _productType = v ?? 'general'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FutureBuilder<List<Warehouse>>(
                        // نطاقُ النسبة: الرصيدُ الافتتاحيُّ يُكتب حركةَ مخزونٍ
                        // في هذا المخزن، فمخزنُ فرعٍ آخرَ يلوّث تقييمَه.
                        future:
                            ref.read(assignableWarehousesProvider(null).future),
                        builder: (context, snapshot) {
                          final warehouses = snapshot.data ?? [];
                          return SizedBox(
                            height: 44,
                            child: DropdownButtonFormField<int?>(
                              initialValue: _selectedWarehouseId,
                              decoration: InputDecoration(
                                labelText: tr('المخزن الافتراضي'),
                                prefixIcon: const Icon(PhosphorIconsBold.warehouse, size: 18),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                              ),
                              items: [
                                 DropdownMenuItem<int?>(value: null, child: Text(tr('بدون'), style: const TextStyle(fontSize: 13))),
                                ...warehouses.map((w) => DropdownMenuItem<int?>(value: w.id, child: Text(w.name, style: const TextStyle(fontSize: 13)))),
                              ],
                              onChanged: (v) => setState(() => _selectedWarehouseId = v),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                // Supplier Dropdown (for Commercial/Purchase mode)
                if (!widget.simplified) ...[
                  const SizedBox(height: 8),
                  FutureBuilder<List<Party>>(
                    future: _suppliersFuture ??=
                        ref.read(productRepositoryProvider).getSuppliers(),
                    builder: (context, snapshot) {
                      final suppliers = snapshot.data ?? [];
                      return Autocomplete<Party>(
                        key: ValueKey(
                            'supplier-${suppliers.length}-$_selectedSupplierId'),
                        initialValue: TextEditingValue(
                          text: _selectedSupplierId != null
                              ? (suppliers.where((s) => s.id == _selectedSupplierId).firstOrNull?.name ?? '')
                              : '',
                        ),
                        optionsBuilder: (textValue) {
                          final q = textValue.text.toLowerCase().trim();
                          if (q.isEmpty) return suppliers;
                          return suppliers.where((s) =>
                              s.name.toLowerCase().contains(q) ||
                              (s.phone?.contains(textValue.text) ?? false));
                        },
                        displayStringForOption: (s) => s.name,
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: tr('المورد'),
                              hintText: tr('ابحث عن المورد...'),
                              prefixIcon: const Icon(PhosphorIconsBold.truck, size: 18),
                              isDense: true,
                              suffixIcon: _selectedSupplierId != null
                                  ? IconButton(
                                      icon: const Icon(PhosphorIconsBold.x, size: 14),
                                      onPressed: () {
                                        controller.clear();
                                        setState(() => _selectedSupplierId = null);
                                      },
                                    )
                                  : null,
                            ),
                            style: const TextStyle(fontSize: 13),
                          );
                        },
                        onSelected: (supplier) {
                          setState(() => _selectedSupplierId = supplier.id);
                        },
                      );
                    },
                  ),
                ],

                const SizedBox(height: 12),

                // Per-Warehouse Pricing Section
                _buildWarehousePricingSection(),

                const SizedBox(height: 12),

                // Multi-Unit Packaging Section
                if (!widget.simplified) _buildPackagingUnitsSection(),

                const SizedBox(height: 12),

                // Cluster 023 / Issue 11 — inline BOM section
                if (!widget.simplified) _buildBomComponentsSection(),

                const SizedBox(height: 12),

                // Options Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column - Options
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Expiry Section
                          buildProductExpirySectionGuarded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionHeader(
                                  tr('إدارة الصلاحية'),
                                  PhosphorIconsBold.calendarBlank,
                                  AppColors.info,
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                           Text(
                                            tr('تتبع الصلاحية'),
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          const Spacer(),
                                          SizedBox(
                                            height: 24,
                                            child: Switch(
                                              value: _trackExpiry,
                                              onChanged: (v) => setState(
                                                  () => _trackExpiry = v),
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_trackExpiry) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _buildMiniTextField(
                                                _shelfDaysController,
                                                tr('مدة الصلاحية (يوم)'),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _buildMiniTextField(
                                                _alertDaysController,
                                                tr('تنبيه قبل (يوم)'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Weight / Scale Section
                          _buildSectionHeader(
                            tr('نوع البيع والميزان'),
                            PhosphorIconsBold.scales,
                            AppColors.warning,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SegmentedButton<String>(
                                  segments:  [
                                    ButtonSegment(
                                      value: 'count',
                                      label: Text(
                                        tr('عدد'),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: 'weight',
                                      label: Text(
                                        tr('ميزان'),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: 'weightByPiece',
                                      label: Text(
                                        tr('ميزان بالحبة'),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: 'display',
                                      label: Text(
                                        tr('عرض'),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  ],
                                  selected: {_scaleType},
                                  onSelectionChanged: (v) =>
                                      setState(() => _scaleType = v.first),
                                  showSelectedIcon: false,
                                  style: ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                    padding: WidgetStateProperty.all(
                                      const EdgeInsets.symmetric(horizontal: 4),
                                    ),
                                  ),
                                ),
                                if (_isSoldByWeight) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildMiniTextField(
                                          _pricePerUnitController,
                                          tr('سعر الكيلو'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _buildMiniTextField(
                                          _scalePluNumberController,
                                          tr('رقم PLU'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Negative Sale
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  PhosphorIconsBold.warning,
                                  size: 14,
                                  color: AppColors.error,
                                ),
                                const SizedBox(width: 4),
                                 Text(
                                  tr('البيع بالسالب'),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const Spacer(),
                                SizedBox(
                                  height: 24,
                                  child: Switch(
                                    value: _allowNegativeSale,
                                    onChanged: (v) =>
                                        setState(() => _allowNegativeSale = v),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Right Column - Image
                    SizedBox(
                      width: 180,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            tr('صورة المنتج'),
                            PhosphorIconsBold.image,
                            AppColors.success,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.border),
                                    color: Theme.of(context).cardColor,
                                  ),
                                  child: _selectedImage != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Image.memory(
                                            _selectedImage!,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : const Icon(
                                          PhosphorIconsBold.image,
                                          size: 32,
                                          color: AppColors.textMuted,
                                        ),
                                ),
                                const SizedBox(height: 8),
                                buildProductImageActionsGuarded(
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        height: 28,
                                        child: OutlinedButton.icon(
                                          onPressed: _pickImage,
                                          icon: const Icon(
                                            PhosphorIconsBold.upload,
                                            size: 12,
                                          ),
                                          label:  Text(
                                            tr('اختيار'),
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            padding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_selectedImage != null) ...[
                                        const SizedBox(width: 4),
                                        SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: IconButton(
                                            onPressed: () => setState(
                                              () => _selectedImage = null,
                                            ),
                                            icon: const Icon(
                                              PhosphorIconsBold.trash,
                                              size: 14,
                                            ),
                                            color: AppColors.error,
                                            padding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إلغاء')),
          ),
          ElevatedButton(
            onPressed: _isLoading ? null : _saveProduct,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                :  Text(tr('حفظ')),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result != null && result.files.first.bytes != null) {
      setState(() => _selectedImage = result.files.first.bytes);
    }
  }

  Future<void> _saveProduct() async {
    // Validation
    if (_nameController.text.isEmpty ||
        _salePriceController.text.isEmpty ||
        _selectedCategoryId == null) {
      AppToast.show(
        context,
        tr('يرجى ملء الحقول المطلوبة (الاسم، السعر، التصنيف)'),
        type: ToastType.error,
      );
      return;
    }

    // Spec 136 ISS-26 — opening balance MUST target a warehouse. Pre-fix the
    // opening-stock step below was gated on `_selectedWarehouseId != null` and
    // silently DROPPED the balance when the warehouse dropdown was left on
    // "بدون" (null) — the product got created with 0 stock and a later POS
    // sale failed with "الصنف غير متوفر نهائياً في المستودع". Field-reported
    // on the mirror (3.1.0+217). Require an explicit warehouse so the opening
    // stock lands in the branch warehouse the cashier sells from.
    final enteredOpeningBalance =
        NumberUtils.tryParseLocale(_openingBalanceController.text) ?? 0.0;
    if (enteredOpeningBalance > 0 && _selectedWarehouseId == null) {
      AppToast.show(
        context,
        tr('اختر المخزن لتسجيل الرصيد الافتتاحي للصنف'),
        type: ToastType.error,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final productRepo = ref.read(productRepositoryProvider);

      // Demo limit check (bypass if activated)
      if (AppConfig.isDemo) {
        // Use cached value first; if false, do a live check as fallback
        bool isActivated = LicenseService.isActivatedCached;
        if (!isActivated) {
          isActivated = await ref.read(licenseServiceProvider).isActivated();
        }
        if (!isActivated) {
          final products = await productRepo.getAllProducts();
          if (products.length >= AppConfig.maxDemoProducts) {
            if (mounted) {
              AppToast.show(
                context,
                tr('النسخة التجريبية: الحد الأقصى للأصناف ({p0} صنف). قم بتفعيل النسخة لرفع الحد.', {'p0': AppConfig.maxDemoProducts}),
                type: ToastType.warning,
              );
            }
            setState(() => _isLoading = false);
            return;
          }
        }
      }

      // Generate code if empty
      final code = _codeController.text.isEmpty
          ? 'PRD${DateTime.now().millisecondsSinceEpoch}'
          : _codeController.text;

      // Code / barcode uniqueness check — runs in EVERY mode now (was
      // previously gated to standalone/server only). The local DB on
      // client and mirror is kept in sync via DeltaPull + post-MM.E
      // first-sync wipe-and-pull, so false positives are rare. The
      // server-side postProduct ALSO rejects code/barcode collisions
      // against a different globalId (api_product_handler.dart), so
      // even if the local cache misses one, the server is the
      // definitive guard.
      if (code.isNotEmpty) {
        final codeUsed = await productRepo.productCodeExists(code);
        if (codeUsed) {
          if (mounted) {
            AppToast.show(
              context,
              tr('هذا الكود مستخدم بالفعل لصنف آخر'),
              type: ToastType.error,
            );
          }
          setState(() => _isLoading = false);
          return;
        }
      }

      if (_barcodeController.text.isNotEmpty) {
        final exists = await productRepo.barcodeExists(_barcodeController.text);
        if (exists) {
          if (mounted) {
            AppToast.show(
              context,
              tr('هذا الباركود مستخدم بالفعل'),
              type: ToastType.error,
            );
          }
          setState(() => _isLoading = false);
          return;
        }
      }

      // Insert product
      final salePrice = NumberUtils.tryParseLocale(_salePriceController.text) ?? 0;
      final costPrice = NumberUtils.tryParseLocale(_costPriceController.text) ?? 0;

      await DiagnosticLogger.log('ADD-PROD', 'start name=${_nameController.text} code=$code warehouseId=$_selectedWarehouseId');

      // ── Client mode: send to server FIRST, use server-assigned ID locally
      // so the product has the SAME id on both sides. Prevents duplicate
      // rows after a later fullSync pulls the product back.
      //
      // P5: Build the units + barcodes lists ONCE here so we can ship them in
      // the createProduct payload (server creates them atomically) AND reuse
      // the same data for the local insert below. Previously the units were
      // ONLY inserted locally — the server saw a "naked" product with no
      // units, which broke unit-barcode lookups in POS.
      final unitsPayload = <Map<String, dynamic>>[];
      if (_unitRows.isNotEmpty) {
        for (int i = 0; i < _unitRows.length; i++) {
          final row = _unitRows[i];
          final unitName = row.unitName.trim();
          if (unitName.isEmpty) continue;
          final factor = NumberUtils.tryParseLocale(row.factorController.text) ?? 1.0;
          final ub = row.barcodeController.text.trim();
          // نفس قاعدة الحفظ المحلي بالظبط — لو اختلفوا، السيرفر يخزّن السعر
          // المشتق والعميل يخزّن المُدخَل، وأول DeltaPull بيدهس سعر المستخدم.
          final payloadSalePrice = ProductFormHelpers.resolveUnitSalePrice(
            typedPrice:
                NumberUtils.tryParseLocale(row.salePriceController.text.trim()),
            baseSalePrice: salePrice,
            factor: factor,
          );
          unitsPayload.add({
            // Pre-mint a globalId so the local insert below uses the SAME UUID
            // the server creates with — DeltaPull then dedupes by globalId
            // instead of producing a phantom duplicate row.
            'globalId': UuidV7.generate(),
            'unitName': unitName,
            'barcode': ub.isNotEmpty ? ub : null,
            'quantityInBase': factor,
            'salePrice': payloadSalePrice,
            'costPrice': costPrice * factor,
            'isBaseUnit': factor == 1.0,
            'isDefaultPurchase': i == _defaultUnitIndex,
            'isDefaultSale': i == _defaultUnitIndex,
            'sortOrder': i,
          });
        }
      }
      final barcodesPayload = <Map<String, dynamic>>[];
      if (_barcodeController.text.isNotEmpty) {
        barcodesPayload.add({
          'barcode': _barcodeController.text,
          'isPrimary': true,
        });
      }

      int? serverId;
      try {
        serverId = await ClientWriteInterceptor.createProduct(
          code: code,
          name: _nameController.text,
          salePrice: salePrice,
          costPrice: costPrice,
          categoryId: _selectedCategoryId,
          supplierId: _selectedSupplierId,
          barcode: _barcodeController.text.isNotEmpty ? _barcodeController.text : null,
          minStock: NumberUtils.tryParseLocale(_minStockController.text) ?? 0,
          taxRate: NumberUtils.tryParseLocale(_taxRateController.text) ?? 0,
          isSoldByWeight: _isSoldByWeight,
          allowNegativeSale: _allowNegativeSale,
          trackExpiry: _trackExpiry,
          defaultShelfDays: int.tryParse(_shelfDaysController.text) ?? 90,
          alertDaysBefore: int.tryParse(_alertDaysController.text) ?? 30,
          pricePerUnit: _isSoldByWeight
              ? NumberUtils.tryParseLocale(_pricePerUnitController.text)
              : null,
          wholesalePrice: NumberUtils.tryParseLocale(_wholesalePriceController.text) ?? 0,
          priceTalabat: NumberUtils.tryParseLocale(_priceTalabatController.text) ?? 0,
          priceCareem: NumberUtils.tryParseLocale(_priceCareemController.text) ?? 0,
          priceAshyae: NumberUtils.tryParseLocale(_priceAshyaeController.text) ?? 0,
          scaleType: _scaleType,
          scalePluNumber: int.tryParse(_scalePluNumberController.text),
          productType: _productType,
          warehouseId: _selectedWarehouseId,
          units: unitsPayload.isEmpty ? null : unitsPayload,
          barcodes: barcodesPayload.isEmpty ? null : barcodesPayload,
        );
        await DiagnosticLogger.log('ADD-PROD', 'step1 server createProduct OK serverId=$serverId units=${unitsPayload.length} barcodes=${barcodesPayload.length}');
      } catch (e, st) {
        debugPrint('[AddProductDialog] server createProduct failed: $e');
        await DiagnosticLogger.log('ADD-PROD', 'step1 server createProduct FAILED: $e\n$st');
        // Spec 136 — on a mirror/client, product master data is
        // server-authoritative (R4/R8). If the server create failed (e.g. HQ
        // offline / errno 1225), do NOT fall through to a local-only insert:
        // that produces an ORPHAN product that exists on the mirror but never
        // reaches the server (product create is not outbox-queued), so a later
        // sale of it dead-letters with "الصنف غير متوفر ... في المستودع".
        // Abort cleanly so the operator retries once HQ is reachable. This
        // catch is only entered in client/mirror mode — in standalone,
        // ClientWriteInterceptor.createProduct returns null WITHOUT throwing,
        // so the local auto-increment insert below still runs as before.
        rethrow;
      }

      // Build companion. When we got a serverId from the server, we INSERT
      // with that explicit id so client+server share the same primary key.
      // Otherwise we let Drift auto-increment (Value.absent on id).
      final companion = ProductsCompanion.insert(
        id: serverId != null ? Value(serverId) : const Value<int>.absent(),
        code: code,
        barcode: Value(
          _barcodeController.text.isNotEmpty ? _barcodeController.text : null,
        ),
        name: _nameController.text,
        categoryId: Value(_selectedCategoryId),
        supplierId: Value(_selectedSupplierId),
        salePrice: Value(salePrice),
        costPrice: Value(costPrice),
        minStock: Value(NumberUtils.tryParseLocale(_minStockController.text) ?? 0),
        trackExpiry: Value(_trackExpiry),
        defaultShelfDays: Value(
          int.tryParse(_shelfDaysController.text) ?? 90,
        ),
        alertDaysBefore: Value(int.tryParse(_alertDaysController.text) ?? 30),
        isSoldByWeight: Value(_isSoldByWeight),
        pricePerUnit: Value(
          _isSoldByWeight
              ? NumberUtils.tryParseLocale(_pricePerUnitController.text)
              : null,
        ),
        imageData: Value(_selectedImage),
        allowNegativeSale: Value(_allowNegativeSale),
        taxRate: Value(NumberUtils.tryParseLocale(_taxRateController.text) ?? 0),
        priceTalabat: Value(
          NumberUtils.tryParseLocale(_priceTalabatController.text) ?? 0,
        ),
        priceCareem: Value(NumberUtils.tryParseLocale(_priceCareemController.text) ?? 0),
        priceAshyae: Value(NumberUtils.tryParseLocale(_priceAshyaeController.text) ?? 0),
        wholesalePrice: Value(
          NumberUtils.tryParseLocale(_wholesalePriceController.text) ?? 0,
        ),
        scaleType: Value(_scaleType),
        scalePluNumber: Value(int.tryParse(_scalePluNumberController.text)),
        productType: Value(_productType),
        // Only set warehouseId if user actually picked a default warehouse.
        // Passing a non-existent id (e.g. stale `_selectedWarehouseId=2` from
        // a previous install) will cause a FK violation on the server.
        warehouseId: _selectedWarehouseId != null
            ? Value(_selectedWarehouseId)
            : const Value.absent(),
      );

      int productId;
      try {
        productId = await productRepo.insertProduct(companion);
        await DiagnosticLogger.log('ADD-PROD', 'step2 local insertProduct OK productId=$productId');
      } catch (e, st) {
        await DiagnosticLogger.log('ADD-PROD', 'step2 local insertProduct FAILED: $e\n$st');
        rethrow;
      }

      // Insert barcode if provided
      if (_barcodeController.text.isNotEmpty) {
        try {
          await productRepo.insertProductBarcode(
            productId,
            _barcodeController.text,
            isPrimary: true,
          );
          await DiagnosticLogger.log('ADD-PROD', 'step3 insertProductBarcode OK');
        } catch (e, st) {
          await DiagnosticLogger.log('ADD-PROD', 'step3 insertProductBarcode FAILED: $e\n$st');
          rethrow;
        }
      }

      // Save warehouse prices
      if (_warehousePriceRows.isNotEmpty) {
        for (final row in _warehousePriceRows) {
          if (row.warehouseId != null) {
            await productRepo.upsertWarehousePrice(
              productId: productId,
              warehouseId: row.warehouseId!,
              salePrice: NumberUtils.tryParseLocale(row.salePriceController.text) ?? 0,
              costPrice: NumberUtils.tryParseLocale(row.costPriceController.text) ?? 0,
              wholesalePrice: NumberUtils.tryParseLocale(row.wholesalePriceController.text) ?? 0,
            );
          }
        }
      }

      // Save product units (multi-unit or default).
      // P5: When unitsPayload was sent to the server (client mode), reuse the
      // pre-minted globalIds so the server-side row and the local cache row
      // share the same UUID — DeltaPull dedupes on globalId, so this prevents
      // the duplicate-units phantom rows after the next sync tick.
      if (_unitRows.isNotEmpty) {
        int payloadIdx = 0;
        for (int i = 0; i < _unitRows.length; i++) {
          final row = _unitRows[i];
          final unitName = row.unitName.trim();
          if (unitName.isEmpty) continue;
          final factor = NumberUtils.tryParseLocale(row.factorController.text) ?? 1.0;
          final barcode = row.barcodeController.text.trim();
          final sharedGid = payloadIdx < unitsPayload.length
              ? unitsPayload[payloadIdx]['globalId'] as String?
              : null;
          payloadIdx++;
          // المُدخَل يفوز، وفاضي = اشتق (السلوك القديم كـسلوك افتراضي).
          final unitSalePrice = ProductFormHelpers.resolveUnitSalePrice(
            typedPrice:
                NumberUtils.tryParseLocale(row.salePriceController.text.trim()),
            baseSalePrice: salePrice,
            factor: factor,
          );
          await productRepo.insertProductUnit(
            ProductUnitsCompanion.insert(
              productId: productId,
              unitName: unitName,
              barcode: Value(barcode.isNotEmpty ? barcode : null),
              quantityInBase: Value(factor),
              salePrice: Value(unitSalePrice),
              costPrice: Value(costPrice * factor),
              isBaseUnit: Value(factor == 1.0),
              isDefaultPurchase: Value(i == _defaultUnitIndex),
              isDefaultSale: Value(i == _defaultUnitIndex),
              sortOrder: Value(i),
              globalId: sharedGid != null ? Value(sharedGid) : const Value.absent(),
            ),
          );
        }
      } else {
        // No custom units — create default piece unit
        try {
          await productRepo.createDefaultProductUnits(
            productId,
            piecePrice: salePrice,
            pieceCost: costPrice,
            pieceBarcode: _barcodeController.text.isNotEmpty
                ? _barcodeController.text
                : null,
          );
          await DiagnosticLogger.log('ADD-PROD', 'step4 createDefaultProductUnits OK');
        } catch (e, st) {
          await DiagnosticLogger.log('ADD-PROD', 'step4 createDefaultProductUnits FAILED: $e\n$st');
          rethrow;
        }
      }

      // Cluster 023 / Issue 11 — inline BOM. When the operator filled any
      // raw-material rows, create a Bill of Materials linking the new
      // product as the finished good and seeding `auto_deplete_on_sale=true`
      // + `depletion_policy='always_auto_deplete'` so a sale of this
      // product runs the Feature 009 / US1 raw-material consumption path.
      // Bom failure surfaces as a non-fatal warning toast — operator can
      // edit/recreate the BOM from the manufacturing screen.
      final validBomRows = _bomRows
          .where((r) =>
              r.rawMaterialId != null &&
              (NumberUtils.tryParseLocale(r.quantityController.text) ?? 0) > 0)
          .toList();
      if (validBomRows.isNotEmpty) {
        try {
          final manufacturingRepo = ref.read(manufacturingRepositoryProvider);
          final components = validBomRows
              .map((r) => <String, dynamic>{
                    'rawMaterialId': r.rawMaterialId!,
                    'quantity':
                        NumberUtils.tryParseLocale(r.quantityController.text) ?? 1.0,
                    'wastagePercent':
                        NumberUtils.tryParseLocale(r.wastageController.text) ?? 0.0,
                  })
              .toList();
          await manufacturingRepo.createBOM(
            finishedProductId: productId,
            bomCode: 'BOM-$productId',
            expectedQuantity: 1,
            components: components,
            isActive: true,
            autoDepleteOnSale: true,
            depletionPolicy: 'always_auto_deplete',
          );
          await DiagnosticLogger.log('ADD-PROD',
              'step4.7 createBOM OK components=${components.length}');
        } catch (e, st) {
          await DiagnosticLogger.log(
              'ADD-PROD', 'step4.7 createBOM FAILED (non-fatal): $e\n$st');
          if (mounted) {
            AppToast.show(context,
                tr('تم إنشاء الصنف لكن فشل تسجيل قائمة الخامات: {e}', {'e': e}),
                type: ToastType.warning);
          }
        }
      }

      // Cluster 023 / Issue 7 — opening stock balance. Mirrors the Excel
      // import pattern (excel_service._applyOpeningStock) so stock_movements
      // (type=opening_stock) + inventory_balances + products.current_stock
      // are populated atomically. Without going through adjustStock, the
      // products.current_stock would exist but inventory_balances would be
      // missing → POS sales fail with "الصنف غير متوفر فى المستودع".
      final openingBalance =
          NumberUtils.tryParseLocale(_openingBalanceController.text) ?? 0.0;
      if (openingBalance > 0 && _selectedWarehouseId != null) {
        try {
          final inventoryRepo = ref.read(inventoryRepositoryProvider);
          await inventoryRepo.adjustStock(
            productId: productId,
            warehouseId: _selectedWarehouseId!,
            quantity: openingBalance,
            type: 'opening_stock',
            notes: tr('رصيد افتتاحى — إضافة صنف'),
          );
          // Fire-and-forget server sync (client mode only; no-op otherwise).
          unawaited(ClientWriteInterceptor.adjustStock(
            productId: productId,
            warehouseId: _selectedWarehouseId!,
            quantity: openingBalance,
            type: 'opening_stock',
            notes: tr('رصيد افتتاحى — إضافة صنف'),
          ).catchError((e) {
            debugPrint('[AddProductDialog] server adjustStock failed (queued): $e');
            return false;
          }));
          await DiagnosticLogger.log(
              'ADD-PROD', 'step4.5 opening_stock OK qty=$openingBalance wh=$_selectedWarehouseId');
        } catch (e, st) {
          await DiagnosticLogger.log(
              'ADD-PROD', 'step4.5 opening_stock FAILED (non-fatal): $e\n$st');
          if (mounted) {
            AppToast.show(context, tr('تم إنشاء الصنف لكن فشل تسجيل الرصيد الافتتاحى: {e}', {'e': e}),
                type: ToastType.warning);
          }
        }
      }

      // Log activity for audit trail (#13)
      try {
        final user = ref.read(authProvider).user;
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id,
          userName: user?.displayName ?? tr('مجهول'),
          action: 'add_product',
          entityType: 'product',
          entityId: productId,
          description:
              tr('إضافة منتج: {p0} بسعر {p1}', {'p0': _nameController.text, 'p1': salePrice.toStringAsFixed(2)}),
        );
        await DiagnosticLogger.log('ADD-PROD', 'step5 logActivity OK');
      } catch (e, st) {
        await DiagnosticLogger.log('ADD-PROD', 'step5 logActivity FAILED: $e\n$st');
        rethrow;
      }

      final result = AddProductResult(
        productId: productId,
        productName: _nameController.text,
        salePrice: salePrice,
        costPrice: costPrice,
      );

      if (mounted) {
        AppToast.show(context, tr('تم إضافة الصنف بنجاح'), type: ToastType.success);

        widget.onProductAdded?.call(result);
        Navigator.pop(context, result);
      }
    } catch (e, st) {
      await DiagnosticLogger.log('ADD-PROD', 'OUTER CATCH: $e\nSTACK:\n$st');
      if (mounted) {
        AppToast.show(context, tr('خطأ في حفظ الصنف: {e}', {'e': e}), type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ISS-13: Delegated to ProductFormHelpers
  Widget _buildSectionHeader(String title, IconData icon, Color color) =>
      ProductFormHelpers.buildSectionHeader(title, icon, color);

  // ISS-13: Delegated to ProductFormHelpers
  Widget _buildCompactTextField(
    TextEditingController controller,
    String label, {
    IconData? icon,
    bool isNumber = false,
  }) =>
      ProductFormHelpers.buildCompactTextField(controller, label,
          icon: icon, isNumber: isNumber);

  // ISS-13: Delegated to ProductFormHelpers
  Widget _buildMiniTextField(
      TextEditingController controller, String label) =>
      ProductFormHelpers.buildMiniTextField(controller, label);

  /// Build multi-unit packaging section (up to 5 units per product)
  Widget _buildPackagingUnitsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with toggle
        InkWell(
          onTap: () {
            setState(() {
              _showPackagingUnits = !_showPackagingUnits;
              if (_showPackagingUnits && _unitRows.isEmpty) {
                // Auto-add first row as base unit (قطعة)
                _unitRows.add(_ProductUnitRow(
                  unitName: tr('قطعة'),
                  factor: '1',
                ));
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.package, size: 18, color: AppColors.info),
                const SizedBox(width: 8),
                 Text(
                  tr('وحدات التعبئة'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.info),
                ),
                 Text(
                  tr('  (قطعة → علبة → كرتونة → صندوق)'),
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                const Spacer(),
                Icon(
                  _showPackagingUnits ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown,
                  size: 16,
                  color: AppColors.info,
                ),
              ],
            ),
          ),
        ),
        if (_showPackagingUnits) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // Column headers
                 Row(
                  children: [
                    SizedBox(width: 40, child: Text(tr('افتراضي'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: Text(tr('اسم الوحدة'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: Text(tr('الباركود'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tr('عامل التحويل'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 30),
                  ],
                ),
                const Divider(height: 12),
                // Unit rows
                ...List.generate(_unitRows.length, (index) {
                  final row = _unitRows[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        // Default radio
                        SizedBox(
                          width: 40,
                          child: Radio<int>(
                            value: index,
                            groupValue: _defaultUnitIndex,
                            onChanged: (v) => setState(() => _defaultUnitIndex = v!),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Unit name dropdown
                        Expanded(
                          flex: 2,
                          child: FutureBuilder<List<Unit>>(
                            future: ref.read(productRepositoryProvider).getAllUnits(),
                            builder: (context, snapshot) {
                              final units = snapshot.data ?? [];
                              return SizedBox(
                                height: 38,
                                child: DropdownButtonFormField<String>(
                                  initialValue: row.unitName.isNotEmpty ? row.unitName : null,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                    isDense: true,
                                    hintText: tr('الوحدة {p0}', {'p0': index + 1}),
                                    hintStyle: const TextStyle(fontSize: 12),
                                  ),
                                  items: units.map((u) => DropdownMenuItem(
                                    value: u.name,
                                    child: Text(u.name, style: const TextStyle(fontSize: 12)),
                                  )).toList(),
                                  onChanged: (v) => setState(() => row.unitName = v ?? ''),
                                  style: TextStyle(
                                     fontSize: 12,
                                     color: Theme.of(context).colorScheme.onSurface,
                                   ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Barcode
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 38,
                            child: TextField(
                              controller: row.barcodeController,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                isDense: true,
                                hintText: tr('باركود {p0}', {'p0': index + 1}),
                                hintStyle: const TextStyle(fontSize: 12),
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Conversion factor
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: TextField(
                              controller: row.factorController,
                              keyboardType: TextInputType.number,
                              enabled: index > 0, // First unit (base) always = 1
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                isDense: true,
                                hintText: tr('مثال: 12'),
                                hintStyle: const TextStyle(fontSize: 12),
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // سعر البيع لهذه الوحدة. فاضي = يُشتق من سعر الصنف ×
                        // المعامل، وهو السلوك الوحيد اللي كان متاحاً قبل كده.
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: TextField(
                              controller: row.salePriceController,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6)),
                                isDense: true,
                                hintText: tr('سعر الوحدة'),
                                hintStyle: const TextStyle(fontSize: 11),
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Delete button (not for first row)
                        SizedBox(
                          width: 26,
                          child: index == 0
                              ? const SizedBox()
                              : InkWell(
                                  onTap: () {
                                    setState(() {
                                      _unitRows.removeAt(index);
                                      if (_defaultUnitIndex >= _unitRows.length) {
                                        _defaultUnitIndex = 0;
                                      }
                                    });
                                  },
                                  child: const Icon(PhosphorIconsBold.trash, size: 14, color: AppColors.error),
                                ),
                        ),
                      ],
                    ),
                  );
                }),
                // Add unit button (max 5)
                if (_unitRows.length < 5)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _unitRows.add(_ProductUnitRow());
                        });
                      },
                      icon: const Icon(PhosphorIconsBold.plus, size: 14),
                      label:  Text(tr('إضافة وحدة'), style: const TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: AppColors.info,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWarehousePricingSection() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () =>
                setState(() => _showWarehousePrices = !_showWarehousePrices),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsBold.warehouse,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                   Text(
                    tr('أسعار المخازن'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_warehousePriceRows.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_warehousePriceRows.length}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    _showWarehousePrices
                        ? PhosphorIconsBold.caretUp
                        : PhosphorIconsBold.caretDown,
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
          if (_showWarehousePrices) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  ..._warehousePriceRows.asMap().entries.map((entry) {
                    final index = entry.key;
                    final row = entry.value;
                    return _buildWarehousePriceRowWidget(row, index);
                  }),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _warehousePriceRows.add(_WarehousePriceRow());
                        });
                      },
                      icon: const Icon(PhosphorIconsBold.plus, size: 14),
                      label:  Text(
                        tr('إضافة سعر مخزن'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWarehousePriceRowWidget(_WarehousePriceRow row, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: FutureBuilder<List<Warehouse>>(
                    future: ref.read(branchRepositoryProvider).getWarehouses(),
                    builder: (context, snapshot) {
                      final warehouses = snapshot.data ?? [];
                      // Filter out already-used warehouses
                      final usedIds = _warehousePriceRows
                          .where((r) => r != row && r.warehouseId != null)
                          .map((r) => r.warehouseId)
                          .toSet();
                      final available = warehouses
                          .where((w) => !usedIds.contains(w.id))
                          .toList();

                      return SizedBox(
                        height: 40,
                        child: DropdownButtonFormField<int?>(
                          initialValue: row.warehouseId,
                          decoration: InputDecoration(
                            labelText: tr('المخزن'),
                            labelStyle: const TextStyle(fontSize: 11),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6)),
                            isDense: true,
                          ),
                          items: available
                              .map((w) => DropdownMenuItem<int?>(
                                    value: w.id,
                                    child: Text(w.name,
                                        style: const TextStyle(fontSize: 12)),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => row.warehouseId = v),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    setState(() {
                      _warehousePriceRows.removeAt(index);
                    });
                  },
                  child: const Icon(PhosphorIconsBold.trash, size: 16,
                      color: AppColors.error),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _buildMiniTextField(
                      row.salePriceController, tr('سعر البيع')),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMiniTextField(
                      row.costPriceController, tr('التكلفة')),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMiniTextField(
                      row.wholesalePriceController, tr('سعر الجملة')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Cluster 023 / Issue 11 — inline BOM section. Lets the operator define
  /// the finished product as a composite (BOM) directly inside the create
  /// dialog so a sale of this product auto-deducts its raw materials —
  /// without forcing them through the separate manufacturing screen.
  Widget _buildBomComponentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _showBomComponents = !_showBomComponents;
              if (_showBomComponents && _bomRows.isEmpty) {
                _bomRows.add(_BomComponentRow());
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.factory,
                    size: 18, color: AppColors.success),
                const SizedBox(width: 8),
                 Text(
                  tr('المواد التجميعية (BOM)'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.success),
                ),
                 Text(
                  tr('  (يتم خصم الخامات تلقائيًا عند البيع)'),
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                const Spacer(),
                Icon(
                  _showBomComponents
                      ? PhosphorIconsBold.caretUp
                      : PhosphorIconsBold.caretDown,
                  size: 16,
                  color: AppColors.success,
                ),
              ],
            ),
          ),
        ),
        if (_showBomComponents) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                 Row(
                  children: [
                    Expanded(
                        flex: 3,
                        child: Text(tr('الخامة'),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(tr('الكمية'),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(tr('الفاقد %'),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 30),
                  ],
                ),
                const Divider(height: 12),
                ...List.generate(_bomRows.length, (index) {
                  final row = _bomRows[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: FutureBuilder<List<ProductEntity>>(
                            future: ref
                                .read(productRepositoryProvider)
                                .getProducts(limit: 1000),
                            builder: (context, snap) {
                              final products = snap.data ?? [];
                              return Autocomplete<ProductEntity>(
                                initialValue: TextEditingValue(
                                    text: row.rawMaterialName),
                                optionsBuilder: (textValue) {
                                  if (textValue.text.isEmpty) {
                                    return products.take(15);
                                  }
                                  final q = textValue.text.toLowerCase();
                                  return products.where((p) =>
                                      p.name.toLowerCase().contains(q) ||
                                      p.code.toLowerCase().contains(q));
                                },
                                displayStringForOption: (p) => p.name,
                                fieldViewBuilder: (context, controller,
                                    focusNode, onFieldSubmitted) {
                                  return SizedBox(
                                    height: 36,
                                    child: TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      style: const TextStyle(fontSize: 12),
                                      decoration:  InputDecoration(
                                        hintText: tr('ابحث عن خامة...'),
                                        hintStyle: const TextStyle(fontSize: 11),
                                        contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 6),
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  );
                                },
                                onSelected: (p) {
                                  setState(() {
                                    row.rawMaterialId = p.id;
                                    row.rawMaterialName = p.name;
                                  });
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 36,
                            child: TextField(
                              controller: row.quantityController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 12),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 36,
                            child: TextField(
                              controller: row.wastageController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 12),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 30,
                          child: IconButton(
                            iconSize: 16,
                            padding: EdgeInsets.zero,
                            icon: const Icon(PhosphorIconsBold.trash,
                                color: AppColors.error),
                            onPressed: () {
                              setState(() {
                                _bomRows.removeAt(index);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _bomRows.add(_BomComponentRow());
                      });
                    },
                    icon: const Icon(PhosphorIconsBold.plus, size: 14),
                    label:  Text(tr('إضافة خامة'),
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Helper class to hold per-warehouse price row data
class _WarehousePriceRow {
  int? warehouseId;
  int? existingId; // DB record ID for updates
  final TextEditingController salePriceController;
  final TextEditingController costPriceController;
  final TextEditingController wholesalePriceController;

  _WarehousePriceRow({
    String? salePrice,
    String? costPrice,
    String? wholesalePrice,
  })  : salePriceController = TextEditingController(text: salePrice ?? ''),
        costPriceController = TextEditingController(text: costPrice ?? ''),
        wholesalePriceController =
            TextEditingController(text: wholesalePrice ?? '');
}

/// Helper class for product unit row data
class _ProductUnitRow {
  String unitName;
  final TextEditingController barcodeController;
  final TextEditingController factorController;

  /// سعر بيع الوحدة. فاضي = اشتق من سعر الصنف × المعامل (السلوك القديم).
  /// شوال السكر سعره جملةً أقل من سعر الكيلو × ٥٠ — والاشتقاق الإجباري
  /// كان بيمنع ده تماماً رغم إن العمود موجود والبيع السريع بتحترمه.
  final TextEditingController salePriceController;

  _ProductUnitRow({
    this.unitName = '',
    String? barcode,
    String? factor,
    String? salePrice,
  })  : barcodeController = TextEditingController(text: barcode ?? ''),
        factorController = TextEditingController(text: factor ?? '1'),
        salePriceController = TextEditingController(text: salePrice ?? '');
}

/// Cluster 023 / Issue 11 — one raw-material row in the inline BOM section.
class _BomComponentRow {
  int? rawMaterialId;
  String rawMaterialName;
  final TextEditingController quantityController;
  final TextEditingController wastageController;

  _BomComponentRow({
    String? quantity,
    String? wastage,
  })  : rawMaterialName = '',
        quantityController = TextEditingController(text: quantity ?? '1'),
        wastageController = TextEditingController(text: wastage ?? '0');
}
