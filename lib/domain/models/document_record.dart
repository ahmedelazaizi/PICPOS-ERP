// صفوفُ **سجلّ المستندات** — ما تعرضه شاشاتُ السجلّ في خ‑٩.
//
// ═══ لماذا هنا لا في الـDAO ═══
//
// شاشاتُ السجلّ الثلاثُ جديدةٌ، و`presentation_db_import_guard` يمنع أيَّ
// ملفِّ عرضٍ **جديد** من استيراد `data/database` والقائمةُ البيضاء مقفولة.
// فالصفُّ يعيش هنا، ويقرؤه الـDAO والمزوِّدُ والشاشةُ معاً.
//
// ═══ 🔴 وأهمُّ ما في هذا الملفّ: سندُ الشيك ليس نوعَه ═══
//
// سندُ القبض النقديُّ يكتب صفّاً بـ`transaction_type = 'receipt'`. أمّا
// **سندُ الشيك** فيكتب صفّاً بنوعٍ ثالثٍ مستقلّ (`cheque_voucher`) —
// `treasury_repository_impl` يمرّر `skipSafeTransaction: true` للشيك،
// فالصفُّ الوحيدُ الذي يخرج هو صفُّ المستند.
//
// ⇒ فترشيحُ السجلّ بـ`transaction_type = 'receipt'` وحدَه **يُخفي كلَّ
// سندات الشيكات** من سجلّها. والفاصلُ بين اتّجاهَي سند الشيك هو **بادئةُ
// رقمه** (`RV` للقبض · `PV` للصرف) — يكتبها الـDAO بيده في
// `_writeChequeVoucherRow`، فهي مصدرٌ موثوقٌ بخلاف `category` الذي يمرّره
// كلُّ منادٍ كما يشاء.

/// اتّجاهُ السند — قبضٌ أو صرف.
enum VoucherDirection {
  receipt('receipt', 'RV', 'سند قبض'),
  payment('payment', 'PV', 'سند صرف');

  const VoucherDirection(this.txnType, this.chequePrefix, this.labelAr);

  /// قيمةُ `safe_transactions.transaction_type` للسند **النقديّ**.
  final String txnType;

  /// بادئةُ رقم **سند الشيك** — الفاصلُ الوحيدُ بين اتّجاهَيه.
  final String chequePrefix;

  final String labelAr;
}

/// نوعُ صفِّ سند الشيك في `safe_transactions` — مستندٌ بلا أثرٍ ماليّ.
///
/// ⚠️ مكرّرٌ عمداً عن `kChequeVoucherTxnType` في `treasury_dao.dart`:
///    هذا الملفُّ لا يستورد `data/database` (ولا يجوز له)، والقيمةُ
///    مشحونةٌ في قواعدَ قائمةٍ فلا تتبدّل. ويشهد عليهما حارسٌ بنيويّ.
const String kChequeVoucherTxnTypeValue = 'cheque_voucher';

/// صفٌّ واحدٌ في سجلّ السندات.
class VoucherRecord {
  const VoucherRecord({
    required this.id,
    required this.voucherNumber,
    required this.date,
    required this.amount,
    required this.discount,
    required this.category,
    required this.isCheque,
    required this.safeId,
    this.safeName,
    this.partyId,
    this.partyName,
    this.description,
  });

  final int id;
  final String voucherNumber;
  final DateTime date;

  /// الصافي كما كُتب على الصفّ.
  final double amount;
  final double discount;

  /// `customer_payment` · `supplier_payment` · `expense` · …
  final String category;

  /// 🔴 **سندُ شيكٍ — مستندٌ بلا أثرٍ ماليّ.** يُعرَض ولا يُجمَع مع النقد،
  /// وإلّا عُدَّ المبلغُ مرّتين: مرّةً هنا ومرّةً في قيد الورقة التجاريّة.
  final bool isCheque;

  final int safeId;
  final String? safeName;
  final int? partyId;
  final String? partyName;
  final String? description;
}

/// صفٌّ واحدٌ في سجلّ مردودات المشتريات.
///
/// ⚠️ **ويُقرأ من `purchase_returns` بتاريخ المردود** لا من
///    `purchase_invoices` بتاريخ الفاتورة — راجع رأسَ
///    `watchPurchaseReturnRecords`.
class PurchaseReturnRecord {
  const PurchaseReturnRecord({
    required this.id,
    required this.originalInvoiceId,
    required this.returnDate,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.refundMethod,
    required this.isFullReturn,
    this.originalInvoiceNumber,
    this.supplierId,
    this.supplierName,
    this.reason,
  });

  final int id;
  final int originalInvoiceId;
  final DateTime returnDate;
  final double subtotal;
  final double tax;
  final double total;

  /// `cash` · `bank` · `credit`
  final String refundMethod;
  final bool isFullReturn;

  final String? originalInvoiceNumber;
  final int? supplierId;
  final String? supplierName;
  final String? reason;
}

/// تسميةُ طريقة الردّ بالعربيّة.
String refundMethodLabelAr(String method) => switch (method) {
      'cash' => 'نقداً',
      'bank' => 'بنكيّاً',
      'credit' => 'على الحساب',
      _ => method,
    };

/// تسميةُ تصنيف السند بالعربيّة — وما لا يُعرَف يُعرَض كما هو لا يُبتَلع.
String voucherCategoryLabelAr(String category) => switch (category) {
      'customer_payment' => 'تحصيل من عميل',
      'supplier_payment' => 'سداد لمورّد',
      'expense' => 'مصروف',
      'salary' => 'راتب',
      'advance' => 'سلفة',
      'sales' => 'مبيعات',
      'purchase' => 'مشتريات',
      'other' => 'أخرى',
      _ => category,
    };
