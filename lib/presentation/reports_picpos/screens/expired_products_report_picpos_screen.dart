import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../picpos_shell/picpos_filter_strip.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import 'inventory_alert_report_support.dart';

final expiredProductsAlertProvider = FutureProvider.autoDispose<List<ProductBatchData>>((ref) {
  return ref.watch(inventoryRepositoryProvider).getExpiredBatches();
});

class ExpiredProductsReportPicposScreen extends ConsumerStatefulWidget {
  const ExpiredProductsReportPicposScreen({super.key});

  @override
  ConsumerState<ExpiredProductsReportPicposScreen> createState() => _ExpiredProductsReportState();
}

class _ExpiredProductsReportState extends ConsumerState<ExpiredProductsReportPicposScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final batches = ref.watch(expiredProductsAlertProvider);
    final products = ref.watch(allProductsProvider).value ?? const [];
    return PicPosScreenScaffold(
      title: tr('منتجات منتهية الصلاحية'),
      subtitle: tr('دفعات منتهية وقيمة المخزون المعرّضة للخسارة'),
      icon: PhosphorIconsBold.xCircle,
      headerActions: [IconButton(onPressed: () => ref.invalidate(expiredProductsAlertProvider), icon: const Icon(PhosphorIconsBold.arrowClockwise), tooltip: tr('تحديث'))],
      subHeader: PicPosFilterStrip(children: [
        SizedBox(width: 240, height: 40, child: TextField(decoration: InputDecoration(hintText: tr('بحث بالاسم أو رقم الدفعة'), prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16), filled: true, fillColor: Theme.of(context).colorScheme.surface, border: const OutlineInputBorder()), onChanged: (value) => setState(() => _query = value.trim().toLowerCase()))),
        PicPosFilterPill(icon: PhosphorIconsBold.calendarBlank, label: tr('الأقدم أولاً')),
      ]),
      bodyPadding: EdgeInsets.zero,
      body: batches.when(loading: () => const Center(child: CircularProgressIndicator()), error: (error, _) => Center(child: Text(tr('تعذّر تحميل التقرير: {p0}', {'p0': error}))), data: (items) {
        final rows = expiryAlertRows(batches: items, products: products, days: 0, expired: true).where((row) => _query.isEmpty || row.name.toLowerCase().contains(_query) || row.code.toLowerCase().contains(_query)).toList();
        if (rows.isEmpty) return inventoryAlertEmpty(tr('لا توجد منتجات منتهية الصلاحية'));
        return ListView(children: [InventoryAlertKpis(rows: rows, mode: 'expired'), InventoryAlertTable(rows: rows, mode: 'expired')]);
      }),
    );
  }
}
