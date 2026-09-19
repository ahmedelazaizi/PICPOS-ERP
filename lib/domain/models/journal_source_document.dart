// «المستند المصدر» — من القيد إلى ما ولّده.
//
// ═══ لماذا خريطةٌ **مغلقةٌ** لا اشتقاقٌ ذكيّ ═══
//
// قرارُ المالك 2026-09-18 على تصميم اليومية العامة: **يُبنى زرُّ القفز** إلى
// المستند المصدر — و`referenceType` و`referenceId` متاحان على كلّ قيد.
//
// و`referenceType` **مفرداتٌ مفتوحةٌ فعلاً**: قياسُ المستودع يجد أكثرَ من
// أربعين قيمةً تُكتَب (‏`sales_invoice` · `purchase_return` · `shift_closing` ·
// `asset_revaluation` · `fiscal_close` · `opening_balance` …)، وأكثرُها
// **لا شاشةَ له تفتح مستنداً بعينه**: إقفالُ سنةٍ ماليّة، وأرصدةٌ افتتاحيّة،
// وتسويةُ ضريبة.
//
// 🔴 **وزرٌّ يُعرَض ولا يقفز أسوأُ من غيابه.** المستخدمُ ينقر فلا يحدث شيء،
// فيظنّ الشاشةَ معطَّلةً أو المستندَ محذوفاً — وكلاهما كذب. ولذلك الخريطةُ
// **مغلقةٌ بالاسم**: ما ليس فيها لا يُعرَض له زرّ.
//
// ⚠️ **والمفرداتُ مترادفةٌ تاريخيّاً**: نفسُ الحدث كُتب بأكثرَ من اسمٍ عبر
// السنين (`sale` · `sales_invoice` · `sale_invoice`، و`purchase` ·
// `purchase_invoice`). فالخريطةُ تقبلها كلَّها وتردّها إلى وجهةٍ واحدة —
// وإسقاطُ مرادفٍ يعني قيوداً قديمةً بلا زرّ.

import '../../core/navigation/screen_id.dart';

/// وجهةُ القفز — شاشةٌ يعرفها المُوجِّه، وتسميةٌ تُقرأ على الزرّ.
class JournalSourceTarget {
  const JournalSourceTarget({required this.screenId, required this.label});

  /// الشاشةُ التي تعرض هذا النوعَ من المستندات.
  final ScreenId screenId;

  /// ما يُقرأ على الزرّ — «فاتورة المبيعات»، «سند القبض» …
  final String label;
}

/// الخريطةُ المغلقة — `referenceType` ← وجهة.
///
/// ⚠️ **وإضافةُ سطرٍ هنا عقدٌ لا تسهيل**: تعني أنّ الشاشةَ المذكورةَ تفتح
/// المستندَ فعلاً. فلا يُضاف نوعٌ قبل أن يكون له أينَ يذهب.
const Map<String, JournalSourceTarget> kJournalSourceTargets = {
  // ── المبيعات ─────────────────────────────────────────────────────────
  'sales_invoice': JournalSourceTarget(
      screenId: ScreenId.salesInvoices, label: 'فاتورة المبيعات'),
  'sale_invoice': JournalSourceTarget(
      screenId: ScreenId.salesInvoices, label: 'فاتورة المبيعات'),
  'sale': JournalSourceTarget(
      screenId: ScreenId.salesInvoices, label: 'فاتورة المبيعات'),
  'sales_invoice_void': JournalSourceTarget(
      screenId: ScreenId.salesInvoices, label: 'فاتورة المبيعات (ملغاة)'),
  'sales_return': JournalSourceTarget(
      screenId: ScreenId.salesInvoices, label: 'مردود المبيعات'),

  // ── المشتريات ────────────────────────────────────────────────────────
  'purchase_invoice': JournalSourceTarget(
      screenId: ScreenId.purchases, label: 'فاتورة المشتريات'),
  'purchase': JournalSourceTarget(
      screenId: ScreenId.purchases, label: 'فاتورة المشتريات'),
  'purchase_invoice_void': JournalSourceTarget(
      screenId: ScreenId.purchases, label: 'فاتورة المشتريات (ملغاة)'),
  'purchase_return': JournalSourceTarget(
      screenId: ScreenId.purchases, label: 'مردود المشتريات'),
  'purchase_return_reverse': JournalSourceTarget(
      screenId: ScreenId.purchases, label: 'عكسُ مردود المشتريات'),

  // ── الخزينة ──────────────────────────────────────────────────────────
  'receipt_voucher': JournalSourceTarget(
      screenId: ScreenId.treasury, label: 'سند القبض'),
  'receipt': JournalSourceTarget(
      screenId: ScreenId.treasury, label: 'سند القبض'),
  'payment_voucher': JournalSourceTarget(
      screenId: ScreenId.treasury, label: 'سند الصرف'),
  'payment': JournalSourceTarget(
      screenId: ScreenId.treasury, label: 'سند الصرف'),
  'safe_transaction': JournalSourceTarget(
      screenId: ScreenId.treasury, label: 'حركة الخزينة'),
  'commercial_paper': JournalSourceTarget(
      screenId: ScreenId.commercialPapers, label: 'الورقة التجاريّة'),

  // ── المخزون ──────────────────────────────────────────────────────────
  'inventory_bond': JournalSourceTarget(
      screenId: ScreenId.inventoryBonds, label: 'سند المخزون'),
  'stock_transfer': JournalSourceTarget(
      screenId: ScreenId.stockTransfer, label: 'التحويل المخزنيّ'),
  'manufacturing_order': JournalSourceTarget(
      screenId: ScreenId.manufacturing, label: 'أمر التصنيع'),

  // ── الأصول والمصروفات ────────────────────────────────────────────────
  'op_expense': JournalSourceTarget(
      screenId: ScreenId.operationalExpenses, label: 'المصروف التشغيليّ'),
};

/// وجهةُ القيد — أو `null` حين **لا مستندَ يُفتَح**.
///
/// وثلاثةُ شروطٍ معاً، وأيُّها ناقصٌ يعني زرّاً لا يقفز:
///   ‏١) نوعٌ معروف، ‏٢) ومعرّفٌ غيرُ فارغ، ‏٣) والشاشةُ **داخلَ النطاق**
///      المسموح لهذه التجهيزة.
///
/// ⚠️ **والنطاقُ يُمرَّر لا يُقرأ هنا**: هذا الملفُّ في `domain` فلا يعرف
/// `AppConfig`، وقراءتُه منه كانت ستربط حساباً خالصاً بإعدادٍ عامّ.
JournalSourceTarget? resolveJournalSourceTarget({
  required String? referenceType,
  required int? referenceId,
  required Set<ScreenId> allowedScreenIds,
}) {
  if (referenceType == null || referenceType.isEmpty) return null;
  if (referenceId == null || referenceId <= 0) return null;
  final target = kJournalSourceTargets[referenceType];
  if (target == null) return null;
  if (!allowedScreenIds.contains(target.screenId)) return null;
  return target;
}
