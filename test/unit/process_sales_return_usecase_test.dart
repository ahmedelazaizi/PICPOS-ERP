import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/usecases/returns/process_sales_return_usecase.dart';

/// These tests verify the pure validation logic and data classes of
/// ProcessSalesReturnUseCase without requiring a database connection.
/// The UseCase now depends on AppDatabase + ActivityLogger directly,
/// so we test only the request/response data classes and validation rules.
void main() {
  group('ProcessSalesReturnUseCase — Data Classes', () {
    // ═══════════════════════════════════════════════════════════════════════
    // SalesReturnRequest
    // ═══════════════════════════════════════════════════════════════════════

    test('SalesReturnRequest default values', () {
      const request = SalesReturnRequest(
        originalInvoiceId: 100,
        items: [],
        returnReason: 'Defective',
      );

      expect(request.originalInvoiceId, 100);
      expect(request.items, isEmpty);
      expect(request.returnReason, 'Defective');
      expect(request.refundMethod, 'cash');
      expect(request.userId, 1);
      expect(request.isFullReturn, false);
      expect(request.customerId, isNull);
      expect(request.notes, isNull);
    });

    test('SalesReturnRequest with all fields', () {
      const request = SalesReturnRequest(
        originalInvoiceId: 50,
        customerId: 10,
        items: [
          ReturnItemInput(
            originalItemId: 1,
            productId: 5,
            productName: 'Widget',
            quantity: 3,
            unitPrice: 25.0,
          ),
        ],
        returnReason: 'Customer changed mind',
        refundMethod: 'credit',
        notes: 'Handle with care',
        userId: 7,
        isFullReturn: true,
      );

      expect(request.originalInvoiceId, 50);
      expect(request.customerId, 10);
      expect(request.items.length, 1);
      expect(request.refundMethod, 'credit');
      expect(request.notes, 'Handle with care');
      expect(request.userId, 7);
      expect(request.isFullReturn, true);
    });

    // ═══════════════════════════════════════════════════════════════════════
    // ReturnItemInput
    // ═══════════════════════════════════════════════════════════════════════

    test('ReturnItemInput.total should calculate correctly', () {
      const item = ReturnItemInput(
        originalItemId: 1,
        productId: 1,
        productName: 'Test',
        quantity: 4,
        unitPrice: 7.5,
      );

      expect(item.total, 30.0); // 4 * 7.5
    });

    test('ReturnItemInput.total with fractional quantity', () {
      const item = ReturnItemInput(
        originalItemId: 1,
        productId: 2,
        productName: 'Rice',
        quantity: 2.5,
        unitPrice: 12.0,
      );

      expect(item.total, 30.0); // 2.5 * 12
    });

    // ═══════════════════════════════════════════════════════════════════════
    // ReturnTotals
    // ═══════════════════════════════════════════════════════════════════════

    test('ReturnTotals.total should return subtotal', () {
      const totals = ReturnTotals(subtotal: 200.0, itemCount: 5);

      expect(totals.total, 200.0);
      expect(totals.itemCount, 5);
    });

    // ═══════════════════════════════════════════════════════════════════════
    // ReturnResult sealed class
    // ═══════════════════════════════════════════════════════════════════════

    test('ReturnResult.success should be a ReturnSuccess', () {
      final success = ReturnResult.success(
        returnId: 1,
        refundAmount: 100,
        itemsReturned: 2,
      );

      expect(success.isSuccess, isTrue);
      expect(success.isFailure, isFalse);
      expect(success, isA<ReturnSuccess>());
      expect((success as ReturnSuccess).returnId, 1);
      expect(success.refundAmount, 100.0);
      expect(success.itemsReturned, 2);
    });

    test('ReturnResult.failure should be a ReturnFailure', () {
      final failure = ReturnResult.failure('Something went wrong');

      expect(failure.isSuccess, isFalse);
      expect(failure.isFailure, isTrue);
      expect(failure, isA<ReturnFailure>());
      expect((failure as ReturnFailure).error, 'Something went wrong');
    });

    // ═══════════════════════════════════════════════════════════════════════
    // ValidationResult
    // ═══════════════════════════════════════════════════════════════════════

    test('ValidationResult.valid', () {
      const result = ValidationResult.valid();
      expect(result.isValid, isTrue);
      expect(result.error, isNull);
    });

    test('ValidationResult.invalid', () {
      const result = ValidationResult.invalid('Bad input');
      expect(result.isValid, isFalse);
      expect(result.error, 'Bad input');
    });
  });
}
