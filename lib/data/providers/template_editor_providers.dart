// مزوّداتُ محرّر النماذج.
//
// ── الحالةُ مستندٌ واحدٌ لا نموذجان ──────────────────────────────────────
// [EditorState] يحمل [TemplateDocument] نفسَه الذي يذهب إلى الورق، وكلُّ
// تعديلٍ دالّةٌ خالصةٌ من `template_edits.dart` تُرجع مستنداً جديداً. فلا
// تحويلَ بين «نموذج تحرير» و«نموذج طباعة» يمكن أن ينحرف.
//
// ── والهجرةُ تقع عند أوّل فتح ─────────────────────────────────────────────
// كسولةٌ لا جماعيّة: الترقيةُ الجماعيّةُ تلمس قوالبَ قد لا يفتحها المستخدمُ
// أبداً، وأيُّ خطأٍ فيها يظهر على ورقِ عميلٍ لا على شاشة. وهي مُعادةٌ آمنة،
// فلا تزحف بالقالب خطوةً في كلِّ فتح.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/printing/print_test_scenarios.dart';
import '../../domain/printing/template_document.dart';
import '../../domain/printing/template_edits.dart';
import '../../domain/printing/template_save_result.dart';
import '../../services/printing/layout_engine.dart';
import '../../services/printing/paint_plan.dart';
import '../../services/printing/template_render_pipeline.dart';
import '../../services/templated_invoice_service.dart';
import 'repository_providers.dart';
import 'template_library_providers.dart';

/// ما هو المحدَّد الآن — عنصرٌ أو نطاقٌ أو الجدول.
enum EditorSelectionKind { none, element, band, table }

class EditorSelection {
  final EditorSelectionKind kind;
  final BandId? bandId;
  final String? elementId;

  const EditorSelection.none()
      : kind = EditorSelectionKind.none,
        bandId = null,
        elementId = null;

  const EditorSelection.element(this.bandId, this.elementId)
      : kind = EditorSelectionKind.element;

  const EditorSelection.band(this.bandId)
      : kind = EditorSelectionKind.band,
        elementId = null;

  const EditorSelection.table()
      : kind = EditorSelectionKind.table,
        bandId = BandId.details,
        elementId = null;
}

class EditorState {
  final int templateId;
  final String name;
  final TemplateDocument document;

  /// المستندُ كما قُرئ — يُقاس به «تعديلاتٌ غير محفوظة».
  final TemplateDocument saved;

  final EditorSelection selection;
  final bool snapToGrid;
  final double zoom;
  final bool previewMode;

  /// هاجر القالبُ عند هذا الفتح — يُخبَر به المستخدم مرّةً.
  final bool migratedOnOpen;

  const EditorState({
    required this.templateId,
    required this.name,
    required this.document,
    required this.saved,
    this.selection = const EditorSelection.none(),
    this.snapToGrid = true,
    this.zoom = 1.0,
    this.previewMode = false,
    this.migratedOnOpen = false,
  });

  /// ⚠️ **مقيسٌ بالمحتوى لا بعَلَمٍ يُرفع يدويّاً**: عَلَمٌ يُنسى رفعُه يجعل
  /// المستخدمَ يغادر فيفقد عملَه بلا سؤال، وعَلَمٌ يُنسى خفضُه يسأله عن
  /// تعديلٍ لم يقع.
  bool get isDirty => !_sameDocument(document, saved);

  EditorState copyWith({
    String? name,
    TemplateDocument? document,
    TemplateDocument? saved,
    EditorSelection? selection,
    bool? snapToGrid,
    double? zoom,
    bool? previewMode,
  }) =>
      EditorState(
        templateId: templateId,
        name: name ?? this.name,
        document: document ?? this.document,
        saved: saved ?? this.saved,
        selection: selection ?? this.selection,
        snapToGrid: snapToGrid ?? this.snapToGrid,
        zoom: zoom ?? this.zoom,
        previewMode: previewMode ?? this.previewMode,
        migratedOnOpen: migratedOnOpen,
      );

  /// العنصرُ المحدَّد — أو `null`.
  TemplateElement? get selectedElement {
    if (selection.kind != EditorSelectionKind.element) return null;
    for (final b in document.bands) {
      if (b.id != selection.bandId) continue;
      for (final e in b.elements) {
        if (e.id == selection.elementId) return e;
      }
    }
    return null;
  }

