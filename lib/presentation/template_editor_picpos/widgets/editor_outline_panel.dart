import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/design_system/typography.dart';
// اللوحةُ اليسرى — بنيةُ المستند، ومكتبةُ الحقول.
//
// ── بنيةُ المستند ليست قائمةَ زينة ───────────────────────────────────────
// هي الطريقةُ الوحيدةُ لبلوغِ عنصرٍ **مخفيٍّ** أو عنصرٍ وقع تحت آخر: الكانفاسُ
// لا يعطيك ما لا تراه. وعينُ الظهور فيها تُبدّل `visible` مباشرةً.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../domain/printing/template_document.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'editor_canvas.dart' show bandLabel, bandTint;

/// حقولُ المكتبة مجموعةً — نفسُ ترتيب التصميم.
List<({String label, Color tint, List<({String key, String label, IconData icon})> items})> get editorFieldGroups => <({String label, Color tint, List<({String key, String label, IconData icon})> items})>[
  (
    label: tr('الشركة'),
    tint: const Color(0xFF0250D3),
    items: [
      (key: 'company_name', label: tr('اسم الشركة'), icon: PhosphorIconsBold.buildings),
      (key: 'company_name_en', label: tr('الاسم بالإنجليزية'), icon: PhosphorIconsBold.buildings),
      (key: 'company_cr_number', label: tr('السجل التجاري'), icon: PhosphorIconsBold.identificationBadge),
      (key: 'company_address', label: tr('العنوان'), icon: PhosphorIconsBold.mapPin),
      (key: 'company_phone', label: tr('الهاتف'), icon: PhosphorIconsBold.phone),
      (key: 'company_tax_number', label: tr('الرقم الضريبي'), icon: PhosphorIconsBold.identificationBadge),
      (key: 'branch_name', label: tr('الفرع'), icon: PhosphorIconsBold.storefront),
      (key: 'logo', label: tr('الشعار'), icon: PhosphorIconsBold.image),
    ],
  ),
  (
    label: tr('المستند'),
    tint: const Color(0xFF8B5CF6),
    items: [
      (key: 'invoice_number', label: tr('رقم الفاتورة'), icon: PhosphorIconsBold.hash),
      (key: 'order_number', label: tr('رقم الطلب'), icon: PhosphorIconsBold.listNumbers),
      (key: 'date', label: tr('التاريخ'), icon: PhosphorIconsBold.calendar),
      (key: 'time', label: tr('الوقت'), icon: PhosphorIconsBold.clock),
      (key: 'cashier_name', label: tr('الكاشير'), icon: PhosphorIconsBold.user),
      (key: 'payment_method', label: tr('طريقة الدفع'), icon: PhosphorIconsBold.creditCard),
    ],
  ),
  (
    label: tr('الطرف'),
    tint: const Color(0xFF4A80E8),
    items: [
      (key: 'customer_name', label: tr('العميل'), icon: PhosphorIconsBold.user),
      (key: 'customer_phone', label: tr('الهاتف'), icon: PhosphorIconsBold.phone),
      (key: 'customer_address', label: tr('العنوان'), icon: PhosphorIconsBold.mapPin),
    ],
  ),
  (
    label: tr('المجاميع'),
    tint: const Color(0xFF22C55E),
    items: [
      (key: 'subtotal', label: tr('الفرعي'), icon: PhosphorIconsBold.currencyCircleDollar),
      (key: 'discount', label: tr('الخصم'), icon: PhosphorIconsBold.tag),
      (key: 'tax_amount', label: tr('الضريبة'), icon: PhosphorIconsBold.percent),
      (key: 'total', label: tr('الإجمالي'), icon: PhosphorIconsBold.coins),
      (key: 'paid', label: tr('المدفوع'), icon: PhosphorIconsBold.money),
      (key: 'remaining', label: tr('المتبقي'), icon: PhosphorIconsBold.arrowsLeftRight),
    ],
  ),
  (
    label: tr('عناصر حرة'),
    tint: const Color(0xFFF59E0B),
    items: [
      (key: 'line', label: tr('خط فاصل'), icon: PhosphorIconsBold.minus),
      (key: 'qr_code', label: tr('كود QR'), icon: PhosphorIconsBold.qrCode),
      (key: 'barcode', label: tr('باركود'), icon: PhosphorIconsBold.barcode),
      (key: 'notes', label: tr('ملاحظات'), icon: PhosphorIconsBold.notepad),
      (key: 'page_number', label: tr('رقم الصفحة'), icon: PhosphorIconsBold.file),
    ],
  ),
];

/// نوعُ العنصر المشتقُّ من مفتاحه — الشعارُ صورةٌ والفاصلُ خطٌّ لا نصّ.
///
/// ⚠️ وبدونه يُضاف الشعارُ نصّاً فارغاً فتُسقطه قاعدةُ «لا تسميةَ معلَّقة»
/// من الورقة، ويظنّ المستخدمُ أنّ إضافتَه لم تعمل.
ElementKind fieldKindOf(String key) => switch (key) {
      'logo' => ElementKind.image,
      'qr_code' => ElementKind.qrCode,
      'barcode' => ElementKind.barcode,
      'line' => ElementKind.line,
      _ => ElementKind.text,
    };

class EditorOutlinePanel extends StatelessWidget {
  const EditorOutlinePanel({
    super.key,
    required this.document,
    required this.selectedBand,
    required this.selectedElement,
    required this.onSelectBand,
    required this.onSelectElement,
    required this.onToggleVisible,
    required this.onAddField,
    required this.onSelectTable,
    required this.tableSelected,
  });

  final TemplateDocument document;
  final BandId? selectedBand;
  final String? selectedElement;
  final ValueChanged<BandId> onSelectBand;
  final void Function(BandId, String) onSelectElement;
  final void Function(BandId, String, bool) onToggleVisible;
  final void Function(String key, String label, ElementKind kind) onAddField;

