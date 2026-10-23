import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/providers/providers.dart';
import '../../domain/entities/product_entity.dart';
import '../picpos_shell/picpos_dialog.dart';

class BomEditorDialog extends ConsumerStatefulWidget {
  const BomEditorDialog({super.key, required this.products, this.bomId});
  final List<ProductEntity> products;
  final int? bomId;

  @override
  ConsumerState<BomEditorDialog> createState() => _BomEditorDialogState();
}

class _BomEditorDialogState extends ConsumerState<BomEditorDialog> {
  final _code = TextEditingController();
  final _expected = TextEditingController(text: '1');
  final _overhead = TextEditingController(text: '0');
  final _profit = TextEditingController(text: '0');
  final _pieceWeight = TextEditingController();
  final _componentQuantity = TextEditingController(text: '1');
  final _componentBaseFactor = TextEditingController(text: '1');
  int? _finishedProduct;
  int? _rawMaterial;
  String _componentUnit = tr('قطعة');
  String _basis = 'after_overhead';
  BomCostPreview? _preview;

  @override
  void initState() {
    super.initState();
    if (widget.bomId != null) Future.microtask(_loadExistingBom);
  }

  @override
  void dispose() {
    for (final controller in [_code, _expected, _overhead, _profit, _pieceWeight, _componentQuantity, _componentBaseFactor]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PicPosDialog(
        icon: PhosphorIconsBold.listDashes,
        title: widget.bomId == null ? tr('قائمة مكوّنات جديدة') : tr('تحرير قائمة المكوّنات'),
        subtitle: tr('التكلفة والتحميل والهامش والوزن والقطع'),
        body: [
          TextField(controller: _code, decoration:  InputDecoration(labelText: tr('كود القائمة'))),
          DropdownButtonFormField<int>(
            value: _finishedProduct,
            decoration:  InputDecoration(labelText: tr('المنتج التام')),
            items: [for (final p in widget.products) DropdownMenuItem(value: p.id, child: Text(p.name))],
            onChanged: (value) => setState(() => _finishedProduct = value),
          ),
          TextField(controller: _expected, decoration:  InputDecoration(labelText: tr('كمية الناتج المتوقعة'))),
          DropdownButtonFormField<int>(
            value: _rawMaterial,
            decoration:  InputDecoration(labelText: tr('الخامة الأولى')),
            items: [for (final p in widget.products.where((p) => p.id != _finishedProduct)) DropdownMenuItem(value: p.id, child: Text(p.name))],
            onChanged: (value) => setState(() => _rawMaterial = value),
          ),
          Row(children: [
            Expanded(child: TextField(controller: _componentQuantity, decoration:  InputDecoration(labelText: tr('كمية الخامة')))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _componentBaseFactor, decoration:  InputDecoration(labelText: tr('معامل التحويل')))),
          ]),
          DropdownButtonFormField<String>(
            value: _componentUnit,
            decoration:  InputDecoration(labelText: tr('وحدة الخامة')),
            items:  [
              DropdownMenuItem(value: tr('جرام'), child: Text(tr('جرام'))),
              DropdownMenuItem(value: tr('كجم'), child: Text(tr('كجم'))),
              DropdownMenuItem(value: tr('قطعة'), child: Text(tr('قطعة'))),
            ],
            onChanged: (value) => setState(() => _componentUnit = value ?? tr('قطعة')),
          ),
          TextField(controller: _overhead, decoration:  InputDecoration(labelText: tr('التحميل %'))),
          TextField(controller: _profit, decoration:  InputDecoration(labelText: tr('الربح %'))),
          DropdownButtonFormField<String>(
            value: _basis,
            decoration:  InputDecoration(labelText: tr('أساس الربح')),
            items:  [
              DropdownMenuItem(value: 'after_overhead', child: Text(tr('بعد التحميل'))),
              DropdownMenuItem(value: 'materials_only', child: Text(tr('المواد فقط'))),
            ],
            onChanged: (value) => setState(() => _basis = value ?? 'after_overhead'),
          ),
          TextField(controller: _pieceWeight, decoration:  InputDecoration(labelText: tr('وزن القطعة بالجرام (اختياري)'))),
           Text(tr('معاينة التكلفة: المواد + مبلغ التحميل = الإجمالي'), style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(tr('السعر المقترح: {p0}', {'p0': _preview?.suggestedSellingPrice.toStringAsFixed(2) ?? '—'})),
          Text(tr('عدد القطع: {p0}', {'p0': _preview?.pieces?.toString() ?? '—'})),
        ],
        primaryAction: PicPosDialogAction(label: tr('حفظ'), icon: PhosphorIconsBold.floppyDisk, onPressed: _save),
        secondaryActions: [PicPosDialogAction(label: tr('تطبيق كسعر بيع'), icon: PhosphorIconsBold.tag, onPressed: _applySalePrice)],
        onCancel: () => Navigator.pop(context),
      );

  Future<void> _loadExistingBom() async {
    final database = ref.read(databaseProvider);
    final bom = await database.getBOM(widget.bomId!);
    final components = await database.getBOMComponents(widget.bomId!);
    if (!mounted || bom == null || components.isEmpty) return;
    final component = components.first;
    setState(() {
      _code.text = bom.bomCode;
      _expected.text = '${bom.expectedQuantity}';
      _finishedProduct = bom.finishedProductId;
      _rawMaterial = component.rawMaterialId;
      _componentQuantity.text = '${component.quantity}';
      _componentBaseFactor.text = '${component.quantityInBase}';
      _componentUnit = component.unit;
    });
    _preview = await database.getBomCostPreview(widget.bomId!);
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final quantity = double.tryParse(_componentQuantity.text) ?? 0;
    if (_finishedProduct == null || _rawMaterial == null || quantity <= 0 || _code.text.trim().isEmpty) return;
    final components = [
      {
        'rawMaterialId': _rawMaterial!,
        'quantity': quantity,
        'quantityInBase': double.tryParse(_componentBaseFactor.text) ?? 1,
        'unit': _componentUnit,
      },
    ];
    final repository = ref.read(manufacturingRepositoryProvider);
    final args = (
      finishedProductId: _finishedProduct!,
      bomCode: _code.text.trim(),
      expectedQuantity: double.tryParse(_expected.text) ?? 1,
      overheadPercent: double.tryParse(_overhead.text) ?? 0,
      profitPercent: double.tryParse(_profit.text) ?? 0,
      pieceWeight: double.tryParse(_pieceWeight.text),
    );
    if (widget.bomId == null) {
      await repository.createBOM(
        finishedProductId: args.finishedProductId,
        bomCode: args.bomCode,
        expectedQuantity: args.expectedQuantity,
        components: components,
        overheadPercent: args.overheadPercent,
        profitPercent: args.profitPercent,
        profitBasis: _basis,
        pieceWeight: args.pieceWeight,
      );
    } else {
      await repository.updateBOM(
        bomId: widget.bomId!,
        finishedProductId: args.finishedProductId,
        bomCode: args.bomCode,
        expectedQuantity: args.expectedQuantity,
        components: components,
        overheadPercent: args.overheadPercent,
        profitPercent: args.profitPercent,
        profitBasis: _basis,
        pieceWeight: args.pieceWeight,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _applySalePrice() async {
    if (widget.bomId == null) return;
    final confirmed = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.tag,
      title: tr('تطبيق كسعر بيع'),
      message: tr('سيُستبدل سعر بيع المنتج التام بالسعر المقترح.'),
      confirmLabel: tr('تأكيد'),
    );
    if (confirmed) await ref.read(databaseProvider).applyBomSuggestedSalePrice(widget.bomId!);
  }
}