  TemplateBand? get selectedBand {
    if (selection.bandId == null) return null;
    for (final b in document.bands) {
      if (b.id == selection.bandId) return b;
    }
    return null;
  }
}

/// مقارنةٌ بنيويّةٌ لما يُحفَظ — لا `==` (‏المستندُ بلا مساواةِ قيمة).
bool _sameDocument(TemplateDocument a, TemplateDocument b) {
  if (a.paper.widthMm != b.paper.widthMm ||
      a.paper.heightMm != b.paper.heightMm) {
    return false;
  }
  if (a.bands.length != b.bands.length) return false;
  for (var i = 0; i < a.bands.length; i++) {
    final x = a.bands[i];
    final y = b.bands[i];
    if (x.id != y.id ||
        x.heightMm != y.heightMm ||
        x.repeatEachPage != y.repeatEachPage ||
        x.autoHeight != y.autoHeight ||
        x.visible != y.visible ||
        x.elements.length != y.elements.length) {
      return false;
    }
    for (var j = 0; j < x.elements.length; j++) {
      final p = x.elements[j];
      final q = y.elements[j];
      if (p.id != q.id ||
          p.xMm != q.xMm ||
          p.yMm != q.yMm ||
          p.wMm != q.wMm ||
          p.hMm != q.hMm ||
          p.labelAr != q.labelAr ||
          p.labelEn != q.labelEn ||
          p.fontSize != q.fontSize ||
          p.bold != q.bold ||
          p.visible != q.visible ||
          p.align != q.align ||
          (p.condition ?? '') != (q.condition ?? '')) {
        return false;
      }
    }
  }

  final ta = a.table;
  final tb = b.table;
  if ((ta == null) != (tb == null)) return false;
  if (ta == null || tb == null) return true;
  if (ta.fontSize != tb.fontSize ||
      ta.headerFontSize != tb.headerFontSize ||
      ta.bilingualHeaders != tb.bilingualHeaders ||
      ta.repeatHeader != tb.repeatHeader ||
      ta.keepRowTogether != tb.keepRowTogether ||
      ta.columns.length != tb.columns.length) {
    return false;
  }
  for (var i = 0; i < ta.columns.length; i++) {
    final p = ta.columns[i];
    final q = tb.columns[i];
    if (p.key != q.key ||
        p.labelAr != q.labelAr ||
        p.labelEn != q.labelEn ||
        p.flex != q.flex ||
        p.decimals != q.decimals ||
        p.align != q.align ||
        p.visible != q.visible ||
        p.wrap != q.wrap) {
      return false;
    }
  }
  return true;
}

/// القالبُ المفتوحُ في المحرّر.
class EditorTemplateNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int? id) => state = id;
}

final editorTemplateIdProvider =
    NotifierProvider<EditorTemplateNotifier, int?>(
        EditorTemplateNotifier.new);

/// يقرأ القالبَ ويهاجره عند الحاجة ثمّ يبني حالةَ المحرّر.
final editorInitialStateProvider =
    FutureProvider.autoDispose<EditorState?>((ref) async {
  final id = ref.watch(editorTemplateIdProvider);
  if (id == null) return null;

  final repo = ref.watch(invoiceTemplatesRepositoryProvider);

  // الهجرةُ أوّلاً: `buildDocument` تشترط أن يحمل **كلُّ** عنصرٍ إحداثيّاته،
  // وإلّا سلكت مسارَ التدفّق فبدا المستندُ نطاقاً واحداً في المحرّر.
  final migrated = await repo.migrateTemplateLayout(id);

  final data = await repo.getTemplateWithData(id);
  if (data == null) return null;

  final document = TemplateRenderPipeline.buildDocument(
    template: data.template,
    orderedElements:
        TemplatedInvoiceService.orderElementsForPrint(data.elements),
    tableSettings: data.tableSettings,
  );

  return EditorState(
    templateId: id,
    name: data.template.name,
    document: document,
    saved: document,
    migratedOnOpen: migrated,
  );
});

