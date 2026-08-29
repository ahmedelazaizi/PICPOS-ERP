part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// INVOICE TEMPLATES DAO - مصمم الفواتير
// ═══════════════════════════════════════════════════════════════════════════

extension InvoiceTemplateDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════════
  // TEMPLATES CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all invoice templates
  Future<List<InvoiceTemplate>> getAllTemplates() =>
      select(invoiceTemplates).get();

  /// Get active templates
  Future<List<InvoiceTemplate>> getActiveTemplates() =>
      (select(invoiceTemplates)..where((t) => t.isActive.equals(true))).get();

  /// Get templates by type (thermal/a4)
  Future<List<InvoiceTemplate>> getTemplatesByType(String type) =>
      (select(invoiceTemplates)..where((t) => t.type.equals(type))).get();

  /// Get default template for a type
  Future<InvoiceTemplate?> getDefaultTemplate(String type) =>
      (select(invoiceTemplates)
            ..where((t) => t.type.equals(type) & t.isDefault.equals(true)))
          .getSingleOrNull();

  /// Get default template for a type AND category (receipt, invoice, kitchen, purchase, quotation)
  Future<InvoiceTemplate?> getDefaultTemplateByCategory(
    String type,
    String category,
  ) =>
      (select(invoiceTemplates)..where(
            (t) =>
                t.type.equals(type) &
                t.templateCategory.equals(category) &
                t.isDefault.equals(true),
          ))
          .getSingleOrNull();

  /// Get default template with data by category
  Future<InvoiceTemplateWithData?> getDefaultTemplateWithDataByCategory(
    String type,
    String category,
  ) async {
    final template = await getDefaultTemplateByCategory(type, category);
    if (template == null) {
      // No category-specific default found — return null.
      // Do NOT fall back to any thermal template, because a receipt template
      // should not be used for kitchen prints and vice versa.
      return null;
    }
    return getTemplateWithData(template.id);
  }

  /// Get template by ID
  Future<InvoiceTemplate?> getTemplateById(int id) => (select(
    invoiceTemplates,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Create a new template
  Future<int> createTemplate({
    required String name,
    required String type,
    String templateCategory = 'receipt',
    String paperSize = '80mm',
    double paperWidth = 80,
    double? paperHeight,
    String defaultFont = 'Cairo',
    double defaultFontSize = 12,
  }) async {
    final templateId = await into(invoiceTemplates).insert(
      InvoiceTemplatesCompanion.insert(
        name: name,
        type: Value(type),
        templateCategory: Value(templateCategory),
        paperSize: Value(paperSize),
        paperWidth: Value(paperWidth),
        paperHeight: Value(paperHeight),
        defaultFont: Value(defaultFont),
        defaultFontSize: Value(defaultFontSize),
      ),
    );

    // Create default elements based on type
    await _seedDefaultElements(templateId, type);

    return templateId;
  }

  /// Update a template
  Future<bool> updateTemplate(
    int id,
    InvoiceTemplatesCompanion template,
  ) async {
    return await (update(invoiceTemplates)..where((t) => t.id.equals(id)))
            .write(template.copyWith(updatedAt: Value(DateTime.now()))) >
        0;
  }

  /// Delete a template (and its elements)
  Future<void> deleteTemplate(int id) async {
    await transaction(() async {
      await (delete(
        invoiceTableSettings,
      )..where((s) => s.templateId.equals(id))).go();
      await (delete(
        invoiceTemplateElements,
      )..where((e) => e.templateId.equals(id))).go();
      await (delete(invoiceTemplates)..where((t) => t.id.equals(id))).go();
    });
  }

  /// Set template as default (unset others of same type)
  Future<void> setDefaultTemplate(int id) async {
    final template = await getTemplateById(id);
    if (template == null) return;

    await transaction(() async {
      // Use raw SQL with sqlBool() for PostgreSQL boolean compatibility.
      // Drift generates SET is_default = 0/1 which PostgreSQL rejects
      // (is_default is BOOLEAN, not INTEGER).
      final falseVal = sqlBool(false);
      final trueVal = sqlBool(true);

      // Unset all defaults of same type AND same category only.
      await customStatement(
        'UPDATE invoice_templates SET is_default = $falseVal '
        'WHERE type = ? AND template_category = ?',
        [template.type, template.templateCategory],
      );
      // Set this as default
      await customStatement(
        'UPDATE invoice_templates SET is_default = $trueVal WHERE id = ?',
        [id],
      );
    });
  }

  /// Get default template with full data for printing
  Future<InvoiceTemplateWithData?> getDefaultTemplateWithData(
    String type,
  ) async {
    final template = await getDefaultTemplate(type);
    if (template == null) return null;
    return getTemplateWithData(template.id);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEMPLATE SEEDING — See invoice_template_seeder_dao.dart
  // ═══════════════════════════════════════════════════════════════════════════


  // ═══════════════════════════════════════════════════════════════════════════
  // TEMPLATE ELEMENTS CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all elements for a template
  Future<List<InvoiceTemplateElement>> getTemplateElements(int templateId) =>
      (select(invoiceTemplateElements)
            ..where((e) => e.templateId.equals(templateId))
            ..orderBy([(e) => OrderingTerm.asc(e.sortOrder)]))
          .get();

  /// Add element to template
  Future<int> addTemplateElement({
    required int templateId,
    required String elementType,
    int sortOrder = 0,
    int rowIndex = 0,
    double flexWidth = 100,
    double xPosition = 0,
    double yPosition = 0,
    double width = 100,
    double height = 20,
    String textAlign = 'center',
    double? fontSize,
    bool isBold = false,
    bool isItalic = false,
    String fontColor = '#000000',
    String? content,
    String? labelAr,
    String? labelEn,
  }) async {
    return into(invoiceTemplateElements).insert(
      InvoiceTemplateElementsCompanion.insert(
        templateId: templateId,
        elementType: elementType,
        sortOrder: Value(sortOrder),
        rowIndex: Value(rowIndex),
        flexWidth: Value(flexWidth),
        xPosition: Value(xPosition),
        yPosition: Value(yPosition),
        width: Value(width),
        height: Value(height),
        textAlign: Value(textAlign),
        fontSize: Value(fontSize ?? 12),
        isBold: Value(isBold),
        isItalic: Value(isItalic),
        fontColor: Value(fontColor),
        content: Value(content),
        labelAr: Value(labelAr),
        labelEn: Value(labelEn),
      ),
    );
  }

  /// Update element
  Future<bool> updateTemplateElement(
    int id,
    InvoiceTemplateElementsCompanion element,
  ) async {
    return await (update(
          invoiceTemplateElements,
        )..where((e) => e.id.equals(id))).write(element) >
        0;
  }

  /// Delete element
  Future<int> deleteTemplateElement(int id) =>
      (delete(invoiceTemplateElements)..where((e) => e.id.equals(id))).go();

  /// Reorder elements
  Future<void> reorderElements(int templateId, List<int> elementIds) async {
    await transaction(() async {
      for (int i = 0; i < elementIds.length; i++) {
        await (update(invoiceTemplateElements)
              ..where((e) => e.id.equals(elementIds[i])))
            .write(InvoiceTemplateElementsCompanion(sortOrder: Value(i)));
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TABLE SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get table settings for template
  Future<InvoiceTableSetting?> getTableSettings(int templateId) => (select(
    invoiceTableSettings,
  )..where((s) => s.templateId.equals(templateId))).getSingleOrNull();

  /// Update or create table settings
  Future<void> saveTableSettings(
    int templateId,
    InvoiceTableSettingsCompanion settings,
  ) async {
    final existing = await getTableSettings(templateId);
    if (existing != null) {
      await (update(
        invoiceTableSettings,
      )..where((s) => s.templateId.equals(templateId))).write(settings);
    } else {
      await into(
        invoiceTableSettings,
      ).insert(settings.copyWith(templateId: Value(templateId)));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FULL TEMPLATE DATA
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get complete template with all elements and settings
  Future<InvoiceTemplateWithData?> getTemplateWithData(int templateId) async {
    final template = await getTemplateById(templateId);
    if (template == null) return null;

    final elements = await getTemplateElements(templateId);
    final tableSettings = await getTableSettings(templateId);

    return InvoiceTemplateWithData(
      template: template,
      elements: elements,
      tableSettings: tableSettings,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IMPORT / EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Import template from JSON string
  Future<int> importTemplateFromJson(String jsonString) async {
    final Map<String, dynamic> data = jsonDecode(jsonString);

    // Create template
    final templateId = await into(invoiceTemplates).insert(
      InvoiceTemplatesCompanion.insert(
        name: data['name'] as String? ?? 'نموذج مستورد',
        type: Value(data['type'] as String? ?? 'thermal'),
        templateCategory: Value(
          data['templateCategory'] as String? ?? 'receipt',
        ),
        paperSize: Value(data['paperSize'] as String? ?? '80mm'),
        paperWidth: Value((data['paperWidth'] as num?)?.toDouble() ?? 80.0),
        paperHeight: Value((data['paperHeight'] as num?)?.toDouble()),
        isDefault: const Value(false),
      ),
    );

    // Import elements
    final elements = data['elements'] as List<dynamic>? ?? [];
    for (int i = 0; i < elements.length; i++) {
      final el = elements[i] as Map<String, dynamic>;
      await into(invoiceTemplateElements).insert(
        InvoiceTemplateElementsCompanion.insert(
          templateId: templateId,
          elementType: el['type'] as String? ?? 'text',
          sortOrder: Value(el['sortOrder'] as int? ?? i),
          rowIndex: Value(el['rowIndex'] as int? ?? 0),
          flexWidth: Value((el['flexWidth'] as num?)?.toDouble() ?? 100),
          xPosition: Value((el['x'] as num?)?.toDouble() ?? 10),
          yPosition: Value((el['y'] as num?)?.toDouble() ?? 10),
          width: Value((el['width'] as num?)?.toDouble() ?? 100),
          height: Value((el['height'] as num?)?.toDouble() ?? 25),
          textAlign: Value(el['textAlign'] as String? ?? 'center'),
          fontSize: Value((el['fontSize'] as num?)?.toDouble() ?? 12),
          isBold: Value(el['isBold'] as bool? ?? false),
          isItalic: Value(el['isItalic'] as bool? ?? false),
          fontColor: Value(el['fontColor'] as String? ?? '#000000'),
          content: Value(el['content'] as String?),
          labelAr: Value(el['labelAr'] as String?),
          labelEn: Value(el['labelEn'] as String?),
        ),
      );
      // Update fields not covered by .insert() companion
      if (el['fontFamily'] != null || el['section'] != null || el['isVisible'] != null ||
          el['backgroundColor'] != null || el['borderColor'] != null ||
          (el['borderWidth'] as num?)?.toDouble() != null || el['formula'] != null) {
        // Get the element we just inserted (last one for this template with this sortOrder)
        final inserted = await (select(invoiceTemplateElements)
              ..where((e) => e.templateId.equals(templateId))
              ..orderBy([(e) => OrderingTerm.desc(e.id)])
              ..limit(1))
            .getSingleOrNull();
        if (inserted != null) {
          await (update(invoiceTemplateElements)..where((e) => e.id.equals(inserted.id))).write(
            InvoiceTemplateElementsCompanion(
              fontFamily: Value(el['fontFamily'] as String?),
              section: Value(el['section'] as String? ?? 'body'),
              isVisible: Value(el['isVisible'] as bool? ?? true),
              backgroundColor: Value(el['backgroundColor'] as String?),
              borderColor: Value(el['borderColor'] as String?),
              borderWidth: Value((el['borderWidth'] as num?)?.toDouble() ?? 0),
              formula: Value(el['formula'] as String?),
            ),
          );
        }
      }
    }

    // Import table settings
    final tableData = data['tableSettings'] as Map<String, dynamic>?;
    if (tableData != null) {
      await into(invoiceTableSettings).insert(
        InvoiceTableSettingsCompanion.insert(
          templateId: templateId,
          xPosition: Value((tableData['x'] as num?)?.toDouble() ?? 10),
          yPosition: Value((tableData['y'] as num?)?.toDouble() ?? 200),
          width: Value((tableData['width'] as num?)?.toDouble() ?? 200),
          fontSize: Value((tableData['fontSize'] as num?)?.toDouble() ?? 12),
          headerFontSize: Value(
            (tableData['headerFontSize'] as num?)?.toDouble() ?? 12,
          ),
          rowHeight: Value((tableData['rowHeight'] as num?)?.toDouble() ?? 25),
          showIndex: Value(tableData['showIndex'] as bool? ?? true),
          showProductCode: Value(
            tableData['showProductCode'] as bool? ?? false,
          ),
          showProductName: Value(tableData['showProductName'] as bool? ?? true),
          showQuantity: Value(tableData['showQuantity'] as bool? ?? true),
          showUnitPrice: Value(tableData['showUnitPrice'] as bool? ?? true),
          showDiscount: Value(tableData['showDiscount'] as bool? ?? false),
          showTax: Value(tableData['showTax'] as bool? ?? false),
          showTotal: Value(tableData['showTotal'] as bool? ?? true),
          showUnit: Value(tableData['showUnit'] as bool? ?? false),
          showBarcode: Value(tableData['showBarcode'] as bool? ?? false),
          showNotes: Value(tableData['showNotes'] as bool? ?? false),
        ),
      );
      // Update fields not covered by .insert() companion
      final insertedSettings = await getTableSettings(templateId);
      if (insertedSettings != null) {
        await (update(invoiceTableSettings)..where((s) => s.templateId.equals(templateId))).write(
          InvoiceTableSettingsCompanion(
            columnWidths: Value(tableData['columnWidths'] as String?),
            headerFontFamily: Value(tableData['headerFontFamily'] as String?),
            headerBgColor: Value(tableData['headerBgColor'] as String? ?? '#333333'),
            headerTextColor: Value(tableData['headerTextColor'] as String? ?? '#FFFFFF'),
            altRowBgColor: Value(tableData['altRowBgColor'] as String?),
          ),
        );
      }
    }

    return templateId;
  }

  /// Export template to JSON string
  Future<String> exportTemplateToJson(int templateId) async {
    final template = await getTemplateById(templateId);
    if (template == null) throw Exception('Template not found');

    final elements = await getTemplateElements(templateId);
    final tableSettings = await getTableSettings(templateId);

    final data = {
      'name': template.name,
      'type': template.type,
      'templateCategory': template.templateCategory,
      'paperSize': template.paperSize,
      'paperWidth': template.paperWidth,
      'paperHeight': template.paperHeight,
      'elements': elements
          .map(
            (e) => <String, dynamic>{
              'type': e.elementType,
              'x': e.xPosition,
              'y': e.yPosition,
              'width': e.width,
              'height': e.height,
              'textAlign': e.textAlign,
              'fontSize': e.fontSize,
              'fontFamily': e.fontFamily,
              'isBold': e.isBold,
              'isItalic': e.isItalic,
              'fontColor': e.fontColor,
              'backgroundColor': e.backgroundColor,
              'borderColor': e.borderColor,
              'borderWidth': e.borderWidth,
              'content': e.content,
              'labelAr': e.labelAr,
              'labelEn': e.labelEn,
              'isVisible': e.isVisible,
              'section': e.section,
              'sortOrder': e.sortOrder,
              'rowIndex': e.rowIndex,
              'flexWidth': e.flexWidth,
              'formula': e.formula,
            },
          )
          .toList(),
      if (tableSettings != null)
        'tableSettings': {
          'x': tableSettings.xPosition,
          'y': tableSettings.yPosition,
          'width': tableSettings.width,
          'fontSize': tableSettings.fontSize,
          'headerFontSize': tableSettings.headerFontSize,
          'headerFontFamily': tableSettings.headerFontFamily,
          'rowHeight': tableSettings.rowHeight,
          'columnWidths': tableSettings.columnWidths,
          'showIndex': tableSettings.showIndex,
          'showProductCode': tableSettings.showProductCode,
          'showProductName': tableSettings.showProductName,
          'showQuantity': tableSettings.showQuantity,
          'showUnitPrice': tableSettings.showUnitPrice,
          'showDiscount': tableSettings.showDiscount,
          'showTax': tableSettings.showTax,
          'showTotal': tableSettings.showTotal,
          'showUnit': tableSettings.showUnit,
          'showBarcode': tableSettings.showBarcode,
          'showNotes': tableSettings.showNotes,
          'headerBgColor': tableSettings.headerBgColor,
          'headerTextColor': tableSettings.headerTextColor,
          'altRowBgColor': tableSettings.altRowBgColor,
        },
    };

    return jsonEncode(data);
  }

  /// ملفّاتُ القوالب الجاهزة — تفويضٌ إلى [kReadyTemplateFiles].
  List<Map<String, String>> getAvailableTemplateFiles() =>
      kReadyTemplateFiles;
}

/// كلُّ ملفّات القوالب الجاهزة في `assets/invoice_templates/` — **مرجعٌ واحد**.
///
/// ── لماذا قائمةٌ واحدةٌ لا اثنتان ────────────────────────────────────────
/// كان في هذا الملفّ **دالّتان بنفس الاسم**: واحدةٌ على الـDAO بثمانيةِ
/// ملفّاتٍ وأخرى على مستوى الملفّ بأربعة — والثانيةُ محجوبةٌ لا تُنادى.
/// فمن التسعةَ عشرَ ملفاً في المستودع كان **أحدَ عشرَ لا يصلها مسارُ
/// استيرادٍ إطلاقاً**، وفيها كلُّ الملفّات الجديدة التي بُني المحرّكُ لأجلها:
/// الفاتورةُ الضريبيّةُ والمرتجعاتُ وكشفا الحساب والتقريرُ العامّ.
///
/// مكتوبةٌ في المستودع، ومقيسةٌ على المحرّك، ولا يراها المالكُ قطّ.
///
/// ⚠️ ويحرسها `template_files_are_complete_test`: أيُّ ملفٍّ يُضاف إلى
/// الأصول ولا يُدرَج هنا يُسقط الاختبار — فلا يتكرّر الغيابُ صامتاً.
const kReadyTemplateFiles = <Map<String, String>>[
  {'name': 'فاتورة حرارية كلاسيكية', 'file': 'thermal_classic.json', 'type': 'thermal'},
  {'name': 'فاتورة حرارية عصرية', 'file': 'thermal_modern.json', 'type': 'thermal'},
  {'name': 'فاتورة حرارية شاملة', 'file': 'thermal_comprehensive.json', 'type': 'thermal'},
  {'name': 'بيع سريع حراري — 80mm', 'file': 'thermal80_quick_sale.json', 'type': 'thermal'},
  {'name': 'بيع سريع حراري — 58mm', 'file': 'thermal58_quick_sale.json', 'type': 'thermal'},
  {'name': 'مرتجع مبيعات حراري — 80mm', 'file': 'thermal80_sales_return.json', 'type': 'thermal'},
  {'name': 'طلب مطبخ احترافي', 'file': 'kitchen_professional.json', 'type': 'kitchen'},
  {'name': 'فاتورة A4 تجارية', 'file': 'a4_commercial.json', 'type': 'a4'},
  {'name': 'فاتورة A4 احترافية', 'file': 'a4_professional.json', 'type': 'a4'},
  {'name': 'فاتورة مبيعات ضريبية — A4', 'file': 'a4_sales_tax_invoice.json', 'type': 'a4'},
  {'name': 'فاتورة مبيعات ضريبية — A5', 'file': 'a5_sales_tax_invoice.json', 'type': 'a4'},
  {'name': 'مرتجع مبيعات — A4', 'file': 'a4_sales_return.json', 'type': 'a4'},
  {'name': 'فاتورة مشتريات A4', 'file': 'a4_purchase.json', 'type': 'a4'},
  {'name': 'فاتورة مشتريات — A4', 'file': 'a4_purchase_invoice.json', 'type': 'a4'},
  {'name': 'مرتجع مشتريات — A4', 'file': 'a4_purchase_return.json', 'type': 'a4'},
  {'name': 'سند قبض / صرف', 'file': 'a4_receipt_voucher.json', 'type': 'a4'},
  {'name': 'كشف حساب عميل — A4', 'file': 'a4_customer_statement.json', 'type': 'statement'},
  {'name': 'كشف حساب مورد — A4', 'file': 'a4_supplier_statement.json', 'type': 'statement'},
  {'name': 'نموذج تقرير عام — A4', 'file': 'a4_report_generic.json', 'type': 'report'},
];

/// Combined template data for printing
class InvoiceTemplateWithData {
  final InvoiceTemplate template;
  final List<InvoiceTemplateElement> elements;
  final InvoiceTableSetting? tableSettings;

  InvoiceTemplateWithData({
    required this.template,
    required this.elements,
    this.tableSettings,
  });
}

/// قائمةُ ملفّات النماذج الجاهزة.
///
/// ⚠️ كانت نسخةً ثانيةً بأربعة ملفّاتٍ **محجوبةً** بدالّةِ الـDAO التي
/// تحمل نفسَ الاسم — تُكتب ولا تُنادى. صارت تفويضاً كي لا يعود
/// الانقسام.
List<Map<String, String>> getAvailableTemplateFiles() => kReadyTemplateFiles;
