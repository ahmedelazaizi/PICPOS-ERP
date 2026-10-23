import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design_system/app_button.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/manufacturing_repository.dart';
import '../picpos_shell/picpos_data_table.dart';
import '../picpos_shell/picpos_dialog.dart';
import '../picpos_shell/picpos_page_header.dart';
import 'butchery_dialogs.dart';

class ButcheryTab extends ConsumerStatefulWidget {
  const ButcheryTab({super.key, required this.products, required this.warehouses});
  final List<ProductEntity> products;
  final List<Warehouse> warehouses;

  @override
  ConsumerState<ButcheryTab> createState() => _ButcheryTabState();
}

class _ButcheryTabState extends ConsumerState<ButcheryTab> {
  List<Map<String, dynamic>> _templates = const [];
  List<Map<String, dynamic>> _orders = const [];
  Map<int, List<Map<String, dynamic>>> _templateLines = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    final repository = ref.read(manufacturingRepositoryProvider);
    try {
      final templates = await repository.getButcheryTemplates();
      final orders = await repository.getButcheryOrders();
      final lines = <int, List<Map<String, dynamic>>>{};
      for (final template in templates) {
        final id = template['id'] as int;
        lines[id] = await repository.getButcheryTemplateLines(id);
      }
      if (mounted) setState(() {
        _templates = templates;
        _orders = orders;
        _templateLines = lines;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        _showError(error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.read(manufacturingRepositoryProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PicPosPageHeader(
        title: tr('التشفية'),
        subtitle: tr('قوالب القطع وأوامر الوزن والفاقد'),
        icon: PhosphorIconsBold.scissors,
        actions: [
          AppButton.secondary(
            onPressed: () async {
              final form = await showButcheryTemplateDialog(context, products: widget.products);
              if (form == null) return;
              try {
                final id = await repository.createButcheryTemplate(
                  carcassProductId: form.carcassProductId,
                  name: form.name,
                  valuationMethod: form.valuationMethod,
                  varianceThresholdPercent: form.varianceThresholdPercent,
                );
                for (final line in form.lines) {
                  await repository.addButcheryTemplateLine(
                    templateId: id,
                    outputProductId: line.productId,
                    expectedYieldPercent: line.expectedYieldPercent,
                    isByProduct: line.isByProduct,
                    valuationPrice: line.valuationPrice,
                  );
                }
                await _reload();
              } catch (error) {
                _showError(error);
              }
            },
            icon: const Icon(PhosphorIconsBold.listPlus),
            child:  Text(tr('قالب جديد')),
          ),
          AppButton.primary(
            onPressed: _templates.isEmpty || widget.warehouses.isEmpty
                ? null
                : () async {
                    final form = await showButcheryOrderDialog(
                      context,
                      templates: _templates,
                      templateLines: _templateLines,
                    );
                    if (form == null) return;
                    try {
                      final id = await repository.createButcheryOrder(
                        carcassProductId: form.carcassProductId,
                        warehouseId: widget.warehouses.first.id,
                        carcassQuantity: form.carcassQuantity,
                        carcassWeight: form.carcassWeight,
                        carcassTotalCost: form.carcassTotalCost,
                        templateId: form.templateId,
                        outputs: form.outputs,
                      );
                      await repository.postButcheryOrder(id);
                      await _reload();
                      if (mounted) _showSuccess(tr('تم إنشاء وترحيل أمر التشفية'));
                    } catch (error) {
                      _showError(error);
                    }
                  },
            icon: const Icon(PhosphorIconsBold.plus),
            child:  Text(tr('أمر تشفية جديد')),
          ),
        ],
      ),
      if (_loading)
        const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
      else ...[
        _templatesTable(),
        const SizedBox(height: 16),
        _ordersTable(repository),
      ],
      ]),
    );
  }

  Widget _templatesTable() => PicPosDataTable(
        title: tr('قوالب التشفية'),
        subtitle: tr('طريقة التقييم وحدود variance والقطع المتوقعة'),
        columns:  [
          PicPosTableColumn(tr('القالب'), flex: 2),
          PicPosTableColumn(tr('الذبيحة'), flex: 1.5),
          PicPosTableColumn(tr('التقييم')),
          PicPosTableColumn(tr('الحد %')),
          PicPosTableColumn(tr('القطع')),
        ],
        rows: [
          for (final template in _templates)
            PicPosTableRow(cells: [
              PicPosTextCell('${template['name']}', bold: true),
              PicPosTextCell('${template['carcass_name'] ?? '—'}'),
              PicPosPillCell(template['valuation_method'] == 'by_weight' ? tr('بالوزن') : tr('قيمة البيع'), Colors.blue),
              PicPosTextCell(_number(template['variance_threshold_percent']).toStringAsFixed(1)),
              PicPosTextCell('${_templateLines[template['id']]?.length ?? 0}'),
            ]),
        ],
      );

  Widget _ordersTable(ManufacturingRepository repository) => PicPosDataTable(
        title: tr('أوامر التشفية'),
        subtitle: tr('الوزن الفعلي والتكلفة والفاقد'),
        headerAction: Text(tr('{p0} أمر', {'p0': _orders.length})),
        columns:  [
          PicPosTableColumn(tr('الأمر'), flex: 1.3),
          PicPosTableColumn(tr('الذبيحة'), flex: 1.4),
          PicPosTableColumn(tr('الحالة')),
          PicPosTableColumn(tr('الفاقد'), align: PicPosCellAlign.end),
          PicPosTableColumn(tr('إجراء')),
        ],
        rows: [
          for (final order in _orders)
            PicPosTableRow(cells: [
              PicPosTextCell('${order['order_number']}', bold: true),
              PicPosTextCell('${order['carcass_name'] ?? '—'}'),
              PicPosPillCell(_orderStatus('${order['status']}'), _orderStatusColor('${order['status']}')),
              PicPosTextCell('${_number(order['loss_percent']).toStringAsFixed(2)}%'),
              order['status'] == 'posted'
                  ? PicPosButtonCell(
                      tr('عكس'),
                      icon: PhosphorIconsBold.arrowUUpLeft,
                      tint: AppColors.error,
                      onPressed: () async {
                        final confirmed = await showPicPosConfirm(
                          context,
                          icon: PhosphorIconsBold.arrowUUpLeft,
                          title: tr('عكس أمر التشفية'),
                          message: tr('سيُعاد المخزون ويُعكس القيد المحاسبي.'),
                          danger: true,
                          confirmLabel: tr('عكس الأمر'),
                        );
                        if (!confirmed) return;
                        try {
                          await repository.reverseButcheryOrder(order['id'] as int);
                          await _reload();
                        } catch (error) {
                          _showError(error);
                        }
                      },
                    )
                  : const PicPosTextCell('—'),
            ]),
        ],
      );

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorText(error)), backgroundColor: AppColors.error));
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

String _orderStatus(String value) => switch (value) {
      'draft' => tr('مسودة'),
      'posted' => tr('مُرحّل'),
      'reversed' => tr('معكوس'),
      _ => value,
    };

Color _orderStatusColor(String value) => switch (value) {
      'posted' => Colors.green,
      'reversed' => AppColors.error,
      _ => Colors.orange,
    };

String _errorText(Object error) => error.toString().replaceFirst('Exception: ', '');
double _number(Object? value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
