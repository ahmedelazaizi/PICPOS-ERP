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
class SalesInvoiceItemWithProduct {
  final SalesInvoiceItem item;
  final Product product;

  SalesInvoiceItemWithProduct({required this.item, required this.product});
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
