import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_colors.dart';

/// Product form widget for add/edit dialogs
class ProductForm extends StatefulWidget {
  final String? initialName;
  final String? initialCode;
  final double? initialSalePrice;
  final double? initialCostPrice;
  final double? initialMinStock;
  final bool initialTrackExpiry;
  final int initialShelfDays;
  final int initialAlertDays;
  final bool initialIsSoldByWeight;
  final double? initialPricePerUnit;
  final Uint8List? initialImage;
  final int? initialCategoryId;
  final double? initialPriceTalabat;
  final double? initialPriceCareem;
  final double? initialPriceAshyae;
  final bool isEdit;
  // Scale fields
  final int? initialScalePluNumber;
  final String initialScaleType;
  // Warehouse
  final int? initialWarehouseId;
  final List<Map<String, dynamic>> warehouses; // [{id, name}]

  const ProductForm({
    super.key,
    this.initialName,
    this.initialCode,
    this.initialSalePrice,
    this.initialCostPrice,
    this.initialMinStock,
    this.initialTrackExpiry = false,
    this.initialShelfDays = 90,
    this.initialAlertDays = 30,
    this.initialIsSoldByWeight = false,
    this.initialPricePerUnit,
    this.initialImage,
    this.initialCategoryId,
    this.initialPriceTalabat,
    this.initialPriceCareem,
    this.initialPriceAshyae,
    this.isEdit = false,
    this.initialScalePluNumber,
    this.initialScaleType = 'count',
    this.initialWarehouseId,
    this.warehouses = const [],
  });

  @override
  State<ProductForm> createState() => ProductFormState();
}

class ProductFormState extends State<ProductForm> {
  late final TextEditingController nameController;
  late final TextEditingController codeController;
  late final TextEditingController salePriceController;
  late final TextEditingController costPriceController;
  late final TextEditingController minStockController;
  late final TextEditingController shelfDaysController;
  late final TextEditingController alertDaysController;
  late final TextEditingController pricePerUnitController;
  late final TextEditingController priceTalabatController;
  late final TextEditingController priceCareemController;
  late final TextEditingController priceAshyaeController;
  late final TextEditingController scalePluNumberController;

  late bool trackExpiry;
  late String scaleType; // 'count', 'weight', 'weightByPiece', 'display'
  Uint8List? selectedImage;
  int? selectedCategoryId;
  int? selectedWarehouseId;

