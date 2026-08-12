// جدولُ الأصناف يقع حيث وضعه المصمّم — لا حيث يستدلّ الكود.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// المُصيِّرُ كان يُقحم جدولَ الأصناف **استدلالاً**: قبل أوّل عنصرٍ يصادفه من
// {subtotal, total, discount, tax, paid, remaining, notes, footer, qr_code}.
// فالجدولُ لا موضعَ له في القالب أصلاً؛ موضعُه أثرٌ جانبيٌّ لترتيب غيره.
//
// وأسوأُ منه: `_migrateOldFormatElements` كانت **تحذف** أيَّ عنصرٍ نوعُه
// `items_table` من قاعدة البيانات بحجّة أن المُصيِّرَ يُقحمه تلقائياً — بينما
// لوحةُ عناصر المصمّم (`invoice_designer_ui.dart:92`) تُنشئه `variable` +
// `content='items_table'`، وقسمُ «جدول الأصناف» في محرّر الأقسام له أزرارُ
// تحريكٍ لأعلى وأسفل. فالمالكُ يحرّك جدولاً لا وجودَ له في القاعدة.
//
// قرارُ المالك 2026-08-12 (الخيار ب): موضعُ الجدول من القالب. وإن خلا قالبٌ
// قديمٌ من عنصرِ جدولٍ فالاستدلالُ القديم يبقى احتياطاً — كي لا ينقلب مطبوع.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

InvoiceTemplateElement el({
  required int id,
  required String elementType,
  String? content,
  int sortOrder = 0,
}) {
  return InvoiceTemplateElement(
    id: id,
    templateId: 1,
    elementType: elementType,
    rowIndex: 0,
    sortOrder: sortOrder,
    flexWidth: 100,
    xPosition: 0,
    yPosition: 0,
    width: 100,
    height: 20,
    textAlign: 'right',
    fontSize: 9,
    isBold: false,
    isItalic: false,
    fontColor: '#000000',
    borderWidth: 0,
    content: content,
    isVisible: true,
    section: 'body',
  );
}

/// `null` في التسلسل = جدولُ الأصناف المُقحَم.
List<String> slotsOf(List<InvoiceTemplateElement?> seq) => seq
    .map((e) => e == null ? '<جدول>' : (e.content ?? e.elementType))
    .toList();

void main() {
  test('عنصرُ الجدول الصريح يقع في موضعه من ترتيب المصمّم', () {
    final seq = TemplatedInvoiceService.layoutSequenceForPrint(
      [
        el(id: 1, elementType: 'variable', content: 'company_name', sortOrder: 0),
        el(id: 2, elementType: 'variable', content: 'items_table', sortOrder: 1),
        el(id: 3, elementType: 'variable', content: 'total_amount', sortOrder: 2),
      ],
      hasItems: true,
    );

    expect(slotsOf(seq), ['company_name', 'items_table', 'total_amount']);
  });

  test('الجدولُ الصريحُ لا يُقحَم مرّتين ولو سبق الإجماليات', () {
    // المالكُ وضع الجدولَ **بعد** الإجماليات عمداً — والاستدلالُ القديم
    // كان سيُقحم جدولاً ثانياً قبل `subtotal`.
    final seq = TemplatedInvoiceService.layoutSequenceForPrint(
      [
        el(id: 1, elementType: 'variable', content: 'subtotal', sortOrder: 0),
        el(id: 2, elementType: 'variable', content: 'total_amount', sortOrder: 1),
        el(id: 3, elementType: 'variable', content: 'items_table', sortOrder: 2),
      ],
      hasItems: true,
    );

    expect(slotsOf(seq), ['subtotal', 'total_amount', 'items_table']);
    expect(seq.where((e) => e == null).length, 0);
  });

  test('قالبٌ قديمٌ بلا عنصرِ جدولٍ — الاستدلالُ يبقى احتياطاً', () {
    final seq = TemplatedInvoiceService.layoutSequenceForPrint(
      [
        el(id: 1, elementType: 'variable', content: 'company_name', sortOrder: 0),
        el(id: 2, elementType: 'line', sortOrder: 1),
        el(id: 3, elementType: 'variable', content: 'subtotal', sortOrder: 2),
        el(id: 4, elementType: 'variable', content: 'total_amount', sortOrder: 3),
      ],
      hasItems: true,
    );

    expect(slotsOf(seq),
        ['company_name', 'line', '<جدول>', 'subtotal', 'total_amount']);
  });

  test('بلا إجمالياتٍ ولا عنصرِ جدولٍ — الجدولُ في الذيل', () {
    final seq = TemplatedInvoiceService.layoutSequenceForPrint(
      [
        el(id: 1, elementType: 'variable', content: 'company_name', sortOrder: 0),
        el(id: 2, elementType: 'variable', content: 'invoice_number', sortOrder: 1),
      ],
      hasItems: true,
    );

    expect(slotsOf(seq), ['company_name', 'invoice_number', '<جدول>']);
  });

  test('بلا أصنافٍ — لا جدولَ يُطبع ولو كان عنصرُه في القالب', () {
    // تقريرُ الوردية يمرّ بنفس المُصيِّر بـ`items: const []`.
    final seq = TemplatedInvoiceService.layoutSequenceForPrint(
      [
        el(id: 1, elementType: 'variable', content: 'shift_total_sales', sortOrder: 0),
        el(id: 2, elementType: 'variable', content: 'items_table', sortOrder: 1),
        el(id: 3, elementType: 'variable', content: 'total_amount', sortOrder: 2),
      ],
      hasItems: false,
    );

    expect(slotsOf(seq), ['shift_total_sales', 'total_amount']);
  });

  test('الأنواعُ خارج القائمة البيضاء تُرشَّح قبل الرسم', () {
    final seq = TemplatedInvoiceService.layoutSequenceForPrint(
      [
        el(id: 1, elementType: 'variable', content: 'company_name', sortOrder: 0),
        // بذرةٌ قديمةُ الصيغة لم تمرّ بالهجرة بعد
        el(id: 2, elementType: 'supplier_name', sortOrder: 1),
        el(id: 3, elementType: 'rectangle', sortOrder: 2),
      ],
      hasItems: false,
    );

    expect(slotsOf(seq), ['company_name', 'rectangle']);
  });
}
