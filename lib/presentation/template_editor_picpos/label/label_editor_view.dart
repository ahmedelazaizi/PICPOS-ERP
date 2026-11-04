import 'package:picpos_erp/core/i18n/tr.dart';
// «قماشُ الملصق» — وضعُ محرّر النماذج لقوالب فئة `barcode`.
//
// ── ما يحلّه ──────────────────────────────────────────────────────────────
// المكتبةُ كانت تستبعد الملصقات والمحرّرُ لا يخدمها، فبقي المصمّمُ القديمُ
// الطريقَ الوحيدَ إليها — وهو يعرضها تدفّقاً بلا إحداثيّاتٍ ويُدرج عناصرَ
// لا يرسمها راسمُ الملصقات. هنا قماشٌ حرٌّ بالمليمتر **يكتب الأعمدةَ التي
// يقرؤها الراسم** (‏`label_layout_writer.dart`).
//
// ── والمعاينةُ بخطّة الملصق، لا براسمٍ ثانٍ ───────────────────────────────
// `labelPaintOps` تترجم فرعَ الراسم إلى [PaintOp]، وتعرضها [SheetPreviewView]
// المشتركةُ مع شاشة الطباعة التجريبيّة ومحرّر النطاقات.
//
// ⚠️ **ولا استيرادَ لـ`data/database`** — حارسُ `presentation_db_import_guard`.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/label_editor_providers.dart';
import '../../../data/providers/repository_providers.dart';
import '../../../data/providers/template_library_providers.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../print_test_picpos/widgets/sheet_preview_view.dart';
import '../widgets/editor_panel_parts.dart';
import 'label_canvas.dart';
import 'label_elements_panel.dart';
import 'label_properties_panel.dart';
import 'template_json_file.dart';

const double _sideWidth = 300;
const double _propsWidth = 340;

/// تحتَه تُطوى لوحةُ العناصر وتبقى الورقةُ والخصائص.
const double _threePaneMinWidth = 1180;

class LabelEditorView extends ConsumerStatefulWidget {
  const LabelEditorView({super.key, required this.templateId});

  final int templateId;

  @override
  ConsumerState<LabelEditorView> createState() => _LabelEditorViewState();
}

