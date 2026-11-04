import 'package:picpos_erp/core/i18n/tr.dart';
// لوحةُ عناصر الملصق — الإضافةُ من الأنواع التي **يرسمها** الراسم، ثمّ القائمة.
//
// ⚠️ **الأنواعُ هنا مفاتيحُ الراسم مباشرةً** (‏`product_name`، `barcode_image`…)
// لا `variable` بمحتوى: لوحةُ المصمّم القديم كانت تُدرج `element_type =
// 'variable'` و`content = 'product_name'`، وراسمُ الملصقات لا يعرف `variable`
// فيسقط إلى `content` ويطبع الكلمةَ «product_name» حرفيّاً على الملصق.

import 'package:flutter/material.dart';

import '../../../domain/printing/label_design.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../widgets/editor_panel_parts.dart';
import 'label_texts.dart';

class LabelElementsPanel extends StatelessWidget {
  const LabelElementsPanel({
    super.key,
    required this.design,
    required this.selectedKey,
    required this.onAdd,
    required this.onSelect,
  });

  final LabelDesign design;
  final String? selectedKey;
  final void Function(String type, {String? content}) onAdd;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = <(String, String?)>[
      for (final t in LabelElementTypes.palette) (t, null),
      // QR ليس نوعاً مستقلّاً عند الراسم: باركودٌ رمزُه `qrCode`.
      (LabelElementTypes.barcode, 'qrCode'),
    ];

    return ListView(
      children: [
        EditorPanelSection(
          title: tr('إضافة عنصر'),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in palette)
                EditorChip(
                  key: Key('label-add-${p.$1}${p.$2 == null ? '' : '-${p.$2}'}'),
                  icon: labelTypeIcon(p.$1, content: p.$2),
                  label: labelTypeName(p.$1, content: p.$2),
                  on: false,
                  onTap: () => onAdd(p.$1, content: p.$2),
                ),
            ],
          ),
        ),
        EditorPanelSection(
          title: tr('العناصر ({p0})', {'p0': design.elements.length}),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in design.elements)
                _Row(
                  element: e,
                  selected: e.key == selectedKey,
                  onTap: () => onSelect(e.key),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.element,
    required this.selected,
    required this.onTap,
  });

  final LabelElement element;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = element;
    final tone = selected ? context.picposBrandInk : context.picposText;
    return InkWell(
      key: Key('label-row-${e.key}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: selected
              ? context.picposBrandInk.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? context.picposBrandInk : context.picposHairline),
        ),
        child: Row(
          children: [
            Icon(labelTypeIcon(e.type, content: e.content), size: 14, color: tone),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                labelTypeName(e.type, content: e.content),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: tone),
              ),
            ),
            Text(
              '${e.xMm.toStringAsFixed(1)}, ${e.yMm.toStringAsFixed(1)} · '
              '${e.wMm.toStringAsFixed(1)}×${e.hMm.toStringAsFixed(1)}',
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 10, color: context.picposMuted),
            ),
          ],
        ),
      ),
    );
  }
}
