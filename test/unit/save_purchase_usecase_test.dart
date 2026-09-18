// ═══════════════════════════════════════════════════════════════════════════
// SavePurchaseUseCase — Unit Tests (coverage: save_purchase_usecase.dart)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/usecases/purchases/save_purchase_usecase.dart';
import 'package:ural_erp/domain/repositories/purchases_repository.dart';
import 'package:ural_erp/domain/entities/invoice_entity.dart';
import 'package:ural_erp/data/database/database.dart';

class _MockPurchasesRepository implements PurchasesRepository {
  bool shouldFail = false;
  bool updateCalled = false;
  int nextId = 99;

  @override
  Future<int> createInvoice(CreatePurchaseInvoiceParams params) async {
    if (shouldFail) throw Exception('DB error');
    return nextId;
  }

  @override
  Future<void> updateInvoice(UpdatePurchaseInvoiceParams params) async {
    if (shouldFail) throw Exception('DB error');
    updateCalled = true;
  }

  @override
  Future<InvoiceEntity?> getInvoiceById(int id) async => null;
  @override
  Stream<List<InvoiceEntity>> watchInvoices() => const Stream.empty();
  @override
  Stream<List<InvoiceEntity>> watchInvoicesByDateRange(DateTime s, DateTime e) =>
      const Stream.empty();
  @override
  Future<void> recordPayment(int invoiceId, double amount, {int? userId}) async {}
  @override
  Future<List<InvoiceEntity>> getPurchasesReport(DateTime s, DateTime e) async =>
      [];
  @override
  Future<List<InvoiceEntity>> getPurchasesBySupplier(int supplierId) async => [];
  @override
  Future<void> deleteInvoice(int invoiceId) async {}
  @override
  Future<void> voidInvoice(int invoiceId, {String? reason}) async {}
  @override
  Future<List<PurchaseInvoiceItemWithProduct>> getInvoiceItemsWithProduct(
          int invoiceId) async =>
      [];
  @override
  Future<PurchaseInvoiceData?> getRawInvoiceById(int id) async => null;
  @override
  Future<double> processPurchaseReturn({
    required PurchaseInvoiceData invoice,
    required List<PurchaseReturnItem> returnItems,
    String? reason,
  }) async =>
      0.0;
  @override
  Future<double> editPurchaseReturn({
    required PurchaseInvoiceData invoice,
    required List<PurchaseReturnItem> newReturnItems,
  }) async =>
      0.0;
}

const _item = PurchaseItemInput(
  productId: 1,
  productName: 'Widget',
  quantity: 5,
  unitCost: 20,
  salePrice: 30,
  taxRate: 0,
  taxAmount: 0,
);

