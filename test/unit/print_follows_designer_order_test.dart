// المطبوعُ يتبع ترتيبَ المصمّم — لا ترتيباً مكتوباً في الكود.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// محرّرُ الأقسام (`invoice_section_editor.dart` · `_recalcSortOrder`) يكتب
// لكلّ عنصرٍ `sortOrder` **عالمياً متسلسلاً** عبر الأقسام كلِّها بترتيبها
// البصريّ على الشاشة. فـ`sortOrder` وحدَه يصف تخطيطَ المصمّم وصفاً تامّاً.
//
// والمُصيِّرُ كان يرمي هذا الوصفَ ويفرز بـ`_contentSectionPriority` — جدولُ
// أولوياتٍ مكتوبٌ في الكود — ثم يستعمل `sortOrder` مرجّحاً ثانوياً فقط. فأيُّ
// ترتيبٍ يرسمه المالكُ على الشاشة يُهدم على الورق ما دام يخالف ذلك الجدول.
//
// وللجدول ذاته عيبان: كلُّ ما لا يعرفه (‏ومنه **كلُّ** مفاتيح `shift_*` وأيُّ
// نصٍّ ثابت) يقع في «٨ — بعد الإجماليات»؛ ثم تأتي إزالةُ التكرار بعد الفرز
// فتُبقي **أوّلَ** ظهورٍ لكلّ نوعٍ مُحَلٍّ وتحذف الباقي — فتبتلع الفواصلَ
// المتكرّرةَ وكلَّ نصٍّ ثابتٍ تكرّر محتواه، وهي عناصرُ رسمها المستخدمُ عمداً.
//
// قرارُ المالك 2026-08-12 (الخيار ب): الطابعةُ تحترم تخطيطَ المصمّم.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';

/// عنصرُ قالبٍ بأقلّ ما يلزم — الباقي قيمٌ محايدةٌ لا يقرؤها الترتيب.
InvoiceTemplateElement el({
  required int id,
  required String elementType,
  String? content,
  int sortOrder = 0,
  double yPosition = 0,
  bool isVisible = true,
  String section = 'body',
}) {
  return InvoiceTemplateElement(
    id: id,
    templateId: 1,
    elementType: elementType,
    rowIndex: 0,
    sortOrder: sortOrder,
    flexWidth: 100,
    xPosition: 0,
    yPosition: yPosition,
    width: 100,
    height: 20,
    textAlign: 'right',
    fontSize: 9,
    isBold: false,
    isItalic: false,
    fontColor: '#000000',
    borderWidth: 0,
    content: content,
    isVisible: isVisible,
    section: section,
  );
}

List<String> keysOf(List<InvoiceTemplateElement> els) =>
    els.map((e) => e.content ?? e.elementType).toList();

