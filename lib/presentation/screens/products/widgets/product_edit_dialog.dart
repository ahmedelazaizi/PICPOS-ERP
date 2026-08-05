import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ural_erp/core/utils/number_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../domain/entities/product_entity.dart';
import '../../../../services/network_service.dart';
import '../../../products/providers/products_controller.dart';
import '../../../../data/providers/providers.dart';
import '../../../widgets/dialogs/product_form_helpers.dart';
import '../../../../core/permissions/permission_codes.dart';
import '../../../widgets/permission_guard.dart';

// ─── أقسام محروسة جوه ديالوج تعديل الصنف (دفعة ٨) ────────────────────────
//
// `products_expiry` و`products_image` كانوا أكواد بلا إنفاذ: قسم «إدارة
// الصلاحية» وأزرار الصورة بيترسموا لأي حد يقدر يفتح الديالوج.
//
// الاتنين حراسة **إخفاء** مش تجاوز مدير: مفيش زرار واحد ينفّذ الفعل — دول
// حقول في فورم، والقيمة بتترحّل مع الحفظ. ديالوج كلمة سر مدير عشان يظهر
// حقل غلط (درس هـ في تسليم الجلسة).
//
// مهم: إخفاء الحقول **ما بيمسحش** البيانات — `trackExpiry` و`selectedImage`
// بيتعبّوا من الصنف في `initState`/`_refreshFromDatabase` والحفظ بيبعتهم زي
// ما هم، فمستخدم بلا الصلاحية بيحفظ باقي الحقول من غير ما يبوّظ تتبّع
// الصلاحية أو يمسح الصورة.
//
// الدالتين بيستعملهم كمان `add_product_dialog.dart` — نفس الحقول في ديالوج
// «إضافة صنف».

/// قسم «إدارة الصلاحية» (تتبّع الصلاحية + مدة/تنبيه) — `products_expiry`.
@visibleForTesting
Widget buildProductExpirySectionGuarded({required Widget child}) {
  return PermissionGuard(
    permission: PermissionCodes.productsExpiry,
    fallback: const SizedBox.shrink(),
    child: child,
  );
}

/// أزرار اختيار/حذف صورة الصنف — `products_image`.
///
/// المعاينة نفسها فاضلة ظاهرة: اسم الكود في الكتالوج «إضافة/تعديل الصورة»
/// — فعل تعديل، مش عرض.
@visibleForTesting
Widget buildProductImageActionsGuarded({required Widget child}) {
  return PermissionGuard(
    permission: PermissionCodes.productsImage,
    fallback: const SizedBox.shrink(),
    child: child,
  );
}

class ProductEditDialog extends ConsumerStatefulWidget {
  final ProductEntity product;

  const ProductEditDialog({super.key, required this.product});

  @override
  ConsumerState<ProductEditDialog> createState() => _ProductEditDialogState();
}

