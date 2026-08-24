import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import '../picpos_shell/picpos_surface.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:drift/drift.dart' show Value;
import '../../data/database/database.dart' as db;
import 'package:file_picker/file_picker.dart';
import '../../core/theme/app_colors.dart';

import '../../data/providers/providers.dart';
import 'invoice_designer/invoice_designer_canvas.dart';
import 'invoice_designer/invoice_designer_toolbar.dart';
import 'invoice_designer/invoice_preview_dialog.dart';
import 'invoice_designer/invoice_section_editor.dart';

// ── Part files (mixin-based extraction) ─────────────────────────────────
part 'invoice_designer/invoice_designer_templates.dart';
part 'invoice_designer/invoice_designer_ui.dart';

/// مصمم الفواتير المخصص
/// شاشة لتصميم قوالب الفواتير Thermal و A4
class InvoiceDesignerScreen extends ConsumerStatefulWidget {
  final int? templateId; // لتعديل قالب موجود

  /// ترويسةُ PicPos الموحّدة بدل `AppBar` المشتركة (`HEADS.designer`).
  ///
  /// ⚠️ **رايةٌ هنا لا استخراجُ جسمٍ كبقيّة الشاشات** — وذلك لسببٍ بنيويّ:
  /// حالةُ هذه الشاشة مبنيّةٌ على mixins (`_InvoiceDesignerTemplatesMixin` و
  /// `_InvoiceDesignerUIMixin`) في ملفّات `part`، فكلُّ حقلٍ ودالّةٍ يعيش في
  /// الحالة نفسِها؛ واستخراجُ «جسمٍ» منها يقتضي تفكيكَ الـmixins أو نسخَها.
  /// والرايةُ تبلغ الغرضَ نفسَه بالشرط نفسِه: افتراضيّاً `false`، فشاشةُ
  /// UralCash لا يتبدّل فيها بايت.
  ///
  /// ⚠️ **و`AppBar` هنا أداةُ تحريرٍ عاملةٌ لا زينة**: اسمُ القالب وتصنيفُه
  /// ونوعُه والتصديرُ والاستيرادُ والقوالبُ المحفوظة. فهي تنزل إلى
  /// `subHeader` كاملةً — لا تُحذَف ولا يُستبدَل بها زرٌّ.
  final bool picposChrome;

  const InvoiceDesignerScreen({
    super.key,
    this.templateId,
    this.picposChrome = false,
  });

  @override
  ConsumerState<InvoiceDesignerScreen> createState() =>
      _InvoiceDesignerScreenState();
}

