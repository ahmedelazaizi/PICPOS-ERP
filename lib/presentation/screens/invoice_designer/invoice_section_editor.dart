import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/template_json_flags.dart';
import '../../../data/database/database.dart';
import '../../../domain/models/invoice_template_layout.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SECTION-BASED INVOICE EDITOR v3
// Professional section-based editor with:
// - Drag-to-reorder fields & sections
// - Element alignment (left/center/right)
// - Side-by-side (inline) field layout
// - Per-field font controls (bold, size)
// - Logo sizing
// - Interactive table with additions/options rows
// - Decimal precision for table numbers
// - Delivery section
// ═══════════════════════════════════════════════════════════════════════════

/// Represents alignment of an element
enum FieldAlignment { right, center, left }

/// Represents a single field within a section
class SectionField {
  final String key;
  final String label;
  final IconData icon;
  final String elementType; // 'variable', 'text', 'image', 'items_table'
  final String? variableContent;
  bool isVisible;
  FieldAlignment alignment;
  double sizePercent; // 0.0 - 1.0 for sizing (e.g. logo width)
  bool isBold;
  double fontSize; // 0 = default (auto), otherwise specific size
  bool isInline; // true = render side-by-side with next inline field

  SectionField({
    required this.key,
    required this.label,
    required this.icon,
    required this.elementType,
    this.variableContent,
    this.isVisible = true,
    this.alignment = FieldAlignment.center,
    this.sizePercent = 1.0,
    this.isBold = false,
    this.fontSize = 0,
    this.isInline = false,
  });
}

/// Represents a section of the invoice
class InvoiceSection {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final List<SectionField> fields;
  bool isExpanded;
  bool isVisible;

  InvoiceSection({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.fields,
    this.isExpanded = false,
    this.isVisible = true,
  });
}

/// The main section-based editor widget
class InvoiceSectionEditor extends StatefulWidget {
  final List<InvoiceTemplateElement> elements;
  final InvoiceTableSetting? tableSettings;
  final String templateType;
  final String templateCategory;
  final double paperWidth;
  final Function(String elementType, {String? variableContent}) onAddElement;
  final Function(InvoiceTemplateElement element, {bool suppressHasChanges}) onElementUpdated;
  final Function() onElementDeleted;
  final Function(InvoiceTableSetting settings) onUpdateTableSettings;

  const InvoiceSectionEditor({
    super.key,
    required this.elements,
    this.tableSettings,
    required this.templateType,
    required this.templateCategory,
    required this.paperWidth,
    required this.onAddElement,
    required this.onElementUpdated,
    required this.onElementDeleted,
    required this.onUpdateTableSettings,
  });

  @override
  State<InvoiceSectionEditor> createState() => _InvoiceSectionEditorState();
}

/// Payload for cross-section drag and drop
class _DragFieldPayload {
  final InvoiceSection sourceSection;
  final int sourceIndex;
  final SectionField field;
  _DragFieldPayload({required this.sourceSection, required this.sourceIndex, required this.field});
}

class _InvoiceSectionEditorState extends State<InvoiceSectionEditor> {
  late List<InvoiceSection> _sections;

  @override
  void initState() {
    super.initState();
    _sections = _buildSections();
    _fullSyncWithElements(); // Load ALL properties from DB on first load
    _loadDecimalPlaces();
  }

