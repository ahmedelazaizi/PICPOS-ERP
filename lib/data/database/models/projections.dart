// ═══════════════════════════════════════════════════════════════════════════
// SHARED DATABASE MODELS & PROJECTIONS
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

/// Helper class for Purchase Invoice Item with Product data
class PurchaseInvoiceItemWithProduct {
  final PurchaseInvoiceItem item;
  final Product product;

  PurchaseInvoiceItemWithProduct({required this.item, required this.product});
}

/// Helper class for Sales Invoice Item with Product data
///
/// [product] is nullable on purpose. `sales_invoice_items` stores no product
/// name, so every display path has to join — and the join used to be an
/// `innerJoin`, which silently DROPPED any line whose product row was gone.
/// That produced invoices whose totals its own lines could not explain, and
/// on the edit path it meant re-saving an invoice quietly lost the line.
/// Surfacing the null lets callers render a "صنف محذوف" placeholder instead.
class SalesInvoiceItemWithProduct {
  final SalesInvoiceItem item;
  final Product? product;

  SalesInvoiceItemWithProduct({required this.item, required this.product});

  /// Display name for the line, falling back to the id when the product row
  /// is missing. Never returns an empty string.
  String get displayName =>
      product?.name ?? 'صنف محذوف #${item.productId}';
}

/// Helper class for Purchase Analytics
class PurchasesAnalytics {
  final double totalPurchases;
  final double totalOutstanding;
  final int invoiceCount;
  final double averagePurchaseValue;

  PurchasesAnalytics({
    required this.totalPurchases,
    required this.totalOutstanding,
    required this.invoiceCount,
    required this.averagePurchaseValue,
  });
}

/// Helper class for Purchase Invoice with Supplier name
class PurchaseInvoiceWithSupplier {
  final PurchaseInvoiceData invoice;
  final String? supplierName;

  PurchaseInvoiceWithSupplier({required this.invoice, this.supplierName});
}

/// Helper class for Sales Analytics
class SalesAnalytics {
  final double totalSales;
  final double totalGrossProfit;
  final double totalNetProfit;
  final double totalProfit; // Duplicate for UI compatibility
  final int salesCount;
  final int invoiceCount; // Duplicate for UI compatibility
  final double averageSaleValue;
  final double averageInvoiceValue; // Duplicate for UI compatibility
  final double totalDiscount;
  final double totalTax;
  final double totalCOGS; // تكلفة البضاعة المباعة الفعلية
  final double totalNetRevenue; // الإيراد الصافي = المبيعات - الخصومات

  SalesAnalytics({
    required this.totalSales,
    required this.totalGrossProfit,
    required this.totalNetProfit,
    required this.totalProfit,
    required this.salesCount,
    required this.invoiceCount,
    required this.averageSaleValue,
    required this.averageInvoiceValue,
    required this.totalDiscount,
    required this.totalTax,
    this.totalCOGS = 0,
    this.totalNetRevenue = 0,
  });
}

/// Helper class for Inventory Analytics
class InventoryAnalytics {
  final double totalCostValue;
  final double totalSaleValue;
  final double potentialProfit;
  final int uniqueProducts;
  final int lowStockCount;
  final int outOfStockCount;
  // BUG-M05: total stock units summed across products — kept as a double so
  // weighted / partial-unit inventory is not truncated by .toInt().
  final double itemsCount;

