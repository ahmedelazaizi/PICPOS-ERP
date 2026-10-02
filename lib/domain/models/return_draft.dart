// مسوّداتُ المرتجعات وصفوفُ سجلّهما — J2 (قرارُ المالك).
//
// ═══ دورةُ الحياة ═══
//
//   «حفظ مسودة»       ← صفٌّ في `return_drafts` بحالة `draft`: لا مخزونَ ولا
//                         قيدَ ولا خزينةَ ولا ورقةَ دفتر سندات — ولا رقمَ مستند.
//   «مراجعة واعتماد»  ← المسارُ القائمُ نفسُه (`processReturn`) يرحّل، ثمّ
//                         يُختَم الصفُّ `posted` برقم المستند الذي وُلِّد في
//                         معاملة الترحيل.
//   إلغاءُ المرتجع     ← (مبيعات) الإلغاءُ القائمُ، ثمّ يُختَم الصفُّ `cancelled`.
//
// ⚠️ **الرقمُ يُولَّد عند الترحيل لا عند الحفظ.** `generateInvoiceNumber`
//    (SRET-/PRET-) يأخذ رقمَه داخلَ معاملة الترحيل فيرجع معها إن فشلت —
//    فتسلسلُ المستندات يبقى بلا فجوات. والمسوّدةُ تُعرَّف بمعرّفها
//    (`مسودة #12`) لا برقمٍ من التسلسل: مسوّدةٌ تُحذَف لا تترك فجوة.
//
// أنواعٌ نقيّةٌ من الطبقة النطاقيّة — الشاشاتُ لا تستورد `data/database`.

/// نوعُ المرتجع.
enum ReturnDraftKind {
  sales('sales'),
  purchase('purchase');

  const ReturnDraftKind(this.code);
  final String code;

  static ReturnDraftKind fromCode(String code) =>
      code == 'purchase' ? purchase : sales;
}

/// حالةُ المستند في السجلّ — مسودة · معتمد · ملغى.
enum ReturnRecordStatus {
  draft('draft'),
  posted('posted'),
  cancelled('cancelled');

  const ReturnRecordStatus(this.code);
  final String code;

  static ReturnRecordStatus fromCode(String? code) => switch (code) {
        'posted' => posted,
        'cancelled' => cancelled,
        _ => draft,
      };
}

/// مسوّدةُ مرتجعٍ محفوظة.
class ReturnDraft {
  const ReturnDraft({
    required this.id,
    required this.kind,
    required this.status,
    required this.originalInvoiceId,
    required this.quantities,
    required this.createdAt,
    this.partyId,
    this.branchId,
    this.warehouseId,
    this.reason,
    this.reasonCategory,
    this.isFullReturn = false,
    this.isDamaged = false,
    this.subtotal = 0,
    this.tax = 0,
    this.total = 0,
    this.settlement,
    this.postedNumber,
    this.postedAt,
    this.userId,
    this.updatedAt,
  });

  final int id;
  final ReturnDraftKind kind;
  final ReturnRecordStatus status;
  final int originalInvoiceId;

  /// الكمّيّاتُ المرتجعة — مفتاحُها معرّفُ **سطر** الفاتورة الأصليّة.
  final Map<int, double> quantities;
  final DateTime createdAt;
  final int? partyId;
  final int? branchId;
  final int? warehouseId;
  final String? reason;
  final String? reasonCategory;
  final bool isFullReturn;
  final bool isDamaged;
  final double subtotal;
  final double tax;
  final double total;

  /// `cash` · `balance` · `bank` · `mixed` — كما ستقسمه/قسمته المحرّك.
  final String? settlement;
  final String? postedNumber;
  final DateTime? postedAt;
  final int? userId;
  final DateTime? updatedAt;

  bool get isDraft => status == ReturnRecordStatus.draft;

  /// المعرّفُ المعروض لمسوّدةٍ لم تأخذ رقمَ مستندٍ بعد.
  String get draftLabel => 'D-$id';
}

