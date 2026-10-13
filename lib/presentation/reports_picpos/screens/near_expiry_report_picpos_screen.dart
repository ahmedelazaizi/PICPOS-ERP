import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../picpos_shell/picpos_filter_strip.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../screens/reports/report_export_guard.dart';
import 'inventory_alert_report_support.dart';
import 'picpos_report_export.dart';

final nearExpiryAlertProvider = FutureProvider.autoDispose.family<List<ProductBatchData>, int>((ref, days) {
  return ref.watch(inventoryRepositoryProvider).getExpiringBatches(days);
});

class NearExpiryReportPicposScreen extends ConsumerStatefulWidget {
  const NearExpiryReportPicposScreen({super.key});

  @override
  ConsumerState<NearExpiryReportPicposScreen> createState() => _NearExpiryReportState();
}

class _NearExpiryReportState extends ConsumerState<NearExpiryReportPicposScreen> {
  String _query = '';
  int? _warehouseId;
  int? _categoryId;
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final batches = ref.watch(nearExpiryAlertProvider(_days));
    final products = ref.watch(allProductsProvider).value ?? const [];
    final warehouses = ref.watch(allWarehousesProvider).value ?? const [];
    final categories = ref.watch(allCategoriesProvider).value ?? const [];
    return PicPosScreenScaffold(
      title: tr('منتجات قاربت على الانتهاء'),
      subtitle: tr('نطاق زمني مرن مع تلوين شدة الخطر وقيمة التكلفة'),
      icon: PhosphorIconsBold.clock,
      headerActions: [
         buildReportExportAction(onExport: _exportToExcel),
         IconButton(onPressed: () => ref.invalidate(nearExpiryAlertProvider(_days)), icon: const Icon(PhosphorIconsBold.arrowClockwise), tooltip: tr('تحديث')),
       ],
      subHeader: PicPosFilterStrip(children: [
        SizedBox(width: 240, height: 40, child: TextField(decoration: InputDecoration(hintText: tr('بحث بالاسم أو رقم الدفعة'), prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16), filled: true, fillColor: Theme.of(context).colorScheme.surface, border: const OutlineInputBorder()), onChanged: (value) => setState(() => _query = value.trim().toLowerCase()))),
        _choice(context, tr('كل المستودعات'), warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(), _warehouseId, (value) => setState(() => _warehouseId = value)),
         _choice(context, tr('كل التصنيفات'), categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(), _categoryId, (value) => setState(() => _categoryId = value)),
         for (final days in [7, 15, 30, 60, 90]) PicPosFilterPill(icon: PhosphorIconsBold.calendar, label: tr('{p0} يوم', {'p0': days}), tone: days == _days ? context.picposBrandInk : null, onTap: () => setState(() => _days = days)),
      ]),
      bodyPadding: EdgeInsets.zero,
      body: batches.when(loading: () => const Center(child: CircularProgressIndicator()), error: (error, _) => Center(child: Text(tr('تعذّر تحميل التقرير: {p0}', {'p0': error}))), data: (items) {
        final productById = {for (final product in products) product.id: product};
        final filteredBatches = items.where((batch) {
          final product = productById[batch.productId];
          final text = '${product?.name ?? ''} ${batch.batchNumber ?? ''}'.toLowerCase();
          return (_query.isEmpty || text.contains(_query)) &&
              (_warehouseId == null || product?.warehouseId == _warehouseId) &&
              (_categoryId == null || product?.categoryId == _categoryId);
        }).toList();
        final rows = expiryAlertRows(batches: filteredBatches, products: products, days: _days, expired: false);
        if (rows.isEmpty) return inventoryAlertEmpty(tr('لا توجد منتجات قاربت على الانتهاء'));
        return ListView(children: [InventoryAlertKpis(rows: rows, mode: 'near'), InventoryAlertTable(rows: rows, mode: 'near')]);
      }),
    );
  }

  Future<void> _exportToExcel() async {
    final items = await ref.read(nearExpiryAlertProvider(_days).future);
    if (!mounted) return;
    final products = ref.read(allProductsProvider).value ?? const [];
    final productById = {for (final product in products) product.id: product};
    final batches = items.where((batch) {
      final product = productById[batch.productId];
      final text = '${product?.name ?? ''} ${batch.batchNumber ?? ''}'.toLowerCase();
      return (_query.isEmpty || text.contains(_query)) &&
          (_warehouseId == null || product?.warehouseId == _warehouseId) &&
          (_categoryId == null || product?.categoryId == _categoryId);
    }).toList();
    final rows = expiryAlertRows(batches: batches, products: products, days: _days, expired: false);
    await exportPicPosReport(
      context: context,
      ref: ref,
      title: tr('منتجات قاربت على الانتهاء'),
      headers: [tr('المنتج'), tr('الرمز / الدفعة'), tr('الكمية'), tr('التاريخ'), tr('قيمة التكلفة')],
      rows: [for (final row in rows) [row.name, row.code, row.quantity, row.reference, row.value]],
    );
  }

  Widget _choice<T>(BuildContext context, String label, List<DropdownMenuItem<T>> items, T? value, ValueChanged<T?> onChanged) => Container(
        height: 40,
        padding: const EdgeInsetsDirectional.only(start: 10),
        decoration: BoxDecoration(color: context.picposField, border: Border.all(color: context.picposHairline), borderRadius: BorderRadius.circular(11)),
        child: DropdownButton<T>(value: value, hint: Text(label), underline: const SizedBox.shrink(), items: items, onChanged: onChanged),
      );
}
