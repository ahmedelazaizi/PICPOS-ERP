import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/usecases/purchases/create_purchase_usecase.dart';
import 'package:ural_erp/domain/repositories/purchases_repository.dart';
import 'package:ural_erp/domain/entities/invoice_entity.dart';
import 'package:ural_erp/data/database/database.dart';

/// Mock repository for testing
class MockPurchasesRepository implements PurchasesRepository {
  int? lastCreatedInvoiceId;
  CreatePurchaseInvoiceParams? lastParams;
  bool shouldFail = false;
  String failureMessage = 'Mock failure';

  @override
  Future<int> createInvoice(CreatePurchaseInvoiceParams params) async {
    if (shouldFail) throw Exception(failureMessage);
    lastParams = params;
    lastCreatedInvoiceId = DateTime.now().millisecondsSinceEpoch % 10000;
    return lastCreatedInvoiceId!;
  }

  @override
  Future<InvoiceEntity?> getInvoiceById(int id) async => null;

  @override
  Stream<List<InvoiceEntity>> watchInvoices() => const Stream.empty();

  @override
  Stream<List<InvoiceEntity>> watchInvoicesByDateRange(DateTime start, DateTime end) => 
      const Stream.empty();

  @override
  Future<void> recordPayment(int invoiceId, double amount, {int? userId}) async {}

  @override
  Future<void> updateInvoice(UpdatePurchaseInvoiceParams params) async {}

  @override
  Future<List<InvoiceEntity>> getPurchasesReport(DateTime start, DateTime end) async => [];

  @override
  Future<List<InvoiceEntity>> getPurchasesBySupplier(int supplierId) async => [];

  @override
  Future<void> deleteInvoice(int invoiceId) async {}

  @override
  Future<void> voidInvoice(int invoiceId, {String? reason}) async {}

  @override
  Future<List<PurchaseInvoiceItemWithProduct>> getInvoiceItemsWithProduct(int invoiceId) async => [];

  @override
  Future<PurchaseInvoiceData?> getRawInvoiceById(int id) async => null;

  @override
  Future<double> processPurchaseReturn({
    required PurchaseInvoiceData invoice,
    required List<PurchaseReturnItem> returnItems,
    String? reason,
  }) async => 0.0;

  @override
  Future<double> editPurchaseReturn({
    required PurchaseInvoiceData invoice,
    required List<PurchaseReturnItem> newReturnItems,
  }) async => 0.0;
}

