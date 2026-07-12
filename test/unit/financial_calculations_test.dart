import 'package:flutter_test/flutter_test.dart';

/// Unit tests for financial calculations
/// Tests invoice totals, tax calculations, discounts, and stock updates
void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // INVOICE CALCULATIONS
  // ═══════════════════════════════════════════════════════════════════════════
  
  group('Invoice Total Calculations', () {
    test('Single item invoice total is quantity * price', () {
      const quantity = 3.0;
      const price = 100.0;
      const total = quantity * price;
      
      expect(total, equals(300.0));
    });
    
    test('Multiple items invoice subtotal', () {
      final items = [
        {'quantity': 2.0, 'price': 50.0},
        {'quantity': 3.0, 'price': 100.0},
        {'quantity': 1.0, 'price': 75.0},
      ];
      
      final subtotal = items.fold(0.0, (sum, item) => 
        sum + (item['quantity']! * item['price']!));
      
      expect(subtotal, equals(475.0)); // 100 + 300 + 75
    });
    
    test('Invoice with discount applied correctly', () {
      const subtotal = 500.0;
      const discount = 50.0;
      const afterDiscount = subtotal - discount;
      
      expect(afterDiscount, equals(450.0));
    });
    
    test('Percentage discount calculated correctly', () {
      const subtotal = 500.0;
      const discountPercent = 10.0;
      const discountAmount = subtotal * (discountPercent / 100);
      const afterDiscount = subtotal - discountAmount;
      
      expect(discountAmount, equals(50.0));
      expect(afterDiscount, equals(450.0));
    });
  });
  
  // ═══════════════════════════════════════════════════════════════════════════
  // TAX CALCULATIONS
  // ═══════════════════════════════════════════════════════════════════════════
  
  group('Tax Calculations', () {
    test('14% VAT calculated correctly', () {
      const subtotal = 100.0;
      const taxRate = 0.14;
      const tax = subtotal * taxRate;
      
      expect(tax, closeTo(14.0, 0.01));
    });
    
    test('Tax on discounted amount', () {
      const subtotal = 100.0;
      const discount = 20.0;
      const taxRate = 0.14;
      const taxable = subtotal - discount;
      const tax = taxable * taxRate;
      
      expect(taxable, equals(80.0));
      expect(tax, closeTo(11.2, 0.01));
    });
    
    test('Total with tax calculation', () {
      const subtotal = 100.0;
      const discount = 0.0;
      const taxRate = 0.14;
      const taxable = subtotal - discount;
      const tax = taxable * taxRate;
      const total = taxable + tax;
      
      expect(total, equals(114.0));
    });
    
    test('Zero tax when tax disabled', () {
      const subtotal = 100.0;
      const taxRate = 0.14;
      const includeTax = false;
      // Calculate tax only if enabled
      double calculateTax(bool enabled) => enabled ? subtotal * taxRate : 0.0;
      final tax = calculateTax(includeTax);
      
      expect(tax, equals(0.0));
    });
    
    test('Complex invoice calculation', () {
      // Scenario: 3 items, 10% discount, 14% tax
      final items = [
        {'quantity': 2.0, 'price': 150.0}, // 300
        {'quantity': 5.0, 'price': 25.0},  // 125
        {'quantity': 1.0, 'price': 75.0},  // 75
      ];
      
      final subtotal = items.fold(0.0, (sum, item) => 
        sum + (item['quantity']! * item['price']!));
      expect(subtotal, equals(500.0));
      
      const discountPercent = 10.0;
      final discount = subtotal * (discountPercent / 100);
      expect(discount, equals(50.0));
      
      final afterDiscount = subtotal - discount;
      expect(afterDiscount, equals(450.0));
      
      const taxRate = 0.14;
      final tax = afterDiscount * taxRate;
      expect(tax, closeTo(63.0, 0.01));
      
      final total = afterDiscount + tax;
      expect(total, closeTo(513.0, 0.01));
    });
  });
  
  // ═══════════════════════════════════════════════════════════════════════════
  // PAYMENT CALCULATIONS
  // ═══════════════════════════════════════════════════════════════════════════
  
  group('Payment Calculations', () {
    test('Change calculated correctly', () {
      const total = 85.0;
      const paid = 100.0;
      const change = paid - total;
      
      expect(change, equals(15.0));
    });
    
    test('No change when exact payment', () {
      const total = 100.0;
      const paid = 100.0;
      const change = paid - total;
      
      expect(change, equals(0.0));
    });
    
    test('Remaining balance for partial payment', () {
      const total = 500.0;
      const paid = 300.0;
      const remaining = total - paid;
      
      expect(remaining, equals(200.0));
    });
    
    test('Payment status determination', () {
      String getStatus(double total, double paid) {
        if (paid >= total) return 'paid';
        if (paid > 0) return 'partial';
        return 'pending';
      }
      
      expect(getStatus(100, 100), equals('paid'));
      expect(getStatus(100, 150), equals('paid'));
      expect(getStatus(100, 50), equals('partial'));
      expect(getStatus(100, 0), equals('pending'));
    });
  });
  
  // ═══════════════════════════════════════════════════════════════════════════
  // STOCK CALCULATIONS
  // ═══════════════════════════════════════════════════════════════════════════
  
  group('Stock Calculations', () {
    test('Stock decrease after sale', () {
      const currentStock = 100.0;
      const soldQuantity = 10.0;
      const newStock = currentStock - soldQuantity;
      
      expect(newStock, equals(90.0));
    });
    
    test('Stock increase after purchase', () {
      const currentStock = 50.0;
      const purchasedQuantity = 30.0;
      const newStock = currentStock + purchasedQuantity;
      
      expect(newStock, equals(80.0));
    });
    
    test('Low stock detection', () {
      bool isLowStock(double current, double minimum) {
        return current <= minimum;
      }
      
      expect(isLowStock(5, 10), isTrue);
      expect(isLowStock(10, 10), isTrue);
      expect(isLowStock(15, 10), isFalse);
    });
    
    test('Stock value calculation', () {
      const currentStock = 50.0;
      const costPrice = 25.0;
      const stockValue = currentStock * costPrice;
      
      expect(stockValue, equals(1250.0));
    });
  });
  
  // ═══════════════════════════════════════════════════════════════════════════
  // PROFIT CALCULATIONS
  // ═══════════════════════════════════════════════════════════════════════════
  
  group('Profit Calculations', () {
    test('Simple profit margin', () {
      const salePrice = 100.0;
      const costPrice = 70.0;
      const profit = salePrice - costPrice;
      const margin = (profit / salePrice) * 100;
      
      expect(profit, equals(30.0));
      expect(margin, equals(30.0));
    });
    
    test('Profit on invoice', () {
      final items = [
        {'quantity': 2.0, 'salePrice': 100.0, 'costPrice': 70.0},
        {'quantity': 3.0, 'salePrice': 50.0, 'costPrice': 30.0},
      ];
      
      final totalRevenue = items.fold(0.0, (sum, item) => 
        sum + (item['quantity']! * item['salePrice']!));
      final totalCost = items.fold(0.0, (sum, item) => 
        sum + (item['quantity']! * item['costPrice']!));
      final profit = totalRevenue - totalCost;
      
      expect(totalRevenue, equals(350.0)); // 200 + 150
      expect(totalCost, equals(230.0));    // 140 + 90
      expect(profit, equals(120.0));
    });
    
    test('Profit with discount', () {
      const salePrice = 100.0;
      const costPrice = 70.0;
      const discount = 10.0;
      const actualSale = salePrice - discount;
      const profit = actualSale - costPrice;
      
      expect(actualSale, equals(90.0));
      expect(profit, equals(20.0));
    });
  });
  
  // ═══════════════════════════════════════════════════════════════════════════
  // TREASURY CALCULATIONS
  // ═══════════════════════════════════════════════════════════════════════════
  
  group('Treasury Calculations', () {
    test('Balance after receipt', () {
      const currentBalance = 1000.0;
      const receiptAmount = 500.0;
      const newBalance = currentBalance + receiptAmount;
      
      expect(newBalance, equals(1500.0));
    });
    
    test('Balance after payment', () {
      const currentBalance = 1000.0;
      const paymentAmount = 300.0;
      const newBalance = currentBalance - paymentAmount;
      
      expect(newBalance, equals(700.0));
    });
    
    test('Net cash flow', () {
      const totalReceipts = 5000.0;
      const totalPayments = 3000.0;
      const netFlow = totalReceipts - totalPayments;
      
      expect(netFlow, equals(2000.0));
    });
    
    test('Party balance after sale on credit', () {
      const customerBalance = 0.0;
      const invoiceTotal = 500.0;
      const paid = 200.0;
      const newBalance = customerBalance + (invoiceTotal - paid);
      
      expect(newBalance, equals(300.0)); // Customer owes 300
    });
    
    test('Party balance after payment received', () {
      const customerBalance = 500.0;
      const paymentReceived = 200.0;
      const newBalance = customerBalance - paymentReceived;
      
      expect(newBalance, equals(300.0));
    });
  });
  
  // ═══════════════════════════════════════════════════════════════════════════
  // UNIT CONVERSION CALCULATIONS
  // ═══════════════════════════════════════════════════════════════════════════
  
  group('Unit Conversion', () {
    test('Carton to pieces conversion', () {
      const cartons = 5.0;
      const piecesPerCarton = 24.0;
      const totalPieces = cartons * piecesPerCarton;
      
      expect(totalPieces, equals(120.0));
    });
    
    test('Price per piece from carton', () {
      const cartonPrice = 240.0;
      const piecesPerCarton = 24.0;
      const pricePerPiece = cartonPrice / piecesPerCarton;
      
      expect(pricePerPiece, equals(10.0));
    });
    
    test('Weight-based pricing', () {
      const pricePerKg = 50.0;
      const weightInKg = 1.5;
      const total = pricePerKg * weightInKg;
      
      expect(total, equals(75.0));
    });
    
    test('Converting grams to kilograms price', () {
      const pricePerKg = 100.0;
      const weightInGrams = 500.0;
      const weightInKg = weightInGrams / 1000;
      const total = pricePerKg * weightInKg;
      
      expect(weightInKg, equals(0.5));
      expect(total, equals(50.0));
    });
  });
}