  @override
  void didUpdateWidget(covariant InvoiceSectionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.templateCategory != widget.templateCategory) {
      _sections = _buildSections();
      _fullSyncWithElements(); // Full reload when category changes
    } else {
      _syncVisibility(); // Only sync visibility — don't overwrite user's property edits
    }
  }

  /// Full sync: load ALL properties (bold, font, align, inline, sizePercent) from DB elements.
  /// Called only on initState and when templateCategory changes.
  /// Also sorts fields within each section by their DB sortOrder for correct ordering.
  void _fullSyncWithElements() {
    final elementsByContent = <String, InvoiceTemplateElement>{};
    for (final e in widget.elements) {
      if (e.content != null && e.content!.isNotEmpty) {
        elementsByContent[e.content!] = e;
      }
    }

    for (final section in _sections) {
      for (final field in section.fields) {
        if (field.elementType == 'items_table') continue;
        if (field.variableContent != null) {
          final dbEl = elementsByContent[field.variableContent!];
          if (dbEl != null) {
            // Always load ALL properties from DB — even for hidden fields
            field.isVisible = dbEl.isVisible;
            field.isBold = dbEl.isBold;
            field.fontSize = dbEl.fontSize;
            field.alignment = _textAlignToFieldAlignment(dbEl.textAlign);
            field.isInline = dbEl.flexWidth < 100;
            // Load logo/image size: width is stored as percentage * 100
            if (field.elementType == 'image') {
              field.sizePercent = (dbEl.width / 100.0).clamp(0.15, 1.0);
            }
          } else {
            field.isVisible = false;
          }
        }
      }

      // Sort fields within section by their DB sortOrder (preserves saved order)
      section.fields.sort((a, b) {
        final aEl = a.variableContent != null ? elementsByContent[a.variableContent!] : null;
        final bEl = b.variableContent != null ? elementsByContent[b.variableContent!] : null;
        final aOrder = aEl?.sortOrder ?? 9999;
        final bOrder = bEl?.sortOrder ?? 9999;
        return aOrder.compareTo(bOrder);
      });
    }

    // Recalc sortOrder to ensure sequential values after sorting
    // suppressHasChanges=true: this is init-time recalc, not a user change
    _recalcSortOrder(suppressHasChanges: true);
  }

  /// Visibility-only sync: update which fields are visible/hidden
  /// WITHOUT overwriting bold/fontSize/alignment that user just changed.
  void _syncVisibility() {
    final elementsByContent = <String, InvoiceTemplateElement>{};
    for (final e in widget.elements) {
      if (e.content != null && e.content!.isNotEmpty) {
        elementsByContent[e.content!] = e;
      }
    }

    for (final section in _sections) {
      for (final field in section.fields) {
        if (field.elementType == 'items_table') continue;
        if (field.variableContent != null) {
          final dbEl = elementsByContent[field.variableContent!];
          field.isVisible = dbEl != null && dbEl.isVisible;
        }
      }
    }
    // NOTE: Do NOT hide orphaned elements — they may be user-created
    // or from seeders with different content keys. Hiding them here
    // causes silent data loss on every widget rebuild.
  }

  String _fieldAlignmentToTextAlign(FieldAlignment a) {
    switch (a) {
      case FieldAlignment.right: return 'right';
      case FieldAlignment.center: return 'center';
      case FieldAlignment.left: return 'left';
    }
  }

  /// Push ALL section field changes to the underlying DB element.
  /// Includes: bold, fontSize, alignment, inline, sizePercent (→width), isVisible.
  void _pushFieldToElement(SectionField field) {
    if (field.variableContent == null) return;
    final match = widget.elements.where(
      (e) => e.content == field.variableContent,
    );
    if (match.isEmpty) return;
    final dbEl = match.first;
    widget.onElementUpdated(
      dbEl.copyWith(
        isBold: field.isBold,
        fontSize: field.fontSize > 0 ? field.fontSize : dbEl.fontSize,
        textAlign: _fieldAlignmentToTextAlign(field.alignment),
        flexWidth: field.isInline ? 50.0 : 100.0,
        isVisible: field.isVisible,
        // For images: store sizePercent as width (percentage * 100)
        width: field.elementType == 'image'
            ? field.sizePercent * 100.0
            : dbEl.width,
      ),
    );
  }

  FieldAlignment _textAlignToFieldAlignment(String? align) {
    switch (align) {
      case 'left':
        return FieldAlignment.left;
      case 'center':
        return FieldAlignment.center;
      case 'right':
      default:
        return FieldAlignment.right;
    }
  }

  List<InvoiceSection> _buildSections() {
    final isKitchen = widget.templateCategory == 'kitchen';
    final isShiftClosing = widget.templateCategory == 'shift_closing';
    final isPurchase = widget.templateCategory == 'purchase';

    return [
      // ── HEADER ──
      InvoiceSection(
        id: 'header',
        title: 'الترويسة',
        icon: PhosphorIconsBold.buildings,
        color: const Color(0xFF2563EB),
        fields: [
          SectionField(key: 'logo', label: 'شعار الشركة', icon: PhosphorIconsBold.image, elementType: 'image', variableContent: 'logo', sizePercent: 0.4),
          SectionField(key: 'company_name', label: 'اسم الشركة', icon: PhosphorIconsBold.buildings, elementType: 'variable', variableContent: 'company_name'),
          SectionField(key: 'company_address', label: 'عنوان الشركة', icon: PhosphorIconsBold.mapPin, elementType: 'variable', variableContent: 'company_address'),
          SectionField(key: 'company_phone', label: 'هاتف الشركة', icon: PhosphorIconsBold.phone, elementType: 'variable', variableContent: 'company_phone'),
          SectionField(key: 'company_tax_number', label: 'الرقم الضريبي', icon: PhosphorIconsBold.identificationBadge, elementType: 'variable', variableContent: 'company_tax_number'),
          SectionField(key: 'branch_name', label: 'اسم الفرع', icon: PhosphorIconsBold.storefront, elementType: 'variable', variableContent: 'branch_name'),
        ],
      ),

      // ── INVOICE INFO ──
      InvoiceSection(
        id: 'invoice_info',
        title: isShiftClosing ? 'بيانات الوردية' : 'بيانات الفاتورة',
        icon: PhosphorIconsBold.fileText,
        color: const Color(0xFF059669),
        fields: [
          SectionField(key: 'invoice_number', label: 'رقم الفاتورة', icon: PhosphorIconsBold.hash, elementType: 'variable', variableContent: 'invoice_number'),
          SectionField(key: 'order_number', label: 'رقم الطلب', icon: PhosphorIconsBold.listNumbers, elementType: 'variable', variableContent: 'order_number'),
          SectionField(key: 'date', label: 'التاريخ', icon: PhosphorIconsBold.calendar, elementType: 'variable', variableContent: 'date'),
          SectionField(key: 'time', label: 'الوقت', icon: PhosphorIconsBold.clock, elementType: 'variable', variableContent: 'time'),
          SectionField(key: 'cashier_name', label: 'الكاشير', icon: PhosphorIconsBold.user, elementType: 'variable', variableContent: 'cashier_name'),
          SectionField(key: 'warehouse_name', label: 'المخزن', icon: PhosphorIconsBold.warehouse, elementType: 'variable', variableContent: 'warehouse_name'),
          SectionField(key: 'payment_method', label: 'طريقة الدفع', icon: PhosphorIconsBold.creditCard, elementType: 'variable', variableContent: 'payment_method'),
          SectionField(key: 'sale_type', label: 'نوع البيع', icon: PhosphorIconsBold.shoppingCart, elementType: 'variable', variableContent: 'sale_type'),
          SectionField(key: 'invoice_type_label', label: 'نوع الفاتورة', icon: PhosphorIconsBold.tag, elementType: 'variable', variableContent: 'invoice_type_label'),
        ],
      ),

      // ── CUSTOMER / SUPPLIER ──
      InvoiceSection(
        id: 'customer',
        title: isPurchase ? 'بيانات المورد' : 'بيانات العميل',
        icon: PhosphorIconsBold.userCircle,
        color: const Color(0xFFD97706),
        fields: [
          SectionField(key: 'customer_name', label: isPurchase ? 'اسم المورد' : 'اسم العميل', icon: PhosphorIconsBold.user, elementType: 'variable', variableContent: isPurchase ? 'supplier_name' : 'customer_name'),
          SectionField(key: 'customer_phone', label: 'الهاتف', icon: PhosphorIconsBold.phone, elementType: 'variable', variableContent: 'customer_phone'),
          SectionField(key: 'customer_address', label: 'العنوان', icon: PhosphorIconsBold.mapPin, elementType: 'variable', variableContent: 'customer_address'),
          if (!isPurchase) ...[
            SectionField(key: 'adhoc_customer_name', label: 'اسم العميل النصي', icon: PhosphorIconsBold.userCircle, elementType: 'variable', variableContent: 'adhoc_customer_name'),
            SectionField(key: 'adhoc_customer_phone', label: 'هاتف العميل النصي', icon: PhosphorIconsBold.phoneCall, elementType: 'variable', variableContent: 'adhoc_customer_phone'),
          ],
          if (isKitchen) ...[
            SectionField(key: 'table_number', label: 'رقم الطاولة', icon: PhosphorIconsBold.table, elementType: 'variable', variableContent: 'table_number'),
            SectionField(key: 'waiter_name', label: 'اسم الويتر', icon: PhosphorIconsBold.user, elementType: 'variable', variableContent: 'waiter_name'),
          ],
        ],
      ),

      // ── DELIVERY SECTION ──
      if (!isShiftClosing && !isKitchen)
        InvoiceSection(
          id: 'delivery',
          title: 'التوصيل',
          icon: PhosphorIconsBold.truck,
          color: const Color(0xFF0891B2),
          isVisible: false,
          fields: [
            SectionField(key: 'delivery_type', label: 'نوع التوصيل', icon: PhosphorIconsBold.truck, elementType: 'variable', variableContent: 'delivery_type'),
            SectionField(key: 'delivery_address', label: 'عنوان التوصيل', icon: PhosphorIconsBold.mapPin, elementType: 'variable', variableContent: 'delivery_address'),
            SectionField(key: 'delivery_fee', label: 'رسوم التوصيل', icon: PhosphorIconsBold.currencyDollar, elementType: 'variable', variableContent: 'delivery_fee'),
            SectionField(key: 'courier_name', label: 'اسم المندوب', icon: PhosphorIconsBold.motorcycle, elementType: 'variable', variableContent: 'courier_name'),
          ],
        ),

      // ── ITEMS TABLE ──
      if (!isShiftClosing)
        InvoiceSection(
          id: 'items_table',
          title: 'جدول الأصناف',
          icon: PhosphorIconsBold.table,
          color: const Color(0xFF7C3AED),
          isExpanded: true,
          fields: [
            // `variableContent` يربطه بعنصرِ القاعدة `variable`/`items_table`
            // فيدخل في إعادة الترقيم — بلا ذلك كان المالكُ يحرّك جدولاً لا
            // يُحفَظ له موضع. و`elementType` يبقى علامةً لواجهةِ القسم.
            SectionField(key: 'items_table', label: 'جدول الأصناف', icon: PhosphorIconsBold.table, elementType: 'items_table', variableContent: 'items_table'),
          ],
        ),

      // ── SHIFT CLOSING sections ──
      if (isShiftClosing) ...[
        InvoiceSection(
          id: 'shift_sales', title: 'ملخص المبيعات', icon: PhosphorIconsBold.chartBar, color: const Color(0xFF7C3AED),
          fields: [
            SectionField(key: 'shift_invoice_count', label: 'عدد الفواتير', icon: PhosphorIconsBold.receipt, elementType: 'variable', variableContent: 'shift_invoice_count'),
            SectionField(key: 'shift_total_sales', label: 'إجمالي المبيعات', icon: PhosphorIconsBold.currencyDollar, elementType: 'variable', variableContent: 'shift_total_sales'),
            SectionField(key: 'shift_total_expenses', label: 'مصروفات الوردية', icon: PhosphorIconsBold.arrowDown, elementType: 'variable', variableContent: 'shift_total_expenses'),
            SectionField(key: 'shift_cash_refunds', label: 'مرتجعات نقدية', icon: PhosphorIconsBold.arrowUUpLeft, elementType: 'variable', variableContent: 'shift_cash_refunds'),
          ],
        ),
        InvoiceSection(
          id: 'shift_cash', title: 'تسوية النقد', icon: PhosphorIconsBold.coins, color: const Color(0xFF059669),
          fields: [
            SectionField(key: 'shift_system_cash', label: 'رصيد النظام (نقد)', icon: PhosphorIconsBold.coins, elementType: 'variable', variableContent: 'shift_system_cash'),
            SectionField(key: 'shift_actual_cash', label: 'النقد الفعلي', icon: PhosphorIconsBold.money, elementType: 'variable', variableContent: 'shift_actual_cash'),
            SectionField(key: 'shift_cash_variance', label: 'فارق النقد', icon: PhosphorIconsBold.plusMinus, elementType: 'variable', variableContent: 'shift_cash_variance'),
          ],
        ),
        InvoiceSection(
          id: 'shift_card', title: 'تسوية البطاقة', icon: PhosphorIconsBold.creditCard, color: const Color(0xFF2563EB),
          fields: [
            SectionField(key: 'shift_system_card', label: 'رصيد النظام (بطاقة)', icon: PhosphorIconsBold.creditCard, elementType: 'variable', variableContent: 'shift_system_card'),
            SectionField(key: 'shift_actual_card', label: 'البطاقة الفعلي', icon: PhosphorIconsBold.creditCard, elementType: 'variable', variableContent: 'shift_actual_card'),
            SectionField(key: 'shift_card_variance', label: 'فارق البطاقة', icon: PhosphorIconsBold.plusMinus, elementType: 'variable', variableContent: 'shift_card_variance'),
          ],
        ),
        // §٥-٢ — «كليك» تدخل في الإجماليات تحت، ولم يكن لها قسمٌ هنا.
        InvoiceSection(
          id: 'shift_click', title: 'تسوية كليك', icon: PhosphorIconsBold.deviceMobile, color: const Color(0xFF7C3AED),
          fields: [
            SectionField(key: 'shift_system_click', label: 'رصيد النظام (كليك)', icon: PhosphorIconsBold.deviceMobile, elementType: 'variable', variableContent: 'shift_system_click'),
            SectionField(key: 'shift_actual_click', label: 'كليك الفعلي', icon: PhosphorIconsBold.deviceMobile, elementType: 'variable', variableContent: 'shift_actual_click'),
            SectionField(key: 'shift_click_variance', label: 'فارق كليك', icon: PhosphorIconsBold.plusMinus, elementType: 'variable', variableContent: 'shift_click_variance'),
          ],
        ),
        InvoiceSection(
          id: 'shift_totals', title: 'الإجماليات', icon: PhosphorIconsBold.calculator, color: const Color(0xFFDC2626),
          fields: [
            SectionField(key: 'shift_total_system', label: 'إجمالي النظام', icon: PhosphorIconsBold.calculator, elementType: 'variable', variableContent: 'shift_total_system'),
            SectionField(key: 'shift_total_actual', label: 'إجمالي الفعلي', icon: PhosphorIconsBold.wallet, elementType: 'variable', variableContent: 'shift_total_actual'),
            SectionField(key: 'shift_total_variance', label: 'الفارق الكلي', icon: PhosphorIconsBold.chartBar, elementType: 'variable', variableContent: 'shift_total_variance'),
            SectionField(key: 'shift_status', label: 'الحالة', icon: PhosphorIconsBold.checkCircle, elementType: 'variable', variableContent: 'shift_status'),
          ],
        ),
      ],

      // ── TOTALS ──
      if (!isShiftClosing)
        InvoiceSection(
          id: 'totals',
          title: 'المبالغ والإجماليات',
          icon: PhosphorIconsBold.currencyDollar,
          color: const Color(0xFFDC2626),
          fields: [
            SectionField(key: 'subtotal', label: 'الإجمالي الفرعي', icon: PhosphorIconsBold.currencyDollar, elementType: 'variable', variableContent: 'subtotal'),
            SectionField(key: 'discount', label: 'الخصم', icon: PhosphorIconsBold.tag, elementType: 'variable', variableContent: 'discount'),
            SectionField(key: 'tax_amount', label: 'الضريبة', icon: PhosphorIconsBold.percent, elementType: 'variable', variableContent: 'tax_amount'),
            SectionField(key: 'total_amount', label: 'الإجمالي النهائي', icon: PhosphorIconsBold.coins, elementType: 'variable', variableContent: 'total_amount'),
            SectionField(key: 'paid', label: 'المدفوع', icon: PhosphorIconsBold.money, elementType: 'variable', variableContent: 'paid'),
            SectionField(key: 'remaining', label: 'المتبقي', icon: PhosphorIconsBold.arrowsLeftRight, elementType: 'variable', variableContent: 'remaining'),
            SectionField(key: 'cash_amount', label: 'مدفوع نقداً', icon: PhosphorIconsBold.money, elementType: 'variable', variableContent: 'cash_amount'),
            SectionField(key: 'bank_amount', label: 'مدفوع بنكياً', icon: PhosphorIconsBold.bank, elementType: 'variable', variableContent: 'bank_amount'),
            SectionField(key: 'click_amount', label: 'مدفوع كليك', icon: PhosphorIconsBold.deviceMobile, elementType: 'variable', variableContent: 'click_amount'),
          ],
        ),

      // ── NOTES (from POS) ──
      InvoiceSection(
        id: 'notes_section',
        title: 'الملاحظات',
        icon: PhosphorIconsBold.notepad,
        color: const Color(0xFF9333EA),
        fields: [
          SectionField(key: 'notes', label: 'ملاحظات الفاتورة', icon: PhosphorIconsBold.notepad, elementType: 'variable', variableContent: 'notes'),
          if (isKitchen)
            SectionField(key: 'kitchen_notes', label: 'ملاحظات المطبخ', icon: PhosphorIconsBold.cookingPot, elementType: 'variable', variableContent: 'kitchen_notes'),
        ],
      ),

      // ── FOOTER ──
      InvoiceSection(
        id: 'footer',
        title: 'التذييل',
        icon: PhosphorIconsBold.textAlignCenter,
        color: const Color(0xFF6B7280),
        fields: [
          SectionField(key: 'footer_text', label: 'نص التذييل', icon: PhosphorIconsBold.textT, elementType: 'text', variableContent: 'footer_text'),
          SectionField(key: 'qr_code', label: 'QR Code', icon: PhosphorIconsBold.qrCode, elementType: 'variable', variableContent: 'qr_code'),
          SectionField(key: 'tax_registration', label: 'الرقم الضريبي (تذييل)', icon: PhosphorIconsBold.identificationBadge, elementType: 'variable', variableContent: 'tax_registration'),
        ],
      ),
    ];
  }

  void _toggleField(SectionField field) {
    setState(() => field.isVisible = !field.isVisible);
    if (field.isVisible) {
      // First check if element already exists → just set visible
      final existing = widget.elements.where((e) => e.content == field.variableContent).toList();
      if (existing.isNotEmpty) {
        // Element exists — mark visible
        widget.onElementUpdated(existing.first.copyWith(isVisible: true));
      } else {
        // No element exists — create new one
        // `items_table` علامةُ واجهةٍ لا نوعُ عنصر: الصيغةُ المخزَّنة
        // `variable` + `content='items_table'`، وما سواها يحذفه
        // `_migrateOldFormatElements` كلَّ إقلاع.
        widget.onAddElement(
          field.elementType == 'items_table' ? 'variable' : field.elementType,
          variableContent: field.variableContent,
        );
      }
    } else {
      // Hide by setting isVisible=false (not deleting)
      final match = widget.elements.where((e) => e.content == field.variableContent).toList();
      if (match.isNotEmpty) {
        widget.onElementUpdated(match.first.copyWith(isVisible: false));
      }
    }
  }

  void _moveFieldUp(InvoiceSection section, int fieldIndex) {
    if (fieldIndex <= 0) return;
    setState(() {
      final field = section.fields.removeAt(fieldIndex);
      section.fields.insert(fieldIndex - 1, field);
    });
    _recalcSortOrder();
  }

  void _moveFieldDown(InvoiceSection section, int fieldIndex) {
    if (fieldIndex >= section.fields.length - 1) return;
    setState(() {
      final field = section.fields.removeAt(fieldIndex);
      section.fields.insert(fieldIndex + 1, field);
    });
    _recalcSortOrder();
  }

  /// Move a field from one section to another (or within same section)
  void _moveFieldCrossSection(
      InvoiceSection fromSection, int fromIndex,
      InvoiceSection toSection, int toIndex) {
    if (fromSection == toSection && fromIndex == toIndex) return;
    setState(() {
      final field = fromSection.fields.removeAt(fromIndex);
      // Adjust target index if within same section and source was before target
      final adjustedIndex = (fromSection == toSection && fromIndex < toIndex)
          ? toIndex - 1
          : toIndex;
      toSection.fields.insert(adjustedIndex.clamp(0, toSection.fields.length), field);
    });
    _recalcSortOrder();
  }

  /// Recalculate sortOrder across all sections → push to DB elements
  /// Also updates the element's DB `section` field when moved between sections
  ///
  /// **يرقّم كلَّ عنصرٍ في القالب لا ما يقابله حقلٌ وحدَه.** المطابقةُ بـ
  /// `content` تترك يتامى: الفواصلُ تُبذر بلا محتوى، ونصُّ التذييل يُبذر
  /// بمحتواه العربيّ بينما حقلُه `footer_text`. وبعد أن صار `sortOrder` حَكَمَ
  /// المطبوع (الخيار ب) كان أوّلُ حفظٍ يقذف «شكراً لتعاملكم معنا» فوق جدول
  /// الأصناف ويبعثر الفواصلَ داخل كتلة العميل. فاليتيمُ يلحق بسابقه.
  void _recalcSortOrder({bool suppressHasChanges = false}) {
    final screenRank = <String, int>{};
    final sectionOf = <String, String>{};
    int order = 0;
    for (final section in _sections) {
      final dbSection = _sectionIdToDbSection(section.id);
      for (final field in section.fields) {
        if (field.variableContent == null) continue;
        screenRank[field.variableContent!] = order;
        sectionOf[field.variableContent!] = dbSection;
        order++;
      }
    }

    final newOrder = resequenceTemplateElements(
      elements: widget.elements
          .map((e) => (id: e.id, content: e.content, sortOrder: e.sortOrder))
          .toList(),
      screenRank: screenRank,
    );

    for (final el in [...widget.elements]) {
      final sort = newOrder[el.id];
      if (sort == null) continue;
      final section = el.content == null ? null : sectionOf[el.content!];
      if (el.sortOrder == sort && (section == null || el.section == section)) {
        continue;
      }
      widget.onElementUpdated(
        el.copyWith(sortOrder: sort, section: section ?? el.section),
        suppressHasChanges: suppressHasChanges,
      );
    }
  }

  /// Map UI section ID to DB section value
  String _sectionIdToDbSection(String sectionId) {
    switch (sectionId) {
      case 'header': return 'header';
      case 'invoice_info': return 'body';
      case 'customer': return 'body';
      case 'delivery': return 'body';
      case 'items_table': return 'details';
      case 'totals': return 'footer';
      case 'notes_section': return 'footer';
      case 'footer': return 'footer';
      default: return 'body'; // shift_* sections
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── LEFT: Section Editor ──
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey.shade50,
            child: Column(
              children: [
                _buildEditorHeader(),
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    itemCount: _sections.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final section = _sections.removeAt(oldIndex);
                        _sections.insert(newIndex, section);
                      });
                      // سحبُ قسمٍ كامل كان يحرّك الشاشةَ ولا يُكتب في القاعدة
                      // — بخلاف تحريك حقلٍ مفرد. فالمالكُ يرتّب أقسامَه ثم
                      // تخرج الورقةُ كما كانت.
                      _recalcSortOrder();
                    },
                    proxyDecorator: (child, _, _) => Material(elevation: 6, borderRadius: BorderRadius.circular(12), child: child),
                    itemBuilder: (_, index) => _buildSectionCard(_sections[index], index),
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── RIGHT: Live Preview ──
        Expanded(flex: 3, child: _buildLivePreview()),
      ],
    );
  }

  Widget _buildEditorHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 3, offset: const Offset(0, 1))],
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.layout, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          const Text('أقسام الفاتورة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: Text('${_sections.where((s) => s.isVisible).length} أقسام',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(InvoiceSection section, int index) {
    final visibleFields = section.fields.where((f) => f.isVisible).length;
    final totalFields = section.fields.length;

    return Card(
      key: ValueKey(section.id),
      elevation: section.isExpanded ? 2 : 0.5,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: section.isExpanded ? section.color.withValues(alpha: 0.5) : Colors.grey.shade200,
          width: section.isExpanded ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // Section Header
          InkWell(
            onTap: () => setState(() => section.isExpanded = !section.isExpanded),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(10),
              bottom: section.isExpanded ? Radius.zero : const Radius.circular(10),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: section.isExpanded ? section.color.withValues(alpha: 0.06) : Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(10),
                  bottom: section.isExpanded ? Radius.zero : const Radius.circular(10),
                ),
              ),
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: Icon(PhosphorIconsBold.dotsSixVertical, size: 14, color: Colors.grey.shade400),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: section.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: Icon(section.icon, size: 14, color: section.color),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(section.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: section.color)),
                        Text('$visibleFields/$totalFields مفعل', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 28,
                    child: Switch(
                      value: section.isVisible,
                      activeThumbColor: section.color,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (val) {
                        setState(() {
                          section.isVisible = val;
                          for (final field in section.fields) {
                            if (field.isVisible != val) _toggleField(field);
                          }
                        });
                      },
                    ),
                  ),
                  AnimatedRotation(
                    turns: section.isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(PhosphorIconsBold.caretLeft, size: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
          // Section Fields
          if (section.isExpanded)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                children: List.generate(section.fields.length, (i) {
                  final field = section.fields[i];
                  if (field.elementType == 'items_table') return _buildItemsTableSection(field, section.color);
                  return _buildFieldRow(field, section, i);
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFieldRow(SectionField field, InvoiceSection section, int index) {
    final isImage = field.elementType == 'image';
    final payload = _DragFieldPayload(sourceSection: section, sourceIndex: index, field: field);

    final fieldContent = Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: field.isVisible ? section.color.withValues(alpha: 0.04) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: field.isVisible ? section.color.withValues(alpha: 0.15) : Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Main row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                // Reorder arrows + drag handle
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: index > 0 ? () => _moveFieldUp(section, index) : null,
                      child: Icon(PhosphorIconsBold.caretUp, size: 12,
                          color: index > 0 ? section.color : Colors.grey.shade300),
                    ),
                    Icon(PhosphorIconsBold.dotsSixVertical, size: 12, color: section.color.withValues(alpha: 0.5)),
                    InkWell(
                      onTap: index < section.fields.length - 1 ? () => _moveFieldDown(section, index) : null,
                      child: Icon(PhosphorIconsBold.caretDown, size: 12,
                          color: index < section.fields.length - 1 ? section.color : Colors.grey.shade300),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                // Icon + Label
                Icon(field.icon, size: 14, color: field.isVisible ? section.color : Colors.grey.shade400),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(field.label, style: TextStyle(fontSize: 11,
                      fontWeight: field.isVisible ? FontWeight.w600 : FontWeight.normal,
                      color: field.isVisible ? Colors.black87 : Colors.grey.shade500)),
                ),
                // Controls (visible when field is on)
                if (field.isVisible) ...[
                  // Inline toggle (side-by-side)
                  _buildMiniButton(
                    icon: PhosphorIconsBold.columns,
                    isActive: field.isInline,
                    color: section.color,
                    tooltip: 'جنب العنصر التالي',
                    onTap: () { setState(() => field.isInline = !field.isInline); _pushFieldToElement(field); },
                  ),
                  const SizedBox(width: 2),
                  // Bold toggle
                  _buildMiniButton(
                    icon: PhosphorIconsBold.textB,
                    isActive: field.isBold,
                    color: section.color,
                    tooltip: 'عريض',
                    onTap: () { setState(() => field.isBold = !field.isBold); _pushFieldToElement(field); },
                  ),
                  const SizedBox(width: 2),
                  // Font size -/+
                  _buildMiniButton(
                    icon: PhosphorIconsBold.minus,
                    isActive: false,
                    color: section.color,
                    tooltip: 'تصغير الخط',
                    onTap: () { setState(() => field.fontSize = (field.fontSize > 0 ? field.fontSize : 11) - 1); _pushFieldToElement(field); },
                  ),
                  if (field.fontSize > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Text('${field.fontSize.toInt()}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: section.color)),
                    ),
                  _buildMiniButton(
                    icon: PhosphorIconsBold.plus,
                    isActive: false,
                    color: section.color,
                    tooltip: 'تكبير الخط',
                    onTap: () { setState(() => field.fontSize = (field.fontSize > 0 ? field.fontSize : 11) + 1); _pushFieldToElement(field); },
                  ),
                  const SizedBox(width: 4),
                  // Alignment controls
                  _buildAlignButton(field, FieldAlignment.right, PhosphorIconsBold.textAlignRight, section.color, pushToElement: true),
                  _buildAlignButton(field, FieldAlignment.center, PhosphorIconsBold.textAlignCenter, section.color, pushToElement: true),
                  _buildAlignButton(field, FieldAlignment.left, PhosphorIconsBold.textAlignLeft, section.color, pushToElement: true),
                  const SizedBox(width: 4),
                ],
                // Toggle
                InkWell(
                  onTap: () => _toggleField(field),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: field.isVisible
                        ? Icon(PhosphorIconsBold.checkCircle, size: 18, color: section.color, key: const ValueKey('on'))
                        : Icon(PhosphorIconsBold.circle, size: 18, color: Colors.grey.shade300, key: const ValueKey('off')),
                  ),
                ),
              ],
            ),
          ),
          // Size slider for images
          if (isImage && field.isVisible)
            Padding(
              padding: const EdgeInsets.only(right: 32, left: 16, bottom: 6),
              child: Row(
                children: [
                  Text('الحجم:', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(overlayShape: SliderComponentShape.noOverlay, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
                      child: Slider(
                        value: field.sizePercent,
                        min: 0.15, max: 1.0,
                        activeColor: section.color,
                        inactiveColor: section.color.withValues(alpha: 0.15),
                        onChanged: (v) {
                        setState(() => field.sizePercent = v);
                        _pushFieldToElement(field);
                      },
                      ),
                    ),
                  ),
                  Text('${(field.sizePercent * 100).toInt()}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: section.color)),
                ],
              ),
            ),
        ],
      ),
    );

    // Wrap with DragTarget + LongPressDraggable for cross-section reorder
    return DragTarget<_DragFieldPayload>(
      onWillAcceptWithDetails: (details) => details.data.field != field,
      onAcceptWithDetails: (details) {
        _moveFieldCrossSection(
          details.data.sourceSection, details.data.sourceIndex,
          section, index,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return Column(
          children: [
            if (isHovered)
              Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: section.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            LongPressDraggable<_DragFieldPayload>(
              data: payload,
              axis: Axis.vertical,
              delay: const Duration(milliseconds: 500),
              feedback: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 250,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: section.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: section.color, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(field.icon, size: 16, color: section.color),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(field.label,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: section.color),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: fieldContent),
              child: fieldContent,
            ),
          ],
        );
      },
    );
  }

  Widget _buildMiniButton({required IconData icon, required bool isActive, required Color color, required String tooltip, required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: isActive ? color.withValues(alpha: 0.4) : Colors.grey.shade300, width: 0.5),
          ),
          child: Icon(icon, size: 12, color: isActive ? color : Colors.grey.shade500),
        ),
      ),
    );
  }

  Widget _buildAlignButton(SectionField field, FieldAlignment align, IconData icon, Color color, {bool pushToElement = false}) {
    final isActive = field.alignment == align;
    return InkWell(
      onTap: () {
        setState(() => field.alignment = align);
        if (pushToElement) _pushFieldToElement(field);
      },
      child: Container(
        padding: const EdgeInsets.all(3),
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 12, color: isActive ? color : Colors.grey.shade400),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ITEMS TABLE SECTION — with additions/options support
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildItemsTableSection(SectionField field, Color sectionColor) {
    final ts = widget.tableSettings;
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: sectionColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sectionColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsBold.table, size: 14, color: sectionColor),
              const SizedBox(width: 6),
              Text('جدول الأصناف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: sectionColor)),
            ],
          ),
          const SizedBox(height: 8),
          // Column toggles
          Text('الأعمدة:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          if (ts != null) ...[
            Wrap(spacing: 4, runSpacing: 4, children: [
              _colChip('م', ts.showIndex, (v) => widget.onUpdateTableSettings(ts.copyWith(showIndex: v))),
              _colChip('المنتج', ts.showProductName, (v) => widget.onUpdateTableSettings(ts.copyWith(showProductName: v))),
              _colChip('كود', ts.showProductCode, (v) => widget.onUpdateTableSettings(ts.copyWith(showProductCode: v))),
              _colChip('الكمية', ts.showQuantity, (v) => widget.onUpdateTableSettings(ts.copyWith(showQuantity: v))),
              _colChip('السعر', ts.showUnitPrice, (v) => widget.onUpdateTableSettings(ts.copyWith(showUnitPrice: v))),
              _colChip('الوحدة', ts.showUnit, (v) => widget.onUpdateTableSettings(ts.copyWith(showUnit: v))),
              _colChip('الخصم', ts.showDiscount, (v) => widget.onUpdateTableSettings(ts.copyWith(showDiscount: v))),
              _colChip('الضريبة', ts.showTax, (v) => widget.onUpdateTableSettings(ts.copyWith(showTax: v))),
              _colChip('الإجمالي', ts.showTotal, (v) => widget.onUpdateTableSettings(ts.copyWith(showTotal: v))),
              _colChip('الباركود', ts.showBarcode, (v) => widget.onUpdateTableSettings(ts.copyWith(showBarcode: v))),
              _colChip('ملاحظات', ts.showNotes, (v) => widget.onUpdateTableSettings(ts.copyWith(showNotes: v))),
            ]),
            const SizedBox(height: 6),
            // Table header visibility toggle
            _colChip('عنوان الجدول', _getJsonBool(ts, '_showHeader', true), (v) => _setJsonBool(ts, '_showHeader', v)),
            const SizedBox(height: 8),
            // Extra rows: additions & options
            Text('صفوف إضافية:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, children: [
              _colChip('إضافات الصنف', _showAdditions, (v) => setState(() => _showAdditions = v)),
              _colChip('خيارات الصنف', _showOptions, (v) => setState(() => _showOptions = v)),
            ]),
            const SizedBox(height: 8),
            // Header font size
            Row(
              children: [
                Text('خط العنوان:', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(overlayShape: SliderComponentShape.noOverlay, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
                    child: Slider(
                      value: ts.headerFontSize.clamp(1, 24),
                      min: 1, max: 24, divisions: 23,
                      activeColor: sectionColor,
                      onChanged: (v) => widget.onUpdateTableSettings(ts.copyWith(headerFontSize: v)),
                    ),
                  ),
                ),
                Text('${ts.headerFontSize.toStringAsFixed(0)}pt', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: sectionColor)),
              ],
            ),
            // Header bold toggle
            _boldToggle('عنوان بولد', _getJsonBool(ts, '_headerBold', true), (v) => _setJsonBool(ts, '_headerBold', v), sectionColor),
            const SizedBox(height: 6),
            // Body font size
            Row(
              children: [
                Text('خط البيانات:', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(overlayShape: SliderComponentShape.noOverlay, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
                    child: Slider(
                      value: ts.fontSize.clamp(1, 24),
                      min: 1, max: 24, divisions: 23,
                      activeColor: sectionColor,
                      onChanged: (v) => widget.onUpdateTableSettings(ts.copyWith(fontSize: v)),
                    ),
                  ),
                ),
                Text('${ts.fontSize.toStringAsFixed(0)}pt', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: sectionColor)),
              ],
            ),
            // Body bold toggle
            _boldToggle('بيانات بولد', _getJsonBool(ts, '_bodyBold', false), (v) => _setJsonBool(ts, '_bodyBold', v), sectionColor),
            const SizedBox(height: 8),
            // Decimal precision
            Row(
              children: [
                Text('العلامة العشرية:', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                const SizedBox(width: 8),
                ...List.generate(4, (i) {
                  final isActive = _decimalPlaces == i;
                  return Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _decimalPlaces = i);
                        // Persist decimal places in columnWidths JSON
                        _saveDecimalPlaces();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isActive ? sectionColor.withValues(alpha: 0.15) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isActive ? sectionColor : Colors.grey.shade300),
                        ),
                        child: Text(i == 0 ? '0' : (1.0).toStringAsFixed(i),
                            style: TextStyle(fontSize: 10, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? sectionColor : Colors.grey.shade600)),
                      ),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 10),
            // ── Custom Header Labels ──
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              dense: true,
              title: Row(
                children: [
                  Icon(PhosphorIconsBold.textAa, size: 14, color: sectionColor),
                  const SizedBox(width: 6),
                  Text('تعديل عناوين الأعمدة', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sectionColor)),
                ],
              ),
              children: [
                _headerLabelRow('index', 'م', ts, sectionColor, visible: ts.showIndex),
                _headerLabelRow('product', 'الصنف', ts, sectionColor, visible: ts.showProductName),
                _headerLabelRow('code', 'الكود', ts, sectionColor, visible: ts.showProductCode),
                _headerLabelRow('quantity', 'العدد', ts, sectionColor, visible: ts.showQuantity),
                _headerLabelRow('price', 'السعر', ts, sectionColor, visible: ts.showUnitPrice),
                _headerLabelRow('discount', 'الخصم', ts, sectionColor, visible: ts.showDiscount),
                _headerLabelRow('tax', 'الضريبة', ts, sectionColor, visible: ts.showTax),
                _headerLabelRow('total', 'الإجمالي', ts, sectionColor, visible: ts.showTotal),
                _headerLabelRow('unit', 'الوحدة', ts, sectionColor, visible: ts.showUnit),
                _headerLabelRow('barcode', 'الباركود', ts, sectionColor, visible: ts.showBarcode),
              ],
            ),
          ] else
            Text('سيتم إنشاء إعدادات الجدول تلقائياً عند الحفظ', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  // State for additional table rows & decimal precision
  bool _showAdditions = true;
  bool _showOptions = true;
  int _decimalPlaces = 2; // 0, 1, 2, 3

  void _loadDecimalPlaces() {
    final ts = widget.tableSettings;
    if (ts?.columnWidths != null) {
      try {
        final decoded = jsonDecode(ts!.columnWidths!) as Map<String, dynamic>;
        if (decoded.containsKey('_decimalPlaces')) {
          _decimalPlaces = (decoded['_decimalPlaces'] as num).toInt();
        }
      } catch (_) {}
    }
  }

  void _saveDecimalPlaces() {
    final ts = widget.tableSettings;
    if (ts == null) return;
    Map<String, dynamic> existing = {};
    try {
      if (ts.columnWidths != null) {
        existing = jsonDecode(ts.columnWidths!) as Map<String, dynamic>;
      }
    } catch (_) {}
    existing['_decimalPlaces'] = _decimalPlaces;
    widget.onUpdateTableSettings(ts.copyWith(columnWidths: Value(jsonEncode(existing))));
  }

  /// Read a boolean flag from the columnWidths JSON
  /// ⚠️ نفسُ تسامح الطابعة والمعاينة: رقاقةٌ تُرسم مطفأةً بينما الطابعةُ
  /// تقرأ العلَمَ مشتعلاً (أو العكس) تجعل المستخدمَ يصلح ما ليس معطوباً.
  /// اقرأ `core/utils/template_json_flags.dart`.
  bool _getJsonBool(InvoiceTableSetting ts, String key, bool defaultValue) {
    if (ts.columnWidths == null || ts.columnWidths!.isEmpty) {
      return defaultValue;
    }
    try {
      final decoded = jsonDecode(ts.columnWidths!);
      if (decoded is! Map<String, dynamic>) return defaultValue;
      if (!decoded.containsKey(key)) return defaultValue;
      return readJsonFlag(decoded[key], defaultValue: defaultValue);
    } catch (_) {
      return defaultValue;
    }
  }

  /// Write a boolean flag to the columnWidths JSON
  void _setJsonBool(InvoiceTableSetting ts, String key, bool value) {
    Map<String, dynamic> existing = {};
    try {
      if (ts.columnWidths != null) {
        existing = jsonDecode(ts.columnWidths!) as Map<String, dynamic>;
      }
    } catch (_) {}
    existing[key] = value;
    widget.onUpdateTableSettings(ts.copyWith(columnWidths: Value(jsonEncode(existing))));
  }

  /// Build a compact bold toggle row
  Widget _boldToggle(String label, bool isActive, ValueChanged<bool> onChanged, Color color) {
    return GestureDetector(
      onTap: () => onChanged(!isActive),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: isActive ? color : Colors.grey.shade400,
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: isActive ? color : Colors.grey.shade600)),
        ],
      ),
    );
  }

  /// Get a custom header label from columnWidths JSON
  String _getHeaderLabel(InvoiceTableSetting ts, String columnKey, String defaultLabel) {
    if (ts.columnWidths != null && ts.columnWidths!.isNotEmpty) {
      try {
        final decoded = jsonDecode(ts.columnWidths!) as Map<String, dynamic>;
        return (decoded['_label_$columnKey'] as String?) ?? defaultLabel;
      } catch (_) {}
    }
    return defaultLabel;
  }

  /// Save a custom header label to columnWidths JSON
  void _setHeaderLabel(InvoiceTableSetting ts, String columnKey, String label, String defaultLabel) {
    Map<String, dynamic> existing = {};
    try {
      if (ts.columnWidths != null) {
        existing = jsonDecode(ts.columnWidths!) as Map<String, dynamic>;
      }
    } catch (_) {}
    if (label.isEmpty || label == defaultLabel) {
      existing.remove('_label_$columnKey');
    } else {
      existing['_label_$columnKey'] = label;
    }
    widget.onUpdateTableSettings(ts.copyWith(columnWidths: Value(jsonEncode(existing))));
  }

  /// Build a compact header label edit row
  Widget _headerLabelRow(String columnKey, String defaultLabel, InvoiceTableSetting ts, Color color, {bool visible = true}) {
    if (!visible) return const SizedBox.shrink();
    final currentLabel = _getHeaderLabel(ts, columnKey, defaultLabel);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(defaultLabel, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_forward, size: 12, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 28,
              child: TextFormField(
                initialValue: currentLabel == defaultLabel ? '' : currentLabel,
                decoration: InputDecoration(
                  hintText: defaultLabel,
                  hintStyle: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: color)),
                  isDense: true,
                ),
                style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
                onChanged: (val) => _setHeaderLabel(ts, columnKey, val.trim(), defaultLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colChip(String label, bool active, ValueChanged<bool> onChanged) {
    const purple = Color(0xFF7C3AED);
    return GestureDetector(
      onTap: () => onChanged(!active),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? purple.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? purple.withValues(alpha: 0.35) : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.circle, size: 12, color: active ? purple : Colors.grey.shade400),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: active ? FontWeight.w600 : FontWeight.normal, color: active ? purple : Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIVE PREVIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLivePreview() {
    final isThermal = widget.templateType == 'thermal' || widget.templateType == 'kitchen';
    final paperWidthPx = isThermal ? 300.0 : 500.0;

    return Container(
      color: const Color(0xFFE5E7EB),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.eye, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                const Text('معاينة مباشرة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                  child: Text(isThermal ? '🧾 ${widget.paperWidth.toInt()}mm' : '📄 A4',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Container(
                  width: paperWidthPx,
                  constraints: const BoxConstraints(minHeight: 300),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))],
                  ),
                  padding: const EdgeInsets.all(14),
                  child: _buildPreviewContent(isThermal),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewContent(bool isThermal) {
    final List<Widget> widgets = [];
    final ph = _placeholders();

    for (final section in _sections) {
      if (!section.isVisible) continue;
      final visible = section.fields.where((f) => f.isVisible).toList();
      if (visible.isEmpty) continue;

      if (widgets.isNotEmpty) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Divider(color: Colors.grey.shade300, height: 1),
        ));
      }

      // Group inline fields together
      int i = 0;
      while (i < visible.length) {
        final field = visible[i];
        if (field.elementType == 'items_table') {
          widgets.add(_previewTable(isThermal));
          i++;
        } else if (field.isInline && i + 1 < visible.length) {
          // Collect consecutive inline fields into a row group
          final group = <SectionField>[field];
          while (i + group.length < visible.length && group.last.isInline) {
            group.add(visible[i + group.length]);
          }
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: group.map((f) {
                if (f.elementType == 'image') {
                  return Expanded(child: _previewImage(f));
                }
                return Expanded(child: _previewField(f, section, ph));
              }).toList(),
            ),
          ));
          i += group.length;
        } else if (field.elementType == 'image') {
          widgets.add(_previewImage(field));
          i++;
        } else {
          widgets.add(_previewField(field, section, ph));
          i++;
        }
      }
    }

    if (widgets.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(PhosphorIconsBold.fileX, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 6),
          Text('لا توجد عناصر مفعلة', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widgets);
  }

  TextAlign _alignToTextAlign(FieldAlignment a) {
    switch (a) {
      case FieldAlignment.right: return TextAlign.right;
      case FieldAlignment.center: return TextAlign.center;
      case FieldAlignment.left: return TextAlign.left;
    }
  }

  Alignment _alignToAlignment(FieldAlignment a) {
    switch (a) {
      case FieldAlignment.right: return Alignment.centerRight;
      case FieldAlignment.center: return Alignment.center;
      case FieldAlignment.left: return Alignment.centerLeft;
    }
  }

  Widget _previewImage(SectionField field) {
    final width = 100.0 * field.sizePercent.clamp(0.15, 1.0);
    return Align(
      alignment: _alignToAlignment(field.alignment),
      child: Container(
        width: width, height: width * 0.6,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(PhosphorIconsBold.image, color: Colors.grey, size: 14),
            const SizedBox(width: 4),
            Text('LOGO', style: TextStyle(color: Colors.grey.shade500, fontSize: 9)),
          ]),
        ),
      ),
    );
  }

  Widget _previewField(SectionField field, InvoiceSection section, Map<String, String> ph) {
    final value = ph[field.variableContent] ?? field.label;
    final isHeader = section.id == 'header';
    final isTotals = section.id == 'totals' || section.id.startsWith('shift_');
    final isMainTotal = field.key == 'total_amount' || field.key == 'shift_total_variance';

    // Per-field font settings
    final baseFontSize = field.fontSize > 0 ? field.fontSize : null;
    final boldWeight = field.isBold ? FontWeight.bold : null;

    if (isHeader && field.key == 'company_name') {
      final fs = baseFontSize ?? 15.0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Text(value, textAlign: _alignToTextAlign(field.alignment),
            style: TextStyle(fontSize: fs, fontWeight: boldWeight ?? FontWeight.bold)),
      );
    }
    if (isHeader) {
      final fs = baseFontSize ?? 10.0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 0.5),
        child: Text(value, textAlign: _alignToTextAlign(field.alignment),
            style: TextStyle(fontSize: fs, fontWeight: boldWeight, color: Colors.grey.shade700)),
      );
    }
    if (isTotals) {
      final fs = baseFontSize ?? (isMainTotal ? 12.0 : 10.0);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(field.label, style: TextStyle(fontSize: fs, fontWeight: boldWeight ?? (isMainTotal ? FontWeight.bold : FontWeight.normal))),
            Text(value, style: TextStyle(fontSize: fs + 1, fontWeight: boldWeight ?? (isMainTotal ? FontWeight.bold : FontWeight.w600))),
          ],
        ),
      );
    }
    // Default key-value layout
    final fs = baseFontSize ?? 11.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text('${field.label}:', style: TextStyle(fontSize: fs - 1, color: Colors.grey.shade600, fontWeight: boldWeight))),
          Expanded(child: Text(value, textAlign: _alignToTextAlign(field.alignment), style: TextStyle(fontSize: fs, fontWeight: boldWeight ?? FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _previewTable(bool isThermal) {
    final ts = widget.tableSettings;
    final headers = <String>[];
    if (ts != null) {
      if (ts.showIndex) headers.add('م');
      if (ts.showProductName) headers.add('المنتج');
      if (ts.showProductCode) headers.add('كود');
      if (ts.showQuantity) headers.add('الكمية');
      if (ts.showUnitPrice) headers.add('السعر');
      if (ts.showUnit) headers.add('الوحدة');
      if (ts.showDiscount) headers.add('خصم');
      if (ts.showTax) headers.add('ض');
      if (ts.showTotal) headers.add('الإجمالي');
      if (ts.showBarcode) headers.add('باركود');
      if (ts.showNotes) headers.add('ملاحظات');
    }
    if (headers.isEmpty) headers.addAll(['م', 'المنتج', 'الكمية', 'السعر', 'الإجمالي']);

    final fontSize = (ts?.fontSize ?? 10).clamp(8, 14).toDouble();

    // Sample data: 3 items
    final items = [
      {'idx': '1', 'name': 'أرز بسمتي 5كجم', 'code': 'P001', 'qty': '2', 'price': '100', 'unit': 'كجم', 'disc': '0', 'tax': '14', 'total': '214', 'barcode': '622115', 'notes': '', 'additions': '+ كيس تعبئة (2 ج)', 'options': 'حجم: كبير'},
      {'idx': '2', 'name': 'زيت ذرة 1لتر', 'code': 'P002', 'qty': '1', 'price': '50', 'unit': 'قطعة', 'disc': '5', 'tax': '7', 'total': '52', 'barcode': '622116', 'notes': '', 'additions': '', 'options': ''},
      {'idx': '3', 'name': 'برجر لحم', 'code': 'P003', 'qty': '1', 'price': '85', 'unit': 'قطعة', 'disc': '0', 'tax': '12', 'total': '97', 'barcode': '622117', 'notes': 'حار', 'additions': '+ جبنة شيدر (+5 ج)\n+ بطاطس (+10 ج)', 'options': 'حجم: وسط | صوص: باربكيو'},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
            child: Row(
              children: headers.map((h) => Expanded(
                flex: h == 'المنتج' ? 3 : (h == 'باركود' || h == 'ملاحظات' ? 2 : 1),
                child: Text(h, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: fontSize - 1, fontWeight: FontWeight.bold, color: Colors.white)),
              )).toList(),
            ),
          ),
          // Rows
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final row = _buildRowCells(ts, item);
            final hasAdditions = _showAdditions && (item['additions'] ?? '').isNotEmpty;
            final hasOptions = _showOptions && (item['options'] ?? '').isNotEmpty;

            return Column(
              children: [
                // Main data row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  decoration: BoxDecoration(
                    color: i.isEven ? Colors.white : Colors.grey.shade50,
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: row.asMap().entries.map((e) {
                      final ci = e.key;
                      return Expanded(
                        flex: ci == 1 ? 3 : (ci >= row.length - 2 && headers.length > 5 ? 2 : 1),
                        child: Text(e.value, textAlign: TextAlign.center, style: TextStyle(fontSize: fontSize - 1)),
                      );
                    }).toList(),
                  ),
                ),
                // Additions row
                if (hasAdditions)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    color: const Color(0xFFF0FDF4),
                    child: Text('  ${item['additions']}',
                        style: TextStyle(fontSize: fontSize - 2, color: const Color(0xFF16A34A), fontStyle: FontStyle.italic)),
                  ),
                // Options row
                if (hasOptions)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    color: const Color(0xFFFEF3C7),
                    child: Text('  ${item['options']}',
                        style: TextStyle(fontSize: fontSize - 2, color: const Color(0xFFD97706), fontStyle: FontStyle.italic)),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  /// Format a numeric string with the configured decimal places
  String _fmtNum(String raw) {
    final n = double.tryParse(raw);
    if (n == null) return raw;
    return n.toStringAsFixed(_decimalPlaces);
  }

  List<String> _buildRowCells(InvoiceTableSetting? ts, Map<String, String> item) {
    if (ts == null) return [item['idx']!, item['name']!, _fmtNum(item['qty']!), _fmtNum(item['price']!), _fmtNum(item['total']!)];
    final cells = <String>[];
    if (ts.showIndex) cells.add(item['idx']!);
    if (ts.showProductName) cells.add(item['name']!);
    if (ts.showProductCode) cells.add(item['code']!);
    if (ts.showQuantity) cells.add(_fmtNum(item['qty']!));
    if (ts.showUnitPrice) cells.add(_fmtNum(item['price']!));
    if (ts.showUnit) cells.add(item['unit']!);
    if (ts.showDiscount) cells.add(_fmtNum(item['disc']!));
    if (ts.showTax) cells.add(_fmtNum(item['tax']!));
    if (ts.showTotal) cells.add(_fmtNum(item['total']!));
    if (ts.showBarcode) cells.add(item['barcode']!);
    if (ts.showNotes) cells.add(item['notes']!);
    if (cells.isEmpty) cells.addAll([item['idx']!, item['name']!, _fmtNum(item['qty']!), _fmtNum(item['price']!), _fmtNum(item['total']!)]);
    return cells;
  }

  Map<String, String> _placeholders() => {
    'company_name': 'سوبر ماركت المدينة',
    'company_address': 'شارع الملك فيصل - الجيزة',
    'company_phone': '01099999999',
    'company_tax_number': '123-456-789',
    'branch_name': 'الفرع الرئيسي',
    'invoice_number': 'R-1234',
    'order_number': '5678',
    'date': '2026/01/01',
    'time': '14:30',
    'cashier_name': 'أحمد محمد',
    'warehouse_name': 'المخزن الرئيسي',
    'payment_method': 'نقدي',
    'sale_type': 'مبيعات',
    'invoice_type_label': 'فاتورة مبيعات',
    'customer_name': 'عميل نقدي',
    'customer_phone': '01012345678',
    'customer_address': 'القاهرة',
    'supplier_name': 'شركة التوريدات',
    'adhoc_customer_name': 'محمد أحمد',
    'adhoc_customer_phone': '01023456789',
    'table_number': 'طاولة 5',
    'waiter_name': 'خالد',
    'delivery_type': 'توصيل منزلي',
    'delivery_address': 'شارع التحرير - الدقي',
    'delivery_fee': '15.00',
    'courier_name': 'محمد السائق',
    'subtotal': '351.50',
    'discount': '5.00',
    'tax_amount': '49.21',
    'total_amount': '395.71',
    'paid': '400.00',
    'remaining': '4.29',
    'cash_amount': '300.00',
    'bank_amount': '100.00',
    'click_amount': '0.00',
    'notes': 'شكراً لزيارتكم',
    'footer_text': 'البضاعة المباعة لا ترد ولا تستبدل',
    'qr_code': '[QR Code]',
    'tax_registration': '123-456-789',
    'kitchen_notes': 'بدون بصل — حار',
    'shift_invoice_count': '45',
    'shift_total_sales': '12,500.00',
    'shift_total_expenses': '350.00',
    'shift_cash_refunds': '150.00',
    'shift_system_cash': '8,500.00',
    'shift_actual_cash': '8,470.00',
    'shift_cash_variance': '-30.00',
    'shift_system_card': '3,500.00',
    'shift_actual_card': '3,500.00',
    'shift_card_variance': '0.00',
    // §٥-٢ — أرقامُ المعاينة **تجمع**: ‏8,500 + 3,500 + 1,200 = 13,200.
    // كانت 12,000 (نقد + بطاقة بلا كليك) فتُعلّم المصمّمَ إجمالياً لا يطابق
    // معروضَه — وهو بعينه العطبُ المرصود في المطبوع.
    'shift_system_click': '1,200.00',
    'shift_actual_click': '1,200.00',
    'shift_click_variance': '0.00',
    'shift_total_system': '13,200.00',
    'shift_total_actual': '13,170.00',
    'shift_total_variance': '-30.00',
    'shift_status': 'عجز: -30.00',
  };
}
