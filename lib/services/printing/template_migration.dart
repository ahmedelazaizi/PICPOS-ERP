// هجرةُ قالبٍ من التدفّق إلى النطاقات — `layout_version` ١ ⇐ ٢.
//
// ── القاعدةُ الحاكمة (‏`MIGRATION-PLAN.md`) ───────────────────────────────
// «القالبُ الذي لم يمسّه المستخدمُ يجب أن يطبع بعد الهجرة نفسَ ما كان يطبعه
// قبلها». فالهجرةُ ليست تحسيناً بل **تثبيتاً**: تكتب بالإحداثيّات ما كان
// التدفّقُ يحسبه ضمناً، فيكتسب المستخدمُ القدرةَ على التحريك ولا يتغيّر ورقُه.
//
// ── ولا تُقرأ `xPosition`/`yPosition` إطلاقاً ────────────────────────────
// وهذا ليس إهمالاً بل شرطُ صحّة: مقيسٌ أنّ الراسمَ التدفّقيَّ **لا يقرؤهما**
// (‏من الخصائص الخمس يصل الورقةَ `fontSize` و`flexWidth` وحدَهما). فقيمتُهما
// المخزَّنةُ لم تؤثّر على مطبوعٍ قطّ، واستعمالُها الآن يعني أن كلَّ قالبٍ
// يقفز إلى شكلٍ لم يره أحد.
//
// فالمواضعُ تُشتقّ من التدفّق نفسِه — و**بالمُخطِّط لا بنسخةٍ منه**:
// `TemplateMapper.fromLegacy` هي عينُ ما يستعمله الراسمُ الجديد، فلو نُسخت
// حلقةُ الرصّ هنا لانحرفت النسختان عند أوّل تعديل، فتُهاجَر القوالبُ إلى
// تخطيطٍ يخالف ما يُرسم.

import 'package:drift/drift.dart' show Value;

import '../../data/database/database.dart';
import '../../domain/printing/template_document.dart';
import '../../domain/printing/template_mapper.dart';
import 'template_render_pipeline.dart';

class TemplateMigration {
  const TemplateMigration._();

  /// هل هاجر هذا القالبُ بعد؟
  static bool isMigrated(InvoiceTemplate t) =>
      t.layoutVersion >= kBandLayoutVersion;

  /// بصمةُ قالبٍ هاجر بالمُخطِّط **المعطوب** — جدولُ الأصناف خارج `details`.
  ///
  /// ── لماذا هذه البصمةُ بالذات ─────────────────────────────────────────
  /// المُخطِّطُ القديمُ كان يرمي كلَّ عنصرٍ قسمُه `'body'` في `info`، وجدولُ
  /// الأصناف منها. فبقي `details` صفريَّ الارتفاع ورُسم الجدولُ **خارجَ
  /// الورقة**. والهجرةُ كتبت ذلك في `band_id` فصار العطبُ محفوظاً: إصلاحُ
  /// المُخطِّط وحدَه لا يصل القوالبَ المهاجَرةَ لأنّ `buildDocument` تقرأ
  /// `band_id` المخزَّنَ ولا تسأل المُخطِّطَ أصلاً.
  ///
  /// ⚠️ **ولا تُتَّخذ بصمةٌ أوسع**: «عنصرٌ نطاقُه يخالف مفتاحَه» تشمل عنصراً
  /// جرّه المستخدمُ بيده إلى نطاقٍ آخر — فيُمحى عملُه. أمّا جدولُ الأصناف
  /// خارجَ `details` فحالةٌ لا يصنعها المحرّرُ ولا يريدها أحد: النطاقُ
  /// المتمدِّدُ هو `details` وحدَه، فالجدولُ في غيره يعني قالباً لم يُخطَّط
  /// قطُّ لا قالباً مُخصَّصاً.
  static bool needsBandRepair(List<InvoiceTemplateElement> elements) {
    for (final e in elements) {
      final key = TemplateRenderPipeline.contentKeyOf(e);
      if (bandForKey(key) != BandId.details) continue;
      if (e.bandId != BandId.details.name) return true;
    }
    return false;
  }

