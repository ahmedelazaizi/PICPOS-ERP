// مزوّداتُ «قماش الملصق» في محرّر النماذج.
//
// الحالةُ تصميمٌ واحدٌ ([LabelDesign]) هو نفسُه ما يُكتب في الصفوف التي
// يقرؤها راسمُ الملصقات — فلا تحويلَ بين «نموذج تحرير» و«نموذج طباعة».
// وكلُّ تعديلٍ دالّةٌ خالصةٌ من `label_design.dart`.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/printing/label_design.dart';
import '../../services/printing/label_paint_plan.dart';
import '../../services/printing/paint_plan.dart';
import 'repository_providers.dart';
import 'template_library_providers.dart';

class LabelEditorState {
  final LabelDesign design;

  /// التصميمُ كما قُرئ أو حُفظ — يُقاس به «تعديلاتٌ غير محفوظة».
  final LabelDesign saved;

  final String? selectedKey;
  final bool snapToGrid;
  final double zoom;
  final bool previewMode;

  const LabelEditorState({
    required this.design,
    required this.saved,
    this.selectedKey,
    this.snapToGrid = true,
    this.zoom = 1.0,
    this.previewMode = false,
  });

  /// مقيسٌ بالمحتوى لا بعَلَم — نفسُ قاعدة محرّر النطاقات.
  bool get isDirty => design != saved;

  LabelElement? get selected => design.byKey(selectedKey);

  LabelEditorState copyWith({
    LabelDesign? design,
    LabelDesign? saved,
    String? selectedKey,
    bool clearSelection = false,
    bool? snapToGrid,
    double? zoom,
    bool? previewMode,
  }) =>
      LabelEditorState(
        design: design ?? this.design,
        saved: saved ?? this.saved,
        selectedKey: clearSelection ? null : (selectedKey ?? this.selectedKey),
        snapToGrid: snapToGrid ?? this.snapToGrid,
        zoom: zoom ?? this.zoom,
        previewMode: previewMode ?? this.previewMode,
      );
}

/// حالةُ قماش الملصق — `null` قبل التحميل أو حين لا ملصق.
class LabelEditorNotifier extends Notifier<LabelEditorState?> {
  @override
  LabelEditorState? build() => null;

  /// يقرأ الملصقَ ويُرجع `false` حين لا يوجد أو ليس من فئة `barcode`.
  Future<bool> load(int templateId) async {
    final d =
        await ref.read(invoiceTemplatesRepositoryProvider).getLabelDesign(templateId);
    if (!ref.mounted) return false;
    state = d == null ? null : LabelEditorState(design: d, saved: d);
    return d != null;
  }

  void _set(LabelDesign Function(LabelDesign) f) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(design: f(s.design));
  }

  void select(String? key) {
    final s = state;
    if (s == null) return;
    state = key == null
        ? s.copyWith(clearSelection: true)
        : s.copyWith(selectedKey: key);
  }

  void setZoom(double z) =>
      state = state?.copyWith(zoom: z.clamp(0.5, 3.0).toDouble());
  void toggleSnap() => state = state?.copyWith(snapToGrid: !state!.snapToGrid);
  void togglePreview() =>
      state = state?.copyWith(previewMode: !state!.previewMode);

  void move(String key, double xMm, double yMm) => _set((d) =>
      moveLabelElement(d, key, xMm, yMm, snap: state!.snapToGrid));

  void resize(String key, double wMm, double hMm) => _set((d) =>
      resizeLabelElement(d, key, wMm, hMm, snap: state!.snapToGrid));

  void edit(
    String key, {
    double? fontSize,
    bool? bold,
    bool? italic,
    String? align,
    String? color,
    String? content,
    double? borderWidth,
  }) =>
      _set((d) => editLabelElement(d, key,
          fontSize: fontSize,
          bold: bold,
          italic: italic,
          align: align,
          color: color,
          content: content,
          borderWidth: borderWidth));

  void add(String type, {String? content}) {
    final s = state;
    if (s == null) return;
    final (d, key) = addLabelElement(s.design, type, content: content);
    state = s.copyWith(design: d, selectedKey: key);
  }

  void remove(String key) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(
        design: removeLabelElement(s.design, key), clearSelection: true);
  }

  void rename(String name) => _set((d) => d.copyWith(name: name));

  void labelSize({double? widthMm, double? heightMm}) =>
      _set((d) => resizeLabel(d, widthMm: widthMm, heightMm: heightMm));

  /// يحفظ ويُعيد قراءةَ الملصق (‏معرِّفاتُ الجديد) ويُبطل ذاكرةَ المكتبة.
  Future<LabelDesign?> save() async {
    final s = state;
    if (s == null) return null;
    final saved =
        await ref.read(invoiceTemplatesRepositoryProvider).saveLabelDesign(s.design);
    if (!ref.mounted) return saved;
    final current = state;
    if (current != null) {
      // التحديدُ يُتبع بموضعه: المفتاحُ الجديدُ `n…` صار `e<id>`.
      String? key;
      final idx = current.design.elements
          .indexWhere((e) => e.key == current.selectedKey);
      if (idx >= 0 && idx < saved.elements.length) {
        key = saved.elements[idx].key;
      }
      state = LabelEditorState(
        design: saved,
        saved: saved,
        selectedKey: key,
        snapToGrid: current.snapToGrid,
        zoom: current.zoom,
        previewMode: current.previewMode,
      );
    }
    ref.read(templateLibraryRefreshProvider.notifier).bump();
    return saved;
  }
}

final labelEditorProvider =
    NotifierProvider.autoDispose<LabelEditorNotifier, LabelEditorState?>(
        LabelEditorNotifier.new);

/// عمليّاتُ رسم المعاينة — بخطّة الملصق نفسِها التي تبني مصغَّرةَ المكتبة.
final labelPreviewOpsProvider = Provider.autoDispose<List<PaintOp>>((ref) {
  final s = ref.watch(labelEditorProvider);
  if (s == null) return const [];
  return labelPaintOps(s.design);
});