class _InvoiceDesignerScreenState extends ConsumerState<InvoiceDesignerScreen>
    with _InvoiceDesignerTemplatesMixin, _InvoiceDesignerUIMixin {
  @override
  InvoiceTemplate? template;
  @override
  List<InvoiceTemplateElement> elements = [];
  @override
  InvoiceTableSetting? tableSettings;
  @override
  InvoiceTemplateElement? selectedElement;
  @override
  Set<int> selectedElementIds = {};
  @override
  bool isLoading = true;
  @override
  // ignore: unused_field - reserved for unsaved changes tracking
  bool hasChanges = false;
  @override
  String templateType = 'thermal';
  @override
  String templateCategory = 'receipt';

  @override
  String printLanguage = 'ar';

  @override
  final TextEditingController nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadTemplate();
    _loadPrintLanguage();
  }

  Future<void> _loadPrintLanguage() async {
    // ISS-09: Use provider instead of direct DB access
    final lang = await ref.read(printLanguageProvider.future);
    if (mounted) {
      setState(() => printLanguage = lang);
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  // ── Element Handlers (shared by both mixins) ──────────────────────────

  @override
  void onElementSelected(InvoiceTemplateElement element, [bool isCtrl = false]) {
    setState(() {
      if (isCtrl) {
        // Ctrl+Click: toggle multi-select
        if (selectedElementIds.contains(element.id)) {
          selectedElementIds.remove(element.id);
          if (selectedElement?.id == element.id) {
            selectedElement = selectedElementIds.isNotEmpty
                ? elements.firstWhere((e) => e.id == selectedElementIds.first)
                : null;
          }
        } else {
          selectedElementIds.add(element.id);
          selectedElement = element;
        }
      } else {
        // Normal click: single select
        selectedElementIds = {element.id};
        selectedElement = element;
      }
    });
  }

  @override
  void onUpdatePosition(InvoiceTemplateElement element, double x, double y) {
    setState(() {
      final index = elements.indexWhere((e) => e.id == element.id);
      if (index != -1) {
        elements[index] = element.copyWith(xPosition: x, yPosition: y);
        selectedElement = elements[index];
        hasChanges = true;
      }
    });
  }

  @override
  void onUpdateSize(
    InvoiceTemplateElement element,
    double width,
    double height,
  ) {
    setState(() {
      final index = elements.indexWhere((e) => e.id == element.id);
      if (index != -1) {
        elements[index] = element.copyWith(width: width, height: height);
        selectedElement = elements[index];
        hasChanges = true;
      }
    });
  }

  @override
  void onElementUpdated(InvoiceTemplateElement element, {bool suppressHasChanges = false}) {
    setState(() {
      final index = elements.indexWhere((e) => e.id == element.id);
      if (index >= 0) elements[index] = element;
      selectedElement = element;
      if (!suppressHasChanges) hasChanges = true;
    });
  }

  @override
  void onTableSettingsUpdated(InvoiceTableSetting settings) {
    setState(() {
      tableSettings = settings;
      selectedElement = null;
      hasChanges = true;
    });
  }

  @override
  Future<void> onAddElement(
    String elementType, {
    String? variableContent,
  }) async {
    if (template == null) await createInitialTemplate();

    if (template != null) {
      final templatesRepo = ref.read(invoiceTemplatesRepositoryProvider);
      double width = 100, height = 30;
      String content = 'نص جديد';

      if (elementType == 'image') {
        width = 100; height = 100; content = variableContent ?? '';
      } else if (elementType == 'line') {
        width = 200; height = 2; content = '';
      } else if (elementType == 'rectangle') {
        width = 100; height = 50; content = '';
      } else if (elementType == 'variable') {
        content = variableContent ?? 'invoice_number';
      }

      await templatesRepo.addTemplateElement(
        templateId: template!.id,
        elementType: elementType,
        xPosition: 50, yPosition: 50,
        width: width, height: height,
        content: content,
      );

      // Merge: reload from DB to pick up the new element,
      // but PRESERVE in-memory versions of existing elements
      // (which may have unsaved styling changes like bold/fontSize/alignment)
      final dbElems = await templatesRepo.getTemplateElements(template!.id);
      final memoryById = <int, InvoiceTemplateElement>{};
      for (final e in elements) {
        memoryById[e.id] = e;
      }
      final merged = dbElems.map((dbEl) => memoryById[dbEl.id] ?? dbEl).toList();
      setState(() { elements = merged; hasChanges = true; });
    }
  }

  @override
  void onElementDeleted() async {
    final idsToDelete = selectedElementIds.isNotEmpty
        ? Set<int>.from(selectedElementIds)
        : (selectedElement != null ? {selectedElement!.id} : <int>{});
    if (idsToDelete.isEmpty) return;

    final templatesRepo = ref.read(invoiceTemplatesRepositoryProvider);
    for (final id in idsToDelete) {
      await templatesRepo.deleteTemplateElement(id);
    }
    setState(() {
      elements.removeWhere((e) => idsToDelete.contains(e.id));
      selectedElement = null;
      selectedElementIds.clear();
      hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) => buildBody();
}

/// Helper class for elements palette
class _PaletteItem {
  final String label;
  final String type;
  final String content;
  final IconData icon;

  const _PaletteItem(this.label, this.type, this.content, this.icon);
}
