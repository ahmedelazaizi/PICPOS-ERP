// قراءةُ ملصق الباركود وحفظُه من المحرّر — **بأعمدة الراسم نفسِها**.
//
// ── العقد ────────────────────────────────────────────────────────────────
// راسمُ الملصقات (`template_barcode_labels.dart`) يقرأ من الصفّ:
//   القالب:  `paper_width` · `paper_height` (الاحتياطُ ٢٥ حين يغيب)
//   العنصر:  `element_type` · `x_position` · `y_position` · `width` ·
//            `height` (مليمتراتٌ من يسار الملصق) · `font_size` · `is_bold` ·
//            `is_italic` · `font_color` · `text_align` · `content` ·
//            `border_width`
// ولا يقرأ `layout_version` ولا `x_mm` ولا `band_id`. فالحفظُ هنا:
//
//   ١ · UPDATE invoice_templates  (الاسم · الورق) — **و`layout_version` لا يُلمس**
//   ٢ · DELETE ما حُذف من العناصر بمعرِّفاته
//   ٣ · UPDATE الباقي بمعرِّفه — فأعمدتُه الأخرى (‏`label_ar`، `section`…)
//       تبقى كما كانت
//   ٤ · INSERT الجديد
//
// كلُّه في معاملةٍ واحدة: انقطاعٌ بين الحذف والكتابة يترك ملصقاً ناقصاً.
//
// ⚠️ **ولا هجرةَ إلى النطاقات**: `TemplateMigration` يكتب `x_mm` ويرفع
// النسخةَ إلى ٢، والراسمُ لا يرى أيّاً منهما — فما يُحرَّك لا يُطبع.

import 'package:drift/drift.dart' show Value;

import '../../domain/printing/label_design.dart';
import '../database/database.dart';

/// صفُّ عنصرٍ ⇒ عنصرُ ملصق.
LabelElement labelElementFromRow(InvoiceTemplateElement r) => LabelElement(
      key: 'e${r.id}',
      id: r.id,
      type: r.elementType,
      xMm: r.xPosition,
      yMm: r.yPosition,
      wMm: r.width,
      hMm: r.height,
      fontSize: r.fontSize,
      bold: r.isBold,
      italic: r.isItalic,
      align: r.textAlign,
      color: r.fontColor,
      content: r.content,
      borderWidth: r.borderWidth,
      labelAr: r.labelAr,
    );

/// يقرأ ملصقاً — `null` حين لا قالبَ أو ليس ملصقاً.
Future<LabelDesign?> loadLabelDesign(AppDatabase db, int templateId) async {
  final t = await db.getTemplateById(templateId);
  if (t == null || t.templateCategory != 'barcode') return null;
  final rows = await db.getTemplateElements(templateId);
  return LabelDesign(
    templateId: t.id,
    name: t.name,
    widthMm: t.paperWidth,
    // نفسُ احتياط الراسم — وإلّا عرض المحرّرُ ملصقاً بطولٍ غيرِ ما يُطبع.
    heightMm: t.paperHeight ?? 25,
    isDefault: t.isDefault,
    elements: [for (final r in rows) labelElementFromRow(r)],
  );
}

InvoiceTemplateElementsCompanion _columns(LabelElement e, int order) =>
    InvoiceTemplateElementsCompanion(
      elementType: Value(e.type),
      sortOrder: Value(order),
      xPosition: Value(e.xMm),
      yPosition: Value(e.yMm),
      width: Value(e.wMm),
      height: Value(e.hMm),
      fontSize: Value(e.fontSize),
      isBold: Value(e.bold),
      isItalic: Value(e.italic),
      fontColor: Value(e.color),
      textAlign: Value(e.align),
      content: Value(e.content),
      borderWidth: Value(e.borderWidth),
    );

/// يحفظ الملصقَ ويُرجعه كما قُرئ بعد الحفظ (بمعرِّفاتِ الجديد).
Future<LabelDesign> saveLabelDesign(AppDatabase db, LabelDesign d) async {
  await db.transaction(() async {
    await db.updateTemplate(
      d.templateId,
      InvoiceTemplatesCompanion(
        name: Value(d.name),
        paperSize: Value(d.paperSize),
        paperWidth: Value(d.widthMm),
        paperHeight: Value(d.heightMm),
      ),
    );

    final existing = await db.getTemplateElements(d.templateId);
    final kept = {for (final e in d.elements) if (e.id != null) e.id!};
    for (final r in existing) {
      if (!kept.contains(r.id)) await db.deleteTemplateElement(r.id);
    }

    for (var i = 0; i < d.elements.length; i++) {
      final e = d.elements[i];
      if (e.id != null) {
        await db.updateTemplateElement(e.id!, _columns(e, i));
      } else {
        await db.into(db.invoiceTemplateElements).insert(
              _columns(e, i).copyWith(
                templateId: Value(d.templateId),
                labelAr: Value(e.labelAr),
              ),
            );
      }
    }
  });
  return (await loadLabelDesign(db, d.templateId))!;
}

/// ينشئ ملصقاً فارغاً بمقاسٍ مخصّص — باسمٍ وعنصرين يبدأ منهما.
///
/// ⚠️ **لا `createTemplate`**: تلك تبذر عناصرَ إيصالٍ حراريٍّ كاملةً لكلِّ
/// قالبٍ من نوع `thermal` — اسمَ الشركة ورقمَ الفاتورة والمجاميع — فيولد
/// الملصقُ وفيه ما لا يرسمه راسمُ الملصقات إلّا نصّاً خاماً.
Future<int> createLabelTemplate(
  AppDatabase db, {
  required String name,
  required double widthMm,
  required double heightMm,
}) {
  final w = widthMm.clamp(kLabelMinMm, kLabelMaxMm).toDouble();
  final h = heightMm.clamp(kLabelMinMm, kLabelMaxMm).toDouble();
  return db.transaction(() async {
    final draft = LabelDesign(
      templateId: 0,
      name: name,
      widthMm: w,
      heightMm: h,
      elements: const [],
    );
    final id = await db.into(db.invoiceTemplates).insert(
          InvoiceTemplatesCompanion.insert(
            name: name,
            type: const Value('thermal'),
            templateCategory: const Value('barcode'),
            paperSize: Value(draft.paperSize),
            paperWidth: Value(w),
            paperHeight: Value(h),
            isDefault: const Value(false),
          ),
        );
    // بدايةٌ مقروءة: الاسمُ أعلاه والباركودُ تحته — كالملصق القياسيّ.
    var d = draft;
    (d, _) = addLabelElement(d, LabelElementTypes.productName);
    (d, _) = addLabelElement(d, LabelElementTypes.barcode);
    final name0 = d.elements[0];
    final code = d.elements[1];
    d = moveLabelElement(d, code.key, code.xMm, name0.yMm + name0.hMm + 0.5,
        snap: false);
    for (var i = 0; i < d.elements.length; i++) {
      await db.into(db.invoiceTemplateElements).insert(
            _columns(d.elements[i], i).copyWith(templateId: Value(id)),
          );
    }
    return id;
  });
}
