# مواصفة امتداد محرر القوالب — كشف الحساب والتقارير

المرجع: نمط `shift_closing` القائم بالفعل في الكود. هذا المستند يصف **ما ينقص بالضبط** لجعل
كشف حساب الطرف ونماذج التقارير تُعدَّل من محرر الفواتير مثل الفواتير تماماً.

---

## ١ · لماذا لا تعمل الآن

كشف الحساب والتقارير تُطبع من `lib/services/printing/report_pdf_generator.dart` —
مولِّدات ثابتة (`printPartyStatement` · `printSalesReport` · `printGeneralLedger` …
حوالي عشرين دالّة) تبني `pw.Document` بأعمدة مكتوبة في الكود.

هذه الدوالّ **لا تمرّ على `TemplatedInvoiceService` إطلاقاً**، ولا تقرأ جدول
`InvoiceTemplates`. فتغيير أي شيء فيها يعني تعديل Dart وإعادة بناء التطبيق.

## ٢ · السابقة: كيف دخل `shift_closing` المنظومة

تقرير إغلاق الوردية ليس فاتورة، ومع ذلك يُصمَّم من نفس المحرر. دخل بثلاث نقاط لمس فقط:

| # | الملف | ما أُضيف |
|---|-------|----------|
| ١ | `templated_invoice_service.dart` | `resolveShiftValue(String type, ShiftClosingSnapshot s)` — تُرجع `String?` و **`null` تعني «هذا النوع ليس لي»** فلا تخطف أنواع الفاتورة |
| ٢ | `templated_invoice_service.dart` → `printWithTemplate` | معامل اختياري `ShiftClosingSnapshot? shift`، ويُستدعى المُحلِّل **قبل** `switch` الفاتورة |
| ٣ | `invoice_section_editor.dart` → `_buildSections()` | أقسام مشروطة بـ `templateCategory == 'shift_closing'` |

نفس النمط حرفياً هو المطلوب هنا.

## ٣ · المطلوب إضافته

### ٣-١ · حمولة البيانات

```dart
// lib/domain/entities/party_statement_snapshot.dart
class PartyStatementLine {
  final DateTime date;
  final String documentNumber;   // INV-2026-1040
  final String description;
  final double debit;
  final double credit;
  final double runningBalance;   // محسوبة تراكمياً — لا تُجمع في التذييل
}

class PartyStatementSnapshot {
  final String partyName, partyCode;
  final String? partyTaxNumber;
  final bool isSupplier;                 // يقلب تسميات المحرر عميل/مورد
  final DateTime periodFrom, periodTo;
  final double creditLimit, openingBalance, closingBalance;
  final double totalDebit, totalCredit;
  final double overdueAmount;            // عميل
  final double outstandingPapers;        // مورد — شيكات صادرة قائمة
  final Map<String, double> ageingBuckets;
  final List<PartyStatementLine> lines;
}
```

وللتقارير حمولة عامة، لأن أعمدة التقرير تختلف من تقرير لآخر:

```dart
class ReportSnapshot {
  final String reportTitle, filterSummary, generatedBy;
  final DateTime periodFrom, periodTo, generatedAt;
  final List<ReportColumn> columns;      // {key, labelAr, labelEn, align, isNumeric}
  final List<List<String>> rows;
  final Map<String, String> totals;      // مفتاح العمود ← المجموع المنسَّق
  final String scopeNote;
}
```

### ٣-٢ · المُحلِّلات — نفس توقيع `resolveShiftValue`

```dart
static String? resolvePartyStatementValue(String type, PartyStatementSnapshot s) {
  String n(double v) => v.toStringAsFixed(_docDecimals);
  switch (type) {
    case 'party_name':        return s.partyName;
    case 'party_code':        return s.partyCode;
    case 'party_tax_number':  return s.partyTaxNumber ?? '';
    case 'period_from':       return _d(s.periodFrom);
    case 'period_to':         return _d(s.periodTo);
    case 'credit_limit':      return n(s.creditLimit);
    case 'opening_balance':   return n(s.openingBalance);
    case 'total_debit':       return n(s.totalDebit);
    case 'total_credit':      return n(s.totalCredit);
    case 'closing_balance':   return n(s.closingBalance);
    case 'overdue_amount':    return s.isSupplier ? null : n(s.overdueAmount);
    case 'outstanding_papers':return s.isSupplier ? n(s.outstandingPapers) : null;
    case 'ageing_buckets':    return _formatAgeing(s.ageingBuckets);
    default:                  return null;   // ← الحرف المهم
  }
}
```