void main() {
  test('ترتيبُ المصمّم هو الحَكَم — لا جدولُ الأولويات المكتوب في الكود', () {
    // المالكُ رسم على الشاشة: ملاحظات ← اسم الشركة ← الإجمالي.
    // جدولُ الأولويات القديم يعطي company_name=0 و total=5 و notes=6،
    // فكان يقلبها إلى: اسم الشركة ← الإجمالي ← ملاحظات.
    final ordered = TemplatedInvoiceService.orderElementsForPrint([
      el(id: 1, elementType: 'variable', content: 'notes', sortOrder: 0),
      el(id: 2, elementType: 'variable', content: 'company_name', sortOrder: 1),
      el(id: 3, elementType: 'variable', content: 'total_amount', sortOrder: 2),
    ]);

    expect(keysOf(ordered), ['notes', 'company_name', 'total_amount']);
  });

  test('مفاتيحُ الوردية تبقى في موضعها لا تُنفى بعد الإجماليات', () {
    // `_contentSectionPriority` لا يعرف `shift_*` فيرميها كلَّها في «٨».
    final ordered = TemplatedInvoiceService.orderElementsForPrint([
      el(id: 1, elementType: 'variable', content: 'shift_total_sales', sortOrder: 0),
      el(id: 2, elementType: 'variable', content: 'total_amount', sortOrder: 1),
      el(id: 3, elementType: 'variable', content: 'footer_text', sortOrder: 2),
    ]);

    expect(keysOf(ordered),
        ['shift_total_sales', 'total_amount', 'footer_text']);
  });

  test('جدولُ الأصناف يقع في موضعه من ترتيب المصمّم', () {
    final ordered = TemplatedInvoiceService.orderElementsForPrint([
      el(id: 1, elementType: 'variable', content: 'customer_name', sortOrder: 0),
      el(id: 2, elementType: 'variable', content: 'items_table', sortOrder: 1),
      el(id: 3, elementType: 'variable', content: 'total_amount', sortOrder: 2),
    ]);

    expect(keysOf(ordered), ['customer_name', 'items_table', 'total_amount']);
  });

  test('الفواصلُ المتكرّرةُ تنجو — رسمها المستخدمُ عمداً', () {
    // `_resolveType` يحوّل كلَّ `line` إلى «divider»، فكانت إزالةُ التكرار
    // تُبقي الأوّلَ وتحذف البقيّة: قالبٌ بثلاثة فواصلَ يُطبع بفاصلٍ واحد.
    final ordered = TemplatedInvoiceService.orderElementsForPrint([
      el(id: 1, elementType: 'line', sortOrder: 0),
      el(id: 2, elementType: 'variable', content: 'total_amount', sortOrder: 1),
      el(id: 3, elementType: 'line', sortOrder: 2),
      el(id: 4, elementType: 'variable', content: 'footer_text', sortOrder: 3),
      el(id: 5, elementType: 'line', sortOrder: 4),
    ]);

    expect(ordered.where((e) => e.elementType == 'line').length, 3);
    expect(keysOf(ordered),
        ['line', 'total_amount', 'line', 'footer_text', 'line']);
  });

  test('النصُّ الثابتُ المتكرّرُ ينجو — محتواه ليس متغيّراً', () {
    final ordered = TemplatedInvoiceService.orderElementsForPrint([
      el(id: 1, elementType: 'text', content: '— — —', sortOrder: 0),
      el(id: 2, elementType: 'variable', content: 'total_amount', sortOrder: 1),
      el(id: 3, elementType: 'text', content: '— — —', sortOrder: 2),
    ]);

    expect(ordered.length, 3);
  });

  test('المتغيّرُ المكرَّرُ يُنقّى — قيمةٌ واحدةٌ لا تُطبع مرّتين', () {
    final ordered = TemplatedInvoiceService.orderElementsForPrint([
      el(id: 1, elementType: 'variable', content: 'total_amount', sortOrder: 0),
      el(id: 2, elementType: 'variable', content: 'grand_total', sortOrder: 1),
    ]);

    // `grand_total` يُحَلُّ إلى `total` نفسِه — تكرارٌ من بذرةٍ قديمة.
    expect(ordered.length, 1);
    expect(keysOf(ordered), ['total_amount']);
  });

  test('غيرُ المرئيِّ لا يُطبع', () {
    final ordered = TemplatedInvoiceService.orderElementsForPrint([
      el(id: 1, elementType: 'variable', content: 'notes', sortOrder: 0),
      el(id: 2, elementType: 'variable', content: 'total_amount', sortOrder: 1, isVisible: false),
    ]);

    expect(keysOf(ordered), ['notes']);
  });

  test('تساوي sortOrder يُحسم بـyPosition لا عشوائياً', () {
    final ordered = TemplatedInvoiceService.orderElementsForPrint([
      el(id: 1, elementType: 'variable', content: 'notes', sortOrder: 0, yPosition: 50),
      el(id: 2, elementType: 'variable', content: 'company_name', sortOrder: 0, yPosition: 10),
    ]);

    expect(keysOf(ordered), ['company_name', 'notes']);
  });
}
