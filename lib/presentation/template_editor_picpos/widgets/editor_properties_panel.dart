import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/design_system/typography.dart';
// اللوحةُ اليمنى — خصائصُ ما هو محدَّد: عنصرٌ أو نطاقٌ أو الجدول.
//
// ── كلُّ حقلٍ هنا يصل الورقةَ ────────────────────────────────────────────
// وهذا ليس بديهيّاً: عقدُ الأزرار يسمّي ثلاثةَ حقولٍ في السطح القديم
// **تُخزَّن ويتجاهلها الراسمُ عمداً** (`headerBgColor` · `headerTextColor` ·
// `headerBold`)، ويقول إنّ الحالَ أسوأُ الخيارين — «المستخدمُ يغيّر ولا يحدث
// شيء». فلا يُعرَض هنا إلّا ما يقرؤه `LayoutEngine`.
//
// ⚠️ و`الخصائصُ بالمليمتر لا بالبكسل`: «البكسلُ يتغيّر بالتكبير».

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/printing/template_document.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'editor_canvas.dart' show bandLabel, bandTint;

/// جاهزاتُ الشرط — «`field op value` فقط، لا مفسّرَ تعابيرَ كامل».
const conditionPresets = <String>[
  'discount > 0',
  'remaining > 0',
  'tax > 0',
  'paid < total',
];

class EditorPropertiesPanel extends StatelessWidget {
  const EditorPropertiesPanel({
    super.key,
    required this.document,
    required this.element,
    required this.band,
    required this.showTable,
    required this.onEditElement,
    required this.onMoveElement,
    required this.onResizeElement,
    required this.onRemoveElement,
    required this.onEditBand,
    required this.onToggleColumn,
    required this.onMoveColumn,
    required this.onEditColumn,
    required this.onEditTable,
  });

  final TemplateDocument document;
  final TemplateElement? element;
  final TemplateBand? band;
  final bool showTable;

  final void Function({
    String? labelAr,
    String? labelEn,
    double? fontSize,
    bool? bold,
    bool? visible,
    TextAlignSpec? align,
    String? condition,
  }) onEditElement;
  final void Function(double xMm, double yMm) onMoveElement;
  final void Function(double wMm, double hMm) onResizeElement;
  final VoidCallback onRemoveElement;

  final void Function({
    double? heightMm,
    bool? repeatEachPage,
    bool? autoHeight,
    bool? visible,
  }) onEditBand;

  final ValueChanged<String> onToggleColumn;
  final void Function(String key, int delta) onMoveColumn;
  final void Function(String key,
      {String? labelAr, String? labelEn, double? flex, int? decimals}) onEditColumn;
  final void Function({
    double? fontSize,
    double? headerFontSize,
    bool? bilingualHeaders,
    bool? repeatHeader,
    bool? keepRowTogether,
  }) onEditTable;

