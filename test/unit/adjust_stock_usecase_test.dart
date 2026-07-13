import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/usecases/inventory/adjust_stock_usecase.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/entities/stock_requisition_entity.dart';
import 'package:ural_erp/domain/entities/stock_requisition_item_entity.dart';
import 'package:ural_erp/data/database/database.dart' as db;

/// Minimal mock for InventoryRepository — only adjustStock and getProductStock
/// are used by AdjustStockUseCase.
class MockInventoryRepository implements InventoryRepository {
  double currentStock = 100;
  bool shouldFail = false;

  @override
  Future<void> adjustStock({
    required int productId,
    required int warehouseId,
    required double quantity,
    String? type,
    String? notes,
    String? adjustmentEventGid, // Spec 135 BUG-A: match interface signature
  }) async {
    if (shouldFail) throw Exception('Mock failure');
    currentStock += quantity;
  }

  @override
  Future<double> getProductStock(int productId, {int? warehouseId}) async =>
      currentStock;

  @override
  Future<bool> hasOpeningStockMovement({
    required int productId,
    required int warehouseId,
  }) async => false;

  @override
  Future<bool> addAuditItemOnce({
    required int auditId,
    required int productId,
    required double expectedQuantity,
  }) async => false;

  // ── Unused stubs ──────────────────────────────────────────────────────────
  @override
  Stream<List<StockMovementData>> watchProductMovements(int productId) =>
      const Stream.empty();
  @override
  Future<List<StockMovementData>> getMovementsByDateRange(
          DateTime from, DateTime to) async =>
      [];
  @override
  Stream<List<StockMovementData>> watchAllStockMovements({int limit = 100}) =>
      const Stream.empty();
  @override
  Stream<List<WarehouseData>> watchWarehouses() => const Stream.empty();
  @override
  Future<WarehouseData?> getWarehouseById(int id) async => null;
  @override
  Future<WarehouseData?> getDefaultWarehouse() async => null;
  @override
  Future<void> transferStock({
    required int productId,
    required int fromWarehouseId,
    required int toWarehouseId,
    required double quantity,
    String? notes,
  }) async {}
  @override
  Future<List<ProductBatchData>> getProductBatches(int productId) async => [];
  @override
  Future<List<ProductBatchData>> getExpiredBatches() async => [];
  @override
  Future<List<ProductBatchData>> getExpiringBatches(int days) async => [];
  @override
  Future<List<LowStockProductData>> getLowStockProducts() async => [];
  @override
  Future<InventoryValuation> getInventoryValuation({int? warehouseId}) async =>
      const InventoryValuation(totalCostValue: 0, totalSaleValue: 0, potentialProfit: 0, itemCount: 0);
  @override
  Stream<List<db.HeldOrder>> watchHeldOrders() => const Stream.empty();
  @override
  Stream<List<db.StockAudit>> watchOpenAudit() => const Stream.empty();
  @override
  Future<List<db.StockAuditItem>> getAuditItems(int auditId) async => [];

  @override
  Future<bool> hasActiveStockAudit() async => false;

  @override
  Future<int> createStockAudit({int? userId}) async => 0;

  @override
  Future<void> saveAuditItem({
    required int auditId,
    required int productId,
    required double expectedQuantity,
    required double actualQuantity,
  }) async {}

  @override
  Future<void> finalizeAudit(int auditId) async {}

  @override
  Stream<List<StockRequisitionEntity>> watchAllStockRequisitions({DateTime? startDate, DateTime? endDate}) => const Stream.empty();

  @override
  Future<StockRequisitionEntity?> getStockRequisitionById(int id) async => null;

  @override
  Future<List<StockRequisitionItemEntity>> getStockRequisitionItems(int requisitionId) async => [];

  @override
  Future<int> createStockRequisition(StockRequisitionEntity requisition, List<StockRequisitionItemEntity> items) async => 0;

  @override
  Future<void> updateStockRequisitionStatus(int id, String status) async {}

  @override
  Future<void> deleteStockRequisition(int id) async {}

  @override
  Future<List<StockMovementData>> getStockMovementsByReference(String referenceType, int referenceId) async => [];

  @override
  Future<void> deleteStockMovement(int id) async {}

  @override
  Future<double> getProductWarehouseCost(int productId, int warehouseId) async => 0;
}

