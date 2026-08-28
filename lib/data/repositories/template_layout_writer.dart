// حفظُ تخطيطِ القالب من المحرّر — معاملةٌ واحدةٌ مُلزَمةُ الترتيب.
//
// ── العقدُ (‏`BUTTON-CONTRACT.md` §١) ─────────────────────────────────────
//
//   ١ · UPDATE invoice_templates          (الورق · الاسم · layout_version = 2)
//   ٢ · DELETE invoice_template_elements  WHERE template_id = ?
//   ٣ · INSERT العناصرَ بترتيبها الجديد
//   ٤ · UPSERT invoice_table_settings     (الأعمدةُ بعناوينها وعروضها)
//   ٥ · UPSERT template_bindings          ← عند «تفعيل كافتراضي» وحدَه
//
// ⚠️ **والحذفُ وإعادةُ الكتابة داخلَ المعاملة**: الانقطاعُ بينهما يترك قالباً
// بلا عناصر — أي فاتورةً تُطبع بيضاء. مذكورٌ صراحةً في العقد.
//
// ── ولماذا هنا لا في ملفِّ DAO ───────────────────────────────────────────
// ملفّاتُ الـDAO أجزاءٌ (‏`part`) من `database.dart`، والجزءُ **لا يملك
// استيراداتِه**. وهذا الحافظُ يقرأ [TemplateDocument] وأنواعَه، فوضعُه جزءاً
// كان يقتضي جرَّ نطاقِ الطباعة كلِّه إلى قاعدة البيانات — وفيه `TableColumn`
// يصطدم باسمٍ في drift.

import 'dart:convert';

import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;

import '../../domain/printing/template_document.dart';
import '../../domain/printing/template_save_result.dart';
import '../../services/printing/template_render_pipeline.dart'
    show kBandLayoutVersion;
import '../database/database.dart';


/// يحفظ تخطيطَ قالبٍ كاملاً من [document]، ويُفعّله عند الطلب.
///
/// [activateForDocumentType] غيرُ فارغٍ ⇒ الخطوةُ الخامسة. والتفعيلُ يقع
/// **داخل** نفس المعاملة: حفظٌ نجح وتفعيلٌ فشل يترك المستخدمَ يظنّ أنّ قالبَه
/// صار افتراضيّاً وهو ليس كذلك.
Future<TemplateSaveResult> saveTemplateLayout(
  AppDatabase db, {
  required int templateId,
  required TemplateDocument document,
  String? name,
  String? activateForDocumentType,
  int? activateBranchId,
  String? activateLocale,
}) {
  final table = document.table;

  return db.transaction(() async {
    // ١ · الورقُ والاسمُ ونسخةُ التخطيط.
    await db.updateTemplate(
      templateId,
      InvoiceTemplatesCompanion(
        name: name == null ? const Value.absent() : Value(name),
        paperWidth: Value(document.paper.widthMm),
        paperHeight: Value(document.paper.heightMm),
        // الحفظُ من المحرّر يعني نطاقاتٍ بإحداثيّات — بلا رجعة.
        layoutVersion: const Value(kBandLayoutVersion),
      ),
    );

    // ٢ · حذفُ العناصر القديمة.
    await (db.delete(db.invoiceTemplateElements)
          ..where((e) => e.templateId.equals(templateId)))
        .go();

    // ٣ · كتابتُها بترتيبها الجديد.
    //
    // `sortOrder` متسلسلٌ عبر النطاقات بترتيبها الرأسيّ — وهو ما يقرؤه
    // `orderElementsForPrint`. فالترتيبُ يبقى ذا معنىً ولو قُرئ القالبُ
    // بقارئٍ لا يعرف النطاقات.
    var order = 0;
    var written = 0;
    for (final band in document.bands) {
      for (final el in band.elements) {
        await db.into(db.invoiceTemplateElements).insert(
              InvoiceTemplateElementsCompanion.insert(
                templateId: templateId,
                elementType: _elementTypeOf(el.kind),
                sortOrder: Value(order++),
                content: Value(el.contentKey),
                labelAr: Value(el.labelAr),
                labelEn: Value(el.labelEn),
                fontSize: Value(el.fontSize),
                isBold: Value(el.bold),
                isVisible: Value(el.visible),
                textAlign: Value(_alignName(el.align)),
                fontColor: Value(el.colorHex ?? '#000000'),
                section: Value(band.id.name),
                bandId: Value(band.id.name),
                xMm: Value(el.xMm),
                yMm: Value(el.yMm),
                wMm: Value(el.wMm),
                hMm: Value(el.hMm),
                condition: Value(
                    (el.condition ?? '').trim().isEmpty ? null : el.condition),
              ),
            );
        written++;
      }
    }

    // ٤ · الأعمدةُ بعناوينها وعروضها ومنازلها.
    if (table != null) {
      await db.saveTableSettings(
        templateId,
        InvoiceTableSettingsCompanion(
          templateId: Value(templateId),
          fontSize: Value(table.fontSize),
          headerFontSize: Value(table.headerFontSize),
          rowHeight: Value(table.rowHeightMm),
          columnsJson: Value(_columnsToJson(table.columns)),
          // أعلامُ `show*` القديمةُ تُسوّى مع الأعمدة: قارئٌ لا يعرف
          // `columnsJson` يبقى يرى نفسَ الأعمدة، فلا يفترق مصدران.
          showIndex: Value(_visible(table, 'index')),
          showProductName: Value(_visible(table, 'name')),
          showProductCode: Value(_visible(table, 'code')),
          showQuantity: Value(_visible(table, 'quantity')),
          showUnitPrice: Value(_visible(table, 'price')),
          showDiscount: Value(_visible(table, 'discount')),
          showTax: Value(_visible(table, 'tax')),
          showTotal: Value(_visible(table, 'total')),
        ),
      );
    }

    // ٥ · الرابطة — عند «تفعيل كافتراضي» وحدَه.
    var cancelled = const <String>[];
    final docType = activateForDocumentType;
    if (docType != null && docType.isNotEmpty) {
      cancelled = await _activateWithin(
        db,
        documentType: docType,
        templateId: templateId,
        branchId: activateBranchId,
        locale: activateLocale,
      );
    }

    return TemplateSaveResult(
      elementCount: written,
      visibleColumnCount: table?.visibleColumns.length ?? 0,
      cancelledDocumentTypes: cancelled,
      activated: docType != null && docType.isNotEmpty,
    );
  });
}

