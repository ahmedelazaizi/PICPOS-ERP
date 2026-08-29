import '../../data/database/database.dart' as db;
import '../printing/template_document.dart';
import '../printing/template_save_result.dart';

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

  // ═══════════════════════════════════════════════════════════════════════
  // المكتبةُ والرابطات
  // ═══════════════════════════════════════════════════════════════════════
  //
  // شاشاتُ الطباعة تُمنع من استيراد `data/database` (حارسُ
  // `presentation_db_import_guard`)، فكلُّ ما تحتاجه المكتبةُ يمرّ من هنا.

  /// كلُّ الرابطات — تقرؤها شاشتا المكتبة والحسم.
  Future<List<db.TemplateBinding>> getAllBindings();

  /// رابطاتُ قالبٍ بعينه — يقرؤها زرُّ الحذف قبل أن يرفض.
  Future<List<db.TemplateBinding>> getBindingsForTemplate(int templateId);

  /// يُفعِّل قالباً لمفتاحٍ رباعيّ ويُرجع **ما أُلغي** من رابطات.
  ///
  /// القائمةُ المرجَعةُ ليست زينة: الإلغاءُ الصامتُ يجعل المستخدمَ يظنّ
  /// قالبين مفعَّلَين. فتُعرَض في الإشعار صراحةً.
  Future<List<db.TemplateBinding>> activateBinding({
    required int templateId,
    required String documentType,
    int? branchId,
    int? printerId,
    String? locale,
    double? printerWidthMm,
  });

  /// يفكّ رابطةَ مفتاحٍ ويُرجع عددَ ما حُذف.
  Future<int> deactivateBinding({
    required String documentType,
    int? branchId,
    int? printerId,
    String? locale,
  });

  /// يحذف قالباً **ما لم يكن مربوطاً** — وإلّا رمى بعدد الرابطات.
  Future<void> deleteTemplateGuarded(int templateId);

  /// نسخةٌ كاملةٌ من قالبٍ بعناصره وإعدادات جدوله — **بلا رابطات**.
  ///
  /// نسخُ الرابطات يجعل النسخةَ تخطف مستنداتِ الأصل لحظةَ إنشائها.
  Future<int> duplicateTemplate(int templateId);

  /// إعداداتُ جدول قالبٍ — تقرؤها بطاقةُ المكتبة لتعدّ الأعمدة.
  Future<db.InvoiceTableSetting?> getTableSettings(int templateId);

  // ═══════════════════════════════════════════════════════════════════════
  // المحرّر
  // ═══════════════════════════════════════════════════════════════════════

  /// يهاجر قالباً من التدفّق إلى النطاقات — **مُعادٌ آمن**.
  ///
  /// يُنادى عند أوّل فتحٍ في المحرّر لا دفعةً واحدة: الترقيةُ الجماعيّةُ تلمس
  /// قوالبَ قد لا يفتحها المستخدمُ أبداً، وأيُّ خطأٍ فيها يظهر على ورقِ عميلٍ
  /// لا على شاشة. ويُرجع `true` حين هاجر فعلاً.
  Future<bool> migrateTemplateLayout(int templateId);

  /// يحفظ تخطيطَ القالب كلَّه في **معاملةٍ واحدةٍ مُلزَمةِ الترتيب**.
  ///
  /// الحذفُ وإعادةُ الكتابة داخلها: الانقطاعُ بينهما يترك قالباً بلا عناصر —
  /// أي فاتورةً تُطبع بيضاء.
  ///
  /// [activateForDocumentType] غيرُ فارغٍ ⇒ تُكتب الرابطةُ في نفس المعاملة،
  /// ويُرجَع ما أُلغي منها كي يذكره الإشعارُ صراحةً.
  Future<TemplateSaveResult> saveTemplateLayout({
    required int templateId,
    required TemplateDocument document,
    String? name,
    String? activateForDocumentType,
    int? activateBranchId,
    String? activateLocale,
  });
}