void main() {
  group('AdjustStockUseCase', () {
    late MockInventoryRepository mockRepository;
    late AdjustStockUseCase useCase;

    setUp(() {
      mockRepository = MockInventoryRepository();
      useCase = AdjustStockUseCase(mockRepository);
    });

    // ═══════════════════════════════════════════════════════════════════════
    // VALIDATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    group('Validation', () {
      test('should fail when product ID is zero', () async {
        const request = StockAdjustmentRequest(
          productId: 0,
          quantity: 10,
          adjustmentType: 'count',
          reason: 'Inventory count',
        );

        final result = await useCase.execute(request);

        expect(result.isFailure, isTrue);
        expect((result as StockAdjustmentFailure).error, 'منتج غير صحيح');
      });

      test('should fail when product ID is negative', () async {
        const request = StockAdjustmentRequest(
          productId: -1,
          quantity: 10,
          adjustmentType: 'count',
          reason: 'Inventory count',
        );

        final result = await useCase.execute(request);

        expect(result.isFailure, isTrue);
        expect((result as StockAdjustmentFailure).error, 'منتج غير صحيح');
      });

      test('should fail when quantity is zero', () async {
        const request = StockAdjustmentRequest(
          productId: 1,
          quantity: 0,
          adjustmentType: 'count',
          reason: 'Inventory count',
        );

        final result = await useCase.execute(request);

        expect(result.isFailure, isTrue);
        expect((result as StockAdjustmentFailure).error, 'كمية التعديل لا يمكن أن تكون صفر');
      });

      test('should fail when reason is empty', () async {
        const request = StockAdjustmentRequest(
          productId: 1,
          quantity: 10,
          adjustmentType: 'count',
          reason: '',
        );

        final result = await useCase.execute(request);

        expect(result.isFailure, isTrue);
        expect((result as StockAdjustmentFailure).error, 'يرجى إدخال سبب التعديل');
      });
    });

    // ═══════════════════════════════════════════════════════════════════════
    // SUCCESS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    group('Success Cases', () {
      test('should adjust stock successfully with positive quantity', () async {
        mockRepository.currentStock = 50;
        const request = StockAdjustmentRequest(
          productId: 1,
          quantity: 50,
          adjustmentType: 'count',
          reason: 'Inventory count adjustment',
        );

        final result = await useCase.execute(request);

        expect(result.isSuccess, isTrue);
        final success = result as StockAdjustmentSuccess;
        expect(success.productId, 1);
        expect(success.adjustment, 50);
      });

      test('should adjust stock successfully with negative quantity', () async {
        mockRepository.currentStock = 100;
        const request = StockAdjustmentRequest(
          productId: 1,
          quantity: -10,
          adjustmentType: 'damage',
          reason: 'Damaged goods removed',
        );

        final result = await useCase.execute(request);

        expect(result.isSuccess, isTrue);
        final success = result as StockAdjustmentSuccess;
        expect(success.adjustment, -10);
      });

      test('should work with batch ID', () async {
        const request = StockAdjustmentRequest(
          productId: 5,
          quantity: 20,
          adjustmentType: 'return',
          reason: 'Customer return',
          batchId: 100,
        );

        final result = await useCase.execute(request);

        expect(result.isSuccess, isTrue);
      });

      test('should use default warehouse ID', () async {
        const request = StockAdjustmentRequest(
          productId: 1,
          quantity: 10,
          adjustmentType: 'transfer',
          reason: 'Transfer from main warehouse',
        );

        expect(request.warehouseId, 1); // Default value

        final result = await useCase.execute(request);
        expect(result.isSuccess, isTrue);
      });
    });

    // ═══════════════════════════════════════════════════════════════════════
    // DATA CLASS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    group('Data Classes', () {
      test('StockAdjustmentRequest should have correct default values', () {
        const request = StockAdjustmentRequest(
          productId: 1,
          quantity: 10,
          adjustmentType: 'count',
          reason: 'Test',
        );

        expect(request.warehouseId, 1);
        expect(request.batchId, isNull);
      });

      test('StockAdjustmentResult.isSuccess should return correct value', () {
        final success = StockAdjustmentResult.success(
          productId: 1,
          newStock: 100,
          adjustment: 10,
        );
        final failure = StockAdjustmentResult.failure('error');

        expect(success.isSuccess, isTrue);
        expect(success.isFailure, isFalse);
        expect(failure.isSuccess, isFalse);
        expect(failure.isFailure, isTrue);
      });

      test('StockAdjustmentSuccess should contain correct values', () {
        final success = StockAdjustmentResult.success(
          productId: 5,
          newStock: 150,
          adjustment: 50,
        );

        final result = success as StockAdjustmentSuccess;
        expect(result.productId, 5);
        expect(result.newStock, 150);
        expect(result.adjustment, 50);
      });

      test('StockAdjustmentFailure should contain error message', () {
        final failure = StockAdjustmentResult.failure('Test error');

        final result = failure as StockAdjustmentFailure;
        expect(result.error, 'Test error');
      });
    });
  });
}
