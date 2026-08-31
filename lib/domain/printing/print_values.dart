// قيمُ حقول المطبوع — حسابٌ خالصٌ، مصدرٌ واحدٌ للمسارين.
//
// ── لماذا هنا لا في الخدمة ────────────────────────────────────────────────
// المسارُ القديم (`layout_version == 1`) يحلّ كلَّ حقلٍ داخل مبدّلٍ يُرجع
// **ودجتَ `pw`**، والمسارُ الجديد (`== 2`) يحتاج **نصّاً** يضعه في
// `LayoutEngine.paginate(values: …)`. فلو كُتب لكلٍّ حاسبُه لافترقا: يُصلَح
// عطبٌ في أحدهما ويبقى في الآخر، ويخرج المستندُ نفسُه بقيمتين مختلفتين حسب
// نسخة التخطيط.
//
// وهذا هو **عينُ** الحساب الذي كان في `TemplatedInvoiceService._getDataValue`
// — نُقل كما هو لا أُعيد كتابتُه، والملفّاتُ الذهبيّةُ السبعةُ والعشرون هي
// الدليلُ على أنّ المطبوعَ لم يتحرّك بحرف.
//
// ولا `package:pdf` هنا ولا `package:flutter`: يحرسه
// `test/structural/template_document_has_no_ui_deps_test.dart`.

import 'party_statement_snapshot.dart';

/// علامةُ **يسار-إلى-يمين** — `U+200E LRM`.
const String kLrm = '‎';

/// يُثبّت اتّجاهَ معرِّفٍ لاتينيٍّ داخلَ فقرةٍ عربيّة.
///
/// ── العطبُ الذي يعالجه ────────────────────────────────────────────────────
///
/// رقمٌ مثل `310-123-456-789` بعد تسميةٍ عربيّةٍ يخرج على الورق
/// `789-456-123-310` — **مقلوبَ المقاطع**. وكان مشحوناً فعلاً؛ يُرى في
/// `test/goldens/printing/asset_a4_customer_statement.txt`.
///
/// ── الجذر: قاعدةُ W2 لا W4 ───────────────────────────────────────────────
///
/// الأرقامُ اللاتينيّةُ صنفُها `EN`، وقاعدةُ **W2** تحوّلها إلى `AN` حين
/// يكون أقربُ صنفٍ قويٍّ **سابقٍ** هو `AL` (حرفٌ عربيّ) — وهو حالُ التسمية
/// قبلها. وبعد التحوّل **تسقط W4**: هي تصل `EN ES EN` فقط ولا تعرف
/// `AN ES AN`، فتبقى الشُّرَطُ محايدةً وتُقطَّع السلسلةُ مقاطعَ تُرتَّب من
/// اليمين لليسار ⇒ الانقلاب.
///
/// ⚠️ **ولا يُعالَج بـ`U+2066 LRI`** رغم أنّه المحرفُ «الصحيح» نظريّاً:
/// حزمةُ الـPDF **لا تنفّذ محارفَ العزل**، فيمرُّ كأنّه لا شيءٌ ويبقى
/// الرقمُ مقلوباً. وقد وُصف ذلك العلاجُ في تسليمٍ أقدمَ وهو لا يعمل.
///
/// و`LRM` يعمل لأنّه **صنفٌ قويٌّ يساريّ**: يصير هو أقربَ صنفٍ قويٍّ سابق،
/// فلا تنطبق W2، فتبقى الأرقامُ `EN`، فتعمل W4 وتصل السلسلةَ مقطعاً واحداً.
///
/// ويُحاط الطرفان: الأوّلُ يمنع W2، والأخيرُ يمنع امتدادَ الاتّجاه
/// اليساريِّ إلى ما بعده.
String ltrIsolate(String value) =>
    value.isEmpty ? value : '$kLrm$value$kLrm';

/// كلُّ ما يحتاجه حقلٌ ليُحلَّ نصّاً.
///
/// حاملُ بياناتٍ خالصٌ — لا يقرأ قاعدةً ولا يبني ودجت. تبنيه طبقةُ الخدمة
/// مرّةً وتمرّره.
class PrintPayload {
  final String invoiceNumber;
  final DateTime date;

  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;
  final String? adhocCustomerName;
  final String? adhocCustomerPhone;

