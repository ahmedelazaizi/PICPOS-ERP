import 'package:ural_erp/core/i18n/tr.dart';
// محرّرُ النماذج — تصميمُ `PicPos Template Editor.dc.html`.
//
// ── ما يحلّه ──────────────────────────────────────────────────────────────
// السطحُ القائمُ يحفظ `xPosition`/`yPosition` والراسمُ **يتجاهلهما**، فيضبط
// المستخدمُ موضعاً ويطبع فيجده في مكانٍ آخر. وهنا يحمل المحرّرُ
// [TemplateDocument] نفسَه الذي يذهب إلى الورق، فما يُحرَّك يُطبع.
//
// ── و«معاينةٌ بالبيانات» ليست راسماً ثانياً ──────────────────────────────
// عقدُ الأزرار: «إن رُسمت براسمٍ ثانٍ عاد عطبُ ‹المعاينة ≠ الورق›. نفسُ
// `PositionedPage`». فوضعُ المعاينة هنا يستدعي `LayoutEngine.paginate` ثمّ
// `planPage` — عينَ ما يستهلكه راسمُ الـPDF — ويعرضه بـ[SheetPreviewView]
// المشتركة مع شاشة الطباعة التجريبيّة.
//
// ⚠️ **ولا استيرادَ لـ`data/database`** — حارسُ `presentation_db_import_guard`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/template_editor_providers.dart';
import '../../../domain/printing/template_document.dart';
import '../../../services/printing/template_resolver.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../print_test_picpos/widgets/sheet_preview_view.dart';
import '../widgets/editor_canvas.dart';
import '../widgets/editor_outline_panel.dart';
import '../widgets/editor_properties_panel.dart';

const double _outlineWidth = 300;
const double _propertiesWidth = 376;

/// تحتَه تُطوى اللوحتان وتبقى الورقةُ — الكانفاسُ لا يقلّ عن ٦٠٠ مقروءاً.
const double _threePaneMinWidth = 1360;

/// مقاساتُ الورق في شريط الأدوات — نفسُ التصميم.
const _papers = <({String label, double w, double? h})>[
  (label: 'A4', w: 210, h: 297),
  (label: 'A5', w: 148, h: 210),
  (label: '80mm', w: 80, h: null),
  (label: '58mm', w: 58, h: null),
];

class TemplateEditorPicposScreen extends ConsumerStatefulWidget {
  const TemplateEditorPicposScreen({super.key, required this.templateId});

  final int templateId;

  @override
  ConsumerState<TemplateEditorPicposScreen> createState() =>
      _TemplateEditorPicposScreenState();
}