`null` في `default` هي ما يمنع المُحلِّل من خطف أنواع الفاتورة — نفس عقد `resolveShiftValue`.

### ٣-٣ · معاملات `printWithTemplate`

```dart
PartyStatementSnapshot? statement,
ReportSnapshot? report,
```

وتُحَلّ قبل `switch` الفاتورة، بنفس ترتيب `shift` الحالي.

### ٣-٤ · الجدول — النقطة الوحيدة الحقيقية

`_buildItemsTable` أعمدته مثبَّتة على بنود الفاتورة (صنف · كمية · سعر · إجمالي).
كشف الحساب يحتاج (تاريخ · مستند · بيان · مدين · دائن · رصيد)، والتقرير يحتاج أعمدة
متغيرة تماماً. فالمطلوب تعميم الدالّة:

```dart
static pw.Widget _buildTable({
  required List<TableColumn> columns,   // بديل أعلام show* المثبَّتة
  required List<List<String>> rows,
  InvoiceTableSetting? settings,
  required pw.TextStyle baseStyle,
});
```

ثم `_buildItemsTable` تصير غلافاً رفيعاً يبني `columns` من أعلام `show*` الحالية —
فلا يتغيّر سلوك أي قالب فاتورة قائم.

ويُضاف عمود واحد لجدول `InvoiceTableSettings`:

```dart
TextColumn get tableKind => text().withDefault(const Constant('items'))();
// items | ledger | report
```

**تحذير على عمود الرصيد الجاري:** الرصيد التراكمي **لا يُجمع** في سطر المجاميع —
مجموعه رقم بلا معنى. التذييل يأخذ قيمة آخر سطر. (نفس الفخّ ظهر في شاشات المعاينة
وعولج هناك بقاعدة «إذا طابق المجموع المكتوب آخر سطر فهو رصيد ختامي لا مجموع».)

### ٣-٥ · أقسام المحرر

في `_buildSections()`، مشروطة بـ `templateCategory`:

```dart
final isStatement = widget.templateCategory == 'party_statement';
final isReport    = widget.templateCategory == 'report';
```

**كشف الحساب** — ثلاثة أقسام:

| القسم | الحقول (`variableContent`) |
|-------|---------------------------|
| بيانات الطرف | `party_name` · `party_code` · `party_tax_number` · `credit_limit` |
| الفترة | `period_from` · `period_to` |
| الحركة | `ledger_table` (elementType خاص مثل `items_table`) |
| المجاميع | `opening_balance` · `total_debit` · `total_credit` · `closing_balance` · `overdue_amount` · `outstanding_papers` · `ageing_buckets` |

**التقرير** — قسمان:

| القسم | الحقول |
|-------|--------|
| ترويسة التقرير | `report_title` · `period_from` · `period_to` · `generated_at` · `generated_by` · `filter_summary` |
| المحتوى | `report_table` · `report_totals` · `row_count` · `page_number` · `scope_note` |

### ٣-٦ · فئتان جديدتان

`InvoiceTemplates.templateCategory` تقبل حالياً `receipt · invoice · kitchen · quotation · purchase`.
يُضاف `party_statement` و `report`. لا حاجة لهجرة — العمود نصّي بقيمة افتراضية.

## ٤ · الملفات الجاهزة في هذا المجلد