  @override
  Widget build(BuildContext context) {
    final el = element;
    if (el != null) {
      return _ElementProperties(
        element: el,
        bandId: band?.id ?? BandId.header,
        onEdit: onEditElement,
        onMove: onMoveElement,
        onResize: onResizeElement,
        onRemove: onRemoveElement,
      );
    }

    if (showTable && document.table != null) {
      return _TableProperties(
        table: document.table!,
        onToggleColumn: onToggleColumn,
        onMoveColumn: onMoveColumn,
        onEditColumn: onEditColumn,
        onEditTable: onEditTable,
      );
    }

    final b = band;
    if (b != null) return _BandProperties(band: b, onEdit: onEditBand);

    return  PicPosEmptyState(
      icon: PhosphorIconsBold.cursorClick,
      title: tr('اختر عنصراً أو نطاقاً'),
      hint: tr('خصائصُه تظهر هنا — وكلُّ حقلٍ فيها يصل الورقة'),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _ElementProperties extends StatefulWidget {
  const _ElementProperties({
    required this.element,
    required this.bandId,
    required this.onEdit,
    required this.onMove,
    required this.onResize,
    required this.onRemove,
  });

  final TemplateElement element;
  final BandId bandId;
  final void Function({
    String? labelAr,
    String? labelEn,
    double? fontSize,
    bool? bold,
    bool? visible,
    TextAlignSpec? align,
    String? condition,
  }) onEdit;
  final void Function(double, double) onMove;
  final void Function(double, double) onResize;
  final VoidCallback onRemove;

  @override
  State<_ElementProperties> createState() => _ElementPropertiesState();
}

class _ElementPropertiesState extends State<_ElementProperties> {
  late final TextEditingController _ar;
  late final TextEditingController _en;
  late final TextEditingController _cond;

  @override
  void initState() {
    super.initState();
    _ar = TextEditingController(text: widget.element.labelAr ?? '');
    _en = TextEditingController(text: widget.element.labelEn ?? '');
    _cond = TextEditingController(text: widget.element.condition ?? '');
  }

  @override
  void didUpdateWidget(_ElementProperties old) {
    super.didUpdateWidget(old);
    // ⚠️ الحقولُ تُعاد تعبئتُها **عند تبدّل العنصر وحدَه** لا عند كلِّ إعادةِ
    //    بناء: التعبئةُ في كلِّ مرّةٍ تقفز بمؤشّر الكتابة إلى أوّل الحقل بعد
    //    كلِّ حرفٍ يكتبه المستخدم.
    if (old.element.id == widget.element.id) return;
    _ar.text = widget.element.labelAr ?? '';
    _en.text = widget.element.labelEn ?? '';
    _cond.text = widget.element.condition ?? '';
  }

  @override
  void dispose() {
    _ar.dispose();
    _en.dispose();
    _cond.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final el = widget.element;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        PicPosSectionHeader(
          title: (el.labelAr?.isNotEmpty ?? false)
              ? el.labelAr!
              : el.contentKey,
          subtitle: '${el.contentKey} · ${bandLabel(widget.bandId)}',
          icon: PhosphorIconsBold.textT,
          actions: [
            IconButton(
              tooltip: tr('حذف العنصر'),
              icon: const Icon(PhosphorIconsBold.trash,
                  size: 15, color: AppColors.error),
              onPressed: widget.onRemove,
            ),
          ],
        ),
        _Section(
          title: tr('التسمية المطبوعة'),
          child: Row(
            children: [
              Expanded(
                child: _Field(
                  label: tr('عربي'),
                  controller: _ar,
                  onChanged: (v) => widget.onEdit(labelAr: v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Field(
                  label: 'English',
                  controller: _en,
                  ltr: true,
                  onChanged: (v) => widget.onEdit(labelEn: v),
                ),
              ),
            ],
          ),
        ),
        _Section(
          title: tr('الموضع والحجم — بالمليمتر داخل النطاق'),
          child: Column(
            children: [
              Row(children: [
                Expanded(
                  child: _Stepper(
                    label: tr('من البداية'),
                    value: el.xMm,
                    onDelta: (d) => widget.onMove(el.xMm + d, el.yMm),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Stepper(
                    label: tr('من أعلى'),
                    value: el.yMm,
                    onDelta: (d) => widget.onMove(el.xMm, el.yMm + d),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _Stepper(
                    label: tr('العرض'),
                    value: el.wMm,
                    step: 2,
                    onDelta: (d) => widget.onResize(el.wMm + d, el.hMm),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Stepper(
                    label: tr('الارتفاع'),
                    value: el.hMm,
                    onDelta: (d) => widget.onResize(el.wMm, el.hMm + d),
                  ),
                ),
              ]),
            ],
          ),
        ),
        _Section(
          title: tr('المظهر'),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Stepper(
                      label: tr('حجم الخط'),
                      value: el.fontSize,
                      step: 0.5,
                      decimals: 1,
                      onDelta: (d) =>
                          widget.onEdit(fontSize: el.fontSize + d),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Toggle(
                    icon: PhosphorIconsBold.textB,
                    label: tr('عريض'),
                    on: el.bold,
                    onTap: () => widget.onEdit(bold: !el.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final a in const [
                    (TextAlignSpec.start, PhosphorIconsBold.textAlignRight),
                    (TextAlignSpec.center, PhosphorIconsBold.textAlignCenter),
                    (TextAlignSpec.end, PhosphorIconsBold.textAlignLeft),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _Toggle(
                          icon: a.$2,
                          on: el.align == a.$1,
                          onTap: () => widget.onEdit(align: a.$1),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _Toggle(
                icon: el.visible
                    ? PhosphorIconsBold.eye
                    : PhosphorIconsBold.eyeSlash,
                label: el.visible ? tr('ظاهر') : tr('مخفيّ'),
                on: el.visible,
                wide: true,
                onTap: () => widget.onEdit(visible: !el.visible),
              ),
            ],
          ),
        ),
        _Section(
          title: tr('شرط الإظهار — اتركه فارغاً ليظهر دائماً'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Field(
                label: 'field op value',
                controller: _cond,
                ltr: true,
                mono: true,
                onChanged: (v) => widget.onEdit(condition: v),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final c in conditionPresets)
                    ActionChip(
                      label: Text(c,
                          style: const TextStyle(
                              fontSize: 10,
                              fontFamily: AppTypography.mono,
                              fontWeight: FontWeight.w700)),
                      onPressed: () {
                        _cond.text = c;
                        widget.onEdit(condition: c);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                tr('العنصرُ الذي لا يتحقّق شرطُه لا يُطبع ولا يترك فراغاً.'),
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    color: context.picposMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _BandProperties extends StatelessWidget {
  const _BandProperties({required this.band, required this.onEdit});

  final TemplateBand band;
  final void Function({
    double? heightMm,
    bool? repeatEachPage,
    bool? autoHeight,
    bool? visible,
  }) onEdit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        PicPosSectionHeader(
          title: tr('نطاق {p0}', {'p0': bandLabel(band.id)}),
          subtitle: _noteOf(band.id),
          icon: PhosphorIconsBold.rows,
        ),
        _Section(
          title: tr('الارتفاع بالمليمتر'),
          child: _Stepper(
            label: tr('ارتفاع النطاق'),
            value: band.heightMm,
            step: 2,
            onDelta: (d) => onEdit(heightMm: (band.heightMm + d).clamp(6, 200)),
          ),
        ),
        _Section(
          title: tr('السلوك'),
          child: Column(
            children: [
              _OptionRow(
                icon: PhosphorIconsBold.repeat,
                title: tr('تكرار على كل صفحة'),
                sub: tr('يُعاد رسمُه على كل ورقةٍ عند انقسام الجدول'),
                on: band.repeatEachPage,
                enabled: band.id == BandId.header || band.id == BandId.footer,
                disabledNote: tr('الرأسُ والتذييلُ وحدَهما يتكرّران'),
                onTap: () => onEdit(repeatEachPage: !band.repeatEachPage),
              ),
              _OptionRow(
                icon: PhosphorIconsBold.eye,
                title: tr('ظاهر'),
                sub: tr('إخفاءُ النطاق يخفي كلَّ عناصره'),
                on: band.visible,
                onTap: () => onEdit(visible: !band.visible),
              ),
              _OptionRow(
                icon: PhosphorIconsBold.arrowsInLineVertical,
                title: tr('ارتفاع تلقائي'),
                sub: tr('يتقلّص لأصغر ارتفاعٍ يسع عناصرَه'),
                on: band.autoHeight,
                onTap: () => onEdit(autoHeight: !band.autoHeight),
              ),
              _OptionRow(
                icon: PhosphorIconsBold.arrowsOutLineVertical,
                title: tr('يتمدّد بالبيانات'),
                // ⚠️ **مقفلٌ عمداً** — عقدُ الأزرار: «إيقافُه يكسر كلَّ قالبٍ
                //    فيه جدول». والضغطُ يشرح لماذا بدل أن يصمت.
                sub: band.growsWithData
                    ? tr('مقفلٌ على نطاق التفاصيل — إيقافُه يجعل الجدولَ يدهس المجاميع')
                    : tr('نطاقُ التفاصيل وحدَه يتمدّد'),
                on: band.growsWithData,
                enabled: false,
                disabledNote: tr('لا يُبدَّل — هو ما يمنع الجدولَ من دهس ما بعده'),
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _noteOf(BandId id) => switch (id) {
        BandId.header => tr('يتكرر على كل صفحة'),
        BandId.info => tr('بيانات المستند'),
        BandId.party => tr('العميل أو المورد'),
        BandId.details => tr('يتمدّد بعدد الأصناف ويدفع ما بعده'),
        BandId.totals => tr('يلتصق أسفل الجدول'),
        BandId.footer => tr('يتكرر على كل صفحة'),
      };
}

// ═══════════════════════════════════════════════════════════════════════════

class _TableProperties extends StatelessWidget {
  const _TableProperties({
    required this.table,
    required this.onToggleColumn,
    required this.onMoveColumn,
    required this.onEditColumn,
    required this.onEditTable,
  });

  final TableSpec table;
  final ValueChanged<String> onToggleColumn;
  final void Function(String, int) onMoveColumn;
  final void Function(String,
      {String? labelAr, String? labelEn, double? flex, int? decimals}) onEditColumn;
  final void Function({
    double? fontSize,
    double? headerFontSize,
    bool? bilingualHeaders,
    bool? repeatHeader,
    bool? keepRowTogether,
  }) onEditTable;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        PicPosSectionHeader(
          title: tr('جدول الأصناف'),
          subtitle: '${table.visibleColumns.length} من ${table.columns.length}'
              ' عمودٍ مُفعَّل',
          icon: PhosphorIconsBold.table,
        ),
        _Section(
          title: tr('الخطوط والعناوين'),
          child: Column(
            children: [
              Row(children: [
                Expanded(
                  child: _Stepper(
                    label: tr('خط البدن'),
                    value: table.fontSize,
                    step: 0.5,
                    decimals: 1,
                    onDelta: (d) =>
                        onEditTable(fontSize: table.fontSize + d),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Stepper(
                    label: tr('العناوين'),
                    value: table.headerFontSize,
                    step: 0.5,
                    decimals: 1,
                    onDelta: (d) =>
                        onEditTable(headerFontSize: table.headerFontSize + d),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              _OptionRow(
                icon: PhosphorIconsBold.translate,
                title: tr('عناوين ثنائية'),
                sub: tr('سطرٌ إنجليزيٌّ تحت العربي — يُطفأ تلقائياً على الحراري'),
                on: table.bilingualHeaders,
                onTap: () => onEditTable(
                    bilingualHeaders: !table.bilingualHeaders),
              ),
              _OptionRow(
                icon: PhosphorIconsBold.repeat,
                title: tr('تكرار رأس الجدول'),
                sub: tr('رؤوسُ الأعمدة تُعاد على كل صفحة'),
                on: table.repeatHeader,
                onTap: () =>
                    onEditTable(repeatHeader: !table.repeatHeader),
              ),
              _OptionRow(
                icon: PhosphorIconsBold.scissors,
                title: tr('منع قطع الصف'),
                sub: tr('الصفُّ لا ينقسم بين صفحتين'),
                on: table.keepRowTogether,
                onTap: () =>
                    onEditTable(keepRowTogether: !table.keepRowTogether),
              ),
            ],
          ),
        ),
        for (var i = 0; i < table.columns.length; i++)
          _ColumnRow(
            column: table.columns[i],
            first: i == 0,
            last: i == table.columns.length - 1,
            onToggle: () => onToggleColumn(table.columns[i].key),
            onUp: () => onMoveColumn(table.columns[i].key, -1),
            onDown: () => onMoveColumn(table.columns[i].key, 1),
            onEdit: (
                    {String? labelAr,
                    String? labelEn,
                    double? flex,
                    int? decimals}) =>
                onEditColumn(table.columns[i].key,
                    labelAr: labelAr,
                    labelEn: labelEn,
                    flex: flex,
                    decimals: decimals),
          ),
      ],
    );
  }
}

class _ColumnRow extends StatefulWidget {
  const _ColumnRow({
    required this.column,
    required this.first,
    required this.last,
    required this.onToggle,
    required this.onUp,
    required this.onDown,
    required this.onEdit,
  });

  final TableColumn column;
  final bool first;
  final bool last;
  final VoidCallback onToggle;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final void Function(
      {String? labelAr,
      String? labelEn,
      double? flex,
      int? decimals}) onEdit;

  @override
  State<_ColumnRow> createState() => _ColumnRowState();
}

class _ColumnRowState extends State<_ColumnRow> {
  late final TextEditingController _ar;
  late final TextEditingController _en;

  @override
  void initState() {
    super.initState();
    _ar = TextEditingController(text: widget.column.labelAr);
    _en = TextEditingController(text: widget.column.labelEn);
  }

  @override
  void didUpdateWidget(_ColumnRow old) {
    super.didUpdateWidget(old);
    // العمودُ يتبدّل بالترتيب لا بالمعرِّف — فالمقارنةُ على المفتاح.
    if (old.column.key == widget.column.key) return;
    _ar.text = widget.column.labelAr;
    _en.text = widget.column.labelEn;
  }

  @override
  void dispose() {
    _ar.dispose();
    _en.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.column;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.visible ? null : context.picposField,
        border: Border(top: BorderSide(color: context.picposHairline)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MiniButton(
                      icon: PhosphorIconsBold.caretUp,
                      onTap: widget.first ? null : widget.onUp),
                  _MiniButton(
                      icon: PhosphorIconsBold.caretDown,
                      onTap: widget.last ? null : widget.onDown),
                ],
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: widget.onToggle,
                child: Icon(
                  c.visible
                      ? PhosphorIconsBold.checkCircle
                      : PhosphorIconsBold.circle,
                  size: 17,
                  color: c.visible
                      ? AppColors.success
                      : context.picposMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Field(
                  label: tr('عربي'),
                  controller: _ar,
                  dense: true,
                  onChanged: (v) => widget.onEdit(labelAr: v),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _Field(
                  label: 'English',
                  controller: _en,
                  ltr: true,
                  dense: true,
                  onChanged: (v) => widget.onEdit(labelEn: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _Stepper(
                  label: tr('عرض'),
                  value: c.flex,
                  step: 0.2,
                  decimals: 1,
                  onDelta: (d) => widget.onEdit(flex: c.flex + d),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stepper(
                  label: tr('خانات'),
                  value: c.decimals.toDouble(),
                  step: 1,
                  decimals: 0,
                  onDelta: (d) =>
                      widget.onEdit(decimals: c.decimals + d.round()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// لبِناتٌ صغيرة
// ═══════════════════════════════════════════════════════════════════════════

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.picposHairline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: context.picposMuted)),
            const SizedBox(height: 9),
            child,
          ],
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.ltr = false,
    this.mono = false,
    this.dense = false,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool ltr;
  final bool mono;
  final bool dense;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        textDirection: ltr ? TextDirection.ltr : null,
        style: TextStyle(
            fontSize: dense ? 11.5 : 12,
            fontWeight: FontWeight.w700,
            fontFamily: mono ? 'monospace' : null),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          labelStyle: TextStyle(fontSize: 10, color: context.picposMuted),
          contentPadding:
              EdgeInsets.symmetric(horizontal: 10, vertical: dense ? 8 : 10),
          border: const OutlineInputBorder(),
        ),
      );
}

/// ± بخطوةٍ ثابتة — بالمليمتر أو بالنقطة.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onDelta,
    this.step = 1,
    this.decimals = 1,
  });

  final String label;
  final double value;
  final ValueChanged<double> onDelta;
  final double step;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: context.picposMuted)),
        ),
        _MiniButton(
            icon: PhosphorIconsBold.minus, onTap: () => onDelta(-step)),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(decimals),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: context.picposText),
          ),
        ),
        _MiniButton(icon: PhosphorIconsBold.plus, onTap: () => onDelta(step)),
      ],
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: context.picposHairline),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon,
              size: 11,
              color: onTap == null
                  ? context.picposHairline
                  : context.picposText),
        ),
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.on,
    required this.onTap,
    this.label,
    this.wide = false,
  });

  final IconData icon;
  final bool on;
  final VoidCallback onTap;
  final String? label;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final tone = on ? context.picposBrandInk : context.picposMuted;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 30,
        width: wide ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(
              color: on ? context.picposBrandInk : context.picposHairline,
              width: 1.5),
          color: on
              ? context.picposBrandInk.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: tone),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(label!,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: tone)),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.title,
    required this.sub,
    required this.on,
    required this.onTap,
    this.enabled = true,
    this.disabledNote,
  });

  final IconData icon;
  final String title;
  final String sub;
  final bool on;
  final VoidCallback onTap;
  final bool enabled;
  final String? disabledNote;

  @override
  Widget build(BuildContext context) {
    final tone = on ? AppColors.success : context.picposMuted;
    return InkWell(
      // ⚠️ الضغطُ على المقفول **يشرح** ولا يصمت — عقدُ الأزرار.
      onTap: enabled
          ? onTap
          : disabledNote == null
              ? null
              : () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(disabledNote!),
                      behavior: SnackBarBehavior.floating,
                    ),
                  ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.picposHairline)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: tone),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? context.picposText
                              : context.picposMuted)),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          color: context.picposMuted)),
                ],
              ),
            ),
            Icon(
              enabled
                  ? (on
                      ? PhosphorIconsBold.toggleRight
                      : PhosphorIconsBold.toggleLeft)
                  : PhosphorIconsBold.lockSimple,
              size: 17,
              color: enabled ? tone : context.picposMuted,
            ),
          ],
        ),
      ),
    );
  }
}
