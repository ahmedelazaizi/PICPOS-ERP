import 'package:flutter/material.dart';
import '../../core/i18n/tr.dart';

class PrinterPaperWidthFields extends StatefulWidget {
  const PrinterPaperWidthFields({
    super.key,
    required this.paperWidthMm,
    required this.onChanged,
  });
  final double paperWidthMm;
  final ValueChanged<double> onChanged;

  @override
  State<PrinterPaperWidthFields> createState() =>
      _PrinterPaperWidthFieldsState();
}

class _PrinterPaperWidthFieldsState extends State<PrinterPaperWidthFields> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(
      text: widget.paperWidthMm.toStringAsFixed(0),
    );
  }

  @override
  void didUpdateWidget(covariant PrinterPaperWidthFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paperWidthMm != widget.paperWidthMm &&
        double.tryParse(controller.text) != widget.paperWidthMm) {
      controller.text = widget.paperWidthMm.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      DropdownButtonFormField<double>(
        initialValue:
            const [58.0, 80.0, 148.0, 210.0].contains(widget.paperWidthMm)
            ? widget.paperWidthMm
            : 80.0,
        decoration: InputDecoration(labelText: tr('المقاس المعتمد')),
        items: [
          for (final width in const [58.0, 80.0, 148.0, 210.0])
            DropdownMenuItem(
              value: width,
              child: Text(
                width == 210
                    ? 'A4 · 210 mm'
                    : width == 148
                    ? 'A5 · 148 mm'
                    : '${width.toStringAsFixed(0)} mm',
              ),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          controller.text = value.toStringAsFixed(0);
          widget.onChanged(value);
        },
      ),
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: tr('عرض مخصص (مم)'),
          helperText: tr('78 mm غير معتمد كمقاس مستقل'),
        ),
        onChanged: (text) {
          final value = double.tryParse(text);
          if (value != null && value > 0) widget.onChanged(value);
        },
      ),
    ],
  );
}
