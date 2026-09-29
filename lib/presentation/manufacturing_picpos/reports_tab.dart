import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design_system/app_button.dart';
import '../../data/providers/providers.dart';
import '../../domain/entities/product_entity.dart';
import '../picpos_shell/picpos_data_table.dart';
import '../picpos_shell/picpos_page_header.dart';

class ManufacturingReportsTab extends ConsumerStatefulWidget {
  const ManufacturingReportsTab({super.key, required this.boms, required this.products});
  final List<BillOfMaterialData> boms;
  final List<ProductEntity> products;

  @override
  ConsumerState<ManufacturingReportsTab> createState() => _ManufacturingReportsTabState();
}

class _ManufacturingReportsTabState extends ConsumerState<ManufacturingReportsTab> {
  late DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  late DateTime _to = DateTime.now().add(const Duration(days: 1));
  List<Map<String, dynamic>> _yieldRows = const [];
  Map<int, BomCostPreview> _bomPreviews = const {};
  String? _errorMessage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    final repository = ref.read(manufacturingRepositoryProvider);
    try {
      final yieldRows = await repository.getButcheryYieldReport(from: _from, to: _to);
      final previews = <int, BomCostPreview>{};
      for (final bom in widget.boms) {
        previews[bom.id] = await repository.getBomCostPreview(bom.id);
      }
      if (mounted) setState(() {
        _yieldRows = yieldRows;
        _bomPreviews = previews;
        _errorMessage = null;
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PicPosPageHeader(
          title: 'تقارير التصنيع',
          subtitle: 'العائد الفعلي وتكلفة قوائم المكونات',
          icon: PhosphorIconsBold.chartLine,
          actions: [
            TextButton.icon(onPressed: () => _pickDate(true), icon: const Icon(PhosphorIconsBold.calendar), label: Text('من ${_shortDate(_from)}')),
            TextButton.icon(onPressed: () => _pickDate(false), icon: const Icon(PhosphorIconsBold.calendar), label: Text('إلى ${_shortDate(_to)}')),
            AppButton.primary(onPressed: _reload, icon: const Icon(PhosphorIconsBold.arrowsClockwise), child: const Text('تحديث التقرير')),
          ],
        ),
        if (_loading)
          const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
        else if (_errorMessage != null)
          Padding(padding: const EdgeInsets.all(24), child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
        else ...[
          _yieldTable(),
          const SizedBox(height: 16),
          _bomTable(),
        ],
      ]),
      );

  Widget _yieldTable() => PicPosDataTable(
        title: 'تقرير عائد التشفية',
        subtitle: 'الفترة ${_shortDate(_from)} — ${_shortDate(_to)}، وإجمالي الفاقد في الفترة',
        columns: const [
          PicPosTableColumn('القطعة', flex: 2),
          PicPosTableColumn('متوقع %'),
          PicPosTableColumn('فعلي %'),
          PicPosTableColumn('variance %'),
          PicPosTableColumn('الكمية'),
          PicPosTableColumn('إجمالي الفاقد', align: PicPosCellAlign.end),
        ],
        rows: [
          for (final row in _yieldRows)
            PicPosTableRow(cells: [
              PicPosTextCell('${row['product_name']}', bold: true),
              PicPosTextCell(_number(row['expected_yield_percent']).toStringAsFixed(2)),
              PicPosTextCell(_number(row['actual_yield_percent']).toStringAsFixed(2)),
              PicPosTextCell(_number(row['variance_percent']).toStringAsFixed(2), tint: _number(row['variance_percent']).abs() > 2 ? Colors.red : Colors.green),
              PicPosTextCell(_number(row['actual_weight']).toStringAsFixed(2)),
              PicPosTextCell(_number(row['total_loss_weight']).toStringAsFixed(2), bold: true),
            ]),
        ],
      );

  Widget _bomTable() {
    final names = {for (final product in widget.products) product.id: product.name};
    return PicPosDataTable(
      title: 'ورقة تكلفة BOM',
      subtitle: 'مواد، تحميل، إجمالي، سعر مقترح وعدد القطع',
      columns: const [
        PicPosTableColumn('المنتج التام', flex: 2),
        PicPosTableColumn('المواد', align: PicPosCellAlign.end),
        PicPosTableColumn('التحميل', align: PicPosCellAlign.end),
        PicPosTableColumn('الإجمالي', align: PicPosCellAlign.end),
        PicPosTableColumn('السعر المقترح', align: PicPosCellAlign.end),
        PicPosTableColumn('القطع', align: PicPosCellAlign.end),
      ],
      rows: [
        for (final bom in widget.boms)
          if (_bomPreviews[bom.id] != null)
            PicPosTableRow(cells: [
              PicPosTextCell(names[bom.finishedProductId] ?? bom.bomCode, bold: true),
              PicPosTextCell(_bomPreviews[bom.id]!.materialsCost.toStringAsFixed(2)),
              PicPosTextCell(_bomPreviews[bom.id]!.overheadAmount.toStringAsFixed(2)),
              PicPosTextCell(_bomPreviews[bom.id]!.totalCost.toStringAsFixed(2), bold: true),
              PicPosTextCell(_bomPreviews[bom.id]!.suggestedSellingPrice.toStringAsFixed(2)),
              PicPosTextCell('${_bomPreviews[bom.id]!.pieces ?? '—'}'),
            ]),
      ],
    );
  }

  Future<void> _pickDate(bool from) async {
    final initial = from ? _from : _to;
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked.add(const Duration(days: 1));
      }
    });
    await _reload();
  }
}

String _shortDate(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
double _number(Object? value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
