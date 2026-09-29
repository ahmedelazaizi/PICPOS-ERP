import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/entities/product_entity.dart';
import '../picpos_shell/picpos_dialog.dart';

class ButcheryTemplateLineForm {
  const ButcheryTemplateLineForm({
    required this.productId,
    required this.expectedYieldPercent,
    required this.isByProduct,
    required this.valuationPrice,
  });

  final int productId;
  final double expectedYieldPercent;
  final bool isByProduct;
  final double valuationPrice;
}

class ButcheryTemplateForm {
  const ButcheryTemplateForm({
    required this.carcassProductId,
    required this.name,
    required this.valuationMethod,
    required this.varianceThresholdPercent,
    required this.lines,
  });

  final int carcassProductId;
  final String name;
  final String valuationMethod;
  final double varianceThresholdPercent;
  final List<ButcheryTemplateLineForm> lines;
}

Future<ButcheryTemplateForm?> showButcheryTemplateDialog(
  BuildContext context, {
  required List<ProductEntity> products,
}) {
  return showDialog<ButcheryTemplateForm>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ButcheryTemplateDialog(products: products),
  );
}

class _TemplateLineDraft {
  _TemplateLineDraft()
      : expected = TextEditingController(text: '0'),
        price = TextEditingController(text: '0');

  int? productId;
  final TextEditingController expected;
  final TextEditingController price;
  bool byProduct = false;

  void dispose() {
    expected.dispose();
    price.dispose();
  }
}

class _ButcheryTemplateDialog extends StatefulWidget {
  const _ButcheryTemplateDialog({required this.products});
  final List<ProductEntity> products;

  @override
  State<_ButcheryTemplateDialog> createState() => _ButcheryTemplateDialogState();
}

class _ButcheryTemplateDialogState extends State<_ButcheryTemplateDialog> {
  final _name = TextEditingController();
  final _threshold = TextEditingController(text: '2');
  late final List<_TemplateLineDraft> _lines = [_TemplateLineDraft()];
  int? _carcassProductId;
  String _valuationMethod = 'sales_value';

  @override
  void dispose() {
    _name.dispose();
    _threshold.dispose();
    for (final line in _lines) line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PicPosDialog(
        icon: PhosphorIconsBold.scissors,
        title: 'قالب تشفية جديد',
        subtitle: 'حدد الذبيحة وطريقة توزيع التكلفة والقطع المتوقعة',
        width: 900,
        body: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم القالب')),
          DropdownButtonFormField<int>(
            value: _carcassProductId,
            decoration: const InputDecoration(labelText: 'منتج الذبيحة'),
            items: [
              for (final product in widget.products)
                DropdownMenuItem(value: product.id, child: Text(product.name)),
            ],
            onChanged: (value) => setState(() => _carcassProductId = value),
          ),
          DropdownButtonFormField<String>(
            value: _valuationMethod,
            decoration: const InputDecoration(labelText: 'طريقة توزيع التكلفة'),
            items: const [
              DropdownMenuItem(value: 'sales_value', child: Text('قيمة البيع')),
              DropdownMenuItem(value: 'by_weight', child: Text('بالوزن')),
            ],
            onChanged: (value) => setState(() => _valuationMethod = value ?? 'sales_value'),
          ),
          TextField(
            controller: _threshold,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'حد variance %'),
          ),
          const Text('القطع ومعدلات العائد', style: TextStyle(fontWeight: FontWeight.w800)),
          for (var i = 0; i < _lines.length; i++) _lineEditor(i),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _lines.add(_TemplateLineDraft())),
              icon: const Icon(PhosphorIconsBold.plus),
              label: const Text('إضافة قطعة'),
            ),
          ),
        ],
        primaryAction: PicPosDialogAction(
          label: 'حفظ القالب',
          icon: PhosphorIconsBold.floppyDisk,
          onPressed: _save,
        ),
        onCancel: () => Navigator.pop(context),
      );

  Widget _lineEditor(int index) {
    final line = _lines[index];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                value: line.productId,
                decoration: const InputDecoration(labelText: 'القطعة'),
                items: [
                  for (final product in widget.products)
                    DropdownMenuItem(value: product.id, child: Text(product.name)),
                ],
                onChanged: (value) => setState(() => line.productId = value),
              ),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: line.expected,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'العائد %'),
              ),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: line.price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'سعر التقييم'),
              ),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(value: line.byProduct, onChanged: (value) => setState(() => line.byProduct = value ?? false)),
              const Text('ثانوي'),
              IconButton(
                tooltip: 'حذف القطعة',
                onPressed: _lines.length == 1 ? null : () => setState(() {
                  final removed = _lines.removeAt(index);
                  removed.dispose();
                }),
                icon: const Icon(PhosphorIconsBold.trash),
                color: AppColors.error,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _save() {
    final lines = <ButcheryTemplateLineForm>[];
    for (final line in _lines) {
      final expected = double.tryParse(line.expected.text) ?? 0;
      if (line.productId == null || expected <= 0) return;
      lines.add(ButcheryTemplateLineForm(
        productId: line.productId!,
        expectedYieldPercent: expected,
        isByProduct: line.byProduct,
        valuationPrice: double.tryParse(line.price.text) ?? 0,
      ));
    }
    final threshold = double.tryParse(_threshold.text) ?? 2;
    if (_carcassProductId == null || _name.text.trim().isEmpty || lines.isEmpty || threshold < 0) return;
    Navigator.pop(
      context,
      ButcheryTemplateForm(
        carcassProductId: _carcassProductId!,
        name: _name.text.trim(),
        valuationMethod: _valuationMethod,
        varianceThresholdPercent: threshold,
        lines: lines,
      ),
    );
  }
}