class _TemplateEditorPicposScreenState
    extends ConsumerState<TemplateEditorPicposScreen> {
  bool _announcedMigration = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(editorTemplateIdProvider.notifier).set(widget.templateId);
    });
  }

  @override
  Widget build(BuildContext context) {
    // يُبقي المزوِّدَ الأساسَ حيّاً كي تُبذَر الحالةُ عند وصوله.
    final initial = ref.watch(editorInitialStateProvider);
    final state = ref.watch(templateEditorProvider);
    final editor = ref.read(templateEditorProvider.notifier);

    if (initial.isLoading && state == null) {
      return  PicPosScreenScaffold(
        title: tr('محرّر النماذج'),
        icon: PhosphorIconsBold.layout,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state == null) {
      return PicPosScreenScaffold(
        title: tr('محرّر النماذج'),
        icon: PhosphorIconsBold.layout,
        body: PicPosEmptyState(
          icon: PhosphorIconsBold.warning,
          title: tr('تعذّر فتحُ القالب'),
          hint: initial.hasError ? '${initial.error}' : tr('القالبُ غيرُ موجود'),
        ),
      );
    }

    // الهجرةُ تُخبَر مرّةً: القالبُ اكتسب إحداثيّاتٍ ولم يتغيّر مطبوعُه.
    if (state.migratedOnOpen && !_announcedMigration) {
      _announcedMigration = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppToast.show(
          context,
          tr('هوجر القالبُ إلى النطاقات — صار قابلاً للتحريك، ومطبوعُه كما كان'),
          type: ToastType.info,
        );
      });
    }

    return PicPosScreenScaffold(
      title: state.name,
      subtitle: _metaOf(state),
      icon: PhosphorIconsBold.layout,
      headerActions: [
        if (state.isDirty)
           Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: _Badge(
              label: tr('تعديلات غير محفوظة'),
              tone: AppColors.warning,
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => _save(editor, activate: false),
          icon: const Icon(PhosphorIconsBold.floppyDisk, size: 16),
          label:  Text(tr('حفظ')),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () => _saveAndActivate(editor, state),
          icon: const Icon(PhosphorIconsBold.checkCircle, size: 16),
          label:  Text(tr('حفظ وتفعيل كافتراضي')),
        ),
      ],
      subHeader: _Toolbar(state: state, editor: editor),
      body: LayoutBuilder(
        builder: (context, box) {
          final canvas = state.previewMode
              ? const _PreviewPane()
              : _CanvasPane(state: state, editor: editor);

          if (box.maxWidth < _threePaneMinWidth) {
            return PicPosContentCard(child: canvas);
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _outlineWidth,
                child: PicPosContentCard(
                  child: EditorOutlinePanel(
                    document: state.document,
                    selectedBand: state.selection.bandId,
                    selectedElement: state.selection.elementId,
                    onSelectBand: (b) =>
                        editor.select(EditorSelection.band(b)),
                    onSelectElement: (b, id) =>
                        editor.select(EditorSelection.element(b, id)),
                    onToggleVisible: (b, id, v) =>
                        editor.edit(b, id, visible: v),
                    onAddField: (key, label, kind) =>
                        editor.addField(key, labelAr: label, kind: kind),
                    onSelectTable: () =>
                        editor.select(const EditorSelection.table()),
                    tableSelected:
                        state.selection.kind == EditorSelectionKind.table,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: PicPosContentCard(child: canvas)),
              const SizedBox(width: 12),
              SizedBox(
                width: _propertiesWidth,
                child: PicPosContentCard(
                  child: EditorPropertiesPanel(
                    document: state.document,
                    element: state.selectedElement,
                    band: state.selectedBand,
                    showTable:
                        state.selection.kind == EditorSelectionKind.table,
                    onEditElement: ({
                      String? labelAr,
                      String? labelEn,
                      double? fontSize,
                      bool? bold,
                      bool? visible,
                      TextAlignSpec? align,
                      String? condition,
                    }) =>
                        editor.edit(
                      state.selection.bandId!,
                      state.selection.elementId!,
                      labelAr: labelAr,
                      labelEn: labelEn,
                      fontSize: fontSize,
                      bold: bold,
                      visible: visible,
                      align: align,
                      condition: condition,
                    ),
                    onMoveElement: (x, y) => editor.move(
                        state.selection.bandId!,
                        state.selection.elementId!,
                        x,
                        y),
                    onResizeElement: (w, h) => editor.resize(
                        state.selection.bandId!,
                        state.selection.elementId!,
                        w,
                        h),
                    onRemoveElement: () => editor.remove(
                        state.selection.bandId!, state.selection.elementId!),
                    onEditBand: ({
                      double? heightMm,
                      bool? repeatEachPage,
                      bool? autoHeight,
                      bool? visible,
                    }) =>
                        editor.band(
                      state.selection.bandId!,
                      heightMm: heightMm,
                      repeatEachPage: repeatEachPage,
                      autoHeight: autoHeight,
                      visible: visible,
                    ),
                    onToggleColumn: editor.columnToggle,
                    onMoveColumn: editor.columnMove,
                    onEditColumn: (key,
                            {String? labelAr,
                            String? labelEn,
                            double? flex,
                            int? decimals}) =>
                        editor.columnEdit(key,
                            labelAr: labelAr,
                            labelEn: labelEn,
                            flex: flex,
                            decimals: decimals),
                    onEditTable: ({
                      double? fontSize,
                      double? headerFontSize,
                      bool? bilingualHeaders,
                      bool? repeatHeader,
                      bool? keepRowTogether,
                    }) =>
                        editor.table(
                      fontSize: fontSize,
                      headerFontSize: headerFontSize,
                      bilingualHeaders: bilingualHeaders,
                      repeatHeader: repeatHeader,
                      keepRowTogether: keepRowTogether,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _metaOf(EditorState s) {
    final elements =
        s.document.bands.fold<int>(0, (a, b) => a + b.elements.length);
    final cols = s.document.table?.visibleColumns.length ?? 0;
    final paper = s.document.paper;
    return tr('{p0}مم · {elements} عنصراً · {cols} عمود', {'p0': paper.widthMm.toStringAsFixed(0), 'elements': elements, 'cols': cols});
  }

  Future<void> _save(TemplateEditorNotifier editor,
      {required bool activate, String? documentType}) async {
    try {
      final r = await editor.save(
          activateForDocumentType: activate ? documentType : null);
      if (!mounted || r == null) return;

      final lines = <String>[
        tr('كُتب {p0} عنصراً و{p1} عموداً', {'p0': r.elementCount, 'p1': r.visibleColumnCount}),
        if (r.activated) tr('وأُنشئت الرابطة — الطباعةُ التالية تقرأ هذه النسخة'),
        // ⚠️ الإلغاءُ **يُقال**: صامتاً يجعل المستخدمَ يظنّ قالبين مفعّلَين.
        if (r.cancelledDocumentTypes.isNotEmpty)
          tr('وأُلغيت رابطةُ: {p0}', {'p0': r.cancelledDocumentTypes.join('، ')}),
      ];
      AppToast.show(context, lines.join(' · '), type: ToastType.success);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('تعذّر الحفظ: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  Future<void> _saveAndActivate(
      TemplateEditorNotifier editor, EditorState state) async {
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title:  Text(tr('تفعيل كافتراضي لأيِّ مستند؟')),
          children: [
            for (final t in TemplateResolver.documentTypes)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, t),
                child: Row(
                  children: [
                    Expanded(child: Text(_documentLabel(t))),
                    if (!TemplateResolver.wiredDocumentTypes.contains(t))
                       Text(tr('بانتظار التوصيل'),
                          style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warning)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (type == null) return;
    await _save(editor, activate: true, documentType: type);
  }
}

String _documentLabel(String type) =>  {
      'sales_invoice': tr('فاتورة مبيعات'),
      'sales_return': tr('مرتجع مبيعات'),
      'purchase_invoice': tr('فاتورة مشتريات'),
      'purchase_return': tr('مرتجع مشتريات'),
      'sales_receipt': tr('إيصال بيع'),
      'quotation': tr('عرض سعر'),
      'kitchen_order': tr('طلب مطبخ'),
      'shift_closing': tr('إقفال وردية'),
      'party_statement': tr('كشف حساب'),
      'report': tr('تقرير'),
    }[type] ??
    type;

// ═══════════════════════════════════════════════════════════════════════════

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.state, required this.editor});

  final EditorState state;
  final TemplateEditorNotifier editor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final p in _papers)
            _Chip(
              label: p.label,
              on: state.document.paper.widthMm == p.w,
              onTap: () => editor.paper(widthMm: p.w, heightMm: p.h),
            ),
          const SizedBox(width: 6),
          _Chip(
            icon: PhosphorIconsBold.minus,
            on: false,
            onTap: () => editor.setZoom(state.zoom - 0.25),
          ),
          Text(tr('{p0}٪', {'p0': (state.zoom * 100).round()}),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: context.picposText)),
          _Chip(
            icon: PhosphorIconsBold.plus,
            on: false,
            onTap: () => editor.setZoom(state.zoom + 0.25),
          ),
          const SizedBox(width: 6),
          _Chip(
            icon: PhosphorIconsBold.gridNine,
            label: tr('محاذاة للشبكة'),
            on: state.snapToGrid,
            onTap: editor.toggleSnap,
          ),
          _Chip(
            icon: state.previewMode
                ? PhosphorIconsBold.pencilSimple
                : PhosphorIconsBold.eye,
            label: state.previewMode ? tr('عودة للتحرير') : tr('معاينة بالبيانات'),
            on: state.previewMode,
            onTap: editor.togglePreview,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.on,
    required this.onTap,
    this.label,
    this.icon,
  });

  final bool on;
  final VoidCallback onTap;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tone = on ? context.picposBrandInk : context.picposMuted;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          border: Border.all(
              color: on ? context.picposBrandInk : context.picposHairline,
              width: 1.5),
          color: on
              ? context.picposBrandInk.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: 13, color: tone),
            if (icon != null && label != null) const SizedBox(width: 5),
            if (label != null)
              Text(label!,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: tone)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: tone)),
      );
}

class _CanvasPane extends ConsumerWidget {
  const _CanvasPane({required this.state, required this.editor});

  final EditorState state;
  final TemplateEditorNotifier editor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: context.picposIsDark
          ? const Color(0xFF060C16)
          : const Color(0xFFE2E8F2),
      child: EditorCanvas(
        document: state.document,
        values: ref.watch(editorSampleValuesProvider),
        rows: ref.watch(editorSampleRowsProvider),
        zoom: state.zoom,
        showGrid: state.snapToGrid,
        selectedBand: state.selection.bandId,
        selectedElement: state.selection.elementId,
        onSelectBand: (b) => editor.select(EditorSelection.band(b)),
        onSelectElement: (b, id) =>
            editor.select(EditorSelection.element(b, id)),
        onSelectTable: () => editor.select(const EditorSelection.table()),
        onMove: editor.move,
        onResize: editor.resize,
      ),
    );
  }
}

/// وضعُ المعاينة — **بالمحرّك نفسِه**، لا راسمَ ثانٍ.
class _PreviewPane extends ConsumerWidget {
  const _PreviewPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref.watch(editorPreviewPagesProvider);

    if (pages.isEmpty) {
      return  PicPosEmptyState(
        icon: PhosphorIconsBold.warningOctagon,
        title: tr('لم تنتج الورقةُ صفحةً'),
        hint: tr('القالبُ بلا عناصرَ ظاهرة، أو الحسابُ انهار'),
      );
    }

    return Container(
      color: context.picposIsDark
          ? const Color(0xFF060C16)
          : const Color(0xFFE2E8F2),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final p in pages) ...[
                SheetPreviewView(
                  widthMm: p.widthMm,
                  heightMm: p.heightMm,
                  ops: p.ops,
                  caption: tr('صفحة {p0} من {p1}', {'p0': p.number, 'p1': p.count}),
                ),
                const SizedBox(width: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