  final String companyName;
  final String companyAddress;
  final String companyPhone;
  final String? companyTaxId;

  final String paymentMethod;
  final String? cashierName;
  final String? notes;

  final double subtotal;
  final double discount;
  final double tax;
  final double deliveryFee;
  final double total;
  final double paid;
  final double remaining;

  final String? orderNumber;
  final String? platformOrderNumber;

  final double? cashAmount;
  final double? bankAmount;

  /// منازلُ الكسر للمستند كلِّه — تُحسم مرّةً في الخدمة كي لا يفترق
  /// الإجماليُّ عن الجدول في نفس الورقة.
  final int decimals;

  const PrintPayload({
    required this.invoiceNumber,
    required this.date,
    required this.companyName,
    required this.companyAddress,
    required this.companyPhone,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.deliveryFee,
    required this.total,
    required this.paid,
    required this.remaining,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.adhocCustomerName,
    this.adhocCustomerPhone,
    this.companyTaxId,
    this.paymentMethod = 'نقدي',
    this.cashierName,
    this.notes,
    this.orderNumber,
    this.platformOrderNumber,
    this.cashAmount,
    this.bankAmount,
    this.decimals = 2,
  });
}

/// قيمةُ الحقل نصّاً — `''` تعني «لا بيانَ لهذا الحقل».
///
/// و`''` ليست إخفاقاً بل قرار: عنصرٌ بلا قيمةٍ **لا يُطبع**. تسميةٌ وحدَها
/// أسوأُ من لا شيء — القارئُ يظنّ البيانَ ناقصاً لا الحقلَ غيرَ مفعَّل، وهو
/// عطبٌ رُصد على ورقٍ حقيقيّ (‏«الكاشير:» و«المخزن:» بلا قيمة).
String resolveContentValue(String type, PrintPayload p) {
  String n(double v) => v.toStringAsFixed(p.decimals);

  switch (type) {
    case 'invoice_number':
      return p.invoiceNumber;
    case 'order_number':
      return p.platformOrderNumber ?? p.orderNumber ?? p.invoiceNumber;
    case 'date':
      return '${p.date.day}/${p.date.month}/${p.date.year}';
    case 'time':
      return '${p.date.hour.toString().padLeft(2, '0')}:'
          '${p.date.minute.toString().padLeft(2, '0')}';
    case 'customer_name':
    case 'customer':
      return p.customerName ?? '';
    case 'customer_phone':
      return ltrIsolate(p.customerPhone ?? '');
    case 'customer_address':
      return p.customerAddress ?? '';
    case 'adhoc_customer_name':
      return p.adhocCustomerName ?? '';
    case 'adhoc_customer_phone':
      return ltrIsolate(p.adhocCustomerPhone ?? '');
    case 'company_name':
      return p.companyName;
    case 'company_address':
      return p.companyAddress;
    case 'company_phone':
      return ltrIsolate(p.companyPhone);
    case 'company_tax_id':
    case 'company_tax_number':
    case 'tax_registration':
      return ltrIsolate(p.companyTaxId ?? '');
    case 'payment_method':
      return mapPaymentMethodLabel(p.paymentMethod);
    case 'sale_type':
    case 'invoice_type_label':
      return p.paymentMethod;
    case 'cashier_name':
      return p.cashierName ?? '';
    case 'supplier_name':
      return p.customerName ?? '';
    case 'notes':
    case 'kitchen_notes':
      return p.notes ?? '';
    case 'subtotal':
      return n(p.subtotal);
    case 'discount':
      return n(p.discount);
    case 'tax':
    case 'tax_amount':
      return n(p.tax);
    case 'delivery_fee':
      return n(p.deliveryFee);
    case 'total':
    case 'total_amount':
    case 'grand_total':
      return n(p.total);
    case 'paid':
    case 'paid_amount':
      return n(p.paid);
    case 'remaining':
    case 'change':
      return n(p.remaining);
    // حقولٌ لم تصل الخدمةَ بياناتُها بعد — تُرجع `''` عن قصد.
    case 'table_number':
      return p.platformOrderNumber ?? p.adhocCustomerName ?? p.customerName ?? '';
    case 'warehouse_name':
    case 'branch_name':
    case 'delivery_type':
    case 'delivery_address':
    case 'courier_name':
    case 'waiter_name':
      // ⚠️ **و`return` لا تعليقٌ وحدَه**: كانت الستّةُ تسقط إلى `cash_amount`
      //    التي تليها، فيطبع «الفرع» و«المخزن» و«الويتر» **المبلغَ النقديَّ**
      //    رقماً. مقيسٌ على البصمة الذهبيّة: «ﺍﻟﻔﺮﻉ: 300.00». وكان نائماً
      //    لأنّ أيَّ قالبٍ مشحونٍ لم يستعمل هذه المفاتيح قطُّ — استيقظ يومَ
      //    استعملها قالبُ A4 الافتراضيُّ الجديد.
      return '';
    // استردادُ مرتجع المبيعات — نقداً وبنكياً.
    case 'cash_amount':
      return p.cashAmount == null ? '' : n(p.cashAmount!);
    case 'bank_amount':
      return p.bankAmount == null ? '' : n(p.bankAmount!);
    case 'click_amount':
      return '';
    default:
      return '';
  }
}

