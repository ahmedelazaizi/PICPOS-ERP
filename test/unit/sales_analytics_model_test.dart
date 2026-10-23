import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

/// Unit tests for SalesAnalytics and PurchasesAnalytics models
///
/// Validates the data models returned by the SQL-optimized analytics queries.
/// These models represent the O(1) memory results from Phase 9.2.
void main() {
  group('SalesAnalytics Model', () {
    test('constructs with all fields', () {
      final analytics = SalesAnalytics(
        totalSales: 50000.0,
        totalGrossProfit: 15000.0,
        totalNetProfit: 12000.0,
        totalProfit: 12000.0,
        totalDiscount: 2500.0,
        totalTax: 3000.0,
        salesCount: 150,
        invoiceCount: 150,
        averageSaleValue: 333.33,
        averageInvoiceValue: 333.33,
      );

      expect(analytics.totalSales, 50000.0);
      expect(analytics.totalGrossProfit, 15000.0);
      expect(analytics.totalNetProfit, 12000.0);
      expect(analytics.totalProfit, 12000.0);
      expect(analytics.totalDiscount, 2500.0);
      expect(analytics.totalTax, 3000.0);
      expect(analytics.invoiceCount, 150);
      expect(analytics.salesCount, 150);
    });

    test('handles zero values (empty date range)', () {
      final analytics = SalesAnalytics(
        totalSales: 0,
        totalGrossProfit: 0,
        totalNetProfit: 0,
        totalProfit: 0,
        totalDiscount: 0,
        totalTax: 0,
        salesCount: 0,
        invoiceCount: 0,
        averageSaleValue: 0,
        averageInvoiceValue: 0,
      );

      expect(analytics.totalSales, 0);
      expect(analytics.invoiceCount, 0);
    });

    test('handles large values (stress test)', () {
      final analytics = SalesAnalytics(
        totalSales: 999999999.99,
        totalGrossProfit: 500000000.0,
        totalNetProfit: 400000000.0,
        totalProfit: 400000000.0,
        totalDiscount: 50000000.0,
        totalTax: 140000000.0,
        salesCount: 1000000,
        invoiceCount: 1000000,
        averageSaleValue: 999.99,
        averageInvoiceValue: 999.99,
      );

      expect(analytics.totalSales, 999999999.99);
      expect(analytics.invoiceCount, 1000000);
    });

    test('duplicate fields match for UI compatibility', () {
      final analytics = SalesAnalytics(
        totalSales: 1000.0,
        totalGrossProfit: 300.0,
        totalNetProfit: 250.0,
        totalProfit: 250.0,
        totalDiscount: 50.0,
        totalTax: 100.0,
        salesCount: 5,
        invoiceCount: 5,
        averageSaleValue: 200.0,
        averageInvoiceValue: 200.0,
      );

      // Verify duplicate fields match
      expect(analytics.totalProfit, analytics.totalNetProfit);
      expect(analytics.invoiceCount, analytics.salesCount);
      expect(analytics.averageInvoiceValue, analytics.averageSaleValue);
    });
  });

  group('PurchasesAnalytics Model', () {
    test('constructs with all fields', () {
      final analytics = PurchasesAnalytics(
        totalPurchases: 75000.0,
        totalOutstanding: 15000.0,
        invoiceCount: 80,
        averagePurchaseValue: 937.5,
      );

      expect(analytics.totalPurchases, 75000.0);
      expect(analytics.totalOutstanding, 15000.0);
      expect(analytics.invoiceCount, 80);
      expect(analytics.averagePurchaseValue, 937.5);
    });

    test('handles zero outstanding (fully paid)', () {
      final analytics = PurchasesAnalytics(
        totalPurchases: 50000.0,
        totalOutstanding: 0.0,
        invoiceCount: 30,
        averagePurchaseValue: 1666.67,
      );

      expect(analytics.totalOutstanding, 0.0);
    });

    test('handles zero purchases', () {
      final analytics = PurchasesAnalytics(
        totalPurchases: 0,
        totalOutstanding: 0,
        invoiceCount: 0,
        averagePurchaseValue: 0,
      );

      expect(analytics.totalPurchases, 0);
      expect(analytics.totalOutstanding, 0);
      expect(analytics.invoiceCount, 0);
    });
  });
}