  InventoryAnalytics({
    required this.totalCostValue,
    required this.totalSaleValue,
    required this.potentialProfit,
    required this.uniqueProducts,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.itemsCount,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// P2-03: TYPED ANALYTICS RESULT CLASSES (ISS-16)
// Replaces List<Map<String, dynamic>> in analytics DAOs with type-safe objects.
// ═══════════════════════════════════════════════════════════════════════════

/// Typed result for getTopSellingProducts
class TopSellingProductRow {
  final int id;
  final String name;
  final double totalQuantity;
  final double totalSales;

  const TopSellingProductRow({
    required this.id,
    required this.name,
    required this.totalQuantity,
    required this.totalSales,
  });
}

/// Typed result for getTopProductsReport
class TopProductRow {
  final int id;
  final String name;
  final double totalQty;
  final double totalValue;

  const TopProductRow({
    required this.id,
    required this.name,
    required this.totalQty,
    required this.totalValue,
  });
}

/// Typed result for getCategoryProfitReport
class CategoryProfitRow {
  final int? categoryId;
  final String categoryName;
  final double totalSales;
  final double totalCost;
  final double profit;
  final double margin;

  const CategoryProfitRow({
    this.categoryId,
    required this.categoryName,
    required this.totalSales,
    required this.totalCost,
    required this.profit,
    required this.margin,
  });
}

/// Typed result for getDailySalesSummary / getDailySalesSimple / getDailySalesForRange
class DailySalesSummaryRow {
  final String date;
  final double total;

  const DailySalesSummaryRow({required this.date, required this.total});
}

/// Typed result for getPaymentMethodStats
class PaymentMethodStatRow {
  final String method;
  final int count;
  final double total;

  const PaymentMethodStatRow({
    required this.method,
    required this.count,
    required this.total,
  });
}

/// H14 · قناةُ الدفع **كما تُعرض**، لا كما تُخزَّن.
///
/// `getPaymentMethodStats` يجمع بـ`GROUP BY payment_method` على القيمة الخام،
/// و`sales_invoices.payment_method` يحمل قيماً متعددةً تقع على قناةٍ واحدة:
/// `card` · `transfer` · `bank` كلُّها «بطاقة/تحويل»، و`multiple` · `mixed`
/// كلاهما «متعدد».
///
/// فكانت الشاشةُ ترسم **شريحةً لكلّ قيمةٍ خام** وتسمّيها بنفس الاسم: فطيرةٌ
/// فيها «بطاقة/تحويل» ثلاثَ مرّاتٍ بثلاث نسبٍ، ولا يستطيع القارئ جمعَها
/// بعينه. الطيُّ هنا كي يبقى العرضُ والتجميعُ على تعريفٍ واحد.
enum PaymentChannel { cash, card, click, credit, multiple, other }

/// يطوي القيمةَ الخام إلى قناتها. المجهولُ يقع على [PaymentChannel.other]
/// بدل أن يُسقَط — إخفاءُ مبلغٍ من الفطيرة أسوأ من تسميته «أخرى».
PaymentChannel paymentChannelOf(String rawMethod) {
  switch (rawMethod.trim().toLowerCase()) {
    case 'cash':
      return PaymentChannel.cash;
    case 'card':
    case 'transfer':
    case 'bank':
    case 'visa':
      return PaymentChannel.card;
    case 'click':
      return PaymentChannel.click;
    case 'credit':
      return PaymentChannel.credit;
    case 'multiple':
    case 'mixed':
      return PaymentChannel.multiple;
    default:
      return PaymentChannel.other;
  }
}

/// نتيجةُ الطيّ — صفٌّ واحدٌ لكلّ قناة، بترتيبٍ ثابتٍ حسب [PaymentChannel]
/// كي لا تقفز الشرائحُ بين تحميلَين.
class PaymentChannelStat {
  final PaymentChannel channel;
  final int count;
  final double total;

  const PaymentChannelStat({
    required this.channel,
    required this.count,
    required this.total,
  });
}

/// يطوي صفوفَ `getPaymentMethodStats` إلى صفٍّ واحدٍ لكلّ قناة.
List<PaymentChannelStat> foldPaymentChannels(List<PaymentMethodStatRow> rows) {
  final byChannel = <PaymentChannel, ({int count, double total})>{};
  for (final r in rows) {
    final ch = paymentChannelOf(r.method);
    final prev = byChannel[ch];
    byChannel[ch] = (
      count: (prev?.count ?? 0) + r.count,
      total: (prev?.total ?? 0) + r.total,
    );
  }
  return [
    for (final ch in PaymentChannel.values)
      if (byChannel[ch] != null)
        PaymentChannelStat(
          channel: ch,
          count: byChannel[ch]!.count,
          total: byChannel[ch]!.total,
        ),
  ];
}

/// Typed result for getSalesByCategory
class SalesByCategoryRow {
  final String category;
  final double quantity;
  final double total;

  const SalesByCategoryRow({
    required this.category,
    required this.quantity,
    required this.total,
  });

  /// Convert back to Map for legacy print/export functions
  Map<String, dynamic> toMap() => {
        'category': category,
        'quantity': quantity,
        'total': total,
      };
}

/// Typed result for getSalesBySaleType
class SalesBySaleTypeRow {
  final String type;
  final int count;
  final double total;

  const SalesBySaleTypeRow({
    required this.type,
    required this.count,
    required this.total,
  });

  /// Convert back to Map for legacy print/export functions
  Map<String, dynamic> toMap() => {
        'type': type,
        'count': count,
        'total': total,
      };
}

/// Typed result for getSalesInvoicesBySaleType
class SalesInvoiceSummaryRow {
  final int id;
  final String invoiceNumber;
  final dynamic invoiceDate; // int (unix) or DateTime depending on DB driver
  final double total;
  final double paid;
  final double cashPaid;
  final double bankPaid;
  final double clickPaid;
  final String paymentMethod;
  final String saleType;
  final double discount;
  final double tax;
  final double deliveryFee;
  final String? customerName;

  const SalesInvoiceSummaryRow({
    required this.id,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.total,
    required this.paid,
    required this.cashPaid,
    required this.bankPaid,
    required this.clickPaid,
    required this.paymentMethod,
    required this.saleType,
    required this.discount,
    required this.tax,
    required this.deliveryFee,
    this.customerName,
  });
}

/// Typed result for getSalesReturnsAnalytics / getPurchaseReturnsAnalytics
class ReturnsAnalyticsSummary {
  final int count;
  final double total;

  const ReturnsAnalyticsSummary({required this.count, required this.total});
}

/// Helper class for Treasury Analytics
class TreasuryAnalytics {
  final double cashBalance;
  final double bankBalance;
  final double totalBalance;
  final double periodIncome;
  final double periodExpense;
  final double netFlow;
  final double openingBalance;
  final double totalIn;
  final double totalOut;
  final double closingBalance;
  final double totalReceipts;
  final double totalPayments;

  TreasuryAnalytics({
    required this.cashBalance,
    required this.bankBalance,
    required this.totalBalance,
    required this.periodIncome,
    required this.periodExpense,
    required this.netFlow,
    required this.openingBalance,
    required this.totalIn,
    required this.totalOut,
    required this.closingBalance,
    required this.totalReceipts,
    required this.totalPayments,
  });
}

/// تجميعُ فترةٍ لطرفٍ واحد — عميلاً كان أو مورّداً.
///
/// يخدم ثلاثةَ تقارير: «تحليل سلوك العملاء» و«تقسيم العملاء (RFM)»
/// و«تحليل سلوك الموردين». والثلاثةُ كانت تفتح شاشةً نائبةً لأنّ الاستعلامَ
/// الوحيدَ القائم (`getPurchasesBySupplier`) يعطي المجموعَ والعددَ فقط —
/// وتقسيمُ RFM يحتاج **آخرَ تاريخ** قبل كلّ شيء.
///
/// [lastInvoiceDate] هو حداثةُ التعامل (R)، و[invoiceCount] تكرارُه (F)،
/// و[totalValue] قيمتُه (M). و`null` في التاريخ تعني طرفاً بلا فاتورةٍ في
/// المدى — وهو لا يظهر أصلاً لأنّ الضمَّ داخليّ.
class PartyPeriodAggregateRow {
  const PartyPeriodAggregateRow({
    required this.partyId,
    required this.partyName,
    required this.invoiceCount,
    required this.totalValue,
    required this.paidValue,
    required this.firstInvoiceDate,
    required this.lastInvoiceDate,
  });

  final int partyId;
  final String partyName;
  final int invoiceCount;
  final double totalValue;
  final double paidValue;
  final DateTime? firstInvoiceDate;
  final DateTime? lastInvoiceDate;

  /// المتبقّي على الطرف في هذا المدى — لا رصيدُه الكلّيّ.
  double get unpaidValue => totalValue - paidValue;

  /// متوسّطُ الفاتورة. لا قسمةَ على صفر: صفرُ فواتيرَ لا يمرّ عبر الضمّ
  /// الداخليّ أصلاً، والحارسُ هنا لأنّ الصفرَ أرخصُ من انهيار.
  double get averageValue => invoiceCount > 0 ? totalValue / invoiceCount : 0;
}

/// ربحُ صنفٍ واحدٍ في فترة — نظيرُ [CategoryProfitRow] درجةً أدنى.
///
/// التكلفةُ من `sales_invoice_items.cost_price` — لقطةُ التكلفة **وقتَ
/// البيع** لا التكلفةُ الحاليّة. وهذا هو الصحيح: صنفٌ ارتفعت تكلفتُه اليومَ
/// لم يكن يُباع بخسارةٍ الشهرَ الماضي، وتقييمُه بتكلفة اليوم كان سيتّهمه.
class ProductProfitRow {
  const ProductProfitRow({
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.quantity,
    required this.totalSales,
    required this.totalCost,
    required this.currentStock,
  });

  final int productId;
  final String productName;
  final String categoryName;

  /// الكمّيّةُ المباعةُ في المدى.
  final double quantity;

  /// الإيرادُ **صافي الضريبة** — كي يقابل تكلفةً صافيةً أصلاً.
  final double totalSales;
  final double totalCost;

  /// الرصيدُ المتاحُ الآن — يجيب «كم بقي من صنفٍ يبيع بخسارة».
  final double currentStock;

  double get profit => totalSales - totalCost;

  /// الهامشُ نسبةً مئويّة. لا قسمةَ على صفر: صنفٌ بيع بصفرِ إيرادٍ (‏هديّةٌ
  /// أو خصمٌ كامل) هامشُه صفرٌ لا لانهاية.
  double get margin => totalSales == 0 ? 0 : profit / totalSales * 100;

  /// متوسّطُ سعر البيع للوحدة — يُقرأ بجانب متوسّط التكلفة فيُفهَم الهامش.
  double get averagePrice => quantity == 0 ? 0 : totalSales / quantity;

  double get averageCost => quantity == 0 ? 0 : totalCost / quantity;
}

// ═══════════════════════════════════════════════════════════════════════════
// كشفُ حساب الطرف — إسقاطاتُ التبويبات (تصميمُ 2026-08-26)
// ═══════════════════════════════════════════════════════════════════════════

/// فاتورةٌ **قائمةٌ** لطرف — لم يُسدَّد كاملُها بعد.
///
/// تخدم «أعمار الدين» للعميل و«المستحق والاستحقاق» للمورد: تبويبتان
/// بنيتُهما واحدةٌ على جدولَين.
class PartyOpenInvoiceRow {
  const PartyOpenInvoiceRow({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.dueDate,
    required this.total,
    required this.paid,
    required this.daysLate,
  });

  final int invoiceId;
  final String invoiceNumber;
  final DateTime invoiceDate;

  /// `COALESCE(due_date, invoice_date)` — فراغُ العمود يعني «يستحق يومَ
  /// إصداره»، فلا تفرّق القراءةُ بين فاتورةٍ سابقةٍ لـv164 وأخرى بلا مهلة.
  final DateTime dueDate;

  final double total;
  final double paid;

  /// أيّامُ التأخّر عن الاستحقاق. **سالبٌ = لم يحن بعد** — ولا تُقصّ إلى صفرٍ
  /// هنا: «يستحق بعد خمسةِ أيّام» بيانةٌ يحتاجها جدولُ الالتزامات القادمة،
  /// وقصُّها في الاستعلام يُفقدها بلا رجعة.
  final int daysLate;

  double get remaining => total - paid;

  bool get overdue => daysLate > 0;

  /// شريحةُ العمر — نفسُ حدود تقرير التقادم كي لا يختلف رقمان لنفس الفاتورة.
  String get bucket {
    if (daysLate <= 0) return 'لم يحن';
    if (daysLate <= 30) return '١—٣٠';
    if (daysLate <= 60) return '٣١—٦٠';
    return 'فوق ٦٠';
  }
}

/// دفعةٌ لطرفٍ ومقدارُ ما رُبط منها بفواتير.
///
/// «مطابقةُ الدفعات» في كشف العميل: الدفعةُ تُخصم من أقدم فاتورةٍ ما لم
/// تُربَط يدويّاً، فالفرقُ بين [amount] و[allocated] هو ما لم يُربَط بعد.
class PartyPaymentMatchRow {
  const PartyPaymentMatchRow({
    required this.paymentId,
    required this.paymentNumber,
    required this.paymentDate,
    required this.amount,
    required this.allocated,
    required this.method,
    required this.invoiceCount,
  });

  final int paymentId;
  final String paymentNumber;
  final DateTime paymentDate;
  final double amount;

  /// مجموعُ `payment_allocations.allocated_amount` لهذه الدفعة.
  final double allocated;

  final String method;

  /// عددُ الفواتير التي وُزّعت عليها.
  final int invoiceCount;

  /// ما لم يُربَط. سالبٌ لا يقع نظريّاً، ويُقصّ لأنّ عرضَ «−٥٠ غيرُ مطابَق»
  /// يُقرأ عطلاً لا بيانة.
  double get unallocated {
    final v = amount - allocated;
    return v < 0 ? 0 : v;
  }

  bool get fullyMatched => unallocated <= 0.01;
}

/// سطرُ مطابقةٍ ثلاثيّة: أمرُ شراءٍ ← مستلَمٌ ← مفوتَر.
///
/// ولا حاجةَ إلى جدول «إذن استلام»: الكمّيّةُ المستلَمةُ تعيش على سطر الأمر
/// نفسِه (`purchase_order_items.received_quantity`)، والفاتورةُ تُربَط بالأمر
/// عبر `purchase_orders.converted_to_invoice_id`.
class PoMatchRow {
  const PoMatchRow({
    required this.orderId,
    required this.orderNumber,
    required this.productName,
    required this.ordered,
    required this.received,
    required this.invoiced,
    required this.orderDate,
    required this.expectedDate,
    required this.receivedAt,
  });

  final int orderId;
  final String orderNumber;
  final String productName;
  final double ordered;
  final double received;

  /// المفوتَرُ فعلاً — صفرٌ إن لم يُحوَّل الأمرُ إلى فاتورةٍ بعد.
  final double invoiced;

  final DateTime orderDate;
  final DateTime? expectedDate;
  final DateTime? receivedAt;

  double get qtyGap => received - ordered;
  double get billingGap => invoiced - received;

  bool get clean => qtyGap.abs() < 0.001 && billingGap.abs() < 0.001;

  /// نوعُ الفرق كما في التصميم — والترتيبُ مقصود: فرقُ الكمّيّة يسبق فرقَ
  /// الفوترة لأنّه سببُه في الغالب.
  String get gapKind {
    if (clean) return 'مطابق';
    if (qtyGap.abs() >= 0.001) return qtyGap < 0 ? 'نقصُ استلام' : 'زيادةُ استلام';
    return billingGap > 0 ? 'فوترةٌ زائدة' : 'فوترةٌ ناقصة';
  }
}

/// معدّلاتٌ **تُحسَب** لملفّ الطرف — لا تُخزَّن ولا تُكتَب بيد.
///
/// ⚠️ رقمُ التزامٍ يكتبه إنسانٌ يكذب. وهذه كلُّها مشتقّةٌ من تواريخَ حقيقيّة:
/// السدادُ من `payment_allocations` مقابلَ استحقاق الفاتورة، والتوريدُ من
/// `purchase_orders.received_at` مقابلَ `expected_date`.
class PartyProfileMetrics {
  const PartyProfileMetrics({
    required this.settledInvoices,
    required this.avgSettlementDays,
    required this.onTimeSettlements,
    required this.receivedOrders,
    required this.onTimeOrders,
  });

  /// عددُ الفواتير المسدَّدةِ كاملاً التي دخلت الحساب.
  final int settledInvoices;

  /// متوسّطُ الأيّام بين استحقاق الفاتورة وآخرِ دفعةٍ سدّدتها. سالبٌ = يسدّد
  /// **قبل** الاستحقاق، وهو خبرٌ جيّدٌ لا عطب.
  final double avgSettlementDays;

  final int onTimeSettlements;

  /// أوامرُ الشراء التي اكتمل استلامُها — وحدَها تدخل نسبةَ الالتزام.
  /// وأمرٌ مفتوحٌ ليس تأخّراً.
  final int receivedOrders;

  final int onTimeOrders;

  /// `null` حين لا فاتورةَ مسدَّدة — و«لا بيانات» ليست «صفر٪».
  double? get onTimeSettlementPct => settledInvoices == 0
      ? null
      : onTimeSettlements / settledInvoices * 100;

  double? get onTimeDeliveryPct =>
      receivedOrders == 0 ? null : onTimeOrders / receivedOrders * 100;
}

/// فاتورةٌ **بصفٍّ واحدٍ لسلوك سدادها** — متى صدرت ومتى استُحقّت ومتى سُدِّدت.
///
/// ⚠️ **صفوفٌ لا متوسّطات.** [PartyProfileMetrics] يعود بمعدّلاتٍ مجمَّعةٍ
/// تكفي المؤشّرات، ولا يكفي لرسم «آخرِ ستّ فواتير» عموداً عموداً. واصطناعُ
/// ستّةِ أعمدةٍ من متوسّطٍ واحدٍ كان يرسم بياناتٍ لا وجودَ لها — فهذا الصفُّ
/// هو ما كان ينقص.
class PartySettlementRow {
  const PartySettlementRow({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.dueDate,
    required this.total,
    required this.paid,
    required this.lastPaymentDate,
    required this.allocationCount,
  });

  final int invoiceId;
  final String invoiceNumber;
  final DateTime invoiceDate;

  /// `COALESCE(due_date, invoice_date)` — كسائرِ استعلامات التقادم، فلا
  /// يختلف رقمان لنفس الفاتورة.
  final DateTime dueDate;

  final double total;
  final double paid;

  /// آخرُ دفعةٍ خُصّصت لهذه الفاتورة. `null` = لم تُسدَّد بعدُ ولو جزئيّاً —
  /// وهي حالةٌ مختلفةٌ عن «سُدّدت في صفرِ يوم».
  final DateTime? lastPaymentDate;

  final int allocationCount;

  double get remaining => total - paid;

  bool get settled => paid >= total - 0.01;

  /// أيّامٌ من **الإصدار** إلى آخرِ سداد — وهو «سلوكُ السداد» في التصميم.
  /// `null` حين لا سداد.
  int? get daysToPay => lastPaymentDate?.difference(invoiceDate).inDays;

  /// أيّامٌ عن **الاستحقاق**: موجبٌ = تأخّر، سالبٌ = سدّد قبله.
  int? get daysVsDue => lastPaymentDate?.difference(dueDate).inDays;

  /// هل وقع السدادُ داخلَ نافذة الخصم المعجَّل؟
  ///
  /// `null` حين لا شرطَ خصمٍ متّفقٌ عليه ([days] صفرٌ أو أقلّ) أو حين لا
  /// سدادَ بعد — و«لا شرط» ليست «فات الخصم».
  bool? discountCaptured(int days) {
    if (days <= 0) return null;
    final d = daysToPay;
    if (d == null) return null;
    return d <= days;
  }
}