/// تسميةُ الحقل العربيّة حين لا يكتب المصمّمُ تسميةً خاصّة.
String contentLabel(String type) => const {
      'invoice_number': 'رقم الفاتورة',
      'order_number': 'رقم الطلب',
      'date': 'التاريخ',
      'time': 'الوقت',
      'customer_name': 'اسم العميل',
      'customer': 'العميل',
      'customer_phone': 'الهاتف',
      'customer_address': 'العنوان',
      'cashier_name': 'الكاشير',
      'payment_method': 'طريقة الدفع',
      'sale_type': 'نوع البيع',
      'invoice_type_label': 'نوع الفاتورة',
      'supplier_name': 'المورد',
      'notes': 'ملاحظات',
      'kitchen_notes': 'ملاحظات',
      'subtotal': 'المجموع',
      'discount': 'الخصم',
      'tax': 'الضريبة',
      'tax_amount': 'الضريبة',
      'delivery_fee': 'رسوم التوصيل',
      'total': 'الإجمالي',
      'total_amount': 'الإجمالي',
      'grand_total': 'الإجمالي',
      'paid': 'المدفوع',
      'paid_amount': 'المدفوع',
      'remaining': 'المتبقي',
      'change': 'الباقي',
      'cash_amount': 'نقداً',
      'bank_amount': 'بنكي',
      'click_amount': 'كليك',
      'company_tax_id': 'السجل الضريبي',
      'company_tax_number': 'السجل الضريبي',
      'tax_registration': 'السجل الضريبي',
      'warehouse_name': 'المخزن',
      'branch_name': 'الفرع',
      'delivery_type': 'نوع التوصيل',
      'delivery_address': 'عنوان التوصيل',
      'courier_name': 'المندوب',
      'table_number': 'رقم الطاولة',
      'waiter_name': 'الويتر',
      'footer_text': 'التذييل',
    }[type] ??
    '';

/// حقلٌ يُرسم صفَّ «تسمية ↔ قيمة» بمحاذاةٍ إلى الحافّتين.
bool isTotalField(String type) => const {
      'subtotal',
      'discount',
      'tax',
      'tax_amount',
      'total',
      'total_amount',
      'grand_total',
      'paid',
      'paid_amount',
      'remaining',
      'change',
      'cash_amount',
      'bank_amount',
      'click_amount',
      'delivery_fee',
    }.contains(type);