class ButcheryOrderForm {
  const ButcheryOrderForm({
    required this.templateId,
    required this.carcassProductId,
    required this.carcassQuantity,
    required this.carcassWeight,
    required this.carcassTotalCost,
    required this.outputs,
  });

  final int templateId;
  final int carcassProductId;
  final double carcassQuantity;
  final double carcassWeight;
  final double carcassTotalCost;
  final List<Map<String, dynamic>> outputs;
}

Future<ButcheryOrderForm?> showButcheryOrderDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> templates,
  required Map<int, List<Map<String, dynamic>>> templateLines,
}) {
  return showDialog<ButcheryOrderForm>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ButcheryOrderDialog(
      templates: templates,
      templateLines: templateLines,
      
    ),
  );
}

class _ButcheryOrderDialog extends StatefulWidget {
  const _ButcheryOrderDialog({required this.templates, required this.templateLines});
  final List<Map<String, dynamic>> templates;
  final Map<int, List<Map<String, dynamic>>> templateLines;

  @override
  State<_ButcheryOrderDialog> createState() => _ButcheryOrderDialogState();
}

class _ButcheryOrderDialogState extends State<_ButcheryOrderDialog> {
  final _quantity = TextEditingController(text: '1');
  final _weight = TextEditingController(text: '1000');
  final _cost = TextEditingController(text: '0');
  int? _templateId;
  late List<TextEditingController> _actualWeights;

  @override
  void initState() {
    super.initState();
    _templateId = widget.templates.isEmpty ? null : widget.templates.first['id'] as int;
    _actualWeights = _controllersFor(_lines);
  }

  List<Map<String, dynamic>> get _lines => widget.templateLines[_templateId] ?? const [];

  List<TextEditingController> _controllersFor(List<Map<String, dynamic>> lines) => [
        for (final line in lines)
          TextEditingController(
            text: (_number(_weight.text) * _number(line['expected_yield_percent']) / 100).toStringAsFixed(2),
          ),
      ];

