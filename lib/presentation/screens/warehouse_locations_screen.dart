import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/i18n/tr.dart';
import '../../core/permissions/permission_codes.dart';
import '../../data/providers/providers.dart';
import '../../services/invoice_generator.dart';
import '../../web/web_write_guard.dart';
import '../widgets/permission_guard.dart';

class WarehouseLocationsScreen extends ConsumerStatefulWidget {
  const WarehouseLocationsScreen({super.key, required this.warehouseId, required this.warehouseName});

  final int warehouseId;
  final String warehouseName;

  @override
  ConsumerState<WarehouseLocationsScreen> createState() => _WarehouseLocationsScreenState();
}

class _WarehouseLocationsScreenState extends ConsumerState<WarehouseLocationsScreen> {
  List<Map<String, dynamic>> locations = [];
  List<Map<String, dynamic>> stock = [];
  List<Map<String, dynamic>> discrepancies = [];
  bool enabled = false;
  bool strictLots = false;
  String? error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final db = ref.read(databaseProvider);
    try {
      final bins = await db.warehouseLocations(widget.warehouseId);
      final quantities = await db.warehouseLocationStock(widget.warehouseId);
      final differences = await db.warehouseBinDiscrepancies();
      final active = await db.getSettingValue('warehouse_bins_enabled') == 'true';
      final blocking = await db.getSettingValue('block_issue_without_valid_batch') == 'true';
      if (mounted) setState(() {
        locations = bins;
        stock = quantities;
        discrepancies = differences;
        enabled = active;
        strictLots = blocking;
        error = null;
      });
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    }
  }

  Future<void> change(Future<void> Function() action) async {
    // م3-9: كتابات مباشرة على AppDatabase غير مدعومة عبر الويب.
    if (!WebWriteGuard.allow(context, feature: tr('مواقع المخزن'))) return;
    if (!await ensurePermission(ref, context, PermissionCodes.warehousesManage,
        actionName: tr('إدارة مواقع التخزين'))) return;
    try {
      await action();
      await refresh();
    } catch (failure) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$failure')));
    }
  }

  Future<void> editLocation([Map<String, dynamic>? location]) async {
    final code = TextEditingController(text: location?['bin_code'] as String? ?? '');
    final aisle = TextEditingController(text: location?['aisle'] as String? ?? '');
    final rack = TextEditingController(text: location?['rack'] as String? ?? '');
    final shelf = TextEditingController(text: location?['shelf'] as String? ?? '');
    final submitted = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: Text(location == null ? tr('إضافة موقع') : tr('تعديل الموقع')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: code, decoration: InputDecoration(labelText: tr('رمز الموقع'))),
        TextField(controller: aisle, decoration: InputDecoration(labelText: tr('الممر'))),
        TextField(controller: rack, decoration: InputDecoration(labelText: tr('الرف'))),
        TextField(controller: shelf, decoration: InputDecoration(labelText: tr('الطبقة'))),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: Text(tr('إلغاء'))),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(tr('حفظ')))],
    ));
    if (submitted == true) {
      await change(() async {
        final db = ref.read(databaseProvider);
        if (location == null) {
          await db.saveWarehouseLocation(warehouseId: widget.warehouseId,
              binCode: code.text, aisle: aisle.text, rack: rack.text, shelf: shelf.text);
        } else {
          await db.editWarehouseLocation(locationId: (location['id'] as num).toInt(),
              binCode: code.text, aisle: aisle.text, rack: rack.text, shelf: shelf.text);
        }
      });
    }
    code.dispose(); aisle.dispose(); rack.dispose(); shelf.dispose();
  }

  Future<void> moveStock(Map<String, dynamic> source) async {
    final quantity = TextEditingController();
    int? productId;
    int? batchId;
    int? targetId;
    final sourceStock = stock.where((row) => row['location_id'] == source['id']).toList();
    final targets = locations.where((bin) => bin['id'] != source['id'] && bin['is_active'] == 1).toList();
    final submitted = await showDialog<bool>(context: context, builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(tr('نقل مخزون بين المواقع')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(initialValue: productId,
              decoration: InputDecoration(labelText: tr('الصنف')),
              items: [for (final id in sourceStock.map((row) => (row['product_id'] as num).toInt()).toSet())
                DropdownMenuItem(value: id, child: Text('${sourceStock.firstWhere(
                    (row) => row['product_id'] == id)['product_name']}'))],
              onChanged: (id) => update(() { productId = id; batchId = null; })),
          DropdownButtonFormField<int>(key: ValueKey(productId), initialValue: batchId,
              decoration: InputDecoration(labelText: tr('الدفعة (اختياري)')),
              items: [for (final row in sourceStock.where((row) => row['product_id'] == productId && row['batch_id'] != null))
                DropdownMenuItem(value: (row['batch_id'] as num).toInt(),
                    child: Text('${row['batch_number']}'))],
              onChanged: (id) => update(() => batchId = id)), 
          TextField(controller: quantity, keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('الكمية'))),
          DropdownButtonFormField<int>(initialValue: targetId,
              decoration: InputDecoration(labelText: tr('الموقع الوجهة')),
              items: [for (final bin in targets) DropdownMenuItem(
                  value: (bin['id'] as num).toInt(), child: Text('${bin['bin_code']}'))],
              onChanged: (id) => update(() => targetId = id)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: Text(tr('إلغاء'))),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(tr('نقل')))],
      ),
    ));
    if (submitted == true) await change(() => ref.read(databaseProvider).moveStockBetweenBins(
        fromLocationId: (source['id'] as num).toInt(), toLocationId: targetId ?? 0,
        productId: productId ?? 0, quantity: double.tryParse(quantity.text) ?? 0,
        batchId: batchId));
    quantity.dispose();
  }

  Future<void> printLabel(String name, String barcode) async {
    await change(() async {
      await InvoiceGenerator.printBarcodeLabel(
          productName: name, barcodeValue: barcode, copies: 1);
    });
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: Text(tr('مواقع المخزن: {name}', {'name': widget.warehouseName}))),
      body: PermissionGuard(permission: PermissionCodes.warehousesView,
        child: RefreshIndicator(onRefresh: refresh, child: ListView(padding: const EdgeInsets.all(16), children: [
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          PermissionGuard(permission: PermissionCodes.warehousesManage,
            child: Wrap(spacing: 12, children: [
              FilledButton.icon(onPressed: () => editLocation(), icon: const Icon(Icons.add),
                  label: Text(tr('إضافة موقع'))),
              FilledButton(onPressed: enabled || discrepancies.isNotEmpty ? null : () => change(
                  () => ref.read(databaseProvider).enableWarehouseBins()),
                  child: Text(enabled ? tr('المواقع مفعلة') : tr('تفعيل المواقع'))),
              if (!enabled && discrepancies.isNotEmpty)
                Text(tr('عالج فروقات التسوية قبل تفعيل المواقع')),
              SwitchListTile(value: strictLots, title: Text(tr('منع البيع بدون دفعة صالحة')),
                onChanged: (value) => change(() => ref.read(databaseProvider).setSetting(
                    'block_issue_without_valid_batch', value ? 'true' : 'false'))),
            ])),
          for (final bin in locations) Card(child: ExpansionTile(
            title: Text('${bin['bin_code']}  •  ${bin['barcode']}'),
            subtitle: Text('${tr('الممر')}: ${bin['aisle'] ?? '-'}  '
                '${tr('الرف')}: ${bin['rack'] ?? '-'}  '
                '${tr('الطبقة')}: ${bin['shelf'] ?? '-'}  '
                '${bin['is_active'] == 1 ? tr('نشط') : tr('معطل')}'),
            children: [
              for (final row in stock.where((entry) => entry['location_id'] == bin['id']))
                ListTile(title: Text('${row['product_name']}  •  ${row['quantity']}'),
                    subtitle: Text('${tr('الدفعة')}: ${row['batch_number'] ?? '-'}'),
                    trailing: PermissionGuard(permission: PermissionCodes.warehousesManage,
                        child: IconButton(tooltip: tr('طباعة ملصق الصنف'),
                            icon: const Icon(Icons.print), onPressed: () async {
                              final product = await ref.read(databaseProvider).getProductById(
                                  (row['product_id'] as num).toInt());
                              if (product != null) await printLabel(product.name,
                                  product.barcode ?? product.code);
                            }))),
              PermissionGuard(permission: PermissionCodes.warehousesManage,
                  child: Wrap(children: [
                    IconButton(tooltip: tr('طباعة ملصق الموقع'), icon: const Icon(Icons.qr_code),
                        onPressed: () => printLabel('${bin['bin_code']}', '${bin['barcode']}')),
                    if (bin['is_default'] != 1) IconButton(tooltip: tr('تعديل'),
                        icon: const Icon(Icons.edit), onPressed: () => editLocation(bin)),
                    if (enabled && bin['is_active'] == 1) IconButton(tooltip: tr('نقل'),
                        icon: const Icon(Icons.swap_horiz), onPressed: () => moveStock(bin)),
                    if (bin['is_default'] != 1 && bin['is_active'] == 1)
                      IconButton(tooltip: tr('تعطيل'), icon: const Icon(Icons.block),
                          onPressed: () => change(() => ref.read(databaseProvider)
                              .deactivateWarehouseLocation((bin['id'] as num).toInt()))),
                  ])),
            ],
          )),
          Text(tr('تقرير تسوية المواقع'), style: Theme.of(context).textTheme.titleLarge),
          if (discrepancies.isEmpty) Text(tr('لا توجد فروقات')),
          for (final row in discrepancies) ListTile(
            title: Text('${tr('الصنف')}: ${row['product_name']}  ${tr('المخزن')}: ${row['warehouse_name']}'),
            subtitle: Text('${tr('رصيد المخزن')}: ${row['warehouse_quantity']}  '
                '${tr('رصيد المواقع')}: ${row['bin_quantity']}  '
                '${tr('رصيد الدفعات')}: ${row['batch_quantity']}'),
          ),
        ]))),
    ),
  );
}
