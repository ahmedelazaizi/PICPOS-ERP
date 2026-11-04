import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../services/printing/barcode_label_printer.dart';
import '../../../../services/printing/barcode_label_spec.dart';
import '../../../pos/services/scale_barcode_config.dart';
import '../../../pos/services/scale_barcode_encoder.dart';
import 'scale_label_availability.dart';
import '../../../../services/printing/label_preset_store.dart';
import '../../../../services/printing/label_item_sample.dart';
import '../../../../domain/printing/label_design.dart';
import 'label_template_preview.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';

typedef LabelPrintCallback =
    Future<bool> Function(List<BarcodeLabelItem> items, LabelSpec spec);
typedef LabelDefaultsLoader =
    Future<List<BarcodeLabelItem>> Function(List<BarcodeLabelItem> items);
typedef LabelTemplatePrintCallback =
    Future<bool> Function(
      List<BarcodeLabelItem> items,
      LabelSpec spec,
      int templateId,
    );

class BarcodeLabelTemplateOption {
  const BarcodeLabelTemplateOption({
    required this.id,
    required this.name,
    required this.widthMm,
    required this.heightMm,
    this.design,
  });

  final int id;
  final String name;
  final double widthMm;
  final double heightMm;

  /// عناصرُ القالب — تُرسم منها المعاينة. `null` ⇒ المعاينةُ المبسّطة.
  final LabelDesign? design;
}

class _Row {
  final BarcodeLabelItem item;
  bool selected = true;
  final TextEditingController copies;
  _Row(this.item) : copies = TextEditingController(text: '${item.copies}');
}

/// حوار طباعة ملصقات الباركود دفعة واحدة: مقاس جاهز/مخصص + نسخ لكل صنف +
/// معاينة. الطباعة تمرّ على [BarcodeLabelPrinter] (قابلة للاستبدال للاختبار).
class BarcodeLabelBatchDialog extends StatefulWidget {
  final List<BarcodeLabelItem> items;
  final LabelPrintCallback? onPrint;
  final LabelTemplatePrintCallback? onPrintTemplate;
  final List<BarcodeLabelTemplateOption> templates;
  final int? defaultTemplateId;

  /// يعدّل النسخ الافتراضية (مثلاً من كمية آخر استلام) بعد فتح الحوار.
  final LabelDefaultsLoader? loadDefaults;
  final Map<String, String> scaleSettings;
  final int? scaleTemplateId;

  const BarcodeLabelBatchDialog({
    super.key,
    required this.items,
    this.onPrint,
    this.onPrintTemplate,
    this.templates = const [],
    this.defaultTemplateId,
    this.loadDefaults,
    this.scaleSettings = const {},
    this.scaleTemplateId,
  });

  static Future<void> show(
    BuildContext context,
    List<BarcodeLabelItem> items, {
    LabelDefaultsLoader? loadDefaults,
    LabelPrintCallback? onPrint,
    LabelTemplatePrintCallback? onPrintTemplate,
    List<BarcodeLabelTemplateOption> templates = const [],
    int? defaultTemplateId,
    Map<String, String> scaleSettings = const {},
    int? scaleTemplateId,
  }) => showDialog(
    context: context,
    builder: (_) => BarcodeLabelBatchDialog(
      items: items,
      loadDefaults: loadDefaults,
      onPrint: onPrint,
      onPrintTemplate: onPrintTemplate,
      templates: templates,
      defaultTemplateId: defaultTemplateId,
      scaleSettings: scaleSettings,
      scaleTemplateId: scaleTemplateId,
    ),
  );

  @override
  State<BarcodeLabelBatchDialog> createState() =>
      _BarcodeLabelBatchDialogState();
}

class _BarcodeLabelBatchDialogState extends State<BarcodeLabelBatchDialog> {
  static const _newId = '__new__';