  /// يكتب النطاقاتِ والإحداثيّاتِ ويرفع `layout_version`.
  ///
  /// **مُعادٌ آمنٌ** (‏idempotent): قالبٌ مهاجَرٌ يُعاد اشتقاقُه من نفس تدفّقه
  /// فيعطي نفسَ الأرقام. وهذا مقصود — الهجرةُ قد تُستدعى من المحرّر عند كلِّ
  /// فتح، فلا يجوز أن تزحف بالقالب خطوةً في كلِّ مرّة.
  ///
  /// و[force] تُعيد الاشتقاق حتى لو كان القالبُ عند ٢ — تحتاجه المعايرةُ
  /// وحدَها؛ والمسارُ العاديُّ يترك القالبَ المهاجَرَ وشأنَه كي لا يُمحى
  /// تحريكٌ كتبه المستخدمُ بيده.
  static Future<bool> migrate(
    AppDatabase db,
    int templateId, {
    bool force = false,
  }) async {
    final template = await db.getTemplateById(templateId);
    if (template == null) return false;

    final elements = await db.getTemplateElements(templateId);
    if (elements.isEmpty) return false;

    // المهاجَرُ يُترك وشأنَه — **إلّا** أن يحمل بصمةَ المُخطِّط المعطوب،
    // فيُعاد اشتقاقُه بالمُخطِّط المُصلَح. وبدون هذا الاستثناء يبقى كلُّ
    // قالبٍ هاجر قبل الإصلاح مقصوصاً إلى الأبد.
    if (isMigrated(template) && !force && !needsBandRepair(elements)) {
      return false;
    }

    final paper = TemplateRenderPipeline.buildPaper(template);
    final settings = await db.getTableSettings(templateId);

    final document = TemplateMapper.fromLegacy(
      paper: paper,
      elements: [
        for (final e in elements)
          LegacyElement(
            elementType: e.elementType,
            content: e.content,
            section: e.section,
            sortOrder: e.sortOrder,
            flexWidth: e.flexWidth,
            fontSize: e.fontSize,
            isBold: e.isBold,
            isVisible: e.isVisible,
            labelAr: e.labelAr,
            labelEn: e.labelEn,
            textAlign: e.textAlign,
            fontColor: e.fontColor,
            condition: e.condition,
            sourceId: '${e.id}',
          ),
      ],
      table: TemplateRenderPipeline.buildTable(settings, paper),
    );

    // الكتابةُ كلُّها في معاملةٍ واحدة: انقطاعٌ في منتصفها يترك قالباً نصفُه
    // بإحداثيّاتٍ ونصفُه بلا — وهو أسوأُ من قالبٍ لم يُهاجَر أصلاً، لأنّ
    // `buildDocument` تشترط أن يحمل **كلُّ** عنصرٍ إحداثيّاته.
    await db.transaction(() async {
      for (final band in document.bands) {
        for (final el in band.elements) {
          final rowId = int.tryParse(el.id);
          if (rowId == null) continue;
          await db.updateTemplateElement(
            rowId,
            InvoiceTemplateElementsCompanion(
              // ⚠️ **والقسمُ مع النطاق**: كانت الهجرةُ تكتب `band_id` وحدَه
              //    فيبقى `section` على `'body'` القديم — صفٌّ يناقض نفسَه،
              //    وأيُّ قارئٍ يسقط إلى المسار التدفّقيِّ يعيد العطبَ.
              section: Value(band.id.name),
              bandId: Value(band.id.name),
              xMm: Value(el.xMm),
              yMm: Value(el.yMm),
              wMm: Value(el.wMm),
              hMm: Value(el.hMm),
            ),
          );
        }
      }
      await db.updateTemplate(
        templateId,
        const InvoiceTemplatesCompanion(
          layoutVersion: Value(kBandLayoutVersion),
        ),
      );
    });

    return true;
  }
}