/// حالةُ المحرّر الحيّة — تُبذَر من [editorInitialStateProvider] ثمّ تُحرَّر.
class TemplateEditorNotifier extends Notifier<EditorState?> {
  @override
  EditorState? build() {
    // ⚠️ `listen` لا `watch`: القراءةُ تقع مرّةً عند وصول القالب. و`watch`
    //    كان يعيد البذرَ عند كلِّ تحديثٍ للمزوّد فيمحو تعديلاتِ المستخدم.
    ref.listen(editorInitialStateProvider, (_, next) {
      final s = next.value;
      if (s != null) state = s;
    });
    return ref.read(editorInitialStateProvider).value;
  }

  void _apply(TemplateDocument Function(TemplateDocument) edit) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(document: edit(s.document));
  }

  void select(EditorSelection sel) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(selection: sel);
  }

  void setZoom(double z) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(zoom: z.clamp(0.5, 3.0));
  }

  void toggleSnap() {
    final s = state;
    if (s == null) return;
    state = s.copyWith(snapToGrid: !s.snapToGrid);
  }

  void togglePreview() {
    final s = state;
    if (s == null) return;
    state = s.copyWith(
      previewMode: !s.previewMode,
      // المعاينةُ تُخفي كرومَ التحديد، فالتحديدُ يُلغى معها كي لا يعود
      // العنصرُ محدَّداً وقد اختفى إطارُه.
      selection: const EditorSelection.none(),
    );
  }

  void move(BandId band, String id, double xMm, double yMm) => _apply(
        (d) => moveElement(d,
            bandId: band,
            elementId: id,
            xMm: xMm,
            yMm: yMm,
            snap: state?.snapToGrid ?? true),
      );

  void resize(BandId band, String id, double wMm, double hMm) => _apply(
        (d) => resizeElement(d,
            bandId: band,
            elementId: id,
            wMm: wMm,
            hMm: hMm,
            snap: state?.snapToGrid ?? true),
      );

  void edit(
    BandId band,
    String id, {
    String? labelAr,
    String? labelEn,
    double? fontSize,
    bool? bold,
    bool? visible,
    TextAlignSpec? align,
    String? condition,
  }) =>
      _apply((d) => editElement(d,
          bandId: band,
          elementId: id,
          labelAr: labelAr,
          labelEn: labelEn,
          fontSize: fontSize,
          bold: bold,
          visible: visible,
          align: align,
          condition: condition));

  void remove(BandId band, String id) {
    _apply((d) => removeElement(d, bandId: band, elementId: id));
    select(EditorSelection.band(band));
  }

  /// يضيف حقلاً من المكتبة إلى النطاق المحدَّد (أو الرأس حين لا تحديد).
  void addField(String contentKey, {String? labelAr, ElementKind? kind}) {
    final s = state;
    if (s == null) return;
    final band = s.selection.bandId ?? BandId.header;
    // معرِّفٌ لا يصطدم بمعرِّفات الصفوف — الصفُّ لم يُكتب بعد.
    final id = 'new:$contentKey:${DateTime.now().microsecondsSinceEpoch}';
    _apply((d) => addElement(d,
        bandId: band,
        id: id,
        contentKey: contentKey,
        labelAr: labelAr,
        kind: kind ?? ElementKind.text));
    select(EditorSelection.element(band, id));
  }

  void band(BandId id,
          {double? heightMm,
          bool? repeatEachPage,
          bool? autoHeight,
          bool? visible}) =>
      _apply((d) => editBand(d,
          bandId: id,
          heightMm: heightMm,
          repeatEachPage: repeatEachPage,
          autoHeight: autoHeight,
          visible: visible));

  void columnToggle(String key) => _apply((d) => toggleColumn(d, key));
  void columnMove(String key, int delta) =>
      _apply((d) => moveColumn(d, key, delta));
  void columnEdit(String key,
          {String? labelAr,
          String? labelEn,
          double? flex,
          int? decimals,
          bool? wrap}) =>
      _apply((d) => editColumn(d, key,
          labelAr: labelAr,
          labelEn: labelEn,
          flex: flex,
          decimals: decimals,
          wrap: wrap));

  void table({
    double? fontSize,
    double? headerFontSize,
    bool? bilingualHeaders,
    bool? repeatHeader,
    bool? keepRowTogether,
  }) =>
      _apply((d) => editTable(d,
          fontSize: fontSize,
          headerFontSize: headerFontSize,
          bilingualHeaders: bilingualHeaders,
          repeatHeader: repeatHeader,
          keepRowTogether: keepRowTogether));

  void paper({required double widthMm, double? heightMm}) =>
      _apply((d) => setPaper(d, widthMm: widthMm, heightMm: heightMm));

  /// يحفظ في معاملةٍ واحدة، ويُفعّل عند تمرير نوع المستند.
  ///
  /// ويُبطل ذاكرةَ المكتبة بعده: «بدونه يعدّل المستخدمُ ويرى القديم، فيظنّ
  /// أنّ الحفظَ لم يعمل — وهو أسوأُ عطبٍ ممكن».
  Future<TemplateSaveResult?> save({String? activateForDocumentType}) async {
    final s = state;
    if (s == null) return null;

    final result = await ref
        .read(invoiceTemplatesRepositoryProvider)
        .saveTemplateLayout(
          templateId: s.templateId,
          document: s.document,
          activateForDocumentType: activateForDocumentType,
          activateLocale: activateForDocumentType == null ? null : 'ar',
        );

    // ما حُفظ صار هو الأساسَ — فتختفي شارةُ «تعديلاتٌ غير محفوظة».
    state = s.copyWith(saved: s.document);
    ref.read(templateLibraryRefreshProvider.notifier).bump();
    return result;
  }
}

