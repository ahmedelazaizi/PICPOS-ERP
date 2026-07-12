import '../../data/database/database.dart' as db;
import '../../domain/repositories/invoice_templates_repository.dart';

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
}
