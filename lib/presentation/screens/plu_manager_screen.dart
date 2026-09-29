import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/design_system/typography.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:ui' as ui;

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/providers.dart';
import '../../domain/repositories/scale_repository.dart';
import '../../services/label_scale_service.dart';
import '../../services/scale_transport.dart';
import 'providers/plu_manager_controller.dart';

part 'plu_manager/plu_table_mixin.dart';
part 'plu_manager/plu_auto_assign_mixin.dart';
part 'plu_manager/plu_csv_mixin.dart';
part 'plu_manager/plu_scale_upload_mixin.dart';

/// PLU Manager Screen
/// Dedicated screen for managing scale PLU assignments.
/// Allows: inline PLU editing, auto-assign, bulk operations, CSV import.
class PluManagerScreen extends ConsumerStatefulWidget {
  const PluManagerScreen({super.key});

  @override
  ConsumerState<PluManagerScreen> createState() => _PluManagerScreenState();
}

class _PluManagerScreenState extends ConsumerState<PluManagerScreen>
    with _PluTableMixin, _PluAutoAssignMixin, _PluCsvMixin, _PluScaleUploadMixin {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  @override
  int? _selectedCategoryId;
  bool _showOnlyAssigned = false;
  bool _showOnlyWeightItems = false;
  @override
  List<Product> _allProducts = [];
  List<Category> _allCategories = [];
  @override
  final Map<int, TextEditingController> _pluControllers = {};
  bool _isLoading = true;

  // Direct scale upload state
  @override
  bool _isUploading = false;
  @override
  String _uploadStatus = '';
  @override
  int _uploadProgress = 0;
  @override
  int _uploadTotal = 0;

  @override
  PluManagerController get _controller =>
      ref.read(pluManagerControllerProvider);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final c in _pluControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final products = await _controller.getAllProducts();
    final categories = await _controller.getAllCategories();
    if (mounted) {
      setState(() {
        _allProducts = products;
        _allCategories = categories;
        _isLoading = false;
        for (final p in products) {
          _pluControllers[p.id] = TextEditingController(
            text: p.scalePluNumber?.toString() ?? '',
          );
        }
      });
    }
  }

  List<Product> get _filteredProducts {
    var list = _allProducts.where((p) => p.isActive).toList();

    if (_selectedCategoryId != null) {
      list = list.where((p) => p.categoryId == _selectedCategoryId).toList();
    }
    if (_showOnlyAssigned) {
      list = list.where((p) => p.scalePluNumber != null).toList();
    }
    if (_showOnlyWeightItems) {
      list = list.where((p) => p.isSoldByWeight).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where(
            (p) =>
                p.name.toLowerCase().contains(q) ||
                p.code.toLowerCase().contains(q) ||
                (p.scalePluNumber?.toString().contains(q) ?? false),
          )
          .toList();
    }

    return list;
  }

  int get _assignedCount =>
      _allProducts.where((p) => p.scalePluNumber != null && p.isActive).length;
  int get _weightItemsCount =>
      _allProducts.where((p) => p.isSoldByWeight && p.isActive).length;

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title:  Text(tr('مدير أرقام PLU')),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(PhosphorIconsBold.arrowRight),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: tr('رجوع'),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              _buildStatsBar(),
              const SizedBox(height: 12),
              _buildToolbar(),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildProductTable(filtered),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(PhosphorIconsBold.barcode, size: 24, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('مدير أرقام PLU'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.headlineMedium?.color,
              ),
            ),
             Text(
              tr('ربط أرقام PLU بالمنتجات للموازين'),
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
        const Spacer(),
        SizedBox(
          width: 280,
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: tr('بحث بالاسم أو الكود أو PLU...'),
              prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(PhosphorIconsBold.x, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // STATS BAR
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildStatsBar() {
    return Row(
      children: [
        _buildStatChip(tr('إجمالي الأصناف'), '${_allProducts.where((p) => p.isActive).length}', PhosphorIconsBold.package, AppColors.primary),
        const SizedBox(width: 8),
        _buildStatChip(tr('أصناف بـ PLU'), '$_assignedCount', PhosphorIconsBold.barcode, AppColors.success),
        const SizedBox(width: 8),
        _buildStatChip(tr('أصناف الوزن'), '$_weightItemsCount', PhosphorIconsBold.scales, AppColors.warning),
        const SizedBox(width: 8),
        _buildStatChip(tr('بدون PLU'), '${_allProducts.where((p) => p.scalePluNumber == null && p.isActive).length}', PhosphorIconsBold.warning, AppColors.error),
      ],
    );
  }

  Widget _buildStatChip(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // TOOLBAR (Filters + Actions)
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<int?>(
              initialValue: _selectedCategoryId,
              isExpanded: true,
              decoration:  InputDecoration(
                labelText: tr('التصنيف'),
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: [
                 DropdownMenuItem<int?>(value: null, child: Text(tr('الكل'))),
                ..._allCategories.map(
                  (c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                ),
              ],
              onChanged: (v) => setState(() => _selectedCategoryId = v),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label:  Text(tr('PLU مُعيّن'), style: const TextStyle(fontSize: 12)),
            selected: _showOnlyAssigned,
            onSelected: (v) => setState(() => _showOnlyAssigned = v),
            selectedColor: AppColors.success.withValues(alpha: 0.2),
          ),
          const SizedBox(width: 4),
          FilterChip(
            label:  Text(tr('أصناف وزن'), style: const TextStyle(fontSize: 12)),
            selected: _showOnlyWeightItems,
            onSelected: (v) => setState(() => _showOnlyWeightItems = v),
            selectedColor: AppColors.warning.withValues(alpha: 0.2),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _showAutoAssignDialog,
            icon: const Icon(PhosphorIconsBold.lightning, size: 16),
            label:  Text(tr('ترقيم تلقائي'), style: const TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warning,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 4),
          OutlinedButton.icon(
            onPressed: _importPluFromCsv,
            icon: const Icon(PhosphorIconsBold.fileArrowDown, size: 16),
            label:  Text(tr('استيراد CSV'), style: const TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          ),
          const SizedBox(width: 4),
          OutlinedButton.icon(
            onPressed: _exportPluToCsv,
            icon: const Icon(PhosphorIconsBold.fileArrowUp, size: 16),
            label:  Text(tr('تصدير CSV'), style: const TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _isUploading ? null : _uploadDirectToScale,
            icon: _isUploading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(PhosphorIconsBold.upload, size: 16),
            label: Text(_isUploading ? tr('جاري الترحيل...') : tr('ترحيل للميزان'), style: const TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.teal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 18),
            onPressed: _loadData,
            tooltip: tr('تحديث'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════

  @override
  Future<void> _savePlu(Product product, String pluText) async {
    final plu = int.tryParse(pluText.trim());
    if (plu == null && pluText.trim().isNotEmpty) {
      AppToast.show(context, tr('رقم PLU يجب أن يكون رقماً صحيحاً'), type: ToastType.error);
      return;
    }

    if (plu != null) {
      final existing = await _controller.getProductByScalePlu(plu);
      if (existing != null && existing.id != product.id) {
        if (!mounted) return;
        AppToast.show(context, tr('رقم PLU {plu} مستخدم بالفعل في: {p0}', {'plu': plu, 'p0': existing.name}), type: ToastType.error);
        return;
      }
    }

    await _controller.updateProductScalePlu(product.id, pluNumber: plu);
    await _loadData();
    if (mounted) {
      AppToast.show(
        context,
        plu != null ? tr('تم حفظ PLU #{plu} لـ {p0}', {'plu': plu, 'p0': product.name}) : tr('تم حذف PLU من {p0}', {'p0': product.name}),
        type: ToastType.success,
      );
    }
  }

  @override
  Future<void> _clearPlu(Product product) async {
    await _controller.clearProductScalePlu(product.id);
    _pluControllers[product.id]?.clear();
    await _loadData();
    if (mounted) {
      AppToast.show(context, tr('تم حذف PLU من {p0}', {'p0': product.name}), type: ToastType.success);
    }
  }

  @override
  Future<void> _toggleWeight(Product product, bool isWeight) async {
    await _controller.updateProductScalePlu(product.id, isSoldByWeight: isWeight);
    await _loadData();
  }
}
