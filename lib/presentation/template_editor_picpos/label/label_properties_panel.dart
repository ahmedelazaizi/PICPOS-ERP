import 'package:picpos_erp/core/i18n/tr.dart';
// لوحةُ خصائص الملصق — مقاسُ الملصق واسمُه، ثمّ خصائصُ العنصر المحدَّد.
//
// كلُّ حقلٍ هنا **عمودٌ يقرؤه راسمُ الملصقات**: لا خيارَ يُعرض ولا يصل الورق.
// ولذلك لا «إظهار/إخفاء»: الراسمُ لا يقرأ `is_visible` فيطبع كلَّ عنصر.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/label_editor_providers.dart';
import '../../../domain/printing/label_design.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../widgets/editor_panel_parts.dart';
import 'label_texts.dart';

/// ألوانُ الحبر المتاحة — ما تطبعه الطابعاتُ الحراريّةُ ملوّنةً أصلاً قليل.
const _swatches = <String>['#000000', '#4B5563', '#B91C1C', '#1D4ED8'];

class LabelPropertiesPanel extends StatelessWidget {
  const LabelPropertiesPanel({
    super.key,
    required this.state,
    required this.editor,
  });

  final LabelEditorState state;
  final LabelEditorNotifier editor;

  @override
  Widget build(BuildContext context) {
    final d = state.design;
    final el = state.selected;
    return ListView(
      children: [
        EditorPanelSection(
          title: tr('الملصق'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NameField(name: d.name, onChanged: editor.rename),
              const SizedBox(height: 10),
              KeyedSubtree(
                key: const Key('label-size-w'),
                child: EditorStepper(
                  label: tr('العرض (مم)'),
                  value: d.widthMm,
                  decimals: 0,
                  onDelta: (v) => editor.labelSize(widthMm: d.widthMm + v),
                ),
              ),
              const SizedBox(height: 6),
              KeyedSubtree(
                key: const Key('label-size-h'),
                child: EditorStepper(
                  label: tr('الارتفاع (مم)'),
                  value: d.heightMm,
                  decimals: 0,
                  onDelta: (v) => editor.labelSize(heightMm: d.heightMm + v),
                ),
              ),
            ],
          ),
        ),
        if (el == null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tr('اختر عنصراً على الملصق لتعديل خصائصه'),
              style: TextStyle(fontSize: 12, color: context.picposMuted),
            ),
          )
        else
          ..._elementSections(context, el),
      ],
    );
  }

  List<Widget> _elementSections(BuildContext context, LabelElement el) {
    final key = el.key;
    Widget step(String id, String label, double value, ValueChanged<double> f,
            {double step = 0.5}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: KeyedSubtree(
            key: Key('label-prop-$id'),
            child: EditorStepper(
                label: label, value: value, step: step, onDelta: f),
          ),
        );

    return [
      EditorPanelSection(
        title: tr('العنصر: {p0}', {'p0': labelTypeName(el.type, content: el.content)}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            step('x', tr('من اليسار (مم)'), el.xMm,
                (v) => editor.move(key, el.xMm + v, el.yMm)),
            step('y', tr('من الأعلى (مم)'), el.yMm,
                (v) => editor.move(key, el.xMm, el.yMm + v)),
            step('w', tr('العرض (مم)'), el.wMm,
                (v) => editor.resize(key, el.wMm + v, el.hMm)),
            step('h', tr('الارتفاع (مم)'), el.hMm,
                (v) => editor.resize(key, el.wMm, el.hMm + v)),
          ],
        ),
      ),
      if (el.hasText)
        EditorPanelSection(
          title: tr('الخط'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              step('font', tr('الحجم (نقطة)'), el.fontSize,
                  (v) => editor.edit(key, fontSize: el.fontSize + v)),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  EditorToggle(
                    key: const Key('label-prop-bold'),
                    icon: PhosphorIconsBold.textB,
                    on: el.bold,
                    onTap: () => editor.edit(key, bold: !el.bold),
                  ),
                  EditorToggle(
                    key: const Key('label-prop-italic'),
                    icon: PhosphorIconsBold.textItalic,
                    on: el.italic,
                    onTap: () => editor.edit(key, italic: !el.italic),
                  ),
                  for (final a in const [
                    ('left', PhosphorIconsBold.textAlignLeft),
                    ('center', PhosphorIconsBold.textAlignCenter),
                    ('right', PhosphorIconsBold.textAlignRight),
                  ])
                    EditorToggle(
                      key: Key('label-prop-align-${a.$1}'),
                      icon: a.$2,
                      on: el.align == a.$1,
                      onTap: () => editor.edit(key, align: a.$1),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final c in _swatches)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: InkWell(
                        key: Key('label-prop-color-$c'),
                        onTap: () => editor.edit(key, color: c),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _hex(c),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: el.color.toUpperCase() == c
                                  ? context.picposBrandInk
                                  : context.picposHairline,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Text(el.color,
                      style: TextStyle(
                          fontSize: 11, color: context.picposMuted)),
                ],
              ),
            ],
          ),
        ),
      if (el.type == LabelElementTypes.text)
        EditorPanelSection(
          title: tr('النص'),
          child: _ContentField(
            key: ValueKey('label-text-$key'),
            value: el.content ?? '',
            onChanged: (v) => editor.edit(key, content: v),
          ),
        ),
      if (el.isBarcode)
        EditorPanelSection(
          title: tr('نوع الرمز'),
          child: DropdownButton<String>(
            key: const Key('label-prop-symbology'),
            isExpanded: true,
            value: kLabelSymbologies.contains(el.content) ? el.content : 'code128',
            items: [
              for (final s in kLabelSymbologies)
                DropdownMenuItem(value: s, child: Text(labelSymbologyName(s))),
            ],
            onChanged: (v) {
              if (v != null) editor.edit(key, content: v);
            },
          ),
        ),
      if (el.isRect)
        EditorPanelSection(
          title: tr('الإطار'),
          child: step('border', tr('السُّمك (نقطة)'), el.borderWidth,
              (v) => editor.edit(key, borderWidth: el.borderWidth + v)),
        ),
      Padding(
        padding: const EdgeInsets.all(14),
        child: OutlinedButton.icon(
          key: const Key('label-prop-delete'),
          onPressed: () => editor.remove(key),
          icon: const Icon(PhosphorIconsBold.trash, size: 15),
          label: Text(tr('حذف العنصر')),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
        ),
      ),
    ];
  }

  Color _hex(String c) =>
      Color(0xFF000000 | (int.tryParse(c.substring(1), radix: 16) ?? 0));
}

/// حقلُ اسم الملصق — يحتفظ بمتحكّمه كي لا يقفز المؤشّرُ مع كلِّ حرف.
class _NameField extends StatefulWidget {
  const _NameField({required this.name, required this.onChanged});

  final String name;
  final ValueChanged<String> onChanged;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final _ctrl = TextEditingController(text: widget.name);

  @override
  void didUpdateWidget(_NameField old) {
    super.didUpdateWidget(old);
    if (widget.name != _ctrl.text) _ctrl.text = widget.name;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        key: const Key('label-name'),
        controller: _ctrl,
        onChanged: widget.onChanged,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          isDense: true,
          labelText: tr('اسم الملصق'),
          border: const OutlineInputBorder(),
        ),
      );
}

class _ContentField extends StatefulWidget {
  const _ContentField({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_ContentField> createState() => _ContentFieldState();
}

class _ContentFieldState extends State<_ContentField> {
  late final _ctrl = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        key: const Key('label-prop-content'),
        controller: _ctrl,
        onChanged: widget.onChanged,
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
        ),
      );
}