  /// يفتح محرّرَ الأعمدة — الجدولُ صفٌّ في البنية لا هدفٌ على الورقة وحدَه.
  final VoidCallback onSelectTable;
  final bool tableSelected;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
           TabBar(
            labelStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            tabs: [
              Tab(height: 42, text: tr('بنية المستند')),
              Tab(height: 42, text: tr('مكتبة الحقول')),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _Outline(
                  document: document,
                  selectedBand: selectedBand,
                  selectedElement: selectedElement,
                  onSelectBand: onSelectBand,
                  onSelectElement: onSelectElement,
                  onToggleVisible: onToggleVisible,
                  onSelectTable: onSelectTable,
                  tableSelected: tableSelected,
                ),
                _FieldLibrary(onAdd: onAddField),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Outline extends StatelessWidget {
  const _Outline({
    required this.document,
    required this.selectedBand,
    required this.selectedElement,
    required this.onSelectBand,
    required this.onSelectElement,
    required this.onToggleVisible,
    required this.onSelectTable,
    required this.tableSelected,
  });

  final TemplateDocument document;
  final BandId? selectedBand;
  final String? selectedElement;
  final ValueChanged<BandId> onSelectBand;
  final void Function(BandId, String) onSelectElement;
  final void Function(BandId, String, bool) onToggleVisible;
  final VoidCallback onSelectTable;
  final bool tableSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final band in document.bands) ...[
          InkWell(
            onTap: () => onSelectBand(band.id),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              color: band.id == selectedBand
                  ? bandTint(band.id).withValues(alpha: 0.12)
                  : bandTint(band.id).withValues(alpha: 0.05),
              child: Row(
                children: [
                  Icon(PhosphorIconsBold.rows,
                      size: 13, color: bandTint(band.id)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(bandLabel(band.id),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: bandTint(band.id))),
                  ),
                  Text(tr('{p0}مم', {'p0': band.heightMm.toStringAsFixed(0)}),
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: context.picposMuted)),
                  if (band.growsWithData) ...[
                    const SizedBox(width: 6),
                    const Icon(PhosphorIconsBold.arrowsOutLineVertical,
                        size: 12, color: Color(0xFFF59E0B)),
                  ],
                ],
              ),
            ),
          ),
          // ⚠️ **الجدولُ صفٌّ في البنية لا نقرةٌ على الكانفاس وحدَها**: محرّرُ
          //    الأعمدة كان يُبلَغ برأس الجدول في الورقة فقط، وهو هدفٌ صغيرٌ
          //    قد يقع خارجَ المرئيّ حين تطول الورقة — فيبدو المحرّرُ عاجزاً
          //    عن تعديل العناوين وهو قادر.
          if (band.growsWithData && document.table != null)
            InkWell(
              onTap: onSelectTable,
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 7, 10, 7),
                decoration: BoxDecoration(
                  color: tableSelected
                      ? context.picposBrandInk.withValues(alpha: 0.08)
                      : null,
                  border: BorderDirectional(
                    bottom: BorderSide(color: context.picposHairline),
                    start: BorderSide(
                      color: tableSelected
                          ? context.picposBrandInk
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsBold.table,
                        size: 13, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(tr('جدول الأصناف'),
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: context.picposText)),
                    ),
                    Text(
                      tr('{p0} عمود', {'p0': document.table!.visibleColumns.length}),
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: context.picposMuted),
                    ),
                  ],
                ),
              ),
            ),
          for (final el in band.elements)
            InkWell(
              onTap: () => onSelectElement(band.id, el.id),
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 7, 10, 7),
                decoration: BoxDecoration(
                  color: el.id == selectedElement
                      ? context.picposBrandInk.withValues(alpha: 0.08)
                      : null,
                  border: BorderDirectional(
                    bottom: BorderSide(color: context.picposHairline),
                    start: BorderSide(
                      color: el.id == selectedElement
                          ? context.picposBrandInk
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // ⚠️ العينُ هنا هي **الطريقُ الوحيد** لإعادة إظهار عنصرٍ
                    //    أُخفي: الكانفاسُ يبهته ولوحةُ الخصائص تحتاج تحديدَه.
                    InkWell(
                      onTap: () =>
                          onToggleVisible(band.id, el.id, !el.visible),
                      child: Icon(
                        el.visible
                            ? PhosphorIconsBold.eye
                            : PhosphorIconsBold.eyeSlash,
                        size: 13,
                        color: el.visible
                            ? context.picposMuted
                            : const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (el.labelAr?.isNotEmpty ?? false)
                            ? el.labelAr!
                            : el.contentKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: el.visible
                                ? context.picposText
                                : context.picposMuted),
                      ),
                    ),
                    if ((el.condition ?? '').trim().isNotEmpty)
                      const Icon(PhosphorIconsBold.funnel,
                          size: 11, color: Color(0xFF8B5CF6)),
                    const SizedBox(width: 6),
                    Text(
                      el.contentKey,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          fontFamily: AppTypography.mono,
                          color: context.picposMuted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _FieldLibrary extends StatelessWidget {
  const _FieldLibrary({required this.onAdd});

  final void Function(String, String, ElementKind) onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            tr('يُضاف الحقلُ إلى النطاق المحدَّد — اختر نطاقاً أوّلاً.'),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.picposMuted),
          ),
        ),
        for (final g in editorFieldGroups) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(g.label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: g.tint)),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in g.items)
                ActionChip(
                  avatar: Icon(f.icon, size: 12, color: g.tint),
                  label: Text(f.label,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                  onPressed: () => onAdd(f.key, f.label, fieldKindOf(f.key)),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}
