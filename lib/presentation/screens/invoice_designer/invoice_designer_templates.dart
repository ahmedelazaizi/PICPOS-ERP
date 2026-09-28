part of '../invoice_designer_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// INVOICE DESIGNER — Template Management: Load, Save, Import, Export, List
// ═══════════════════════════════════════════════════════════════════════════

mixin _InvoiceDesignerTemplatesMixin
    on ConsumerState<InvoiceDesignerScreen> {
  // Abstract — provided by the shell
  InvoiceTemplate? get template;
  set template(InvoiceTemplate? val);
  List<InvoiceTemplateElement> get elements;
  set elements(List<InvoiceTemplateElement> val);
  InvoiceTableSetting? get tableSettings;
  set tableSettings(InvoiceTableSetting? val);
  InvoiceTemplateElement? get selectedElement;
  set selectedElement(InvoiceTemplateElement? val);
  bool get hasChanges;
  set hasChanges(bool val);
  String get templateType;
  set templateType(String val);
  String get templateCategory;
  set templateCategory(String val);
  TextEditingController get nameController;
  bool get isLoading;
  set isLoading(bool val);

  Future<void> loadTemplate() async {
    try {
      final templatesRepo = ref.read(invoiceTemplatesRepositoryProvider);
      await templatesRepo.seedDefaultTemplates();

      InvoiceTemplateWithData? data;

      if (widget.templateId != null) {
        // Explicit template ID provided
        data = await templatesRepo.getTemplateWithData(widget.templateId!);
      } else {
        // Try loading the last-edited template
        final settingsRepo = ref.read(settingsRepositoryProvider);
        final lastEditedIdStr = await settingsRepo.getSetting('last_edited_template_id');
        if (lastEditedIdStr != null && lastEditedIdStr.isNotEmpty) {
          final lastId = int.tryParse(lastEditedIdStr);
          if (lastId != null) {
            data = await templatesRepo.getTemplateWithData(lastId);
          }
        }
        // Fall back to the default template if last-edited not found
        data ??= await templatesRepo.getDefaultTemplateWithData(templateType);
      }

      if (data != null) {
        setState(() {
          template = data!.template;
          elements = data.elements;
          tableSettings = data.tableSettings;
          templateType = data.template.type;
          templateCategory = data.template.templateCategory;
          nameController.text = data.template.name;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e, st) {
      debugPrint('[InvoiceDesigner] ❌ loadTemplate error: $e\n$st');
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> createInitialTemplate() async {
    final templatesRepo = ref.read(invoiceTemplatesRepositoryProvider);
    final templateId = await templatesRepo.createTemplate(
      name: nameController.text.isEmpty ? 'قالب جديد' : nameController.text,
      type: templateType,
      templateCategory: templateCategory,
    );
    final data = await templatesRepo.getTemplateWithData(templateId);
    if (data != null) {
      setState(() {
        template = data.template;
        elements = data.elements;
        tableSettings = data.tableSettings;
        hasChanges = true;
      });
    }
  }

  Future<void> saveTemplate() async {
    final templatesRepo = ref.read(invoiceTemplatesRepositoryProvider);

    if (template == null) {
      await createInitialTemplate();
      if (mounted) {
        final user = ref.read(authProvider).user;
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id,
          userName: user?.displayName ?? 'مجهول',
          action: 'create_invoice_template',
          entityType: 'invoice_template',
          description: 'إنشاء قالب فاتورة: ${nameController.text.isEmpty ? 'قالب جديد' : nameController.text} ($templateType)',
        );
        if (!mounted) return;
        AppToast.show(context, 'تم حفظ القالب بنجاح', type: ToastType.success);
      }
    } else {
      await templatesRepo.updateTemplate(
        template!.id,
        db.InvoiceTemplatesCompanion(
          name: Value(nameController.text),
          type: Value(templateType),
          templateCategory: Value(templateCategory),
        ),
      );

      if (tableSettings != null) {
        await templatesRepo.saveTableSettings(
          template!.id,
          db.InvoiceTableSettingsCompanion(
            xPosition: Value(tableSettings!.xPosition),
            yPosition: Value(tableSettings!.yPosition),
            width: Value(tableSettings!.width),
            fontSize: Value(tableSettings!.fontSize),
            headerFontSize: Value(tableSettings!.headerFontSize),
            headerFontFamily: Value(tableSettings!.headerFontFamily),
            rowHeight: Value(tableSettings!.rowHeight),
            columnWidths: Value(tableSettings!.columnWidths),
            showIndex: Value(tableSettings!.showIndex),
            showProductName: Value(tableSettings!.showProductName),
            showProductCode: Value(tableSettings!.showProductCode),
            showQuantity: Value(tableSettings!.showQuantity),
            showUnitPrice: Value(tableSettings!.showUnitPrice),
            showDiscount: Value(tableSettings!.showDiscount),
            showTax: Value(tableSettings!.showTax),
            showTotal: Value(tableSettings!.showTotal),
            showUnit: Value(tableSettings!.showUnit),
            showBarcode: Value(tableSettings!.showBarcode),
            showNotes: Value(tableSettings!.showNotes),
          ),
        );
      }

      for (final element in elements) {
        await templatesRepo.updateTemplateElement(
          element.id,
          db.InvoiceTemplateElementsCompanion(
            xPosition: Value(element.xPosition),
            yPosition: Value(element.yPosition),
            width: Value(element.width),
            height: Value(element.height),
            content: Value(element.content),
            labelAr: Value(element.labelAr),
            labelEn: Value(element.labelEn),
            fontSize: Value(element.fontSize),
            fontFamily: Value(element.fontFamily),
            fontColor: Value(element.fontColor),
            isBold: Value(element.isBold),
            isItalic: Value(element.isItalic),
            isVisible: Value(element.isVisible),
            textAlign: Value(element.textAlign),
            sortOrder: Value(element.sortOrder),
            section: Value(element.section),
            rowIndex: Value(element.rowIndex),
            flexWidth: Value(element.flexWidth),
            backgroundColor: Value(element.backgroundColor),
            borderColor: Value(element.borderColor),
            borderWidth: Value(element.borderWidth),
            formula: Value(element.formula),
            extraStyles: Value(element.extraStyles),
          ),
        );
      }

      // Post-save: reload elements from DB to ensure in-memory ↔ DB consistency
      final reloaded = await templatesRepo.getTemplateWithData(template!.id);
      if (reloaded != null && mounted) {
        setState(() {
          elements = reloaded.elements;
          tableSettings = reloaded.tableSettings;
          hasChanges = false;
        });
      } else {
        setState(() => hasChanges = false);
      }

      if (mounted) {
        final user = ref.read(authProvider).user;
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id,
          userName: user?.displayName ?? 'مجهول',
          action: 'update_invoice_template',
          entityType: 'invoice_template',
          entityId: template!.id,
          description: 'تعديل قالب فاتورة: ${nameController.text}',
        );
        if (!mounted) return;
        // Bug 5: Persist last-edited template ID so designer reopens to this template
        final settingsRepo = ref.read(settingsRepositoryProvider);
        await settingsRepo.saveSetting('last_edited_template_id', template!.id.toString());
        if (!mounted) return;
        AppToast.show(context, 'تم حفظ التغييرات', type: ToastType.success);
      }
    }
  }

  void onReset() async {
    await loadTemplate();
    setState(() {
      hasChanges = false;
      selectedElement = null;
    });
  }

  Future<void> showPreview() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final rsData = await settingsRepo.getReceiptSettings();
    
    // ReceiptSettings object mapping
    final companyName = rsData['companyName'] ?? '';
    final companyAddress = rsData['companyAddress'] ?? 'عنوان الشركة';
    final companyPhone = rsData['companyPhone'] ?? '01000000000';
    final taxNumber = rsData['taxNumber'] ?? '';

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => InvoicePreviewDialog(
        template: template,
        elements: elements,
        tableSettings: tableSettings,
        templateType: templateType,
        companyData: {
          'company_name': companyName,
          'company_address': companyAddress,
          'company_phone': companyPhone,
          'company_tax_number': taxNumber,
        },
      ),
    );
  }

  Future<void> showTemplatesList() async {
    final templatesRepo = ref.read(invoiceTemplatesRepositoryProvider);
    final templates = await templatesRepo.getAllTemplates();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.folder, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('القوالب المحفوظة'),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(PhosphorIconsBold.plus, size: 18),
              label: const Text('قالب جديد'),
              onPressed: () { Navigator.pop(ctx); createNewTemplate(); },
            ),
          ],
        ),
        content: SizedBox(
          width: 500, height: 400,
          child: templates.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsLight.fileText, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('لا توجد قوالب محفوظة', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: templates.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final t = templates[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: t.isDefault
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.1),
                        child: Icon(
                          t.type == 'thermal' ? PhosphorIconsBold.receipt
                              : t.type == 'kitchen' ? PhosphorIconsBold.cookingPot
                              : PhosphorIconsBold.file,
                          color: t.isDefault ? AppColors.primary : Colors.grey, size: 20,
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(t.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                          if (t.isDefault) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('افتراضي', style: TextStyle(fontSize: 10, color: AppColors.success)),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        '${t.type == 'thermal' ? 'حراري' : t.type == 'kitchen' ? 'مطبخ' : t.type == 'shift_closing' ? 'تقرير إغلاق' : 'A4'} • ${t.paperSize}',
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(PhosphorIconsBold.dotsThreeVertical),
                        onSelected: (action) async {
                          Navigator.pop(ctx);
                          switch (action) {
                            case 'edit': loadTemplateById(t.id); break;
                            case 'default':
                              await templatesRepo.setDefaultTemplate(t.id);
                               if (!mounted) return;
                              // Reload the newly-defaulted template into memory
                              loadTemplateById(t.id);
                               if (!context.mounted) return;
                               AppToast.show(context, 'تم تعيين القالب كافتراضي');
                              break;
                            case 'delete': await confirmDeleteTemplate(t); break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'edit', child: Row(children: [Icon(PhosphorIconsBold.pencil, size: 18), SizedBox(width: 8), Text('تعديل')])),
                          if (!t.isDefault) const PopupMenuItem(value: 'default', child: Row(children: [Icon(PhosphorIconsBold.star, size: 18), SizedBox(width: 8), Text('تعيين كافتراضي')])),
                          const PopupMenuItem(value: 'delete', child: Row(children: [Icon(PhosphorIconsBold.trash, size: 18, color: AppColors.error), SizedBox(width: 8), Text('حذف', style: TextStyle(color: AppColors.error))])),
                        ],
                      ),
                      onTap: () { Navigator.pop(ctx); loadTemplateById(t.id); },
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
      ),
    );
  }

  Future<void> loadTemplateById(int id) async {
    final templatesRepo = ref.read(invoiceTemplatesRepositoryProvider);
    final data = await templatesRepo.getTemplateWithData(id);
    if (data != null && mounted) {
      setState(() {
        template = data.template;
        elements = data.elements;
        tableSettings = data.tableSettings;
        templateType = data.template.type;
        templateCategory = data.template.templateCategory;
        nameController.text = data.template.name;
        hasChanges = false;
      });
    }
  }

  Future<void> createNewTemplate() async {
    setState(() {
      template = null;
      elements = [];
      tableSettings = null;
      nameController.text = '';
      hasChanges = false;
      selectedElement = null;
    });
  }

  Future<void> confirmDeleteTemplate(InvoiceTemplate t) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف القالب "${t.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final templatesRepo = ref.read(invoiceTemplatesRepositoryProvider);
      await templatesRepo.deleteTemplate(t.id);
      final user = ref.read(authProvider).user;
      final activityLogRepo = ref.read(activityLogRepositoryProvider);
      await activityLogRepo.logActivity(
        userId: user?.id,
        userName: user?.displayName ?? 'مجهول',
        action: 'delete_invoice_template',
        entityType: 'invoice_template',
        entityId: t.id,
        description: 'حذف قالب فاتورة: ${t.name}',
      );
      if (!mounted) return;
      AppToast.show(context, 'تم حذف القالب', type: ToastType.success);
    }
  }

  Future<void> showImportDialog() async {
    final templatesRepo = ref.read(invoiceTemplatesRepositoryProvider);
    final availableTemplates = templatesRepo.getAvailableTemplateFiles();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.downloadSimple, color: AppColors.primary),
            SizedBox(width: 8),
            Text('استيراد نموذج جاهز'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('اختر نموذجاً جاهزاً لاستيراده:', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 16),
              ...availableTemplates.map(
                (t) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      t['type'] == 'thermal' ? PhosphorIconsBold.receipt
                          : t['type'] == 'kitchen' ? PhosphorIconsBold.cookingPot
                          : PhosphorIconsBold.file,
                      color: AppColors.primary,
                    ),
                    title: Text(t['name'] ?? 'نموذج', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      t['type'] == 'thermal' ? 'فاتورة حرارية 80mm'
                          : t['type'] == 'kitchen' ? 'طلب مطبخ 80mm'
                          : t['type'] == 'a4' ? 'فاتورة A4'
                          : 'نموذج',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    trailing: const Icon(PhosphorIconsBold.arrowRight),
                    onTap: () async { Navigator.pop(ctx); await importTemplate(t['file']!); },
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء'))],
      ),
    );
  }

  Future<void> importTemplate(String filename) async {
    try {
      final jsonString = await DefaultAssetBundle.of(context).loadString('assets/invoice_templates/$filename');
      final templatesRepo = ref.read(invoiceTemplatesRepositoryProvider);
      final newId = await templatesRepo.importTemplateFromJson(jsonString);

      if (mounted) {
        final user = ref.read(authProvider).user;
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id, userName: user?.displayName ?? 'مجهول',
          action: 'import_invoice_template', entityType: 'invoice_template',
          description: 'استيراد قالب فاتورة من نموذج: $filename',
        );
        if (!mounted) return;
        AppToast.show(context, 'تم استيراد النموذج بنجاح!', type: ToastType.success);
        await loadTemplateById(newId);
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ في الاستيراد: $e', type: ToastType.error);
    }
  }

  Future<void> exportTemplateToFile() async {
    if (template == null) {
      AppToast.show(context, 'لا يوجد قالب لتصديره', type: ToastType.warning);
      return;
    }
    // Auto-save before export to ensure DB is up-to-date with in-memory edits
    await saveTemplate();
    try {
      final templatesRepo = ref.read(invoiceTemplatesRepositoryProvider);
      final jsonString = await templatesRepo.exportTemplateToJson(template!.id);
      final prettyJson = const JsonEncoder.withIndent('  ').convert(jsonDecode(jsonString));

      final result = await FilePicker.saveFile(
        dialogTitle: 'تصدير تصميم الفاتورة',
        fileName: '${template!.name.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_')}.json',
        type: FileType.custom, allowedExtensions: ['json'],
      );

      if (result != null) {
        await File(result).writeAsString(prettyJson, flush: true);
        if (mounted) AppToast.show(context, 'تم تصدير "${template!.name}" بنجاح!', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ في التصدير: $e', type: ToastType.error);
    }
  }

  Future<void> importTemplateFromFile() async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'استيراد تصميم فاتورة',
        type: FileType.custom, allowedExtensions: ['json'], withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        String jsonString;

        if (file.bytes != null) {
          jsonString = utf8.decode(file.bytes!);
        } else if (file.path != null) {
          jsonString = await File(file.path!).readAsString();
        } else {
          throw Exception('لم يتم قراءة الملف');
        }

        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        if (!data.containsKey('elements')) {
          throw Exception('ملف JSON غير صالح — لا يحتوي على عناصر القالب');
        }

        final templatesRepo = ref.read(invoiceTemplatesRepositoryProvider);
        final newId = await templatesRepo.importTemplateFromJson(jsonString);

        if (mounted) {
          final user = ref.read(authProvider).user;
          final activityLogRepo = ref.read(activityLogRepositoryProvider);
          await activityLogRepo.logActivity(
            userId: user?.id, userName: user?.displayName ?? 'مجهول',
            action: 'import_invoice_template', entityType: 'invoice_template',
            description: 'استيراد قالب فاتورة من ملف: ${data['name'] ?? 'نموذج'}',
          );
          if (!mounted) return;
          AppToast.show(context, 'تم استيراد "${data['name'] ?? 'نموذج'}" بنجاح!', type: ToastType.success);
          await loadTemplateById(newId);
        }
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ في الاستيراد: $e', type: ToastType.error);
    }
  }
}
