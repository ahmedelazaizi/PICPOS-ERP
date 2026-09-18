// مستنداتُ المشتريات في قائمةٍ واحدة — فاتورةٌ أو أمرُ شراء.
//
// قرارُ المالك 2026-09-18 على تصميم «الاستعلام عن المشتريات»: مرشِّحُ «نوع
// المستند» يفرّق **فاتورة شراء / أمر شراء** — لا فاتورة/مردود.
//
// ═══ ولماذا نموذجٌ هنا لا `InvoiceEntity` مُوسَّعة ═══
//
// أمرُ الشراء **ليس فاتورةً ناقصةً** بل مستندٌ آخر: لا مسدَّدَ له ولا متبقّي،
// ولا قيدَ في الأستاذ، ولا فرعَ مختوماً عليه، ودورةُ حياته خمسُ حالاتٍ لا
// ثلاث. فحشرُه في `InvoiceEntity` كان سيجعل كلَّ مستهلِكٍ يرى «مدفوعٌ ٠ من
// ٥٠٠٠» على التزامٍ لم يُستلَم بعد — ويجعل زرَّ الطباعة والتعديل والحذف
// يعمل عليه كأنّه فاتورة.
//
// ⚠️ **ولا أنواعَ drift هنا.** `PurchaseOrderData` تعيش في `data/database`،
// وطبقةُ العرض ممنوعةٌ من استيرادها (‏`presentation_db_import_guard`، قائمةٌ
// بيضاءُ مقفولة). فالتحويلُ يقع مرّةً واحدةً في المتحكّم، وما بعده يرى
// حقولاً خالصة.

import '../entities/invoice_entity.dart';

/// صفُّ أمرِ شراءٍ كما يُعرَض — حقولٌ خالصةٌ لا صفُّ قاعدة.
class PurchaseOrderRow {
  const PurchaseOrderRow({
    required this.id,
    required this.orderNumber,
    required this.supplierId,
    required this.orderDate,
    required this.total,
    required this.status,
    this.warehouseId,
    this.costCenterId,
    this.convertedToInvoiceId,
  });

  final int id;
  final String orderNumber;
  final int supplierId;
  final DateTime orderDate;
  final double total;

  /// `draft` · `sent` · `confirmed` · `received` · `cancelled`.
  final String status;

  final int? warehouseId;
  final int? costCenterId;

  /// معرّفُ الفاتورة التي حوّل إليها — `null` ⇒ ما زال أمراً مفتوحاً.
  final int? convertedToInvoiceId;

  /// هل استُهلك الأمرُ بفاتورة؟
  bool get isConverted => convertedToInvoiceId != null;
}

/// مستندُ مشترياتٍ واحدٌ في القائمة الموحَّدة.
sealed class PurchaseDoc {
  const PurchaseDoc();

  /// تاريخُ المستند — مفتاحُ الترتيب في القائمة المدموجة.
  DateTime get date;

  /// معرّفُ المورد — لمرشِّح المورد وعرضِ الاسم.
  int get supplierId;
}

/// فاتورةُ مشترياتٍ مُرحَّلةٌ (أو قابلةٌ للترحيل).
class PurchaseInvoiceDoc extends PurchaseDoc {
  const PurchaseInvoiceDoc(this.invoice);
  final InvoiceEntity invoice;

  @override
  DateTime get date => invoice.invoiceDate;

  @override
  int get supplierId => invoice.partyId ?? 0;
}

/// أمرُ شراءٍ — **التزامٌ لا مشترى**.
class PurchaseOrderDoc extends PurchaseDoc {
  const PurchaseOrderDoc(this.order);
  final PurchaseOrderRow order;

  @override
  DateTime get date => order.orderDate;

  @override
  int get supplierId => order.supplierId;
}

/// قيمُ مرشِّح «نوع المستند».
enum PurchaseDocTypeFilter {
  all,
  invoice,
  order;

  /// هل يمرّ [doc] من هذا المرشِّح؟
  bool accepts(PurchaseDoc doc) => switch (this) {
        PurchaseDocTypeFilter.all => true,
        PurchaseDocTypeFilter.invoice => doc is PurchaseInvoiceDoc,
        PurchaseDocTypeFilter.order => doc is PurchaseOrderDoc,
      };
}

/// يدمج الفواتيرَ والأوامرَ في قائمةٍ واحدةٍ مرتَّبةٍ **بالأحدث أوّلاً**.
///
/// ⚠️ **والأوامرُ لا تدخل الإجماليّات.** أمرُ الشراء التزامٌ لم يُستلَم ولم
/// يُرحَّل؛ وضمُّه إلى «إجمالي المشتريات» يضاعف الرقمَ عند تحويله إلى فاتورة
/// — مرّةً كأمرٍ ومرّةً كفاتورة. فالشريطُ النحيفُ يبقى على الفواتير وحدَها،
/// وهذه الدالّةُ تخدم **العرضَ** لا الحساب.
List<PurchaseDoc> mergePurchaseDocs({
  required List<InvoiceEntity> invoices,
  required List<PurchaseOrderRow> orders,
  PurchaseDocTypeFilter typeFilter = PurchaseDocTypeFilter.all,
}) {
  final merged = <PurchaseDoc>[
    for (final i in invoices)
      if (typeFilter.accepts(PurchaseInvoiceDoc(i))) PurchaseInvoiceDoc(i),
    for (final o in orders)
      if (typeFilter.accepts(PurchaseOrderDoc(o))) PurchaseOrderDoc(o),
  ];
  merged.sort((a, b) => b.date.compareTo(a.date));
  return merged;
}
