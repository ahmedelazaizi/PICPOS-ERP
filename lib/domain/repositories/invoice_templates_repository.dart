import '../../data/database/database.dart' as db;

abstract class IInvoiceTemplatesRepository {
  Future<void> seedDefaultTemplates();
  Future<db.InvoiceTemplateWithData?> getTemplateWithData(int id);
  Future<db.InvoiceTemplateWithData?> getDefaultTemplateWithData(String type);
  Future<int> createTemplate({required String name, required String type, String templateCategory = 'receipt'});
  Future<void> updateTemplate(int id, db.InvoiceTemplatesCompanion companion);
  Future<void> saveTableSettings(int templateId, db.InvoiceTableSettingsCompanion companion);
  Future<void> updateTemplateElement(int id, db.InvoiceTemplateElementsCompanion companion);
  Future<void> addTemplateElement({
    required int templateId,
    required String elementType,
    required double xPosition,
    required double yPosition,
    required double width,
    required double height,
    required String content,
  });
  Future<void> deleteTemplateElement(int id);
  Future<List<db.InvoiceTemplateElement>> getTemplateElements(int templateId);
  Future<List<db.InvoiceTemplate>> getAllTemplates();
  Future<void> setDefaultTemplate(int id);
  Future<void> deleteTemplate(int id);
  Future<int> importTemplateFromJson(String jsonString);
  Future<String> exportTemplateToJson(int templateId);
  List<Map<String, String>> getAvailableTemplateFiles();
}
