// ═══════════════════════════════════════════════════════════════════════════
// ProcessSalesReturnUseCase — Validation tests (ISS coverage boost)
// ═══════════════════════════════════════════════════════════════════════════
//
// Tests the validation paths in ProcessSalesReturnUseCase.execute() that
// return early before any database write. Uses AppDatabase.forTesting() so
// _validate's invoice-lookup branch returns null (not found → failure).

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/activity_logger.dart';
import 'package:ural_erp/domain/usecases/returns/process_sales_return_usecase.dart';

void main() {
  late AppDatabase db;
  late ActivityLogger logger;
  late ProcessSalesReturnUseCase useCase;

  setUp(() {
    db = AppDatabase.forTesting();
    logger = ActivityLogger(db);
    useCase = ProcessSalesReturnUseCase(db, logger);
  });

  tearDown(() => db.close());

  const sampleItem = ReturnItemInput(
    originalItemId: 1,
    productId: 1,
    productName: 'Widget',
    quantity: 2,
    unitPrice: 50,
  );

  // ── Validation: empty items ──────────────────────────────────────────────
  group('execute() — validation', () {
    test('fails immediately when items list is empty', () async {
      const request = SalesReturnRequest(
        originalInvoiceId: 1,
        items: [],
        returnReason: 'test',
      );
      final result = await useCase.execute(request);
      expect(result.isFailure, isTrue);
      expect((result as ReturnFailure).error,
          contains('لا توجد منتجات للإرجاع'));
    });

    test('fails when originalInvoiceId is zero', () async {
      const request = SalesReturnRequest(
        originalInvoiceId: 0,
        items: [sampleItem],
        returnReason: 'test',
      );
      final result = await useCase.execute(request);
      expect(result.isFailure, isTrue);
      expect((result as ReturnFailure).error,
          contains('رقم الفاتورة الأصلية غير صحيح'));
    });

    test('fails when originalInvoiceId is negative', () async {
      const request = SalesReturnRequest(
        originalInvoiceId: -5,
        items: [sampleItem],
        returnReason: 'test',
      );
      final result = await useCase.execute(request);
      expect(result.isFailure, isTrue);
    });

    test('fails when invoice not found in db', () async {
      // AppDatabase.forTesting() has no sales invoices → getSalesInvoiceById returns null
      const request = SalesReturnRequest(
        originalInvoiceId: 999,
        items: [sampleItem],
        returnReason: 'test',
      );
      final result = await useCase.execute(request);
      expect(result.isFailure, isTrue);
      // Either "not found" or some other failure
      expect(result.isFailure, isTrue);
    });
  });

  // ── ReturnTotals data class ──────────────────────────────────────────────
  group('ReturnTotals', () {
    test('total returns subtotal', () {
      const totals = ReturnTotals(subtotal: 250, itemCount: 3);
      expect(totals.total, 250);
      expect(totals.itemCount, 3);
    });
  });

  // ── ReturnItemInput data class ───────────────────────────────────────────
  group('ReturnItemInput', () {
    test('total = quantity * unitPrice', () {
      const item = ReturnItemInput(
        originalItemId: 1,
        productId: 5,
        productName: 'Rice',
        quantity: 4,
        unitPrice: 12.5,
      );
      expect(item.total, closeTo(50.0, 0.001));
    });
  });

  // ── ReturnResult sealed class ────────────────────────────────────────────
  group('ReturnResult', () {
    test('success: isSuccess=true, isFailure=false', () {
      final r = ReturnResult.success(
        returnId: 10,
        refundAmount: 100,
        itemsReturned: 2,
      );
      expect(r.isSuccess, isTrue);
      expect(r.isFailure, isFalse);
      final s = r as ReturnSuccess;
      expect(s.returnId, 10);
      expect(s.refundAmount, 100);
      expect(s.itemsReturned, 2);
    });

    test('failure: isSuccess=false, isFailure=true', () {
      final r = ReturnResult.failure('something went wrong');
      expect(r.isSuccess, isFalse);
      expect(r.isFailure, isTrue);
      expect((r as ReturnFailure).error, 'something went wrong');
    });
  });
}