final templateEditorProvider =
    NotifierProvider<TemplateEditorNotifier, EditorState?>(
        TemplateEditorNotifier.new);

// ═══════════════════════════════════════════════════════════════════════════

/// حمولةُ العيّنة في المحرّر — أوّلُ حالةِ اختبارٍ، فما يُرى هنا هو ما تراه
/// المعاينةُ التجريبيّةُ بلا مفاجأة.
final _sampleScenario = buildPrintScenarios().first;

/// القيمُ المحلولةُ للعرض على الكانفاس.
///
/// ⚠️ **من `buildValues` نفسِها**: قائمةٌ ثانيةٌ من العيّنات تجعل المحرّرَ
/// يعرض نصّاً والراسمَ يعرض غيرَه.
final editorSampleValuesProvider =
    Provider.autoDispose<Map<String, String>>((ref) {
  final s = ref.watch(templateEditorProvider);
  if (s == null) return const {};
  return TemplateRenderPipeline.buildValues(
      s.document, _sampleScenario.payload);
});

/// صفوفُ العيّنة لجدولِ الكانفاس — **بالمحرّك نفسِه** الذي يطبع.
///
/// ولا تُكتب بيانةٌ ثابتةٌ بجانب الواجهة: عمودٌ يُضاف أو تُغيَّر منازلُه
/// كان سيظهر في المعاينة ولا يظهر في الكانفاس، فيصير الاثنان قالبَين.
final editorSampleRowsProvider =
    Provider.autoDispose<List<List<String>>>((ref) {
  final s = ref.watch(templateEditorProvider);
  if (s == null) return const [];
  return TemplateRenderPipeline.buildRows(
      _sampleScenario.items, s.document.table, 2);
});

/// صفحاتُ المعاينة — بالمحرّك نفسِه الذي يطبع.
final editorPreviewPagesProvider =
    Provider.autoDispose<List<({double widthMm, double heightMm, List<PaintOp> ops, int number, int count})>>(
        (ref) {
  final s = ref.watch(templateEditorProvider);
  if (s == null) return const [];
  try {
    final pages = LayoutEngine.paginate(
      document: s.document,
      rows: TemplateRenderPipeline.buildRows(
          _sampleScenario.items, s.document.table, 2),
      values: TemplateRenderPipeline.buildValues(
          s.document, _sampleScenario.payload),
    );
    return [
      for (final p in pages)
        (
          widthMm: p.widthMm,
          heightMm: p.heightMm,
          ops: planPage(p),
          number: p.pageNumber,
          count: p.pageCount,
        ),
    ];
  } catch (_) {
    // معاينةٌ منهارةٌ لا تُسقط المحرّرَ ومعه عملُ المستخدم.
    return const [];
  }
});
