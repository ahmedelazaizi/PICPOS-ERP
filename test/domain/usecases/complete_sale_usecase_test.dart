import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/usecases/sales/complete_sale_usecase.dart';
import 'package:ural_erp/domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/repositories/sales_repository.dart';
import 'package:ural_erp/domain/entities/invoice_entity.dart';
import 'package:ural_erp/data/database/database.dart';

/// Manual Mock for SalesRepository to avoid build_runner dependency
class MockSalesRepository implements SalesRepository {
  int? nextInvoiceId;
  
  @override
  Future<int> createSalesInvoice({
    required int? customerId,
    required int warehouseId,
    required int userId,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    required String paymentMethod,
    required List<CartItemEntity> items,
    double? cashAmount,
    double? bankAmount,
    double? clickAmount,
    int? cashSafeId,
    int? bankSafeId,
    int? clickSafeId,
    double deliveryFee = 0,
    int? deliveryCompanyId,
    int? courierId,
    String? deliveryStatus,
    String? platformOrderNumber,
    String? notes,
    String? adhocCustomerName,
    String? adhocCustomerPhone,
  }) async {
    return nextInvoiceId ?? 1;
  }

  @override
  Future<void> cancelInvoice(int invoiceId, {int? userId}) async {}

  @override
  Future<SaleResult> completeSalesTransaction(SaleRequest request) async {
    // Day 9: validation moved to CompleteSaleUseCase — the repository mock
    // simply persists and returns success (policy is the UseCase's job).
    return SaleResult.success(
      invoiceId: nextInvoiceId ?? 1,
      invoiceNumber: 'INV-${nextInvoiceId ?? 1}',
      totals: null,
    );
  }

  @override
  Future<void> voidInvoice(int invoiceId, {String? reason, int? userId}) async {}

  @override
  Future<SalesPrintData?> getSalesPrintData(int invoiceId) async => null;

  @override
  Future<InvoiceEntity?> getInvoiceById(int id) async => null;

  @override
  Future<InvoiceEntity?> getInvoiceByNumber(String invoiceNumber) async => null;

  @override
  Future<void> recordPayment(int invoiceId, double amount, {int? userId}) async {}

  @override
  Stream<List<InvoiceEntity>> watchInvoices() => Stream.value([]);

  @override
  Future<List<InvoiceEntity>> getInvoicesPaged({int limit = 500, int offset = 0}) async => [];

  @override
  Stream<List<InvoiceEntity>> watchInvoicesByDateRange(DateTime start, DateTime end) => Stream.value([]);

  @override
  Future<List<SalesInvoiceItem>> getSalesInvoiceItems(int invoiceId) async => [];

  @override
  Future<SalesInvoiceData?> getRawInvoiceById(int id) async => null;

  @override
  Future<String> generateInvoiceNumber(String prefix) async => '$prefix-001';

  @override
  Stream<List<InvoiceEntity>> watchPaginatedInvoices({
    int limit = 50,
    int offset = 0,
    DateTime? fromDate,
    DateTime? toDate,
    String? status,
  }) => Stream.value([]);

  @override
  Stream<List<SalesInvoiceData>> watchTodaySales() => Stream.value([]);

  @override
  Stream<List<SalesInvoiceData>> watchTodaySalesForUser(int userId) => Stream.value([]);

  @override
  Stream<List<SalesInvoiceData>> watchSalesSince(DateTime from, {int? userId}) =>
      Stream.value([]);

  @override
  Future<List<SalesInvoiceData>> getInvoicesSince(DateTime since) async => [];

  @override
  Future<void> updateInvoiceStatus(int invoiceId, String status) async {}

  @override
  Future<List<SalesInvoiceData>> searchInvoicesByNumber(String query) async => [];

  @override
  Future<void> updateSalesInvoicePayment(
    int invoiceId,
    String paymentMethod,
    String? notes, {
    double? newCashAmount,
    double? newBankAmount,
  }) async {}

  @override
  Future<List<SalesInvoiceItemWithProduct>> getInvoiceItemsWithProduct(int invoiceId) async => [];

  @override
  Future<void> updateFullSalesInvoice({
    required int invoiceId,
    int? customerId,
    int warehouseId = 1,
    required double paid,
    required String paymentMethod,
    String? notes,
    required List<CartItemEntity> items,
    int? costCenterId,
  }) async {}

  @override
  Stream<List<SalesInvoiceData>> watchAllRawInvoices() => Stream.value([]);

  @override
  Future<void> updateSaleType(int invoiceId, String saleType) async {}

  @override
  Future<List<InvoiceEntity>> getRawInvoices({int limit = 500}) async => [];

  @override
  Future<DiagnosticSample> getDiagnosticSample({int limit = 20}) async =>
      const DiagnosticSample(totalCount: 0, undeletedSample: [], sampleText: '');
}

