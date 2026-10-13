import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../picpos_shell/picpos_filter_strip.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'inventory_alert_report_support.dart';

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
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final batches = ref.watch(nearExpiryAlertProvider(_days));
    final products = ref.watch(allProductsProvider).value ?? const [];
    return PicPosScreenScaffold(
      title: tr('منتجات قاربت على الانتهاء'),
      subtitle: tr('نطاق زمني مرن مع تلوين شدة الخطر وقيمة التكلفة'),
      icon: PhosphorIconsBold.clock,
      headerActions: [IconButton(onPressed: () => ref.invalidate(nearExpiryAlertProvider(_days)), icon: const Icon(PhosphorIconsBold.arrowClockwise), tooltip: tr('تحديث'))],
      subHeader: PicPosFilterStrip(children: [
        SizedBox(width: 240, height: 40, child: TextField(decoration: InputDecoration(hintText: tr('بحث بالاسم أو رقم الدفعة'), prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16), filled: true, fillColor: Theme.of(context).colorScheme.surface, border: const OutlineInputBorder()), onChanged: (value) => setState(() => _query = value.trim().toLowerCase()))),
        for (final days in [7, 15, 30, 60, 90]) PicPosFilterPill(icon: PhosphorIconsBold.calendar, label: tr('{p0} يوم', {'p0': days}), tone: days == _days ? context.picposBrandInk : null, onTap: () => setState(() => _days = days)),
      ]),
      bodyPadding: EdgeInsets.zero,
      body: batches.when(loading: () => const Center(child: CircularProgressIndicator()), error: (error, _) => Center(child: Text(tr('تعذّر تحميل التقرير: {p0}', {'p0': error}))), data: (items) {
        final rows = expiryAlertRows(batches: items, products: products, days: _days, expired: false).where((row) => _query.isEmpty || row.name.toLowerCase().contains(_query) || row.code.toLowerCase().contains(_query)).toList();
        if (rows.isEmpty) return inventoryAlertEmpty(tr('لا توجد منتجات قاربت على الانتهاء'));
        return ListView(children: [InventoryAlertKpis(rows: rows, mode: 'near'), InventoryAlertTable(rows: rows, mode: 'near')]);
      }),
    );
  }
}
