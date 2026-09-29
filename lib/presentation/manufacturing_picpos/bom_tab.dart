import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/providers/providers.dart';
import '../../domain/entities/product_entity.dart';
import '../picpos_shell/picpos_data_table.dart';

class BomTab extends StatelessWidget {
  const BomTab({super.key, required this.boms, required this.products, required this.onEdit});
  final List<BillOfMaterialData> boms;
  final List<ProductEntity> products;
  final Future<void> Function(List<ProductEntity>, [int?]) onEdit;

  @override
  Widget build(BuildContext context) {
    final productNames = {for (final product in products) product.id: product.name};
    return PicPosDataTable(
      title: 'قوائم المكوّنات',
      subtitle: 'التكلفة تشمل المواد والتحميل وتقترح سعر البيع',
      columns: const [
        PicPosTableColumn('المنتج التام', flex: 2),
        PicPosTableColumn('الكود'),
        PicPosTableColumn('الناتج'),
        PicPosTableColumn('التكلفة', align: PicPosCellAlign.end),
        PicPosTableColumn('إجراء'),
      ],
      rows: [
        for (final bom in boms)
          PicPosTableRow(cells: [
            PicPosTextCell(productNames[bom.finishedProductId] ?? 'منتج غير معروف', bold: true),
            PicPosTextCell(bom.bomCode),
            PicPosTextCell('${bom.expectedQuantity}'),
            PicPosTextCell(bom.estimatedCost.toStringAsFixed(2), bold: true),
            PicPosButtonCell('تحرير', icon: PhosphorIconsBold.pencilSimple, tint: Colors.blue, onPressed: () => onEdit(products, bom.id)),
          ]),
      ],
    );
  }
}
