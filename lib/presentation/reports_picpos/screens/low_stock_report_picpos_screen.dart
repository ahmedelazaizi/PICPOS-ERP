import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/entities/product_entity.dart';
import '../../picpos_shell/picpos_filter_strip.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../screens/reports/report_export_guard.dart';
import 'inventory_alert_report_support.dart';
import 'picpos_report_export.dart';

final lowStockAlertProvider = FutureProvider.autoDispose<List<ProductEntity>>((ref) {
  return ref.watch(productRepositoryProvider).getLowStockProducts();
});

class LowStockReportPicposScreen extends ConsumerStatefulWidget {
  const LowStockReportPicposScreen({super.key});

  @override
  ConsumerState<LowStockReportPicposScreen> createState() => _LowStockReportState();
}

class _LowStockReportState extends ConsumerState<LowStockReportPicposScreen> {
  String _query = '';
  int? _warehouseId;
  int? _categoryId;
  bool _shortageFirst = true;

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(lowStockAlertProvider);
    final warehouses = ref.watch(allWarehousesProvider).value ?? const [];
    final categories = ref.watch(allCategoriesProvider).value ?? const [];
    return PicPosScreenScaffold(
      title: tr('أصناف منخفضة المخزون'),
      subtitle: tr('الأصناف تحت حد إعادة الطلب مع مقدار الاحتياج'),
      icon: PhosphorIconsBold.warning,
      headerActions: [
         buildReportExportAction(onExport: _exportToExcel),
         IconButton(onPressed: () => ref.invalidate(lowStockAlertProvider), icon: const Icon(PhosphorIconsBold.arrowClockwise), tooltip: tr('تحديث')),
       ],
      subHeader: PicPosFilterStrip(children: [
        SizedBox(width: 240, height: 40, child: TextField(decoration: InputDecoration(hintText: tr('بحث بالاسم أو الباركود'), prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16), filled: true, fillColor: context.picposField, border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: context.picposHairline))), onChanged: (value) => setState(() => _query = value.trim().toLowerCase()))),
        _choice(context, tr('كل المستودعات'), warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(), _warehouseId, (value) => setState(() => _warehouseId = value)),
        _choice(context, tr('كل التصنيفات'), categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(), _categoryId, (value) => setState(() => _categoryId = value)),
        PicPosFilterPill(icon: PhosphorIconsBold.sortAscending, label: _shortageFirst ? tr('الأكبر احتياجاً') : tr('الاسم'), onTap: () => setState(() => _shortageFirst = !_shortageFirst)),
      ]),
      bodyPadding: EdgeInsets.zero,
      body: products.when(loading: () => const Center(child: CircularProgressIndicator()), error: (error, _) => Center(child: Text(tr('تعذّر تحميل التقرير: {p0}', {'p0': error}))), data: (items) {
        final filtered = items.where((product) => _matches(product)).toList()..sort((a, b) => _shortageFirst ? (b.minStock - b.currentStock).compareTo(a.minStock - a.currentStock) : a.name.compareTo(b.name));
        final rows = filtered.map((product) => InventoryAlertRow(name: product.name, code: product.barcode ?? product.code, quantity: product.currentStock, reference: tr('نقص {p0}', {'p0': (product.minStock - product.currentStock).toStringAsFixed(2)}), detail: tr('الحد الأدنى: {p0}', {'p0': product.minStock.toStringAsFixed(2)}), value: product.currentStock * product.costPrice, severity: product.currentStock <= 0 ? 1 : 0)).toList();
        if (rows.isEmpty) return inventoryAlertEmpty(tr('لا توجد أصناف منخفضة المخزون'));
        return ListView(children: [InventoryAlertKpis(rows: rows, mode: 'low'), InventoryAlertTable(rows: rows, mode: 'low')]);
      }),
    );
  }

  Future<void> _exportToExcel() async {
    final items = await ref.read(lowStockAlertProvider.future);
    if (!mounted) return;
    final filtered = items.where(_matches).toList()
      ..sort((a, b) => _shortageFirst
          ? (b.minStock - b.currentStock).compareTo(a.minStock - a.currentStock)
          : a.name.compareTo(b.name));
    await exportPicPosReport(
      context: context,
      ref: ref,
      title: tr('أصناف منخفضة المخزون'),
      headers: [tr('المنتج'), tr('الرمز / الباركود'), tr('الكمية'), tr('الحد / النقص'), tr('قيمة التكلفة')],
      rows: [
        for (final product in filtered)
          [
            product.name,
            product.barcode ?? product.code,
            product.currentStock,
            tr('الحد الأدنى: {p0} · نقص {p1}', {
              'p0': product.minStock.toStringAsFixed(2),
              'p1': (product.minStock - product.currentStock).toStringAsFixed(2),
            }),
            product.currentStock * product.costPrice,
          ],
      ],
      scopedBranchIds: null,
    );
  }

  bool _matches(ProductEntity product) {
    final queryMatches = _query.isEmpty || product.name.toLowerCase().contains(_query) || product.code.toLowerCase().contains(_query) || (product.barcode ?? '').toLowerCase().contains(_query);
    return queryMatches && (_warehouseId == null || product.warehouseId == _warehouseId) && (_categoryId == null || product.categoryId == _categoryId);
  }

  Widget _choice<T>(BuildContext context, String label, List<DropdownMenuItem<T>> items, T? value, ValueChanged<T?> onChanged) => Container(height: 40, padding: const EdgeInsetsDirectional.only(start: 10), decoration: BoxDecoration(color: context.picposField, border: Border.all(color: context.picposHairline), borderRadius: BorderRadius.circular(11)), child: DropdownButton<T>(value: value, hint: Text(label), underline: const SizedBox.shrink(), items: items, onChanged: onChanged));
}