| الملف | الحالة |
|-------|--------|
| `a4_sales_tax_invoice.json` | ✅ يُستورد الآن |
| `a5_sales_tax_invoice.json` | ✅ يُستورد الآن |
| `a4_purchase_invoice.json` | ✅ يُستورد الآن |
| `thermal80_quick_sale.json` | ✅ يُستورد الآن |
| `thermal58_quick_sale.json` | ✅ يُستورد الآن |
| `a4_sales_return.json` | ✅ يُستورد الآن |
| `thermal80_sales_return.json` | ✅ يُستورد الآن |
| `a4_purchase_return.json` | ✅ يُستورد الآن |
| `a4_customer_statement.json` | ⏳ يعمل فور تنفيذ §٣ |
| `a4_supplier_statement.json` | ⏳ يعمل فور تنفيذ §٣ |
| `a4_report_generic.json` | ⏳ يعمل فور تنفيذ §٣ |

الثلاثة الأخيرة مكتوبة بنفس بنية `importTemplateFromJson` بالضبط، فلا تحتاج إعادة كتابة —
فقط الأنواع والمفاتيح الموصوفة أعلاه.

## ٥ · المرتجعات — قرار مطلوب

لا توجد فئة `sales_return` أو `purchase_return`. القوالب الحالية تستعمل `invoice` و `purchase`
مع عنوان مختلف وحقلَي `cash_amount` / `bank_amount` (وهما موجودان في الكود ومكتوب في تعليقهما
أنهما «مبلغا الاسترداد في مرتجع المبيعات»).

النتيجة: `getDefaultTemplateByCategory` لا تفرّق بين الفاتورة ومرتجعها، فالقالب الافتراضي واحد.
الحل بسطر واحد — إضافة `sales_return` و `purchase_return` للفئات، وتمرير الفئة الصحيحة عند
الطباعة من شاشة المرتجعات.

## ٦ · ثلاث ملاحظات رُصدت أثناء المراجعة

**١ · `footer_text` يُطبع حرفياً.**
محرر الأقسام يعرّف `SectionField(key:'footer_text', elementType:'text', variableContent:'footer_text')`،
و`_pushFieldToElement` يضع `content = 'footer_text'`. وفي الطباعة `_resolveType` يستبدل نوع عنصر
النصّ بمحتواه، فلا تُطابَق أي حالة، ويسقط على حارس `default`:

```dart
if ((element.elementType == 'text' || …) && (element.content?.isNotEmpty ?? false))
  return pw.Text(element.content!, …);   // يطبع السلسلة "footer_text"
```

قوالب هذا المجلد تتجنّبه باستعمال `"type": "footer"` مع النصّ الفعلي في `content` — يمرّ على
`case 'footer'` ويُطبع صحيحاً. الإصلاح الجذري: إمّا `case 'footer_text'` يقرأ `labelAr`، أو
يخزّن المحرر النصّ لا المفتاح.

**٢ · القوالب المبذورة الحالية غير مرئية في محرر الأقسام.**
`_fullSyncWithElements` يفهرس العناصر بـ **`content`**:

```dart
if (e.content != null && e.content!.isNotEmpty) elementsByContent[e.content!] = e;
```

و`a4_professional.json` (والبقية) تكتب `{"type": "company_name"}` بلا `content`. فالحقل يُطبع
لكن المحرر لا يجده ويضع `field.isVisible = false` — يظهر للمستخدم مُطفأً رغم أنه على الورق.
كل قوالب هذا المجلد تحمل `content` صحيحاً لكل حقل، فتظهر مرئية وقابلة للسحب فوراً.
يُنصح بتصحيح القوالب الثمانية القديمة بنفس الطريقة.

**٣ · `defaultFont` عمود مُضلِّل.**
`InvoiceTemplates.defaultFont` قيمته الافتراضية `'Cairo'`، لكن `BaseGenerator` يتجاهله عمداً
ويحمّل Noto Naskh لأن Cairo ينقصه الياء المنفصلة U+FEF1 فتُطبع أسماء مثل «صبري» و«المصري»
والياء راكبة. العمود إمّا يُوصَل فعلياً بقائمة خطوط آمنة، وإمّا يُحذف حتى لا يَعِد بما لا يفي به.