/// ما يُحفَظ في مسوّدة — من حالة الاستمارة.
class ReturnDraftInput {
  const ReturnDraftInput({
    required this.kind,
    required this.originalInvoiceId,
    required this.quantities,
    this.id,
    this.partyId,
    this.branchId,
    this.warehouseId,
    this.reason,
    this.reasonCategory,
    this.isFullReturn = false,
    this.isDamaged = false,
    this.subtotal = 0,
    this.tax = 0,
    this.total = 0,
    this.settlement,
    this.userId,
  });

  /// `null` = مسوّدةٌ جديدة؛ وإلا تعديلُ مسوّدةٍ قائمة.
  final int? id;
  final ReturnDraftKind kind;
  final int originalInvoiceId;
  final Map<int, double> quantities;
  final int? partyId;
  final int? branchId;
  final int? warehouseId;
  final String? reason;
  final String? reasonCategory;
  final bool isFullReturn;
  final bool isDamaged;
  final double subtotal;
  final double tax;
  final double total;
  final String? settlement;
  final int? userId;
}

/// ما كتبه مرتجعٌ مرحَّلٌ واحدٌ تحت رقم سنده (SRET-/PRET-): ساقُ النقد/البنك
/// و/أو مذكّرةُ تسوية الرصيد — تتشارك رقماً واحداً.
class ReturnVoucherLegs {
  ReturnVoucherLegs(this.voucher, {this.at});
  final String voucher;
  final DateTime? at;
  bool cash = false;
  bool balance = false;

  /// `cash` · `balance` · `mixed`.
  String get settlement =>
      cash && balance ? 'mixed' : (balance ? 'balance' : 'cash');
}

/// ما يُكمّل سجلَّ مردودات المشتريات فوق مستنداته المرحَّلة: المسوّدات،
/// والمستنداتُ الملغاة (أبطلها مسارُ التعديل القائم)، وأرقامُ السندات.
class PurchaseReturnRecordExtras {
  const PurchaseReturnRecordExtras({
    this.drafts = const [],
    this.voided = const [],
    this.vouchers = const {},
  });

  final List<ReturnRecordRow> drafts;
  final List<ReturnRecordRow> voided;

  /// سنداتُ المرتجع لكلّ فاتورةٍ أصل، بترتيب الترحيل.
  final Map<int, List<ReturnVoucherLegs>> vouchers;
}

/// صفٌّ في سجلّ المرتجعات — مسوّدةٌ أو مستندٌ مرحَّلٌ أو ملغى.
class ReturnRecordRow {
  const ReturnRecordRow({
    required this.key,
    required this.status,
    required this.number,
    required this.date,
    required this.originalInvoiceId,
    required this.total,
    this.draftId,
    this.documentId,
    this.originalInvoiceNumber,
    this.partyName,
    this.reason,
    this.settlement,
    this.tax = 0,
    this.isFullReturn = false,
  });

  /// مفتاحٌ ثابتٌ للاختيار في الجدول — `d<id>` للمسوّدة و`p<id>` للمرحَّل.
  final String key;
  final ReturnRecordStatus status;
  final String number;
  final DateTime date;
  final int originalInvoiceId;
  final double total;

  /// معرّفُ صفّ المسوّدة (إن وُجد).
  final int? draftId;

  /// معرّفُ مستند المرتجع المرحَّل (`purchase_returns.id` للمشتريات).
  final int? documentId;
  final String? originalInvoiceNumber;
  final String? partyName;
  final String? reason;

  /// `cash` · `balance` · `bank` · `mixed` · `credit`.
  final String? settlement;
  final double tax;
  final bool isFullReturn;

  /// يطابق البحثَ بالرقم أو الفاتورة الأصل أو الطرف أو السبب.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    bool hit(String? s) => (s ?? '').toLowerCase().contains(q);
    return hit(number) ||
        hit(originalInvoiceNumber) ||
        hit(partyName) ||
        hit(reason);
  }
}