  @override
  void dispose() {
    _quantity.dispose();
    _weight.dispose();
    _cost.dispose();
    for (final controller in _actualWeights) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputWeight = _number(_weight.text);
    final outputsWeight = _actualWeights.fold<double>(0, (sum, controller) => sum + _number(controller.text));
    final loss = (inputWeight - outputsWeight).clamp(0, double.infinity).toDouble();
    final lossPercent = inputWeight <= 0 ? 0.0 : loss * 100 / inputWeight;
    final previewRows = _previewRows(inputWeight, outputsWeight);
    return PicPosDialog(
      icon: PhosphorIconsBold.scissors,
      title: 'أمر تشفية جديد',
      subtitle: 'راجع الأوزان والتكلفة قبل الإنشاء والترحيل',
      width: 980,
      body: [
        DropdownButtonFormField<int>(
          value: _templateId,
          decoration: const InputDecoration(labelText: 'قالب التشفية'),
          items: [
            for (final template in widget.templates)
              DropdownMenuItem(value: template['id'] as int, child: Text('${template['name']}')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _templateId = value;
              for (final controller in _actualWeights) controller.dispose();
              _actualWeights = _controllersFor(_lines);
            });
          },
        ),
        Row(children: [
          Expanded(child: TextField(controller: _quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'كمية الذبيحة'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'وزن الذبيحة بالجرام'), onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'التكلفة الكلية'))),
        ]),
        const Text('الأوزان الفعلية للقطع', style: TextStyle(fontWeight: FontWeight.w800)),
        for (var i = 0; i < _lines.length; i++) _weightLine(i),
        _preview(previewRows, loss, lossPercent),
      ],
      primaryAction: PicPosDialogAction(
        label: 'حفظ وترحيل',
        icon: PhosphorIconsBold.check,
        onPressed: () => _save(inputWeight),
      ),
      onCancel: () => Navigator.pop(context),
    );
  }

  Widget _weightLine(int index) {
    final line = _lines[index];
    return Row(children: [
      Expanded(child: Text('${line['output_name'] ?? 'قطعة'} (متوقع ${_number(line['expected_yield_percent']).toStringAsFixed(1)}%)')),
      SizedBox(
        width: 170,
        child: TextField(
          controller: _actualWeights[index],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'الوزن الفعلي'),
          onChanged: (_) => setState(() {}),
        ),
      ),
    ]);
  }

  Widget _preview(List<Map<String, dynamic>> rows, double loss, double lossPercent) => Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('المعاينة الحية', style: TextStyle(fontWeight: FontWeight.w800)),
            for (final row in rows)
              Text('${row['name']}: تكلفة الوحدة ${_number(row['unitCost']).toStringAsFixed(2)} — قيمة ثانوية ${_number(row['byProductValue']).toStringAsFixed(2)}'),
            Text('الفاقد: ${loss.toStringAsFixed(2)} جم (${lossPercent.toStringAsFixed(2)}%)'),
            Text(lossPercent > 2 ? 'راية variance: تجاوز الحد' : 'راية variance: ضمن الحد', style: TextStyle(color: lossPercent > 2 ? AppColors.error : Colors.green)),
          ]),
        ),
      );

  List<Map<String, dynamic>> _previewRows(double inputWeight, double outputWeight) {
    final template = widget.templates.firstWhere((row) => row['id'] == _templateId, orElse: () => const {});
    final method = template['valuation_method']?.toString() ?? 'sales_value';
    final cost = _number(_cost.text);
    final loss = inputWeight <= 0 ? 0 : (inputWeight - outputWeight).clamp(0, double.infinity).toDouble();
    final allocatable = inputWeight <= 0 ? 0 : cost * (1 - loss / inputWeight);
    final mainWeight = _lines.where((line) => !_isTrue(line['is_by_product'])).fold<double>(0, (sum, line) {
      final index = _lines.indexOf(line);
      return sum + (index >= 0 ? _number(_actualWeights[index].text) : 0);
    });
    final mainValue = _lines.where((line) => !_isTrue(line['is_by_product'])).fold<double>(0, (sum, line) {
      final index = _lines.indexOf(line);
      return sum + (index >= 0 ? _number(_actualWeights[index].text) * _number(line['valuation_price']) : 0);
    });
    return [
      for (var i = 0; i < _lines.length; i++)
        () {
          final line = _lines[i];
          final weight = _number(_actualWeights[i].text);
          final byProduct = _isTrue(line['is_by_product']);
          final value = weight * _number(line['valuation_price']);
          final allocation = byProduct
              ? (method == 'sales_value' ? value : 0)
              : method == 'by_weight'
                  ? (mainWeight <= 0 ? 0 : allocatable * weight / mainWeight)
                  : (mainValue <= 0 ? 0 : (allocatable - _byProductValue()) * value / mainValue);
          return {'name': line['output_name'], 'unitCost': weight <= 0 ? 0 : allocation / weight, 'byProductValue': byProduct ? value : 0};
        }(),
    ];
  }

  double _byProductValue() => _lines.asMap().entries.fold(0, (sum, entry) {
        final line = entry.value;
        return sum + (_isTrue(line['is_by_product']) ? _number(_actualWeights[entry.key].text) * _number(line['valuation_price']) : 0);
      });

  void _save(double inputWeight) {
    final quantity = _number(_quantity.text);
    final cost = _number(_cost.text);
    if (_templateId == null || quantity <= 0 || inputWeight <= 0 || cost < 0 || _lines.isEmpty) return;
    Navigator.pop(
      context,
      ButcheryOrderForm(
        templateId: _templateId!,
        carcassProductId: widget.templates.firstWhere((row) => row['id'] == _templateId)['carcass_product_id'] as int,
        carcassQuantity: quantity,
        carcassWeight: inputWeight,
        carcassTotalCost: cost,
        outputs: [
          for (var i = 0; i < _lines.length; i++) {
            'outputProductId': _lines[i]['output_product_id'],
            'actualWeight': _number(_actualWeights[i].text),
            'isByProduct': _isTrue(_lines[i]['is_by_product']),
            'salePrice': _number(_lines[i]['valuation_price']),
          },
        ],
      ),
    );
  }
}

double _number(Object? value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
bool _isTrue(Object? value) => value == true || value == 1 || value == '1';