/// تفعيلٌ **داخلَ معاملةٍ قائمة**.
///
/// ⚠️ ولا تُنادى `db.activateBinding`: تلك تفتح معاملتَها الخاصّة، والعقدُ
/// يقول «معاملةٌ واحدة» — فحفظٌ نجح وتفعيلٌ أخفق يترك المستخدمَ يظنّ قالبَه
/// افتراضيّاً وهو ليس كذلك.
Future<List<String>> _activateWithin(
  AppDatabase db, {
  required String documentType,
  required int templateId,
  int? branchId,
  String? locale,
}) async {
  final conflicts = await (db.select(db.templateBindings)
        ..where((b) {
          var w = b.documentType.equals(documentType);
          w = w &
              (branchId == null
                  ? b.branchId.isNull()
                  : b.branchId.equals(branchId));
          // المحرّرُ يفعّل بلا طابعةٍ — الربطُ بطابعةٍ بعينها من شاشة الحسم.
          w = w & b.printerId.isNull();
          w = w &
              (locale == null ? b.locale.isNull() : b.locale.equals(locale));
          return w;
        }))
      .get();

  final cancelled = conflicts
      .where((b) => b.templateId != templateId)
      .map((b) => b.documentType)
      .toList(growable: false);

  for (final c in conflicts) {
    await (db.delete(db.templateBindings)..where((b) => b.id.equals(c.id))).go();
  }

  await db.into(db.templateBindings).insert(
        TemplateBindingsCompanion.insert(
          documentType: documentType,
          templateId: templateId,
          branchId: Value(branchId),
          locale: Value(locale),
        ),
      );

  return cancelled;
}

bool _visible(TableSpec t, String key) =>
    t.columns.any((c) => c.key == key && c.visible);

/// نوعُ العنصر في العمود القديم — يقرؤه المسارُ التدفّقيُّ والمُصدِّر.
String _elementTypeOf(ElementKind k) => switch (k) {
      ElementKind.image => 'image',
      ElementKind.qrCode => 'qr',
      ElementKind.barcode => 'barcode',
      ElementKind.line => 'line',
      ElementKind.rect => 'rect',
      ElementKind.spacer => 'spacer',
      ElementKind.text => 'variable',
    };

String _alignName(TextAlignSpec a) => switch (a) {
      TextAlignSpec.start => 'right',
      TextAlignSpec.center => 'center',
      TextAlignSpec.end => 'left',
    };

/// تسلسلُ الأعمدة — **بنفس مفاتيح** `_columnsFromJson` في خطّ الرسم.
///
/// مفتاحٌ يُكتب هنا ولا يُقرأ هناك يعني عموداً يختفي بعد أوّل حفظ. ويقيس
/// `template_layout_writer_test` الدورةَ كاملةً: كتابةٌ ثمّ قراءةٌ بالخطّ.
String _columnsToJson(List<TableColumn> columns) => jsonEncode([
      for (final c in columns)
        {
          'key': c.key,
          'labelAr': c.labelAr,
          'labelEn': c.labelEn,
          'flex': c.flex,
          'decimals': c.decimals,
          'align': switch (c.align) {
            ColumnAlign.start => 'start',
            ColumnAlign.center => 'center',
            ColumnAlign.end => 'end',
          },
          'visible': c.visible,
          'wrap': c.wrap,
          if (c.formula != null) 'formula': c.formula,
        },
    ]);