void main() {
  group('CreatePurchaseUseCase', () {
    late MockPurchasesRepository mockRepository;
    late CreatePurchaseUseCase useCase;

    setUp(() {
      mockRepository = MockPurchasesRepository();
      useCase = CreatePurchaseUseCase(mockRepository);
    });

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    group('Validation', () {
      test('should fail when items list is empty', () async {
        const request = PurchaseRequest(
          supplierId: 1,
          items: [],
          paidAmount: 0,
        );

        final result = await useCase.execute(request);

        expect(result.isFailure, isTrue);
        expect((result as PurchaseFailure).error, 'لا توجد منتجات في الفاتورة');
      });

      test('should fail when supplier ID is zero', () async {
        const request = PurchaseRequest(
          supplierId: 0,
          items: [
            PurchaseItemInput(
              productId: 1,
              productName: 'Test Product',
              quantity: 5,
              unitCost: 10,
              salePrice: 15,
              taxRate: 0,
              taxAmount: 0,
            ),
          ],
          paidAmount: 50,
        );

        final result = await useCase.execute(request);

        expect(result.isFailure, isTrue);
        expect((result as PurchaseFailure).error, 'يرجى اختيار مورد');
      });

      test('should fail when supplier ID is negative', () async {
        const request = PurchaseRequest(
          supplierId: -1,
          items: [
            PurchaseItemInput(
              productId: 1,
              productName: 'Test Product',
              quantity: 5,
              unitCost: 10,
              salePrice: 15,
              taxRate: 0,
              taxAmount: 0,
            ),
          ],
          paidAmount: 50,
        );

        final result = await useCase.execute(request);

        expect(result.isFailure, isTrue);
        expect((result as PurchaseFailure).error, 'يرجى اختيار مورد');
      });

      test('should fail when item quantity is zero', () async {
        const request = PurchaseRequest(
          supplierId: 1,
          items: [
            PurchaseItemInput(
              productId: 1,
              productName: 'Test Product',
              quantity: 0,
              unitCost: 10,
              salePrice: 15,
              taxRate: 0,
              taxAmount: 0,
            ),
          ],
          paidAmount: 0,
        );

        final result = await useCase.execute(request);

        expect(result.isFailure, isTrue);
        expect((result as PurchaseFailure).error, 'الكمية يجب أن تكون أكبر من صفر');
      });

      test('should fail when item quantity is negative', () async {
        const request = PurchaseRequest(
          supplierId: 1,
          items: [
            PurchaseItemInput(
              productId: 1,
              productName: 'Test Product',
              quantity: -5,
              unitCost: 10,
              salePrice: 15,
              taxRate: 0,
              taxAmount: 0,
            ),
          ],
          paidAmount: 0,
        );

        final result = await useCase.execute(request);

        expect(result.isFailure, isTrue);
        expect((result as PurchaseFailure).error, 'الكمية يجب أن تكون أكبر من صفر');
      });

      test('should fail when unit cost is negative', () async {
        const request = PurchaseRequest(
          supplierId: 1,
          items: [
            PurchaseItemInput(
              productId: 1,
              productName: 'Test Product',
              quantity: 5,
              unitCost: -10,
              salePrice: 15,
              taxRate: 0,
              taxAmount: 0,
            ),
          ],
          paidAmount: 0,
        );

        final result = await useCase.execute(request);

        expect(result.isFailure, isTrue);
        expect((result as PurchaseFailure).error, 'سعر التكلفة لا يمكن أن يكون سالباً');
      });
    });

    // ═══════════════════════════════════════════════════════════════════════
    // SUCCESS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    group('Success Cases', () {
      test('should create purchase invoice successfully', () async {
        const request = PurchaseRequest(
          supplierId: 1,
          items: [
            PurchaseItemInput(
              productId: 1,
              productName: 'Test Product',
              quantity: 5,
              unitCost: 10,
              salePrice: 15,
              taxRate: 0,
              taxAmount: 0,
            ),
          ],
          paidAmount: 50,
        );

        final result = await useCase.execute(request);

        expect(result.isSuccess, isTrue);
        final success = result as PurchaseSuccess;
        expect(success.invoiceId, isNotNull);
        expect(success.totals.subtotal, 50.0); // 5 * 10
        expect(success.totals.itemCount, 1);
      });

      test('should calculate totals correctly for multiple items', () async {
        const request = PurchaseRequest(
          supplierId: 1,
          items: [
            PurchaseItemInput(
              productId: 1,
              productName: 'Product A',
              quantity: 10,
              unitCost: 5.0,
              salePrice: 8.0,
              taxRate: 0,
              taxAmount: 0,
            ),
            PurchaseItemInput(
              productId: 2,
              productName: 'Product B',
              quantity: 3,
              unitCost: 20.0,
              salePrice: 30.0,
              taxRate: 0,
              taxAmount: 0,
            ),
          ],
          paidAmount: 110,
        );

        final result = await useCase.execute(request);

        expect(result.isSuccess, isTrue);
        final success = result as PurchaseSuccess;
        expect(success.totals.subtotal, 110.0); // (10*5) + (3*20) = 50 + 60
        expect(success.totals.itemCount, 2);
      });

      test('should pass correct parameters to repository', () async {
        const request = PurchaseRequest(
          supplierId: 5,
          items: [
            PurchaseItemInput(
              productId: 10,
              productName: 'Test',
              quantity: 7,
              unitCost: 15,
              salePrice: 22,
              taxRate: 0,
              taxAmount: 0,
              batchNumber: 'BATCH-001',
            ),
          ],
          paidAmount: 100,
          notes: 'Test notes',
        );

        await useCase.execute(request);

        expect(mockRepository.lastParams, isNotNull);
        expect(mockRepository.lastParams!.supplierId, 5);
        expect(mockRepository.lastParams!.paid, 100);
        expect(mockRepository.lastParams!.notes, 'Test notes');
        expect(mockRepository.lastParams!.items.length, 1);
        expect(mockRepository.lastParams!.items.first.productId, 10);
        expect(mockRepository.lastParams!.items.first.quantity, 7);
        expect(mockRepository.lastParams!.items.first.unitCost, 15);
        expect(mockRepository.lastParams!.items.first.batchNumber, 'BATCH-001');
      });
    });

    // ═══════════════════════════════════════════════════════════════════════
    // ERROR HANDLING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    group('Error Handling', () {
      test('should return failure when repository throws exception', () async {
        mockRepository.shouldFail = true;
        mockRepository.failureMessage = 'Database error';

        const request = PurchaseRequest(
          supplierId: 1,
          items: [
            PurchaseItemInput(
              productId: 1,
              productName: 'Test',
              quantity: 5,
              unitCost: 10,
              salePrice: 15,
              taxRate: 0,
              taxAmount: 0,
            ),
          ],
          paidAmount: 50,
        );

        final result = await useCase.execute(request);

        expect(result.isFailure, isTrue);
        expect((result as PurchaseFailure).error, contains('فشل في حفظ فاتورة الشراء'));
      });
    });

    // ═══════════════════════════════════════════════════════════════════════
    // DATA CLASS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    group('Data Classes', () {
      test('PurchaseItemInput.total should calculate correctly', () {
        const item = PurchaseItemInput(
          productId: 1,
          productName: 'Test',
          quantity: 7.5,
          unitCost: 12.0,
          salePrice: 18.0,
          taxRate: 0,
          taxAmount: 0,
        );

        expect(item.total, 90.0); // 7.5 * 12
      });

      test('PurchaseTotals.total should return subtotal', () {
        const totals = PurchaseTotals(subtotal: 150.0, itemCount: 3);
        
        expect(totals.total, 150.0);
      });

      test('PurchaseResult.isSuccess should return correct value', () {
        final success = PurchaseResult.success(
          invoiceId: 1,
          totals: const PurchaseTotals(subtotal: 100, itemCount: 1),
        );
        final failure = PurchaseResult.failure('error');

        expect(success.isSuccess, isTrue);
        expect(success.isFailure, isFalse);
        expect(failure.isSuccess, isFalse);
        expect(failure.isFailure, isTrue);
      });
    });
  });
}