  late final List<_Row> _rows;
  List<LabelSpec> _specs = LabelSpec.presets;
  String _selectedId = LabelSpec.defaultSpec.id;
  bool _printing = false;
  bool _scaleTemplateSelected = false;
  int? _selectedTemplateId;

  final _weight = TextEditingController();
  final _name = TextEditingController();
  final _width = TextEditingController(text: '50');
  final _height = TextEditingController(text: '25');
  final _margin = TextEditingController(text: '2');
  final _columns = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _rows = [for (final i in widget.items) _Row(i)];
    // كان يكفي وجودُ صنفٍ موزون؛ الآن يلزم أيضاً تفعيلُ باركود الوزن وPLU
    // وإعدادٌ صالح — وإلّا يبقى الخيار معطّلاً مع سببه ([_scaleBlock]).
    _scaleTemplateSelected = _scaleBlock == null;
    _selectedTemplateId = _scaleTemplateSelected
        ? widget.scaleTemplateId
        : widget.defaultTemplateId;
    _load();
  }

  Future<void> _load() async {
    final specs = await LabelPresetStore.loadAll();
    final active = await LabelPresetStore.activeSpec();
    if (!mounted) return;
    setState(() {
      _specs = specs;
      _selectedId =
          _scaleTemplateSelected && specs.any((s) => s.id == 'roll_58x40')
          ? 'roll_58x40'
          : active.id;
    });
    if (active.isCustom) _fillEditor(active);
    final loader = widget.loadDefaults;
    if (loader != null) {
      final loaded = await loader(widget.items);
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _rows.length && i < loaded.length; i++) {
          _rows[i].copies.text = '${loaded[i].copies}';
        }
      });
    }
  }

  ScaleBarcodeConfig get _scaleConfig =>
      ScaleBarcodeConfig.fromSettings(widget.scaleSettings);

  ScaleLabelBlock? get _scaleBlock => scaleLabelBlockFor(
    scaleTemplateId: widget.scaleTemplateId,
    items: [for (final r in _rows) r.item],
    config: _scaleConfig,
  );

  @override
  void didUpdateWidget(covariant BarcodeLabelBatchDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    // إعدادٌ أُطفئ/أُفسد والحوار مفتوح ⇒ لا يبقى ملصق الميزان مختاراً.
    if (_scaleTemplateSelected && _scaleBlock != null) {
      _scaleTemplateSelected = false;
      _selectedTemplateId = widget.defaultTemplateId;
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.copies.dispose();
    }
    for (final c in [_weight, _name, _width, _height, _margin, _columns]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _editing =>
      _selectedId == _newId ||
      _specs.any((s) => s.id == _selectedId && s.isCustom);

  void _fillEditor(LabelSpec s) {
    _name.text = s.name;
    _width.text = _fmt(s.widthMm);
    _height.text = _fmt(s.heightMm);
    _margin.text = _fmt(s.marginMm);
    _columns.text = '${s.columns}';
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  LabelSpec? get _scaleLabelSpec {
    for (final spec in _specs) {
      if (spec.id == 'roll_58x40') return spec;
    }
    return null;
  }

  LabelSpec? get _effectiveSpec =>
      _templateSpec ?? (_scaleTemplateSelected ? _scaleLabelSpec : _spec);

  LabelSpec? get _templateSpec {
    final selected = _selectedTemplateId;
    if (selected == null) return null;
    for (final template in widget.templates) {
      if (template.id == selected) {
        return LabelSpec.roll(
          id: 'stored_${template.id}',
          name: template.name,
          widthMm: template.widthMm,
          heightMm: template.heightMm,
          marginMm: 0,
        );
      }
    }
    return _scaleTemplateSelected ? _scaleLabelSpec : null;
  }

  /// التنسيق الفعّال: المحدد، أو مسودة المحرر. `null` إن كانت المسودة غير صالحة.
  LabelSpec? get _spec {
    if (!_editing) {
      return _specs.firstWhere(
        (s) => s.id == _selectedId,
        orElse: () => LabelSpec.defaultSpec,
      );
    }
    final w = double.tryParse(_width.text.trim());
    final h = double.tryParse(_height.text.trim());
    final m = double.tryParse(_margin.text.trim());
    final c = int.tryParse(_columns.text.trim());
    if (w == null || h == null || m == null || c == null) return null;
    final name = _name.text.trim().isEmpty
        ? '${_fmt(w)}×${_fmt(h)} mm'
        : _name.text.trim();
    final spec = LabelSpec.roll(
      id: _selectedId == _newId
          ? 'custom_${DateTime.now().microsecondsSinceEpoch}'
          : _selectedId,
      name: name,
      widthMm: w,
      heightMm: h,
      marginMm: m,
      columns: c,
      gapMm: c > 1 ? 2 : 0,
      isCustom: true,
    );
    return spec.validate() == null ? spec : null;
  }

  _Row? get _selectedScaleRow {
    for (final row in _rows) {
      if (row.selected && row.item.isSoldByWeight) return row;
    }
    return null;
  }

  double? get _scaleWeight =>
      double.tryParse(_weight.text.trim().replaceAll(',', '.'));

  String? get _scaleBarcode {
    final row = _selectedScaleRow;
    final weight = _scaleWeight;
    if (row == null || weight == null || row.item.scalePluNumber == null) {
      return null;
    }
    try {
      // نفس قراءة شاشة الإعداد (المفاتيح + الاحتياط + الافتراض) ⇒ نفس الرمز.
      return _scaleConfig.encode(
        plu: '${row.item.scalePluNumber}',
        value: weight,
        kind: ScaleBarcodeValueKind.weight,
      );
    } on ArgumentError {
      return null;
    }
  }

  bool get _scaleInputValid =>
      _scaleWeight != null && _scaleWeight! > 0 && _scaleBarcode != null;

  List<BarcodeLabelItem> get _items => [
    for (final r in _rows)
      if (r.selected)
        if (_scaleTemplateSelected && r.item.isSoldByWeight && _scaleInputValid)
          r.item
              .withCopies(
                LabelLayout.clampCopies(int.tryParse(r.copies.text) ?? 0),
              )
              .withScaleData(weight: _scaleWeight!, value: _scaleBarcode!)
        else
          r.item.withCopies(
            LabelLayout.clampCopies(int.tryParse(r.copies.text) ?? 0),
          ),
  ];

  Future<void> _saveCustom() async {
    final spec = _spec;
    if (spec == null) return;
    await LabelPresetStore.saveCustom(spec);
    final all = await LabelPresetStore.loadAll();
    if (!mounted) return;
    setState(() {
      _specs = all;
      _selectedId = spec.id;
    });
  }

  Future<void> _deleteCustom() async {
    await LabelPresetStore.deleteCustom(_selectedId);
    final all = await LabelPresetStore.loadAll();
    if (!mounted) return;
    setState(() {
      _specs = all;
      _selectedId = LabelSpec.defaultSpec.id;
    });
  }

  Future<void> _print() async {
    final spec = _effectiveSpec;
    final items = _items;
    if (spec == null || _printing) return;
    if (_scaleTemplateSelected && !_scaleInputValid) {
      AppToast.show(
        context,
        tr('قيمة خارج النطاق المسموح'),
        type: ToastType.warning,
      );
      return;
    }
    final total = LabelLayout.totalLabels(items);
    if (total == 0) {
      AppToast.show(
        context,
        tr('لا توجد ملصقات للطباعة'),
        type: ToastType.warning,
      );
      return;
    }
    if (total > LabelSpec.maxTotalLabels) return;
    setState(() => _printing = true);
    final templatePrint = widget.onPrintTemplate;
    final printed = _selectedTemplateId != null && templatePrint != null
        ? await templatePrint(items, spec, _selectedTemplateId!)
        : await (widget.onPrint ??
              ((i, s) => BarcodeLabelPrinter.print(i, spec: s)))(items, spec);
    if (printed && _specs.any((s) => s.id == spec.id)) {
      await LabelPresetStore.setActiveId(spec.id);
    }
    if (!mounted) return;
    AppToast.show(
      context,
      printed
          ? tr('تمت طباعة {copies} نسخة من الباركود', {'copies': total})
          : tr('أُلغيت طباعة الباركود'),
      type: printed ? ToastType.success : ToastType.warning,
    );
    if (printed) {
      Navigator.pop(context);
    } else {
      setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = _effectiveSpec;
    final items = _items;
    final total = LabelLayout.totalLabels(items);
    final pages = spec == null ? 0 : LabelLayout.paginate(spec, items).length;
    final tooMany = total > LabelSpec.maxTotalLabels;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.barcode, color: AppColors.warning),
            const SizedBox(width: 8),
            Text(tr('طباعة ملصقات الباركود')),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _itemsList(),
                const SizedBox(height: 12),
                _templatePicker(),
                const SizedBox(height: 8),
                ?_scaleHint(),
                if (_scaleTemplateSelected) _scaleLabelControls(),
                if (!_scaleTemplateSelected && _selectedTemplateId == null)
                  _sizePicker(),
                if (!_scaleTemplateSelected &&
                    _selectedTemplateId == null &&
                    _editing)
                  _customEditor(),
                const SizedBox(height: 12),
                Text(
                  tr('معاينة'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Center(child: _preview(spec, items)),
                const SizedBox(height: 6),
                Text(
                  tooMany
                      ? tr('تجاوز الحد الأقصى ({n}) للملصقات', {
                          'n': LabelSpec.maxTotalLabels,
                        })
                      : tr('{n} ملصق على {p} صفحة', {'n': total, 'p': pages}),
                  key: const Key('label_summary'),
                  style: TextStyle(
                    color: tooMany ? AppColors.error : context.picposSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('إلغاء')),
          ),
          ElevatedButton.icon(
            key: const Key('label_print_button'),
            onPressed:
                (spec == null ||
                    total == 0 ||
                    tooMany ||
                    _printing ||
                    (_scaleTemplateSelected && !_scaleInputValid))
                ? null
                : _print,
            icon: const Icon(PhosphorIconsBold.printer, size: 16),
            label: Text(tr('طباعة')),
          ),
        ],
      ),
    );
  }

  /// القالبُ المحفوظُ المختارُ بعناصره — يُرسم ملصقُ أوّلِ صنفٍ منه بنفس
  /// عيّنة الطباعة (‏`labelSampleForItem`)، فما يُرى هو ما يخرج.
  Widget _preview(LabelSpec? spec, List<BarcodeLabelItem> items) {
    final design = widget.templates
        .where((t) => t.id == _selectedTemplateId)
        .firstOrNull
        ?.design;
    if (design == null || items.isEmpty) {
      return LabelPagePreview(spec: spec, items: items);
    }
    return LabelTemplatePreview(
      design: design,
      sample: labelSampleForItem(items.first),
    );
  }

  /// «ملصق ميزان» عنصرٌ في قائمة القوالب نفسها — معطّلٌ مع سببه حين لا
  /// يُتاح. (كان قالباً عادياً في هذه القائمة يُطبع بلا وزن، وله قائمةٌ ثانية
  /// منفصلة «مقاس الملصق: باركود قياسي/الميزان» تظهر للموزون فقط — فاختيارُه
  /// من الأولى لا يُظهر حقل الوزن. وُحّدت القائمتان هنا.)
  DropdownMenuItem<int?> _scaleOption(String name) {
    final blocked = _scaleBlock != null;
    return DropdownMenuItem<int?>(
      value: widget.scaleTemplateId,
      enabled: !blocked,
      child: Text(
        blocked ? tr('{name} (غير متاح)', {'name': name}) : name,
        key: const Key('scale_template_option'),
        style: blocked ? TextStyle(color: context.picposSecondary) : null,
      ),
    );
  }

  void _selectTemplate(int? id) => setState(() {
    _selectedTemplateId = id;
    _scaleTemplateSelected =
        id != null && id == widget.scaleTemplateId && _scaleBlock == null;
    if (_scaleTemplateSelected && _specs.any((s) => s.id == 'roll_58x40')) {
      _selectedId = 'roll_58x40';
    }
  });

  Widget _templatePicker() => KeyedSubtree(
    // `initialValue` يُقرأ مرّة؛ المفتاحُ يعيد بناءه إن تغيّر الاختيار برمجياً
    // (‏didUpdateWidget عند إطفاء الإعداد).
    key: ValueKey('tpl_$_selectedTemplateId'),
    child: DropdownButtonFormField<int?>(
      key: const Key('barcode_template_dropdown'),
      initialValue: _selectedTemplateId,
      isExpanded: true,
      decoration: InputDecoration(labelText: tr('قالب الملصق'), isDense: true),
      items: [
        DropdownMenuItem<int?>(
          value: null,
          child: Text(tr('التصميم الافتراضي القديم')),
        ),
        for (final template in widget.templates)
          if (template.id == widget.scaleTemplateId)
            _scaleOption(template.name)
          else
            DropdownMenuItem<int?>(
              value: template.id,
              child: Text(template.name),
            ),
        if (widget.scaleTemplateId != null &&
            !widget.templates.any(
              (template) => template.id == widget.scaleTemplateId,
            ))
          _scaleOption(tr('ملصق ميزان')),
      ],
      onChanged: _selectTemplate,
    ),
  );

  /// سببُ تعطيل ملصق الميزان — لا صمت. لا يُعرض لصنفٍ عاديٍّ بلا قالب ميزان.
  Widget? _scaleHint() {
    final block = _scaleBlock;
    if (block == null) return null;
    if (block == ScaleLabelBlock.noTemplate &&
        !_rows.any((r) => r.item.isSoldByWeight)) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        scaleLabelBlockText(block),
        key: const Key('scale_label_unavailable_hint'),
        style: TextStyle(
          fontSize: 12,
          color: block == ScaleLabelBlock.notWeighed
              ? context.picposSecondary
              : AppColors.warning,
        ),
      ),
    );
  }

  Widget _scaleLabelControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_scaleTemplateSelected) ...[
        const SizedBox(height: 8),
        TextField(
          key: const Key('scale_label_weight_input'),
          controller: _weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: tr('الوزن (كجم)'),
            isDense: true,
            errorText: _weight.text.isEmpty || _scaleInputValid
                ? null
                : tr('قيمة خارج النطاق المسموح'),
          ),
        ),
        if (_scaleBarcode != null)
          SelectableText(
            _scaleBarcode!,
            key: const Key('scale_label_barcode_preview'),
            textDirection: TextDirection.ltr,
          ),
      ],
    ],
  );

  Widget _itemsList() => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 200),
    child: ListView(
      shrinkWrap: true,
      children: [
        for (var i = 0; i < _rows.length; i++)
          Row(
            children: [
              Checkbox(
                key: Key('label_item_check_$i'),
                value: _rows[i].selected,
                onChanged: (v) =>
                    setState(() => _rows[i].selected = v ?? false),
              ),
              Expanded(
                child: Text(
                  _rows[i].item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 90,
                child: TextField(
                  key: Key('label_item_copies_$i'),
                  controller: _rows[i].copies,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: tr('عدد النسخ'),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
      ],
    ),
  );

  Widget _sizePicker() => Row(
    children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          key: const Key('label_size_dropdown'),
          initialValue: _selectedId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: tr('مقاس الملصق'),
            isDense: true,
          ),
          items: [
            for (final s in _specs)
              DropdownMenuItem(value: s.id, child: Text(s.name)),
            DropdownMenuItem(value: _newId, child: Text(tr('مقاس مخصص...'))),
          ],
          onChanged: (id) {
            if (id == null) return;
            setState(() {
              _selectedId = id;
              if (id == _newId) {
                _name.clear();
              } else {
                final s = _specs.firstWhere((s) => s.id == id);
                if (s.isCustom) _fillEditor(s);
              }
            });
          },
        ),
      ),
    ],
  );

  Widget _field(
    String key,
    TextEditingController c,
    String label, {
    bool text = false,
  }) => SizedBox(
    width: text ? 150 : 100,
    child: TextField(
      key: Key(key),
      controller: c,
      keyboardType: text ? TextInputType.text : TextInputType.number,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label, isDense: true),
    ),
  );

  Widget _customEditor() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _field('label_custom_name', _name, tr('اسم المقاس'), text: true),
        _field('label_custom_width', _width, tr('العرض (مم)')),
        _field('label_custom_height', _height, tr('الارتفاع (مم)')),
        _field('label_custom_margin', _margin, tr('الهامش (مم)')),
        _field('label_custom_columns', _columns, tr('عدد الأعمدة')),
        TextButton.icon(
          key: const Key('label_custom_save'),
          onPressed: _spec == null ? null : _saveCustom,
          icon: const Icon(PhosphorIconsBold.floppyDisk, size: 16),
          label: Text(tr('حفظ')),
        ),
        if (_selectedId != _newId)
          TextButton.icon(
            key: const Key('label_custom_delete'),
            onPressed: _deleteCustom,
            icon: const Icon(PhosphorIconsBold.trash, size: 16),
            label: Text(tr('حذف')),
          ),
      ],
    ),
  );
}

