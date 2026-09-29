import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design_system/app_button.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../domain/repositories/manufacturing_repository.dart';
import '../picpos_shell/picpos_data_table.dart';
import '../picpos_shell/picpos_dialog.dart';

class ManufacturingOrdersTab extends ConsumerWidget {
  const ManufacturingOrdersTab({
    super.key,
    required this.orders,
    required this.boms,
    required this.warehouses,
  });

  final List<ManufacturingOrderData> orders;
  final List<BillOfMaterialData> boms;
  final List<Warehouse> warehouses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bomNames = {for (final bom in boms) bom.id: bom.bomCode};
    final repository = ref.read(manufacturingRepositoryProvider);
    Future<void> runAction(Future<void> Function() action, String success) async {
      try {
        await action();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_arabicError(error)), backgroundColor: AppColors.error),
          );
        }
      }
    }

    return PicPosDataTable(
      title: tr('أوامر الإنتاج'),
      subtitle: tr('إنشاء، بدء، إكمال، وعكس أوامر الإنتاج مع قيد المخزون'),
      headerAction: AppButton.primary(
        onPressed: () async {
          final form = await showProductionOrderDialog(
            context,
            boms: boms,
            warehouses: warehouses,
          );
          if (form == null) return;
          await runAction(
            () => repository.createManufacturingOrder(
              bomId: form.bomId,
              orderedQty: form.quantity,
              warehouseId: form.warehouseId,
              startDate: DateTime.now(),
              notes: form.notes,
            ).then((_) {}),
            tr('تم إنشاء أمر الإنتاج'),
          );
        },
        icon: const Icon(PhosphorIconsBold.plus),
        child:  Text(tr('أمر إنتاج جديد')),
      ),
      columns:  [
        PicPosTableColumn(tr('الأمر'), flex: 1.3),
        PicPosTableColumn(tr('قائمة المكونات'), flex: 1.4),
        PicPosTableColumn(tr('الكمية')),
        PicPosTableColumn(tr('الحالة')),
        PicPosTableColumn(tr('الإجراء'), flex: 1.5),
      ],
      rows: [
        for (final order in orders)
          PicPosTableRow(cells: [
            PicPosTextCell(order.orderNumber, bold: true),
            PicPosTextCell(bomNames[order.bomId] ?? '—'),
            PicPosTextCell('${order.orderedQty}'),
            PicPosPillCell(_statusLabel(order.status), _statusColor(order.status)),
            _actionCell(context, repository, order, runAction),
          ]),
      ],
    );
  }

  PicPosCell _actionCell(
    BuildContext context,
    ManufacturingRepository repository,
    ManufacturingOrderData order,
    Future<void> Function(Future<void> Function(), String) runAction,
  ) {
    if (order.status == 'draft') {
      return PicPosButtonCell(
        tr('بدء'),
        icon: PhosphorIconsBold.play,
        tint: Colors.blue,
        onPressed: () => runAction(
          () => repository.startProduction(order.id),
          tr('بدأ أمر الإنتاج وتم صرف الخامات'),
        ),
      );
    }
    if (order.status == 'in_progress') {
      return PicPosButtonCell(
        tr('إكمال'),
        icon: PhosphorIconsBold.check,
        tint: Colors.green,
        onPressed: () async {
          final quantity = await showActualQuantityDialog(context, order.orderedQty);
          if (quantity == null) return;
          await runAction(
            () => repository.completeProduction(order.id, actualProducedQty: quantity),
            tr('اكتمل أمر الإنتاج'),
          );
        },
      );
    }
    if (order.status == 'completed') {
      return PicPosButtonCell(
        tr('عكس'),
        icon: PhosphorIconsBold.arrowUUpLeft,
        tint: AppColors.error,
        onPressed: () async {
          final confirmed = await showPicPosConfirm(
            context,
            icon: PhosphorIconsBold.arrowUUpLeft,
            title: tr('عكس أمر الإنتاج'),
            message: tr('سيُعكس أثر المخزون والقيد المحاسبي للأمر {p0}.', {'p0': order.orderNumber}),
            danger: true,
            confirmLabel: tr('عكس الأمر'),
          );
          if (!confirmed) return;
          await runAction(
            () => repository.reverseManufacturingOrder(order.id),
            tr('تم عكس أمر الإنتاج'),
          );
        },
      );
    }
    return const PicPosTextCell('—');
  }
}

class ProductionOrderForm {
  const ProductionOrderForm({
    required this.bomId,
    required this.quantity,
    required this.warehouseId,
    this.notes,
  });

  final int bomId;
  final double quantity;
  final int warehouseId;
  final String? notes;
}