void main() {
  late _MockPurchasesRepository mock;
  late SavePurchaseUseCase useCase;

  setUp(() {
    mock = _MockPurchasesRepository();
    useCase = SavePurchaseUseCase(mock);
  });

  // ── Validation ─────────────────────────────────────────────────────────────
  group('Validation', () {
    test('fails when items list is empty', () async {
      const req = PurchaseRequest(supplierId: 1, items: [], paidAmount: 0);
      final result = await useCase.execute(req);
      expect(result.isFailure, isTrue);
      expect(result.errorMessage, 'لا توجد منتجات في الفاتورة');
    });

    test('fails when supplierId is zero', () async {
      const req =
          PurchaseRequest(supplierId: 0, items: [_item], paidAmount: 100);
      final result = await useCase.execute(req);
      expect(result.isFailure, isTrue);
      expect(result.errorMessage, 'يرجى اختيار مورد');
    });

    test('fails when supplierId is negative', () async {
      const req =
          PurchaseRequest(supplierId: -3, items: [_item], paidAmount: 100);
      final result = await useCase.execute(req);
      expect(result.isFailure, isTrue);
      expect(result.errorMessage, 'يرجى اختيار مورد');
    });

    test('fails when item quantity is zero', () async {
      const req = PurchaseRequest(
        supplierId: 1,
        items: [
          PurchaseItemInput(
            productId: 1,
            productName: 'X',
            quantity: 0,
            unitCost: 10,
            salePrice: 15,
            taxRate: 0,
            taxAmount: 0,
          )
        ],
        paidAmount: 0,
      );
      final result = await useCase.execute(req);
      expect(result.isFailure, isTrue);
      expect(result.errorMessage, 'الكمية يجب أن تكون أكبر من صفر');
    });

    test('fails when item quantity is negative', () async {
      const req = PurchaseRequest(
        supplierId: 1,
        items: [
          PurchaseItemInput(
            productId: 1,
            productName: 'X',
            quantity: -2,
            unitCost: 10,
            salePrice: 15,
            taxRate: 0,
            taxAmount: 0,
          )
        ],
        paidAmount: 0,
      );
      final result = await useCase.execute(req);
      expect(result.isFailure, isTrue);
    });

    test('fails when unit cost is negative', () async {
      const req = PurchaseRequest(
        supplierId: 1,
        items: [
          PurchaseItemInput(
            productId: 1,
            productName: 'X',
            quantity: 5,
            unitCost: -1,
            salePrice: 15,
            taxRate: 0,
            taxAmount: 0,
          )
        ],
        paidAmount: 0,
      );
      final result = await useCase.execute(req);
      expect(result.isFailure, isTrue);
      expect(result.errorMessage, 'سعر التكلفة لا يمكن أن يكون سالباً');
    });
  });

  // ── Create mode ────────────────────────────────────────────────────────────
  group('Create mode', () {
    test('creates invoice and returns success with correct id', () async {
      mock.nextId = 77;
      const req =
          PurchaseRequest(supplierId: 1, items: [_item], paidAmount: 100);
      final result = await useCase.execute(req);
      expect(result.isSuccess, isTrue);
      expect(result.invoiceId, 77);
    });

    test('calculates totals: subtotal = qty * cost, total = subtotal + tax',
        () async {
      const req = PurchaseRequest(
        supplierId: 1,
        items: [
          PurchaseItemInput(
            productId: 1,
            productName: 'A',
            quantity: 4,
            unitCost: 25,
            salePrice: 40,
            taxRate: 10,
            taxAmount: 10,
          ),
          PurchaseItemInput(
            productId: 2,
            productName: 'B',
            quantity: 2,
            unitCost: 50,
            salePrice: 70,
            taxRate: 0,
            taxAmount: 0,
          ),
        ],
        paidAmount: 210,
      );
      final result = await useCase.execute(req);
      expect(result.isSuccess, isTrue);
      final success = result as PurchaseSuccess;
      expect(success.totals.subtotal, closeTo(200, 0.001)); // 4*25+2*50
      expect(success.totals.tax, closeTo(10, 0.001));
      expect(success.totals.total, closeTo(210, 0.001));
      expect(success.totals.itemCount, 2);
    });

    test('returns failure when repository throws', () async {
      mock.shouldFail = true;
      const req =
          PurchaseRequest(supplierId: 1, items: [_item], paidAmount: 100);
      final result = await useCase.execute(req);
      expect(result.isFailure, isTrue);
      expect(result.errorMessage, contains('فشل في حفظ فاتورة الشراء'));
    });
  });

  // ── Edit mode ──────────────────────────────────────────────────────────────
  group('Edit mode (isEditMode = true)', () {
    test('calls updateInvoice instead of createInvoice', () async {
      const req = PurchaseRequest(
        invoiceId: 10,
        isEditMode: true,
        supplierId: 1,
        items: [_item],
        paidAmount: 100,
      );
      final result = await useCase.execute(req);
      expect(result.isSuccess, isTrue);
      expect(mock.updateCalled, isTrue);
      expect(result.invoiceId, 10); // returns the existing invoiceId
    });

    test('returns failure when updateInvoice throws', () async {
      mock.shouldFail = true;
      const req = PurchaseRequest(
        invoiceId: 10,
        isEditMode: true,
        supplierId: 1,
        items: [_item],
        paidAmount: 100,
      );
      final result = await useCase.execute(req);
      expect(result.isFailure, isTrue);
    });
  });

  // ── Data classes ───────────────────────────────────────────────────────────
  group('PurchaseItemInput', () {
    test('total = (qty * cost) + taxAmount', () {
      const item = PurchaseItemInput(
        productId: 1,
        productName: 'X',
        quantity: 3,
        unitCost: 10,
        salePrice: 15,
        taxRate: 5,
        taxAmount: 1.5,
      );
      expect(item.total, closeTo(31.5, 0.001)); // 3*10 + 1.5
    });

    test('default quantityInBase is 1.0', () {
      const item = PurchaseItemInput(
        productId: 1,
        productName: 'X',
        quantity: 1,
        unitCost: 10,
        salePrice: 15,
        taxRate: 0,
        taxAmount: 0,
      );
      expect(item.quantityInBase, 1.0);
    });
  });

  group('PurchaseResult sealed class', () {
    test('isSuccess / isFailure flags are mutually exclusive', () {
      final s = PurchaseResult.success(
        invoiceId: 5,
        totals: const PurchaseTotals(subtotal: 0, tax: 0, total: 0, itemCount: 0),
      );
      final f = PurchaseResult.failure('oops');
      expect(s.isSuccess, isTrue);
      expect(s.isFailure, isFalse);
      expect(f.isSuccess, isFalse);
      expect(f.isFailure, isTrue);
    });

    test('invoiceId accessible on success, null on failure', () {
      final s = PurchaseResult.success(
        invoiceId: 42,
        totals: const PurchaseTotals(subtotal: 0, tax: 0, total: 0, itemCount: 0),
      );
      final f = PurchaseResult.failure('err');
      expect(s.invoiceId, 42);
      expect(f.invoiceId, isNull);
    });

    test('errorMessage accessible on failure, null on success', () {
      final s = PurchaseResult.success(
        invoiceId: 1,
        totals: const PurchaseTotals(subtotal: 0, tax: 0, total: 0, itemCount: 0),
      );
      final f = PurchaseResult.failure('bad thing');
      expect(s.errorMessage, isNull);
      expect(f.errorMessage, 'bad thing');
    });
  });

  group('ValidationResult', () {
    test('valid() — isValid=true, error=null', () {
      const r = ValidationResult.valid();
      expect(r.isValid, isTrue);
      expect(r.error, isNull);
    });

    test('invalid() — isValid=false, error set', () {
      const r = ValidationResult.invalid('something went wrong');
      expect(r.isValid, isFalse);
      expect(r.error, 'something went wrong');
    });
  });
}