/// معاينة مبسّطة للصفحة الأولى: مستطيل الصفحة وخلايا الملصقات (المشغولة مظلّلة).
class LabelPagePreview extends StatelessWidget {
  final LabelSpec? spec;
  final List<BarcodeLabelItem> items;
  static const double _maxHeight = 180;
  static const double _maxWidth = 360;

  const LabelPagePreview({super.key, required this.spec, required this.items});

  @override
  Widget build(BuildContext context) {
    final s = spec;
    if (s == null) return const SizedBox(height: 40);
    final pageW = s.pageWidthMm, pageH = s.pageHeightMm;
    final k = (_maxWidth / pageW) < (_maxHeight / pageH)
        ? _maxWidth / pageW
        : _maxHeight / pageH;
    final firstPage = LabelLayout.paginate(s, items);
    final used = firstPage.isEmpty ? 0 : firstPage.first.length;
    final cells = <Widget>[];
    for (var r = 0; r < s.rows; r++) {
      for (var c = 0; c < s.columns; c++) {
        final idx = r * s.columns + c;
        final left = (s.pageMarginMm + c * (s.cellWidthMm + s.gapMm)) * k;
        final top = (s.pageMarginMm + r * (s.cellHeightMm + s.gapMm)) * k;
        final filled = idx < used;
        cells.add(
          Positioned(
            left: left,
            top: top,
            width: s.cellWidthMm * k,
            height: s.cellHeightMm * k,
            child: Container(
              key: Key('label_preview_cell_$idx'),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: filled
                    ? AppColors.warning.withValues(alpha: 0.25)
                    : null,
                border: Border.all(color: Colors.grey),
              ),
              child: filled
                  ? Text(
                      firstPage.first[idx].item.name,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      // dark-ok: نص على ورقة معاينة بيضاء ثابتة
                      style: const TextStyle(
                        fontSize: 11,
                        // dark-ok: label preview paper is intentionally white.
                        color: Colors.black87,
                      ),
                    )
                  : null,
            ),
          ),
        );
      }
    }
    return Container(
      key: const Key('label_preview_page'),
      width: pageW * k,
      height: pageH * k,
      decoration: BoxDecoration(
        // dark-ok: معاينة ورقة ملصق مطبوعة — بيضاء دائماً بغض النظر عن الثيم
        color: Colors.white,
        border: Border.all(color: Colors.black54),
      ),
      child: Stack(children: cells),
    );
  }
}