Future<ProductionOrderForm?> showProductionOrderDialog(
  BuildContext context, {
  required List<BillOfMaterialData> boms,
  required List<Warehouse> warehouses,
}) {
  return showDialog<ProductionOrderForm>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProductionOrderDialog(boms: boms, warehouses: warehouses),
  );
}

class _ProductionOrderDialog extends StatefulWidget {
  const _ProductionOrderDialog({required this.boms, required this.warehouses});
  final List<BillOfMaterialData> boms;
  final List<Warehouse> warehouses;

  @override
  State<_ProductionOrderDialog> createState() => _ProductionOrderDialogState();
}

class _ProductionOrderDialogState extends State<_ProductionOrderDialog> {
  final _quantity = TextEditingController(text: '1');
  final _notes = TextEditingController();
  int? _bomId;
  int? _warehouseId;

  @override
  void initState() {
    super.initState();
    _bomId = widget.boms.isEmpty ? null : widget.boms.first.id;
    _warehouseId = widget.warehouses.isEmpty ? null : widget.warehouses.first.id;
  }

  @override
  void dispose() {
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PicPosDialog(
        icon: PhosphorIconsBold.factory,
        title: tr('أمر إنتاج جديد'),
        subtitle: tr('اختر القائمة والكمية والمخزن قبل الترحيل'),
        body: [
          DropdownButtonFormField<int>(
            value: _bomId,
            decoration:  InputDecoration(labelText: tr('قائمة المكونات')),
            items: [
              for (final bom in widget.boms)
                DropdownMenuItem(value: bom.id, child: Text(bom.bomCode)),
            ],
            onChanged: (value) => setState(() => _bomId = value),
          ),
          TextField(
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:  InputDecoration(labelText: tr('الكمية المطلوبة')),
          ),
          DropdownButtonFormField<int>(
            value: _warehouseId,
            decoration:  InputDecoration(labelText: tr('المخزن')),
            items: [
              for (final warehouse in widget.warehouses)
                DropdownMenuItem(value: warehouse.id, child: Text(warehouse.name)),
            ],
            onChanged: (value) => setState(() => _warehouseId = value),
          ),
          TextField(controller: _notes, decoration:  InputDecoration(labelText: tr('ملاحظات (اختياري)'))),
        ],
        primaryAction: PicPosDialogAction(
          label: tr('إنشاء'),
          icon: PhosphorIconsBold.floppyDisk,
          onPressed: () {
            final quantity = double.tryParse(_quantity.text);
            if (_bomId == null || _warehouseId == null || quantity == null || quantity <= 0) return;
            Navigator.pop(
              context,
              ProductionOrderForm(
                bomId: _bomId!,
                quantity: quantity,
                warehouseId: _warehouseId!,
                notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              ),
            );
          },
        ),
        onCancel: () => Navigator.pop(context),
      );
}

Future<double?> showActualQuantityDialog(BuildContext context, double initial) {
  return showDialog<double>(
    context: context,
    builder: (_) => _ActualQuantityDialog(initial: initial),
  );
}

class _ActualQuantityDialog extends StatefulWidget {
  const _ActualQuantityDialog({required this.initial});
  final double initial;

  @override
  State<_ActualQuantityDialog> createState() => _ActualQuantityDialogState();
}

class _ActualQuantityDialogState extends State<_ActualQuantityDialog> {
  late final TextEditingController _quantity = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PicPosDialog(
        icon: PhosphorIconsBold.check,
        title: tr('إكمال أمر الإنتاج'),
        body: [
          TextField(
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:  InputDecoration(labelText: tr('الكمية الفعلية')),
          ),
        ],
        primaryAction: PicPosDialogAction(
          label: tr('إكمال'),
          icon: PhosphorIconsBold.check,
          onPressed: () {
            final value = double.tryParse(_quantity.text);
            if (value != null && value > 0) Navigator.pop(context, value);
          },
        ),
        onCancel: () => Navigator.pop(context),
      );
}

String _arabicError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '');
  return text.isEmpty ? tr('تعذر تنفيذ العملية') : text;
}

String _statusLabel(String status) => switch (status) {
      'draft' => tr('مسودة'),
      'in_progress' => tr('قيد التنفيذ'),
      'completed' => tr('مكتمل'),
      'reversed' => tr('معكوس'),
      'cancelled' => tr('ملغى'),
      _ => status,
    };

Color _statusColor(String status) => switch (status) {
      'completed' => Colors.green,
      'in_progress' => Colors.orange,
      'reversed' || 'cancelled' => AppColors.error,
      _ => Colors.blueGrey,
    };
