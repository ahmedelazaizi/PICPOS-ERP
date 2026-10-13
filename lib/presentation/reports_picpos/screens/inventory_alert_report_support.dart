import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../domain/entities/product_entity.dart';
import '../../../domain/repositories/inventory_repository.dart';

import '../../../core/i18n/tr.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_hub_kpi.dart';
import '../../picpos_shell/picpos_surface.dart';

class InventoryAlertRow {
  const InventoryAlertRow({
    required this.name,
    required this.code,
    required this.quantity,
    required this.reference,
    required this.detail,
    required this.value,
    this.severity = 0,
  });

  final String name;
  final String code;
  final double quantity;
  final String reference;
  final String detail;
  final double value;
  final int severity;
}

class InventoryAlertKpis extends StatelessWidget {
  const InventoryAlertKpis({super.key, required this.rows, required this.mode});

  final List<InventoryAlertRow> rows;
  final String mode;

  @override
  Widget build(BuildContext context) {
    final quantity = rows.fold<double>(0, (sum, row) => sum + row.quantity);
    final value = rows.fold<double>(0, (sum, row) => sum + row.value);
    final label = mode == 'low'
        ? tr('أصناف تحت الحد')
        : mode == 'expired'
            ? tr('دفعات منتهية')
            : tr('دفعات قريبة');
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 12),
      child: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(width: (constraints.maxWidth - 20) / 3, child: PicPosHubKpiCard(kpi: PicPosHubKpi(icon: PhosphorIconsBold.package, label: label, value: '${rows.length}', tint: context.picposBrandInk))),
            SizedBox(width: (constraints.maxWidth - 20) / 3, child: PicPosHubKpiCard(kpi: PicPosHubKpi(icon: PhosphorIconsBold.cube, label: tr('إجمالي الكمية'), value: quantity.toStringAsFixed(2), tint: context.picposBrandInk))),
            SizedBox(width: (constraints.maxWidth - 20) / 3, child: PicPosHubKpiCard(kpi: PicPosHubKpi(icon: PhosphorIconsBold.coins, label: tr('قيمة التكلفة المعرّضة'), value: value.toStringAsFixed(2), tint: context.picposBrandInk))),
          ],
        ),
      ),
    );
  }
}

class InventoryAlertTable extends StatelessWidget {
  const InventoryAlertTable({super.key, required this.rows, required this.mode});

  final List<InventoryAlertRow> rows;
  final String mode;

  @override
  Widget build(BuildContext context) {
    final quantity = rows.fold<double>(0, (sum, row) => sum + row.quantity);
    final value = rows.fold<double>(0, (sum, row) => sum + row.value);
    return PicPosContentCard(
      padding: EdgeInsets.zero,
      child: PicPosDataTable(
        title: mode == 'low' ? tr('تفاصيل النقص') : tr('تفاصيل الدفعات'),
        subtitle: tr('اضغط عنوان العمود للترتيب من الفلتر أعلاه'),
        columns: [
          PicPosTableColumn(tr('المنتج'), flex: 2.4),
          PicPosTableColumn(tr('الرمز / الدفعة'), flex: 1.5),
          PicPosTableColumn(tr('الكمية'), align: PicPosCellAlign.end),
          PicPosTableColumn(mode == 'low' ? tr('الحد / النقص') : tr('التاريخ'), flex: 1.5),
          PicPosTableColumn(tr('قيمة التكلفة'), align: PicPosCellAlign.end),
        ],
        rows: [
          for (final row in rows)
            PicPosTableRow(cells: [
              PicPosTextCell(row.name, sub: row.detail, bold: true),
              PicPosTextCell(row.code),
              PicPosTextCell(row.quantity.toStringAsFixed(2), bold: true),
              PicPosTextCell(row.reference, tint: row.severity > 0 ? Theme.of(context).colorScheme.error : context.picposText),
              PicPosTextCell(row.value.toStringAsFixed(2), bold: true),
            ]),
        ],
        totals: [tr('الإجمالي'), '', quantity.toStringAsFixed(2), '', value.toStringAsFixed(2)],
        emptyLabel: mode == 'low' ? tr('لا توجد أصناف منخفضة المخزون') : mode == 'expired' ? tr('لا توجد منتجات منتهية الصلاحية') : tr('لا توجد منتجات قاربت على الانتهاء'),
      ),
    );
  }
}

List<InventoryAlertRow> expiryAlertRows({
  required List<ProductBatchData> batches,
  required List<ProductEntity> products,
  required int days,
  required bool expired,
}) {
  final names = {for (final product in products) product.id: product};
  return [
    for (final batch in batches)
      if (batch.expiryDate != null)
        InventoryAlertRow(
          name: names[batch.productId]?.name ?? tr('منتج #{p0}', {'p0': batch.productId}),
          code: batch.batchNumber ?? tr('بدون رقم دفعة'),
          quantity: batch.quantity,
          reference: DateFormat('dd/MM/yyyy').format(batch.expiryDate!),
          detail: expired ? tr('منتهٍ') : tr('متبقٍ {p0} يوماً', {'p0': batch.daysUntilExpiry ?? 0}),
          value: batch.quantity * batch.costPrice,
          severity: expired || (batch.daysUntilExpiry ?? days) <= 7 ? 1 : 0,
        ),
  ];
}

Widget inventoryAlertEmpty(String message) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsBold.checkCircle, size: 56),
          const SizedBox(height: 12),
          Text(message),
        ],
      ),
    );
