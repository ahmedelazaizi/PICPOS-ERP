import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design_system/app_button.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/manufacturing_providers.dart';
import '../../data/providers/providers.dart';
import '../picpos_shell/picpos_data_table.dart';
import '../picpos_shell/picpos_dialog.dart';
import '../picpos_shell/picpos_page_header.dart';

class AdditionalCostsTab extends ConsumerWidget {
  const AdditionalCostsTab({super.key, required this.orders});
  final List<ManufacturingOrderData> orders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costs = ref.watch(allMfgOrderCostsProvider).value ?? const <MfgOrderCostData>[];
    final orderNames = {for (final order in orders) order.id: order.orderNumber};
    final repository = ref.read(manufacturingRepositoryProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PicPosPageHeader(
        title: tr('التكاليف الإضافية'),
        subtitle: tr('تكاليف مرتبطة بأوامر الإنتاج والتوزيع الشهري'),
        icon: PhosphorIconsBold.coins,
        actions: [
          AppButton.secondary(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final form = await showMfgCostDialog(context, orders: orders);
              if (form == null || !context.mounted) return;
              try {
                await repository.addMfgOrderCost(
                  orderId: form.orderId,
                  costType: form.costType,
                  description: form.description,
                  amount: form.amount,
                );
                messenger.showSnackBar( SnackBar(content: Text(tr('تمت إضافة التكلفة'))));
              } catch (error) {
                _showError(messenger, error);
              }
            },
            icon: const Icon(PhosphorIconsBold.plus),
            child:  Text(tr('إضافة تكلفة')),
          ),
          AppButton.primary(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final confirmed = await showPicPosConfirm(
                context,
                icon: PhosphorIconsBold.arrowsClockwise,
                title: tr('توزيع التكاليف الشهرية'),
                message: tr('سيتم تحميل المصروفات الإنتاجية غير الموزعة على أوامر هذا الشهر.'),
                confirmLabel: tr('تشغيل التوزيع'),
              );
              if (!confirmed || !context.mounted) return;
              try {
                await repository.allocateMonthlyExpenses(month: DateTime.now());
                messenger.showSnackBar( SnackBar(content: Text(tr('تم تشغيل التوزيع الشهري'))));
              } catch (error) {
                _showError(messenger, error);
              }
            },
            icon: const Icon(PhosphorIconsBold.arrowsClockwise),
            child:  Text(tr('توزيع الشهر')),
          ),
        ],
      ),
      PicPosDataTable(
        title: tr('التكاليف المرتبطة'),
        subtitle: tr('كل سطر مرتبط بأمر إنتاج ولا يُحذف بعد الترحيل'),
        columns:  [
          PicPosTableColumn(tr('أمر الإنتاج')),
          PicPosTableColumn(tr('النوع')),
          PicPosTableColumn(tr('الوصف'), flex: 2),
          PicPosTableColumn(tr('المبلغ'), align: PicPosCellAlign.end),
        ],
        rows: [
          for (final cost in costs)
            PicPosTableRow(cells: [
              PicPosTextCell(orderNames[cost.orderId] ?? '#${cost.orderId}', bold: true),
              PicPosTextCell(cost.costType),
              PicPosTextCell(cost.description),
              PicPosTextCell(cost.amount.toStringAsFixed(2), bold: true),
            ]),
        ],
      ),
    ]);
  }
}

class MfgCostForm {
  const MfgCostForm({required this.orderId, required this.costType, required this.description, required this.amount});
  final int orderId;
  final String costType;
  final String description;
  final double amount;
}

Future<MfgCostForm?> showMfgCostDialog(BuildContext context, {required List<ManufacturingOrderData> orders}) => showDialog<MfgCostForm>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MfgCostDialog(orders: orders),
    );

class _MfgCostDialog extends StatefulWidget {
  const _MfgCostDialog({required this.orders});
  final List<ManufacturingOrderData> orders;

  @override
  State<_MfgCostDialog> createState() => _MfgCostDialogState();
}

class _MfgCostDialogState extends State<_MfgCostDialog> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  int? _orderId;
  String _costType = 'overhead';

  @override
  void initState() {
    super.initState();
    _orderId = widget.orders.isEmpty ? null : widget.orders.first.id;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PicPosDialog(
        icon: PhosphorIconsBold.coins,
        title: tr('إضافة تكلفة إنتاج'),
        body: [
          DropdownButtonFormField<int>(
            value: _orderId,
            decoration:  InputDecoration(labelText: tr('أمر الإنتاج')),
            items: [for (final order in widget.orders) DropdownMenuItem(value: order.id, child: Text(order.orderNumber))],
            onChanged: (value) => setState(() => _orderId = value),
          ),
          DropdownButtonFormField<String>(
            value: _costType,
            decoration:  InputDecoration(labelText: tr('نوع التكلفة')),
            items:  [
              DropdownMenuItem(value: 'overhead', child: Text(tr('تحميل'))), DropdownMenuItem(value: 'labor', child: Text(tr('عمالة'))), DropdownMenuItem(value: 'other', child: Text(tr('أخرى'))),
            ],
            onChanged: (value) => setState(() => _costType = value ?? 'overhead'),
          ),
          TextField(controller: _description, decoration:  InputDecoration(labelText: tr('الوصف'))),
          TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration:  InputDecoration(labelText: tr('المبلغ'))),
        ],
        primaryAction: PicPosDialogAction(
          label: tr('إضافة'),
          icon: PhosphorIconsBold.floppyDisk,
          onPressed: () {
            final amount = double.tryParse(_amount.text);
            if (_orderId == null || _description.text.trim().isEmpty || amount == null || amount <= 0) return;
            Navigator.pop(context, MfgCostForm(orderId: _orderId!, costType: _costType, description: _description.text.trim(), amount: amount));
          },
        ),
        onCancel: () => Navigator.pop(context),
      );
}

void _showError(ScaffoldMessengerState messenger, Object error) {
  messenger.showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')), backgroundColor: AppColors.error));
}