void main() {
  late CompleteSaleUseCase useCase;
  late MockSalesRepository mockRepository;
  late CalculateInvoiceTotalsUseCase totalsUseCase;

  setUp(() {
    mockRepository = MockSalesRepository();
    totalsUseCase = CalculateInvoiceTotalsUseCase();
    useCase = CompleteSaleUseCase(mockRepository);
  });

  group('CompleteSaleUseCase', () {
    final testItems = [
      const CartItemEntity(
        productId: 1,
        productName: 'منتج 1',
        productCode: 'P001',
        quantity: 2,
        unitPrice: 10.0,
      ),
      const CartItemEntity(
        productId: 2,
        productName: 'منتج 2',
        productCode: 'P002',
        quantity: 1,
        unitPrice: 15.0,
      ),
    ];

    test('should fail when cart is empty', () async {
      const request = SaleRequest(
        items: [],
        paymentMethod: 'cash',
        paidAmount: 0,
      );

      final result = await useCase.execute(request);

      expect(result.isFailure, true);
      expect((result as SaleFailure).error, contains('فارغة'));
    });

    test('should fail when credit sale has no customer', () async {
      final request = SaleRequest(
        items: testItems,
        paymentMethod: 'credit',
        paidAmount: 0,
        customerId: null,
      );

      final result = await useCase.execute(request);

      expect(result.isFailure, true);
      expect((result as SaleFailure).error, contains('عميل'));
    });

    test('should fail when mixed payment is less than total', () async {
      final request = SaleRequest(
        items: testItems,
        paymentMethod: 'mixed',
        paidAmount: 0,
        cashAmount: 10,
        bankAmount: 5, // Total = 15, but subtotal = 35 + tax
      );

      final result = await useCase.execute(request);

      expect(result.isFailure, true);
      expect((result as SaleFailure).error, contains('أقل'));
    });

    test('should succeed with valid cash payment', () async {
      mockRepository.nextInvoiceId = 123;

      final request = SaleRequest(
        items: testItems,
        paymentMethod: 'cash',
        paidAmount: 50, // More than enough
        taxEnabled: true,
        taxPercent: 14,
      );

      final result = await useCase.execute(request);

      expect(result.isSuccess, true);
      final success = result as SaleSuccess;
      expect(success.invoiceId, 123);
    });

    test('should succeed with credit sale when customer selected', () async {
      mockRepository.nextInvoiceId = 456;

      final request = SaleRequest(
        items: testItems,
        paymentMethod: 'credit',
        paidAmount: 0,
        customerId: 5,
      );

      final result = await useCase.execute(request);

      expect(result.isSuccess, true);
      final success = result as SaleSuccess;
      expect(success.invoiceId, 456);
    });
    // ── Day 9 PIR: validation lives in UseCase, not in Repository ──────────

    test('D-09: empty-cart validation runs before repository is called', () async {
      // If the UseCase delegates validation to the repo, the mock would need
      // to return failure. This test uses a mock that ALWAYS returns success —
      // proving the UseCase itself is the one blocking the empty cart.
      mockRepository.nextInvoiceId = 99;
      const request = SaleRequest(items: [], paymentMethod: 'cash', paidAmount: 0);

      final result = await useCase.execute(request);

      expect(result.isFailure, true);
      expect((result as SaleFailure).error, contains('فارغة'));
    });

    test('D-09: credit-without-customer validation runs in UseCase', () async {
      mockRepository.nextInvoiceId = 99; // Would succeed if repo were called
      final request = SaleRequest(
        items: testItems,
        paymentMethod: 'credit',
        paidAmount: 0,
        customerId: null,
      );

      final result = await useCase.execute(request);

      expect(result.isFailure, true);
      expect((result as SaleFailure).error, contains('عميل'));
    });

    test('D-09: mixed payment exactly covering total succeeds', () async {
      // Total = 35 (no tax) → paying exactly 35 in cash+bank must succeed.
      mockRepository.nextInvoiceId = 77;
      final request = SaleRequest(
        items: testItems, // 2*10 + 1*15 = 35
        paymentMethod: 'mixed',
        paidAmount: 35,
        cashAmount: 20,
        bankAmount: 15,
        taxEnabled: false, // no tax → total = 35
      );

      final result = await useCase.execute(request);

      expect(result.isSuccess, true);
      expect((result as SaleSuccess).invoiceId, 77);
    });

    test('D-09: click amount counts towards mixed-payment coverage', () async {
      mockRepository.nextInvoiceId = 88;
      final request = SaleRequest(
        items: testItems, // subtotal = 35
        paymentMethod: 'multiple',
        paidAmount: 35,
        cashAmount: 10,
        bankAmount: 10,
        clickAmount: 15, // total coverage = 35
        taxEnabled: false,
      );

      final result = await useCase.execute(request);

      expect(result.isSuccess, true);
    });

    test('BUG-C04: mixed payment must cover the delivery fee', () async {
      // items total = 35, delivery = 5 => amount due = 40.
      // Paying exactly the item total (35) must be REJECTED.
      final request = SaleRequest(
        items: testItems,
        paymentMethod: 'mixed',
        paidAmount: 35,
        cashAmount: 35,
        bankAmount: 0,
        deliveryFee: 5,
        taxEnabled: false,
      );

      final result = await useCase.execute(request);

      expect(result.isFailure, true);
      expect((result as SaleFailure).error, contains('أقل'));
    });

    group('CalculateInvoiceTotalsUseCase', () {
    test('should calculate correctly with tax', () {
      final totals = totalsUseCase.execute(
        items: [
          const CartItemEntity(
            productId: 1,
            productName: 'A',
            productCode: 'A',
            quantity: 2,
            unitPrice: 100,
          ),
        ],
        taxPercent: 15,
      );
      
      expect(totals.subtotal, 200);
      expect(totals.taxAmount, 30);
      expect(totals.total, 230);
    });

    test('should handle discounts correctly', () {
      final totals = totalsUseCase.execute(
        items: [
          const CartItemEntity(
            productId: 1,
            productName: 'A',
            productCode: 'A',
            quantity: 2,
            unitPrice: 100,
            discountPercent: 10, // 20 discount
          ),
        ],
        invoiceDiscountPercent: 10, // (200-20) * 0.1 = 18
      );
      
      expect(totals.subtotal, 200);
      expect(totals.itemDiscounts, 20);
      expect(totals.invoiceDiscount, 18);
      expect(totals.total, 162);
    });
  });
  });
}