class _ProductEditDialogState extends ConsumerState<ProductEditDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController nameController;
  late final TextEditingController codeController;
  late final TextEditingController barcodeController;
  late final TextEditingController salePriceController;
  late final TextEditingController costPriceController;
  late final TextEditingController minStockController;
  late final TextEditingController shelfDaysController;
  late final TextEditingController alertDaysController;
  late final TextEditingController pricePerUnitController;
  late final TextEditingController taxRateController;
  late final TextEditingController priceTalabatController;
  late final TextEditingController priceCareemController;
  late final TextEditingController priceAshyaeController;
  late final TextEditingController wholesalePriceController;
  late final TextEditingController scalePluNumberController;

  late bool trackExpiry;
  late String scaleType;
  late bool allowNegativeSale;
  Uint8List? selectedImage;
  int? selectedCategoryId;
  int? selectedSupplierId;
  int? selectedWarehouseId;
  late String _productType;
  bool _showWarehousePrices = false;
  final List<_EditWarehousePriceRow> _warehousePriceRows = [];
  final Set<int> _deletedWarehousePriceIds = {};

  // Multi-unit packaging
  bool _showPackagingUnits = false;
  final List<_EditProductUnitRow> _unitRows = [];
  int _defaultUnitIndex = 0;

  bool _saving = false;

  // Built ONCE, not inside build(). `FutureBuilder` restarts whenever it is
  // handed a new Future, so creating these inline made every `setState` flip
  // the selectors back to an empty option list — which is what stopped the
  // category name from ever rendering (see `_buildCategorySelector`).
  Future<List<Category>>? _categoriesFuture;
  Future<List<Party>>? _suppliersFuture;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    final p = widget.product;
    nameController = TextEditingController(text: p.name);
    codeController = TextEditingController(text: p.code);
    barcodeController = TextEditingController(text: p.barcode);
    salePriceController = TextEditingController(text: p.salePrice.toString());
    costPriceController = TextEditingController(text: p.costPrice.toString());
    minStockController = TextEditingController(text: p.minStock.toString());
    shelfDaysController = TextEditingController(
      text: p.defaultShelfDays.toString(),
    );
    alertDaysController = TextEditingController(
      text: p.alertDaysBefore.toString(),
    );
    pricePerUnitController = TextEditingController(
      text: p.pricePerUnit?.toString() ?? '',
    );
    taxRateController = TextEditingController(text: p.taxRate.toString());
    priceTalabatController = TextEditingController(
      text: p.priceTalabat.toString(),
    );
    priceCareemController = TextEditingController(
      text: p.priceCareem.toString(),
    );
    priceAshyaeController = TextEditingController(
      text: p.priceAshyae.toString(),
    );
    wholesalePriceController = TextEditingController(
      text: p.wholesalePrice.toString(),
    );
    scalePluNumberController = TextEditingController(
      text: p.scalePluNumber?.toString() ?? '',
    );

    trackExpiry = p.trackExpiry;
    scaleType = p.scaleType ?? 'count';
    if (scaleType == 'count' && p.isSoldByWeight) scaleType = 'weight';
    allowNegativeSale = p.allowNegativeSale;
    selectedImage = p.imageData;
    selectedCategoryId = p.categoryId;
    selectedSupplierId = p.supplierId;
    selectedWarehouseId = p.warehouseId;
    _productType = p.productType;

    // Load existing warehouse prices
    _loadWarehousePrices();
    // Load existing product units
    _loadProductUnits();
    // Cluster 023 / Issue 8 — re-fetch the product fresh from the DB so
    // every field reflects the latest persisted state. The list-stream
    // entity is mapped through ProductEntity (domain layer) and can lag
    // briefly after a save; that lag is what surfaced as "blank fields"
    // for cost / prices / tax / weight settings on the next reopen.
    _refreshFromDatabase();
  }

  Future<void> _refreshFromDatabase() async {
    final repo = ref.read(productRepositoryProvider);
    final fresh = await repo.getProductById(widget.product.id);
    if (!mounted || fresh == null) return;
    setState(() {
      nameController.text = fresh.name;
      codeController.text = fresh.code;
      barcodeController.text = fresh.barcode ?? '';
      salePriceController.text = fresh.salePrice.toString();
      costPriceController.text = fresh.costPrice.toString();
      minStockController.text = fresh.minStock.toString();
      shelfDaysController.text = fresh.defaultShelfDays.toString();
      alertDaysController.text = fresh.alertDaysBefore.toString();
      pricePerUnitController.text = fresh.pricePerUnit?.toString() ?? '';
      taxRateController.text = fresh.taxRate.toString();
      priceTalabatController.text = fresh.priceTalabat.toString();
      priceCareemController.text = fresh.priceCareem.toString();
      priceAshyaeController.text = fresh.priceAshyae.toString();
      wholesalePriceController.text = fresh.wholesalePrice.toString();
      scalePluNumberController.text = fresh.scalePluNumber?.toString() ?? '';
      trackExpiry = fresh.trackExpiry;
      scaleType = fresh.scaleType ?? 'count';
      if (scaleType == 'count' && fresh.isSoldByWeight) scaleType = 'weight';
      allowNegativeSale = fresh.allowNegativeSale;
      selectedImage = fresh.imageData;
      selectedCategoryId = fresh.categoryId;
      selectedSupplierId = fresh.supplierId;
      selectedWarehouseId = fresh.warehouseId;
      _productType = fresh.productType;
    });
  }

  Future<void> _loadWarehousePrices() async {
    final repository = ref.read(productRepositoryProvider);
    final prices = await repository.getWarehousePricesForProduct(widget.product.id);
    if (mounted) {
      setState(() {
        _warehousePriceRows.clear();
        for (final wp in prices) {
          _warehousePriceRows.add(_EditWarehousePriceRow(
            warehouseId: wp.warehouseId,
            existingId: wp.id,
            salePrice: wp.salePrice > 0 ? wp.salePrice.toString() : '',
            costPrice: wp.costPrice > 0 ? wp.costPrice.toString() : '',
            wholesalePrice: wp.wholesalePrice > 0 ? wp.wholesalePrice.toString() : '',
          ));
        }
      });
    }
  }

  Future<void> _loadProductUnits() async {
    final repo = ref.read(productRepositoryProvider);
    final units = await repo.getProductUnits(widget.product.id);
    if (mounted && units.isNotEmpty) {
      setState(() {
        _showPackagingUnits = true;
        _unitRows.clear();
        for (int i = 0; i < units.length; i++) {
          final u = units[i];
          _unitRows.add(_EditProductUnitRow(
            existingId: u.id,
            unitName: u.unitName,
            barcode: u.barcode,
            factor: u.quantityInBase.toString(),
            // كان بيتجاهل السعر المخزّن، فأي سعر مخصّص كان بيضيع مع أول حفظ
            // (الحفظ بيمسح الوحدات ويعيد إدراجها).
            // نفس صيغة حقل المعامل فوق (‏toString) — بتدور ذهاباً وإياباً بأمان
            // مع tryParseLocale، على عكس الصيغ اللي بتحطّ فواصل آلاف.
            salePrice: u.salePrice > 0 ? u.salePrice.toString() : null,
          ));
          if (u.isDefaultSale) _defaultUnitIndex = i;
        }
      });
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    codeController.dispose();
    barcodeController.dispose();
    salePriceController.dispose();
    costPriceController.dispose();
    minStockController.dispose();
    shelfDaysController.dispose();
    alertDaysController.dispose();
    pricePerUnitController.dispose();
    taxRateController.dispose();
    priceTalabatController.dispose();
    priceCareemController.dispose();
    priceAshyaeController.dispose();
    wholesalePriceController.dispose();
    scalePluNumberController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// v138 (Issue 2): block edits on a client when the row was created
  /// directly on the server. Editing a server-canonical product from a
  /// client would either (a) be silently rejected by the server's auth
  /// rules or (b) overwrite an admin's deliberate change with branch-
  /// local input. Either way it confuses operators. We surface it as a
  /// banner so they know to use the server.
  bool get _lockedFromServer =>
      NetworkService.instance.isClient && widget.product.createdOnServer;

  @override
  Widget build(BuildContext context) {
    final locked = _lockedFromServer;
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
                PhosphorIconsBold.pencil,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('تعديل الصنف', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 700,
          height: 520,
          child: Column(
            children: [
              if (locked) _buildLockedBanner(),
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(PhosphorIconsBold.package, size: 15), text: 'أساسي'),
                  Tab(icon: Icon(PhosphorIconsBold.currencyDollar, size: 15), text: 'الأسعار'),
                  Tab(icon: Icon(PhosphorIconsBold.warehouse, size: 15), text: 'المخزون'),
                  Tab(icon: Icon(PhosphorIconsBold.stack, size: 15), text: 'التعبئة'),
                  Tab(icon: Icon(PhosphorIconsBold.image, size: 15), text: 'الوسائط'),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: AbsorbPointer(
                  absorbing: locked,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBasicTab(),
                      _buildPricingTab(),
                      _buildInventoryTab(),
                      _buildPackagingTab(),
                      _buildMediaTab(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(locked ? 'إغلاق' : 'إلغاء'),
          ),
          ElevatedButton(
            onPressed: (locked || _saving) ? null : _saveProduct,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsBold.lock, color: Colors.amber.shade800, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'هذا الصنف تم إنشاؤه على السيرفر — التعديل متاح من شاشة السيرفر فقط.',
              style: TextStyle(
                color: Colors.amber.shade900,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab builders ────────────────────────────────────────────────────────────

  Widget _buildBasicTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'البيانات الأساسية',
            PhosphorIconsBold.package,
            AppColors.primary,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildCompactTextField(
                  nameController,
                  'اسم الصنف *',
                  icon: PhosphorIconsBold.tag,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactTextField(
                  codeController,
                  'الكود',
                  icon: PhosphorIconsBold.hash,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactTextField(
                  barcodeController,
                  'الباركود',
                  icon: PhosphorIconsBold.barcode,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildCategorySelector(),
          const SizedBox(height: 8),
          _buildSupplierSelector(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: DropdownButtonFormField<String>(
                    initialValue: _productType,
                    decoration: InputDecoration(
                      labelText: 'نوع الصنف',
                      prefixIcon:
                          const Icon(PhosphorIconsBold.factory, size: 18),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'general',
                          child: Text('عام', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(
                          value: 'raw_material',
                          child:
                              Text('خامة', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(
                          value: 'finished_goods',
                          child: Text('منتج تام',
                              style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(
                          value: 'service',
                          child:
                              Text('خدمة', style: TextStyle(fontSize: 13))),
                    ],
                    onChanged: (v) =>
                        setState(() => _productType = v ?? 'general'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildWarehouseSelector()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPricingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'الأسعار الأساسية',
            PhosphorIconsBold.currencyDollar,
            AppColors.primary,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildCompactTextField(
                  salePriceController,
                  'سعر البيع *',
                  isNumber: true,
                  icon: PhosphorIconsBold.currencyDollar,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactTextField(
                  costPriceController,
                  'سعر التكلفة',
                  isNumber: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                // البند 4: كان حقلاً نصياً حراً يقبل أي رقم.
                child: ProductFormHelpers.buildTaxRateDropdown(
                  taxRateController,
                  icon: PhosphorIconsBold.percent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactTextField(
                  minStockController,
                  'الحد الأدنى',
                  isNumber: true,
                  icon: PhosphorIconsBold.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'أسعار المنصات',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildCompactTextField(
                  priceTalabatController,
                  'سعر طلبات',
                  isNumber: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactTextField(
                  priceCareemController,
                  'سعر كريم',
                  isNumber: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactTextField(
                  priceAshyaeController,
                  'سعر أشيائي',
                  isNumber: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactTextField(
                  wholesalePriceController,
                  'سعر الجملة',
                  isNumber: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildWarehousePricingSection(),
        ],
      ),
    );
  }

  Widget _buildInventoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildProductExpirySectionGuarded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(
                  'إدارة الصلاحية',
                  PhosphorIconsBold.calendarBlank,
                  AppColors.info,
                ),
                _buildExpirySection(),
                const SizedBox(height: 12),
              ],
            ),
          ),
          _buildSectionHeader(
            'البيع بالوزن',
            PhosphorIconsBold.scales,
            AppColors.warning,
          ),
          _buildWeightSection(),
          const SizedBox(height: 12),
          _buildNegativeSaleSection(),
        ],
      ),
    );
  }

  Widget _buildPackagingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: _buildPackagingUnitsSection(),
    );
  }

  Widget _buildMediaTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildImageSection(),
      ),
    );
  }

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

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const Expanded(child: Divider(indent: 8)),
        ],
      ),
    );
  }

  Widget _buildCategorySelector() {
    _categoriesFuture ??= ref.read(productRepositoryProvider).getCategories();
    return FutureBuilder<List<Category>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        final categories = snapshot.data ?? [];
        return Autocomplete<Category>(
          // `RawAutocomplete` reads `initialValue` exactly once, in its own
          // initState. On the first build the categories haven't loaded yet,
          // so the resolved name is '' — and without a key the element is
          // reused when they arrive, leaving the field permanently blank on
          // edit even though `selectedCategoryId` was correct all along.
          // Keying on both inputs forces a fresh State once either changes.
          key: ValueKey('category-${categories.length}-$selectedCategoryId'),
          optionsBuilder: (textValue) {
            if (textValue.text.isEmpty) return categories;
            return categories.where(
              (c) =>
                  c.name.toLowerCase().contains(textValue.text.toLowerCase()),
            );
          },
          displayStringForOption: (c) => c.name,
          initialValue: selectedCategoryId != null
              ? TextEditingValue(
                  text:
                      categories
                          .where((c) => c.id == selectedCategoryId)
                          .firstOrNull
                          ?.name ??
                      '',
                )
              : null,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: 'التصنيف *',
                labelStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(PhosphorIconsBold.squaresFour, size: 18),
                hintText: 'ابحث عن التصنيف...',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
                suffixIcon: selectedCategoryId != null
                    ? IconButton(
                        icon: const Icon(PhosphorIconsBold.x, size: 14),
                        onPressed: () {
                          controller.clear();
                          setState(() => selectedCategoryId = null);
                        },
                      )
                    : null,
              ),
            );
          },
          onSelected: (category) =>
              setState(() => selectedCategoryId = category.id),
        );
      },
    );
  }

  Widget _buildSupplierSelector() {
    _suppliersFuture ??= ref.read(productRepositoryProvider).getSuppliers();
    return FutureBuilder<List<Party>>(
      future: _suppliersFuture,
      builder: (context, snapshot) {
        final suppliers = snapshot.data ?? [];
        return Autocomplete<Party>(
          // Same one-shot `initialValue` trap as the category selector above.
          key: ValueKey('supplier-${suppliers.length}-$selectedSupplierId'),
          optionsBuilder: (textValue) {
            if (textValue.text.isEmpty) return suppliers;
            return suppliers.where(
              (s) =>
                  s.name.toLowerCase().contains(textValue.text.toLowerCase()) ||
                  (s.phone?.contains(textValue.text) ?? false),
            );
          },
          displayStringForOption: (s) => s.name,
          initialValue: selectedSupplierId != null
              ? TextEditingValue(
                  text:
                      suppliers
                          .where((s) => s.id == selectedSupplierId)
                          .firstOrNull
                          ?.name ??
                      '',
                )
              : null,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: 'المورد',
                labelStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(PhosphorIconsBold.truck, size: 18),
                hintText: 'ابحث عن المورد...',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
                suffixIcon: selectedSupplierId != null
                    ? IconButton(
                        icon: const Icon(PhosphorIconsBold.x, size: 14),
                        onPressed: () {
                          controller.clear();
                          setState(() => selectedSupplierId = null);
                        },
                      )
                    : null,
              ),
            );
          },
          onSelected: (supplier) =>
              setState(() => selectedSupplierId = supplier.id),
        );
      },
    );
  }

  Widget _buildWarehouseSelector() {
    return FutureBuilder<List<Warehouse>>(
      future: ref.read(branchRepositoryProvider).getWarehouses(),
      builder: (context, snapshot) {
        final warehouses = snapshot.data ?? [];
        return SizedBox(
          height: 48,
          child: DropdownButtonFormField<int?>(
            initialValue: selectedWarehouseId,
            decoration: InputDecoration(
              labelText: 'المخزن الافتراضي',
              labelStyle: const TextStyle(fontSize: 12),
              prefixIcon:
                  const Icon(PhosphorIconsBold.warehouse, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('بدون', style: TextStyle(fontSize: 13)),
              ),
              ...warehouses.map(
                (w) => DropdownMenuItem<int?>(
                  value: w.id,
                  child: Text(w.name,
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            ],
            onChanged: (v) =>
                setState(() => selectedWarehouseId = v),
          ),
        );
      },
    );
  }

  Widget _buildExpirySection() {
    return Container(
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
              const Text('تتبع الصلاحية', style: TextStyle(fontSize: 12)),
              const Spacer(),
              SizedBox(
                height: 24,
                child: Switch(
                  value: trackExpiry,
                  onChanged: (v) => setState(() => trackExpiry = v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (trackExpiry) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildMiniTextField(
                    shelfDaysController,
                    'مدة الصلاحية (يوم)',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMiniTextField(
                    alertDaysController,
                    'تنبيه قبل (يوم)',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeightSection() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'count',
                label: Text('عدد', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: 'weight',
                label: Text('ميزان', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: 'weightByPiece',
                label: Text('ميزان بالحبة', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: 'display',
                label: Text('عرض', style: TextStyle(fontSize: 11)),
              ),
            ],
            selected: {scaleType},
            onSelectionChanged: (v) => setState(() => scaleType = v.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
          if (scaleType == 'weight' || scaleType == 'weightByPiece') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildMiniTextField(
                    pricePerUnitController,
                    'سعر الكيلو',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMiniTextField(
                    scalePluNumberController,
                    'رقم PLU',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNegativeSaleSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          const Text('البيع بالسالب', style: TextStyle(fontSize: 12)),
          const Spacer(),
          SizedBox(
            height: 24,
            child: Switch(
              value: allowNegativeSale,
              onChanged: (v) => setState(() => allowNegativeSale = v),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSection() {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'صورة المنتج',
            PhosphorIconsBold.image,
            AppColors.success,
          ),
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
                    color: Colors.white,
                  ),
                  child: selectedImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            selectedImage!,
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 28,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final result = await FilePicker.pickFiles(
                              type: FileType.image,
                              withData: true,
                            );
                            if (result != null &&
                                result.files.first.bytes != null) {
                              setState(
                                () => selectedImage = result.files.first.bytes,
                              );
                            }
                          },
                          icon: const Icon(PhosphorIconsBold.upload, size: 12),
                          label: const Text(
                            'اختيار',
                            style: TextStyle(fontSize: 11),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                      if (selectedImage != null) ...[
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: IconButton(
                            onPressed: () =>
                                setState(() => selectedImage = null),
                            icon: const Icon(PhosphorIconsBold.trash, size: 14),
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
    );
  }

  Future<void> _saveProduct() async {
    if (_saving) return;
    if (nameController.text.isEmpty || salePriceController.text.isEmpty) {
      AppToast.show(
        context,
        'يرجى ملء الحقول المطلوبة (الاسم، السعر)',
        type: ToastType.error,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _doSaveProduct();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _doSaveProduct() async {
    final repository = ref.read(productRepositoryProvider);

    // Check code uniqueness
    if (codeController.text.isNotEmpty) {
      final codeUsed = await repository.productCodeExists(
        codeController.text,
        excludeProductId: widget.product.id,
      );
      if (codeUsed) {
        if (mounted) {
          AppToast.show(
            context,
            'هذا الكود مستخدم بالفعل لصنف آخر',
            type: ToastType.error,
          );
        }
        return;
      }
    }

    // Check barcode uniqueness
    if (barcodeController.text.isNotEmpty) {
      final barcodeUsed = await repository.barcodeExists(
        barcodeController.text,
        excludeProductId: widget.product.id,
      );
      if (barcodeUsed) {
        if (mounted) {
          AppToast.show(
            context,
            'هذا الباركود مستخدم بالفعل لصنف آخر',
            type: ToastType.error,
          );
        }
        return;
      }
    }

    // GAP-P3-FIX-16: Warn when costPrice is zero (inflates COGS reports)
    final parsedCostPrice = NumberUtils.tryParseLocale(costPriceController.text) ?? widget.product.costPrice;
    if (parsedCostPrice == 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(children: [
              Icon(Icons.warning_amber, color: Colors.orange),
              SizedBox(width: 8),
              Text('تحذير: تكلفة المنتج صفر'),
            ]),
            content: const Text(
              'سعر التكلفة مُدخل كصفر. هذا سيُظهر الربح مُضخَّماً في تقارير تكلفة البضاعة المباعة (COGS).\n\nهل تريد المتابعة؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('مراجعة السعر'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('متابعة'),
              ),
            ],
          ),
        ),
      );
      if (proceed != true) return;
    }

    final isSoldByWeight =
        scaleType == 'weight' || scaleType == 'weightByPiece';
    final updatedProduct = widget.product.copyWith(
      name: nameController.text,
      code: codeController.text,
      barcode: barcodeController.text.isNotEmpty
          ? barcodeController.text
          : null,
      categoryId: selectedCategoryId,
      salePrice:
          NumberUtils.tryParseLocale(salePriceController.text) ?? widget.product.salePrice,
      costPrice:
          NumberUtils.tryParseLocale(costPriceController.text) ?? widget.product.costPrice,
      minStock:
          NumberUtils.tryParseLocale(minStockController.text) ?? widget.product.minStock,
      trackExpiry: trackExpiry,
      defaultShelfDays: int.tryParse(shelfDaysController.text) ?? 90,
      alertDaysBefore: int.tryParse(alertDaysController.text) ?? 30,
      isSoldByWeight: isSoldByWeight,
      pricePerUnit: isSoldByWeight
          ? NumberUtils.tryParseLocale(pricePerUnitController.text)
          : null,
      imageData: selectedImage,
      allowNegativeSale: allowNegativeSale,
      taxRate:
          NumberUtils.tryParseLocale(taxRateController.text) ?? widget.product.taxRate,
      priceTalabat:
          NumberUtils.tryParseLocale(priceTalabatController.text) ??
          widget.product.priceTalabat,
      priceCareem:
          NumberUtils.tryParseLocale(priceCareemController.text) ??
          widget.product.priceCareem,
      priceAshyae:
          NumberUtils.tryParseLocale(priceAshyaeController.text) ??
          widget.product.priceAshyae,
      wholesalePrice:
          NumberUtils.tryParseLocale(wholesalePriceController.text) ??
          widget.product.wholesalePrice,
      supplierId: selectedSupplierId,
      warehouseId: selectedWarehouseId,
      productType: _productType,
      scaleType: scaleType,
      scalePluNumber: int.tryParse(scalePluNumberController.text),
    );

    // Use controller to save changes
    final success = await ref
        .read(productsControllerProvider.notifier)
        .updateProduct(updatedProduct);

    // Save warehouse prices
    if (success) {
      // Delete removed rows
      for (final deletedId in _deletedWarehousePriceIds) {
        await repository.deleteWarehousePrice(deletedId);
      }

      // Upsert remaining rows
      for (final row in _warehousePriceRows) {
        if (row.warehouseId != null) {
          await repository.upsertWarehousePrice(
            productId: widget.product.id,
            warehouseId: row.warehouseId!,
            salePrice: NumberUtils.tryParseLocale(row.salePriceController.text) ?? 0,
            costPrice: NumberUtils.tryParseLocale(row.costPriceController.text) ?? 0,
            wholesalePrice: NumberUtils.tryParseLocale(row.wholesalePriceController.text) ?? 0,
          );
        }
      }

      // Save product units (delete all old, insert new)
      final repo = ref.read(productRepositoryProvider);
      final salePrice = NumberUtils.tryParseLocale(salePriceController.text) ?? widget.product.salePrice;
      final costPrice = NumberUtils.tryParseLocale(costPriceController.text) ?? widget.product.costPrice;
      await repo.deleteProductUnits(widget.product.id);
      if (_unitRows.isNotEmpty) {
        for (int i = 0; i < _unitRows.length; i++) {
          final row = _unitRows[i];
          final unitName = row.unitName.trim();
          if (unitName.isEmpty) continue;
          final factor = NumberUtils.tryParseLocale(row.factorController.text) ?? 1.0;
          final barcode = row.barcodeController.text.trim();
          // سعر الوحدة: المُدخَل يفوز، وفاضي = اشتق (السلوك القديم كـسلوك
          // افتراضي). ده اللي بيخلّي شوال السكر يتسعّر جملةً بدل ما يبقى
          // مجبراً على سعر الكيلو × ٥٠.
          final unitSalePrice = ProductFormHelpers.resolveUnitSalePrice(
            typedPrice:
                NumberUtils.tryParseLocale(row.salePriceController.text.trim()),
            baseSalePrice: salePrice,
            factor: factor,
          );
          await repo.insertProductUnit(
            ProductUnitsCompanion.insert(
              productId: widget.product.id,
              unitName: unitName,
              barcode: Value(barcode.isNotEmpty ? barcode : null),
              quantityInBase: Value(factor),
              salePrice: Value(unitSalePrice),
              costPrice: Value(costPrice * factor),
              isBaseUnit: Value(factor == 1.0),
              isDefaultPurchase: Value(i == _defaultUnitIndex),
              isDefaultSale: Value(i == _defaultUnitIndex),
              sortOrder: Value(i),
            ),
          );
        }
      }
    }

    if (mounted && success) {
      Navigator.pop(context);
      AppToast.show(context, 'تم تحديث الصنف بنجاح', type: ToastType.success);
    }
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
                  const Text(
                    'أسعار المخازن',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
                          _warehousePriceRows.add(_EditWarehousePriceRow());
                        });
                      },
                      icon: const Icon(PhosphorIconsBold.plus, size: 14),
                      label: const Text(
                        'إضافة سعر مخزن',
                        style: TextStyle(fontSize: 12),
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

  Widget _buildWarehousePriceRowWidget(_EditWarehousePriceRow row, int index) {
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
                      final usedIds = _warehousePriceRows
                          .where((r) => r != row && r.warehouseId != null)
                          .map((r) => r.warehouseId)
                          .toSet();
                      final available = warehouses
                          .where((w) => !usedIds.contains(w.id) || w.id == row.warehouseId)
                          .toList();

                      return SizedBox(
                        height: 40,
                        child: DropdownButtonFormField<int?>(
                          initialValue: row.warehouseId,
                          decoration: InputDecoration(
                            labelText: 'المخزن',
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
                      final removed = _warehousePriceRows.removeAt(index);
                      if (removed.existingId != null) {
                        _deletedWarehousePriceIds.add(removed.existingId!);
                      }
                    });
                  },
                  child: Icon(PhosphorIconsBold.trash, size: 16,
                      color: Colors.red.shade400),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      controller: row.salePriceController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'سعر البيع',
                        labelStyle: const TextStyle(fontSize: 11),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6)),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      controller: row.costPriceController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'التكلفة',
                        labelStyle: const TextStyle(fontSize: 11),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6)),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      controller: row.wholesalePriceController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'سعر الجملة',
                        labelStyle: const TextStyle(fontSize: 11),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6)),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build multi-unit packaging section
  Widget _buildPackagingUnitsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _showPackagingUnits = !_showPackagingUnits;
              if (_showPackagingUnits && _unitRows.isEmpty) {
                _unitRows.add(_EditProductUnitRow(unitName: 'قطعة', factor: '1'));
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
                const Text('وحدات التعبئة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.info)),
                const Text('  (قطعة → علبة → كرتونة)', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                const Spacer(),
                if (_unitRows.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                    child: Text('${_unitRows.length}', style: const TextStyle(fontSize: 11, color: AppColors.info, fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(width: 4),
                Icon(_showPackagingUnits ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown, size: 16, color: AppColors.info),
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
                // Headers
                const Row(
                  children: [
                    SizedBox(width: 40, child: Text('افتراضي', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    SizedBox(width: 8),
                    Expanded(flex: 2, child: Text('اسم الوحدة', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    SizedBox(width: 8),
                    Expanded(flex: 2, child: Text('الباركود', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    SizedBox(width: 8),
                    Expanded(child: Text('عامل التحويل', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    SizedBox(width: 30),
                  ],
                ),
                const Divider(height: 12),
                ...List.generate(_unitRows.length, (index) {
                  final row = _unitRows[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          // ignore: deprecated_member_use
                          child: Radio<int>(
                            value: index,
                            // ignore: deprecated_member_use
                            groupValue: _defaultUnitIndex,
                            // ignore: deprecated_member_use
                            onChanged: (v) => setState(() => _defaultUnitIndex = v!),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 8),
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
                                    hintText: 'الوحدة ${index + 1}',
                                    hintStyle: const TextStyle(fontSize: 12),
                                  ),
                                  items: units.map((u) => DropdownMenuItem(
                                    value: u.name,
                                    child: Text(u.name, style: const TextStyle(fontSize: 12)),
                                  )).toList(),
                                  onChanged: (v) => setState(() => row.unitName = v ?? ''),
                                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
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
                                hintText: 'باركود ${index + 1}',
                                hintStyle: const TextStyle(fontSize: 12),
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: TextField(
                              controller: row.factorController,
                              keyboardType: TextInputType.number,
                              enabled: index > 0,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                isDense: true,
                                hintText: 'مثال: 12',
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
                                hintText: 'سعر الوحدة',
                                hintStyle: const TextStyle(fontSize: 11),
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 26,
                          child: index == 0
                              ? const SizedBox()
                              : InkWell(
                                  onTap: () {
                                    setState(() {
                                      _unitRows.removeAt(index);
                                      if (_defaultUnitIndex >= _unitRows.length) _defaultUnitIndex = 0;
                                    });
                                  },
                                  child: const Icon(PhosphorIconsBold.trash, size: 14, color: AppColors.error),
                                ),
                        ),
                      ],
                    ),
                  );
                }),
                if (_unitRows.length < 5)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _unitRows.add(_EditProductUnitRow())),
                      icon: const Icon(PhosphorIconsBold.plus, size: 14),
                      label: const Text('إضافة وحدة', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.info),
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

/// Helper class to hold per-warehouse price row data for editing
class _EditWarehousePriceRow {
  int? warehouseId;
  int? existingId;
  final TextEditingController salePriceController;
  final TextEditingController costPriceController;
  final TextEditingController wholesalePriceController;

  _EditWarehousePriceRow({
    this.warehouseId,
    this.existingId,
    String? salePrice,
    String? costPrice,
    String? wholesalePrice,
  })  : salePriceController = TextEditingController(text: salePrice ?? ''),
        costPriceController = TextEditingController(text: costPrice ?? ''),
        wholesalePriceController =
            TextEditingController(text: wholesalePrice ?? '');
}

/// Helper class for product unit row data (edit mode)
class _EditProductUnitRow {
  int? existingId;
  String unitName;
  final TextEditingController barcodeController;
  final TextEditingController factorController;

  /// سعر بيع الوحدة. فاضي = اشتق من سعر الصنف × المعامل (السلوك القديم).
  ///
  /// `product_units.sale_price` كان موجوداً في السكيما ونقطة البيع بتحترمه
  /// (‏cart_item_tile.dart) — لكن النموذج ده كان بيدهسه دايماً بـ
  /// «سعر أساسي × معامل»، ومفيش حقل يدخّله. فشوال السكر لازم يساوي سعر
  /// الكيلو × ٥٠ بالظبط، ومستحيل تحطّله سعر جملة. وأسوأ: التحميل عند الفتح
  /// كان بيتجاهل القيمة المخزّنة، فأي سعر مخصّص بيضيع مع أول حفظ.
  final TextEditingController salePriceController;

  _EditProductUnitRow({
    this.existingId,
    this.unitName = '',
    String? barcode,
    String? factor,
    String? salePrice,
  })  : barcodeController = TextEditingController(text: barcode ?? ''),
        factorController = TextEditingController(text: factor ?? '1'),
        salePriceController = TextEditingController(text: salePrice ?? '');
}
