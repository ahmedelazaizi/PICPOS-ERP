import 'dart:convert';

import '../../data/database/database.dart' as db;
import '../../domain/printing/template_document.dart';
import '../../domain/printing/template_save_result.dart';
import '../../domain/repositories/invoice_templates_repository.dart';
import '../../services/printing/template_migration.dart';
import 'template_layout_writer.dart' as writer;

class InvoiceTemplatesRepositoryImpl implements IInvoiceTemplatesRepository {
  final db.AppDatabase _db;

  InvoiceTemplatesRepositoryImpl(this._db);

  @override
  Future<void> seedDefaultTemplates() async {
    await _db.seedDefaultTemplates();
  }

  @override
  Future<db.InvoiceTemplateWithData?> getTemplateWithData(int id) async {
    return _db.getTemplateWithData(id);
  }

  @override
  Future<db.InvoiceTemplateWithData?> getDefaultTemplateWithData(String type) async {
    return _db.getDefaultTemplateWithData(type);
  }

  @override
  Future<int> createTemplate({required String name, required String type, String templateCategory = 'receipt'}) async {
    return _db.createTemplate(name: name, type: type, templateCategory: templateCategory);
  }

  @override
  Future<void> updateTemplate(int id, db.InvoiceTemplatesCompanion companion) async {
    await _db.updateTemplate(id, companion);
  }

  @override
  Future<void> saveTableSettings(int templateId, db.InvoiceTableSettingsCompanion companion) async {
    await _db.saveTableSettings(templateId, companion);
  }

  @override
  Future<void> updateTemplateElement(int id, db.InvoiceTemplateElementsCompanion companion) async {
    await _db.updateTemplateElement(id, companion);
  }

  @override
  Future<void> addTemplateElement({
    required int templateId,
    required String elementType,
    required double xPosition,
    required double yPosition,
    required double width,
    required double height,
    required String content,
  }) async {
    await _db.addTemplateElement(
      templateId: templateId,
      elementType: elementType,
      xPosition: xPosition,
      yPosition: yPosition,
      width: width,
      height: height,
      content: content,
    );
  }

  @override
  Future<void> deleteTemplateElement(int id) async {
    await _db.deleteTemplateElement(id);
  }

  @override
  Future<List<db.InvoiceTemplateElement>> getTemplateElements(int templateId) async {
    return _db.getTemplateElements(templateId);
  }

  @override
  Future<List<db.InvoiceTemplate>> getAllTemplates() async {
    return _db.getAllTemplates();
  }

  @override
  Future<void> setDefaultTemplate(int id) async {
    await _db.setDefaultTemplate(id);
  }

  @override
  Future<void> deleteTemplate(int id) async {
    await _db.deleteTemplate(id);
  }

  @override
  Future<int> importTemplateFromJson(String jsonString) async {
    return _db.importTemplateFromJson(jsonString);
  }

  @override
  Future<String> exportTemplateToJson(int templateId) async {
    return _db.exportTemplateToJson(templateId);
  }

  @override
  List<Map<String, String>> getAvailableTemplateFiles() {
    return _db.getAvailableTemplateFiles();
  }

  @override
  Future<bool> migrateTemplateLayout(int templateId) =>
      TemplateMigration.migrate(_db, templateId);

  @override
  Future<TemplateSaveResult> saveTemplateLayout({
    required int templateId,
    required TemplateDocument document,
    String? name,
    String? activateForDocumentType,
    int? activateBranchId,
    String? activateLocale,
  }) =>
      writer.saveTemplateLayout(
        _db,
        templateId: templateId,
        document: document,
        name: name,
        activateForDocumentType: activateForDocumentType,
        activateBranchId: activateBranchId,
        activateLocale: activateLocale,
      );

  @override
  Future<List<db.TemplateBinding>> getAllBindings() => _db.getAllBindings();

  @override
  Future<List<db.TemplateBinding>> getBindingsForTemplate(int templateId) =>
      _db.getBindingsForTemplate(templateId);

  @override
  Future<List<db.TemplateBinding>> activateBinding({
    required int templateId,
    required String documentType,
    int? branchId,
    int? printerId,
    String? locale,
    double? printerWidthMm,
  }) =>
      _db.activateBinding(
        templateId: templateId,
        documentType: documentType,
        branchId: branchId,
        printerId: printerId,
        locale: locale,
        printerWidthMm: printerWidthMm,
      );

  @override
  Future<int> deactivateBinding({
    required String documentType,
    int? branchId,
    int? printerId,
    String? locale,
  }) =>
      _db.deactivateBinding(
        documentType: documentType,
        branchId: branchId,
        printerId: printerId,
        locale: locale,
      );

  @override
  Future<void> deleteTemplateGuarded(int templateId) =>
      _db.deleteTemplateGuarded(templateId);

  @override
  Future<db.InvoiceTableSetting?> getTableSettings(int templateId) =>
      _db.getTableSettings(templateId);

  /// النسخُ يمرّ بالتصدير والاستيراد — لا بنسخِ صفوفٍ بيد.
  ///
  /// `exportTemplateToJson` و`importTemplateFromJson` يعرفان كلَّ حقلٍ في
  /// القالب ويتطوّران معه. ونسخٌ يدويٌّ للصفوف يُنسى تحديثُه عند إضافة
  /// عمود، فتخرج النسخةُ ناقصةً بصمت — وهي فئةُ عطبٍ لا يراها إلّا من
  /// يقارن الورقتين.
  ///
  /// والمستوردُ يكتب `isDefault = false` ولا يلمس الرابطات، وهو المطلوب
  /// بالضبط: نسخةٌ لا تخطف مستنداتِ أصلها.
  @override
  Future<int> duplicateTemplate(int templateId) async {
    final json = await _db.exportTemplateToJson(templateId);
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final base = (decoded['name'] as String?) ?? 'نموذج';
    decoded['name'] = '$base — نسخة';
    return _db.importTemplateFromJson(jsonEncode(decoded));
  }
}