  /// Whether this product is sold by weight (derived from scaleType)
  bool get isSoldByWeight =>
      scaleType == 'weight' || scaleType == 'weightByPiece';

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.initialName);
    codeController = TextEditingController(text: widget.initialCode);
    salePriceController = TextEditingController(
      text: widget.initialSalePrice?.toString(),
    );
    costPriceController = TextEditingController(
      text: widget.initialCostPrice?.toString(),
    );
    minStockController = TextEditingController(
      text: widget.initialMinStock?.toString() ?? '0',
    );
    shelfDaysController = TextEditingController(
      text: widget.initialShelfDays.toString(),
    );
    alertDaysController = TextEditingController(
      text: widget.initialAlertDays.toString(),
    );
    pricePerUnitController = TextEditingController(
      text: widget.initialPricePerUnit?.toString(),
    );
    priceTalabatController = TextEditingController(
      text: widget.initialPriceTalabat?.toString(),
    );
    priceCareemController = TextEditingController(
      text: widget.initialPriceCareem?.toString(),
    );
    priceAshyaeController = TextEditingController(
      text: widget.initialPriceAshyae?.toString(),
    );
    scalePluNumberController = TextEditingController(
      text: widget.initialScalePluNumber?.toString(),
    );

    trackExpiry = widget.initialTrackExpiry;
    // Backward compat: if old isSoldByWeight is true but scaleType is 'count', upgrade to 'weight'
    if (widget.initialScaleType == 'count' && widget.initialIsSoldByWeight) {
      scaleType = 'weight';
    } else {
      scaleType = widget.initialScaleType;
    }
    selectedImage = widget.initialImage;
    selectedCategoryId = widget.initialCategoryId;
    selectedWarehouseId = widget.initialWarehouseId;
  }

  @override
  void dispose() {
    nameController.dispose();
    codeController.dispose();
    salePriceController.dispose();
    costPriceController.dispose();
    minStockController.dispose();
    shelfDaysController.dispose();
    alertDaysController.dispose();
    pricePerUnitController.dispose();
    priceTalabatController.dispose();
    priceCareemController.dispose();
    priceAshyaeController.dispose();
    scalePluNumberController.dispose();
    super.dispose();
  }

  /// Get form data for submission
  Map<String, dynamic> getFormData() {
    return {
      'name': nameController.text,
      'code': codeController.text,
      'salePrice': double.tryParse(salePriceController.text) ?? 0,
      'costPrice': double.tryParse(costPriceController.text) ?? 0,
      'minStock': double.tryParse(minStockController.text) ?? 0,
      'trackExpiry': trackExpiry,
      'shelfDays': int.tryParse(shelfDaysController.text) ?? 90,
      'alertDays': int.tryParse(alertDaysController.text) ?? 30,
      'isSoldByWeight': isSoldByWeight,
      'pricePerUnit': isSoldByWeight
          ? double.tryParse(pricePerUnitController.text)
          : null,
      'image': selectedImage,
      'categoryId': selectedCategoryId,
      'priceTalabat': double.tryParse(priceTalabatController.text) ?? 0,
      'priceCareem': double.tryParse(priceCareemController.text) ?? 0,
      'priceAshyae': double.tryParse(priceAshyaeController.text) ?? 0,
      'scaleType': scaleType,
      'scalePluNumber': int.tryParse(scalePluNumberController.text),
      'warehouseId': selectedWarehouseId,
    };
  }

  bool validate() {
    return nameController.text.isNotEmpty &&
        salePriceController.text.isNotEmpty &&
        (widget.isEdit || selectedCategoryId != null);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Basic Info
          _buildTextField(
            nameController,
            'اسم المنتج *',
            icon: PhosphorIconsBold.package,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            codeController,
            'الكود (PLU)',
            icon: PhosphorIconsBold.barcode,
          ),
          const Padding(
            padding: EdgeInsets.only(right: 12, top: 4, bottom: 8),
            child: Text(
              'كود الصنف الداخلي — يُستخدم في باركود الميزان. أدخل نفس الكود المبرمج على الميزان.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),

          // Prices
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  salePriceController,
                  'سعر البيع *',
                  isNumber: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  costPriceController,
                  'سعر التكلفة',
                  isNumber: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Multi-level pricing
          const Text(
            'أسعار المنصات',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  priceTalabatController,
                  'سعر طلبات',
                  isNumber: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTextField(
                  priceCareemController,
                  'سعر كريم',
                  isNumber: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTextField(
                  priceAshyaeController,
                  'سعر أشيائي',
                  isNumber: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          _buildTextField(
            minStockController,
            'الحد الأدنى',
            isNumber: true,
            icon: PhosphorIconsBold.warning,
          ),

          // Warehouse selector
          if (widget.warehouses.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: selectedWarehouseId,
              decoration: InputDecoration(
                labelText: 'المخزن الرئيسي',
                prefixIcon: const Icon(PhosphorIconsBold.warehouse, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('بدون مخزن')),
                ...widget.warehouses.map((w) => DropdownMenuItem<int?>(
                  value: w['id'] as int,
                  child: Text(w['name'] as String),
                )),
              ],
              onChanged: (v) => setState(() => selectedWarehouseId = v),
            ),
          ],

          const SizedBox(height: 16),
          const Divider(),

          // Expiry Tracking
          _buildSectionHeader(
            'إدارة الصلاحية',
            PhosphorIconsBold.calendarBlank,
            AppColors.warning,
          ),
          SwitchListTile(
            title: const Text('يتطلب تتبع صلاحية'),
            value: trackExpiry,
            onChanged: (v) => setState(() => trackExpiry = v),
            dense: true,
          ),
          if (trackExpiry) ...[
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    shelfDaysController,
                    'مدة الصلاحية (أيام)',
                    isNumber: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    alertDaysController,
                    'التنبيه قبل (أيام)',
                    isNumber: true,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          const Divider(),

          // Scale Type Selection (replaces old isSoldByWeight toggle)
          _buildSectionHeader(
            'نوع البيع والميزان',
            PhosphorIconsBold.scales,
            AppColors.info,
          ),
          const SizedBox(height: 8),
          _buildScaleTypeSelector(),
          const SizedBox(height: 8),

          // PLU number (shown for weight and weightByPiece types)
          if (scaleType == 'weight' || scaleType == 'weightByPiece') ...[
            _buildTextField(
              scalePluNumberController,
              'رقم المادة عالميزان (PLU)',
              isNumber: true,
              icon: PhosphorIconsBold.hash,
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12, top: 4, bottom: 4),
              child: Text(
                'الرقم المخزن على الميزان لهذا الصنف — يُستخدم لتصدير الأصناف للميزان',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Price per unit (shown for weight-based types)
          if (isSoldByWeight)
            _buildTextField(
              pricePerUnitController,
              'سعر الكيلو',
              isNumber: true,
            ),

          const SizedBox(height: 16),
          const Divider(),

          // Image
          _buildSectionHeader(
            'صورة المنتج',
            PhosphorIconsBold.image,
            AppColors.success,
          ),
          const SizedBox(height: 8),
          Center(child: _buildImagePicker()),
        ],
      ),
    );
  }

  /// Builds the 4-option scale type selector matching the reference system
  Widget _buildScaleTypeSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'count',
          label: Text('عدد', style: TextStyle(fontSize: 12)),
          icon: Icon(PhosphorIconsBold.cube, size: 16),
        ),
        ButtonSegment(
          value: 'weight',
          label: Text('ميزان', style: TextStyle(fontSize: 12)),
          icon: Icon(PhosphorIconsBold.scales, size: 16),
        ),
        ButtonSegment(
          value: 'weightByPiece',
          label: Text('ميزان بالحبة', style: TextStyle(fontSize: 12)),
          icon: Icon(PhosphorIconsBold.circleHalf, size: 16),
        ),
        ButtonSegment(
          value: 'display',
          label: Text('عرض', style: TextStyle(fontSize: 12)),
          icon: Icon(PhosphorIconsBold.eye, size: 16),
        ),
      ],
      selected: {scaleType},
      onSelectionChanged: (Set<String> selected) {
        setState(() => scaleType = selected.first);
      },
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    IconData? icon,
    bool isNumber = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        isDense: true,
      ),
    );
  }

  Widget _buildImagePicker() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: selectedImage != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(selectedImage!, fit: BoxFit.cover),
                )
              : const Icon(
                  PhosphorIconsBold.image,
                  size: 40,
                  color: AppColors.textMuted,
                ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(PhosphorIconsBold.upload, size: 16),
              label: const Text('اختيار'),
            ),
            if (selectedImage != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => setState(() => selectedImage = null),
                icon: const Icon(PhosphorIconsBold.trash),
                color: AppColors.error,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result != null && result.files.first.bytes != null) {
      setState(() => selectedImage = result.files.first.bytes);
    }
  }
}
