import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/usecases/quotations/create_quotation_usecase.dart';
import 'package:picpos_erp/domain/repositories/i_quotations_repository.dart';
import 'package:picpos_erp/domain/entities/quotation_entity.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:flutter/material.dart';

/// Fake repository for testing usecases without DB
class FakeQuotationsRepository implements IQuotationsRepository {
  int _nextId = 1;
  final List<Map<String, dynamic>> _saved = [];
  String? lastStatus;

  @override
  Future<int> saveQuotation({
    required List<CartItemEntity> items,
    required int? customerId,
    int? warehouseId,
    required int userId,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    String? notes,
  }) async {
    _saved.add({'items': items, 'total': total});
    return _nextId++;
  }

  @override
  Future<void> updateQuotationStatus(int id, String status,
      {int? convertedInvoiceId}) async {
    lastStatus = status;
  }

  @override
  Future<List<QuotationEntity>> getQuotationsPaginated({
    int limit = 50,
    int offset = 0,
    String? searchQuery,
    DateTimeRange? dateRange,
    String? status,
  }) async => [];

  @override
  Future<QuotationEntity?> getQuotationWithDetails(int id) async => null;

  @override
  Future<void> deleteQuotation(int id) async {}

  @override
  Future<void> deleteQuotationAndItems(int id) async {}

  @override
  Future<void> updateFullQuotation({
    required int id,
    required List<CartItemEntity> items,
    required int? customerId,
    required int userId,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    String? notes,
    required String status,
  }) async {}
}

/// Helper to create a valid CartItemEntity for test
CartItemEntity _item({
  int productId = 1,
  String productName = 'Test Product',
  String productCode = 'TST-001',
  double quantity = 1,
  double unitPrice = 50.0,
}) =>
    CartItemEntity(
      productId: productId,
      productName: productName,
      productCode: productCode,
      quantity: quantity,
      unitPrice: unitPrice,
    );

void main() {
  late FakeQuotationsRepository fakeRepo;
  late CreateQuotationUseCase createUseCase;
  late ConvertQuotationUseCase convertUseCase;

  setUp(() {
    fakeRepo = FakeQuotationsRepository();
    createUseCase = CreateQuotationUseCase(fakeRepo);
    convertUseCase = ConvertQuotationUseCase(fakeRepo);
  });

  group('CreateQuotationUseCase', () {
    test('succeeds with valid data', () async {
      final id = await createUseCase.execute(
        items: [_item(quantity: 2, unitPrice: 50.0)],
        customerId: 1,
        userId: 1,
        subtotal: 100.0,
        discount: 0.0,
        tax: 0.0,
        total: 100.0,
      );
      expect(id, 1);
    });

    test('fails with empty items', () async {
      expect(
        () => createUseCase.execute(
          items: [],
          customerId: 1,
          userId: 1,
          subtotal: 0.0,
          discount: 0.0,
          tax: 0.0,
          total: 100.0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fails with zero total', () async {
      expect(
        () => createUseCase.execute(
          items: [_item(unitPrice: 0.0)],
          customerId: null,
          userId: 1,
          subtotal: 0.0,
          discount: 0.0,
          tax: 0.0,
          total: 0.0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fails with invalid userId', () async {
      expect(
        () => createUseCase.execute(
          items: [_item()],
          customerId: null,
          userId: 0,
          subtotal: 10.0,
          discount: 0.0,
          tax: 0.0,
          total: 10.0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('allows null customerId', () async {
      final id = await createUseCase.execute(
        items: [_item(unitPrice: 25.0)],
        customerId: null,
        userId: 1,
        subtotal: 25.0,
        discount: 0.0,
        tax: 0.0,
        total: 25.0,
      );
      expect(id, isPositive);
    });
  });

  group('ConvertQuotationUseCase', () {
    test('succeeds with valid IDs', () async {
      await convertUseCase.execute(1, 10);
      expect(fakeRepo.lastStatus, 'converted');
    });

    test('fails with invalid quotation ID', () async {
      expect(
        () => convertUseCase.execute(0, 10),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fails with invalid invoice ID', () async {
      expect(
        () => convertUseCase.execute(1, -1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