/// كودُ طريقة الدفع ⇒ تسميةٌ عربيّة.
///
/// وما لا يُعرف يُعاد كما هو لا يُبتلع: تسميةٌ عربيةٌ وصلت جاهزةً من منادٍ
/// آخر تمرّ، وكودٌ جديدٌ يظهر فيُرى بدل أن يختفي صامتاً.
String mapPaymentMethodLabel(String method) {
  switch (method.trim().toLowerCase()) {
    case 'cash':
      return 'نقدي';
    case 'card':
    case 'visa':
    case 'mastercard':
      return 'بطاقة';
    case 'bank':
    case 'transfer':
      return 'تحويل بنكي';
    case 'click':
      return 'كليك';
    case 'credit':
    case 'deferred':
      return 'آجل';
    case 'wallet':
      return 'محفظة';
    case 'mixed':
    case 'multi':
      return 'مختلط';
    default:
      return method;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// كشفُ حساب الطرف
// ═══════════════════════════════════════════════════════════════════════════

/// أعمدةُ جدول الحركة، بمفاتيحها كما يبنيها [PartyStatementSnapshot.rowMaps].
///
/// ⚠️ **مصدرٌ واحدٌ للاثنين**: مفتاحٌ في الصفوف بلا عمودٍ هنا يختفي من الورقة،
/// وعمودٌ هنا بلا مفتاحٍ هناك يخرج فارغاً — وكلاهما صامت.
const ledgerColumnKeys = <String>[
  'date',
  'document',
  'description',
  'debit',
  'credit',
  'balance',
];

/// قيمةُ حقلٍ من لقطة كشف الحساب — **و`null` تعني «هذا النوع ليس لي»**.
///
/// ── ولماذا `null` لا `''` ─────────────────────────────────────────────────
/// نفسُ عقد `resolveShiftValue` بحرفه: `''` تعني «حقلي وقيمتُه فارغة»
/// فيُسقَط العنصرُ من الورقة، و`null` تعني «ليس حقلي» فيُسأل مُحلِّلُ الفاتورة
/// بعدي. ولو أرجعتُ `''` في `default` لخطفتُ **كلَّ** حقول الفاتورة فخرج
/// كشفُ الحساب بلا اسم شركةٍ ولا تاريخ.
///
/// و[decimals] منازلُ المستند — تُحسم مرّةً كي لا يفترق الإجماليُّ عن الجدول
/// في نفس الورقة.
String? resolvePartyStatementValue(
  String type,
  PartyStatementSnapshot s, {
  int decimals = 2,
}) {
  String n(double v) => v.toStringAsFixed(decimals);
  String d(DateTime v) => '${v.day}/${v.month}/${v.year}';

  switch (type) {
    case 'party_name':
      return s.partyName;
    case 'party_code':
      return s.partyCode;
    case 'party_tax_number':
      return s.partyTaxNumber ?? '';
    case 'period_from':
      return d(s.periodFrom);
    case 'period_to':
      return d(s.periodTo);
    case 'credit_limit':
      return n(s.creditLimit);
    case 'opening_balance':
      return n(s.openingBalance);
    case 'total_debit':
      return n(s.totalDebit);
    case 'total_credit':
      return n(s.totalCredit);
    case 'closing_balance':
      return n(s.closingBalance);

    // ⚠️ حقلانِ متبادلان: المتأخّراتُ للعميل، والأوراقُ القائمةُ للمورد.
    //    و`null` للطرف الآخر تعني «ليس حقلي» فيُحذف العنصرُ من الورقة بدل
    //    أن يطبع «متأخرات: 0.00» على كشف مورد.
    case 'overdue_amount':
      return s.isSupplier ? null : n(s.overdueAmount);
    case 'outstanding_papers':
      return s.isSupplier ? n(s.outstandingPapers) : null;

    case 'ageing_buckets':
      return formatAgeingBuckets(s.ageingBuckets, decimals: decimals);

    // تسميةُ الطرف تنقلب بنوعه — كشفُ مورّدٍ لا يقول «العميل».
    case 'party_role':
      return s.isSupplier ? 'مورد' : 'عميل';

    default:
      // ← الحرفُ المهمّ: لا يخطف أنواعَ الفاتورة.
      return null;
  }
}

/// «٠-٣٠: ١٢٣٫٠٠ · ٣١-٦٠: ٤٥٫٠٠» — سطرٌ واحد.
///
/// وفارغةٌ تُرجع `''` لا «لا يوجد»: العنصرُ بلا قيمةٍ لا يُطبع أصلاً.
String formatAgeingBuckets(Map<String, double> buckets, {int decimals = 2}) {
  if (buckets.isEmpty) return '';
  return buckets.entries
      .map((e) => '${e.key}: ${e.value.toStringAsFixed(decimals)}')
      .join(' · ');
}