class _LabelEditorViewState extends ConsumerState<LabelEditorView> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref.read(labelEditorProvider.notifier).load(widget.templateId);
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(labelEditorProvider);
    final editor = ref.read(labelEditorProvider.notifier);

    if (state == null) {
      return PicPosScreenScaffold(
        title: tr('محرّر الملصقات'),
        icon: PhosphorIconsBold.barcode,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : PicPosEmptyState(
                icon: PhosphorIconsBold.warning,
                title: tr('تعذّر فتحُ القالب'),
                hint: tr('ليس ملصقَ باركود أو غيرُ موجود'),
              ),
      );
    }

    final d = state.design;
    return PicPosScreenScaffold(
      title: d.name,
      subtitle: tr('ملصق باركود · {w}×{h}مم · {n} عنصراً', {
        'w': d.widthMm.toStringAsFixed(0),
        'h': d.heightMm.toStringAsFixed(0),
        'n': d.elements.length,
      }),
      icon: PhosphorIconsBold.barcode,
      headerActions: [
        if (state.isDirty)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: EditorBadge(
                label: tr('تعديلات غير محفوظة'), tone: AppColors.warning),
          ),
        OutlinedButton.icon(
          key: const Key('label-export'),
          onPressed: () => _export(editor, state),
          icon: const Icon(PhosphorIconsBold.export, size: 16),
          label: Text(tr('تصدير JSON')),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          key: const Key('label-import'),
          onPressed: _import,
          icon: const Icon(PhosphorIconsBold.downloadSimple, size: 16),
          label: Text(tr('استيراد JSON')),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const Key('label-save'),
          onPressed: () => _save(editor),
          icon: const Icon(PhosphorIconsBold.floppyDisk, size: 16),
          label: Text(tr('حفظ')),
        ),
      ],
      subHeader: _Toolbar(state: state, editor: editor),
      body: LayoutBuilder(
        builder: (context, box) {
          final canvas = state.previewMode
              ? _Preview(state: state)
              : LabelCanvas(
                  design: d,
                  zoom: state.zoom,
                  showGrid: state.snapToGrid,
                  selectedKey: state.selectedKey,
                  onSelect: editor.select,
                  onMove: editor.move,
                  onResize: editor.resize,
                );
          final props = SizedBox(
            width: _propsWidth,
            child: PicPosContentCard(
              child: LabelPropertiesPanel(state: state, editor: editor),
            ),
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (box.maxWidth >= _threePaneMinWidth) ...[
                SizedBox(
                  width: _sideWidth,
                  child: PicPosContentCard(
                    child: LabelElementsPanel(
                      design: d,
                      selectedKey: state.selectedKey,
                      onAdd: editor.add,
                      onSelect: editor.select,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: PicPosContentCard(child: canvas)),
              const SizedBox(width: 12),
              props,
            ],
          );
        },
      ),
    );
  }

  Future<void> _save(LabelEditorNotifier editor) async {
    try {
      final saved = await editor.save();
      if (!mounted || saved == null) return;
      AppToast.show(
        context,
        tr('حُفظ الملصق — {p0} عنصراً بإحداثيّات الطباعة', {'p0': saved.elements.length}),
        type: ToastType.success,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('تعذّر الحفظ: {e}', {'e': e}),
            type: ToastType.error);
      }
    }
  }

  /// التصديرُ يقرأ من القاعدة — فيُحفظ أوّلاً كما كان يفعل المصمّمُ القديم.
  Future<void> _export(
      LabelEditorNotifier editor, LabelEditorState state) async {
    try {
      if (state.isDirty) await editor.save();
      final repo = ref.read(invoiceTemplatesRepositoryProvider);
      final json = await repo.exportTemplateToJson(state.design.templateId);
      final ok = await saveTemplateJsonFile(
        dialogTitle: tr('تصدير الملصق'),
        baseName: state.design.name,
        json: json,
      );
      if (ok && mounted) {
        AppToast.show(context, tr('تم تصدير "{p0}" بنجاح!', {'p0': state.design.name}),
            type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ في التصدير: {e}', {'e': e}),
            type: ToastType.error);
      }
    }
  }

  /// الاستيرادُ يُنشئ ملصقاً جديداً ويفتحه — ولا يقبل إلّا ملفَّ ملصق.
  Future<void> _import() async {
    try {
      final json = await pickTemplateJsonFile(dialogTitle: tr('استيراد ملصق'));
      if (json == null) return;
      final data = jsonDecode(json) as Map<String, dynamic>;
      if (data['templateCategory'] != 'barcode' || data['elements'] is! List) {
        if (mounted) {
          AppToast.show(context, tr('الملفُّ ليس ملصقَ باركود'),
              type: ToastType.error);
        }
        return;
      }
      final repo = ref.read(invoiceTemplatesRepositoryProvider);
      final id = await repo.importTemplateFromJson(json);
      ref.read(templateLibraryRefreshProvider.notifier).bump();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => LabelEditorView(templateId: id),
      ));
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ في الاستيراد: {e}', {'e': e}),
            type: ToastType.error);
      }
    }
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.state, required this.editor});

  final LabelEditorState state;
  final LabelEditorNotifier editor;

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
          EditorChip(
            icon: PhosphorIconsBold.minus,
            on: false,
            onTap: () => editor.setZoom(state.zoom - 0.25),
          ),
          Text(tr('{p0}٪', {'p0': (state.zoom * 100).round()}),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: context.picposText)),
          EditorChip(
            icon: PhosphorIconsBold.plus,
            on: false,
            onTap: () => editor.setZoom(state.zoom + 0.25),
          ),
          const SizedBox(width: 6),
          EditorChip(
            icon: PhosphorIconsBold.gridNine,
            label: tr('محاذاة للشبكة'),
            on: state.snapToGrid,
            onTap: editor.toggleSnap,
          ),
          EditorChip(
            key: const Key('label-preview-toggle'),
            icon: state.previewMode
                ? PhosphorIconsBold.pencilSimple
                : PhosphorIconsBold.eye,
            label: state.previewMode ? tr('عودة للتحرير') : tr('معاينة الملصق'),
            on: state.previewMode,
            onTap: editor.togglePreview,
          ),
        ],
      ),
    );
  }
}

/// المعاينةُ بخطّة الملصق — عيّنةٌ ثابتةٌ بالقيم التي يمرّرها مستدعي الطباعة.
class _Preview extends ConsumerWidget {
  const _Preview({required this.state});

  final LabelEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = ref.watch(labelPreviewOpsProvider);
    final d = state.design;
    return Container(
      color: context.picposIsDark
          ? const Color(0xFF060C16)
          : const Color(0xFFE2E8F2),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SheetPreviewView(
          key: const Key('label-preview'),
          widthMm: d.widthMm,
          heightMm: d.heightMm,
          ops: ops,
          zoom: 2.5 * state.zoom,
          caption: tr('معاينة الملصق — {w}×{h}مم', {
            'w': d.widthMm.toStringAsFixed(0),
            'h': d.heightMm.toStringAsFixed(0),
          }),
        ),
      ),
    );
  }
}
