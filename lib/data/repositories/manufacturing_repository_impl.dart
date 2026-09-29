import 'package:drift/drift.dart' show Value;
import '../database/database.dart';
import '../../domain/repositories/manufacturing_repository.dart';

/// Implementation of [ManufacturingRepository] using Drift DAO.
class ManufacturingRepositoryImpl implements ManufacturingRepository {
  final AppDatabase _db;

  ManufacturingRepositoryImpl(this._db);

  // ── Bill of Materials (BOM) ───────────────────────────────────────────

  @override
  Stream<List<BillOfMaterialData>> watchBOMs() => _db.watchBOMs();

  @override
  Future<BillOfMaterialData?> getBOM(int id) => _db.getBOM(id);

  @override
  Future<List<BomComponentData>> getBOMComponents(int bomId) =>
      _db.getBOMComponents(bomId);

  @override
  Future<int> createBOM({
    required int finishedProductId,
    required String bomCode,
    double expectedQuantity = 1,
    String? notes,
    required List<Map<String, dynamic>> components,
    bool autoDepleteOnSale = false,
    String depletionPolicy = 'prefer_finished_stock',
    bool isActive = true,
     double overheadPercent = 0,
     double profitPercent = 0,
     String profitBasis = 'after_overhead',
     double? pieceWeight,
     double? outputQuantityOverride,
     String outputUnit = 'g',
  }) =>
      _db.createBOM(
        finishedProductId: finishedProductId,
        bomCode: bomCode,
        expectedQuantity: expectedQuantity,
        notes: notes,
        components: components,
        autoDepleteOnSale: autoDepleteOnSale,
        depletionPolicy: depletionPolicy,
         overheadPercent: overheadPercent,
         profitPercent: profitPercent,
         profitBasis: profitBasis,
         pieceWeight: pieceWeight,
         outputQuantityOverride: outputQuantityOverride,
         outputUnit: outputUnit,
        isActive: isActive,
      );

  // ── Manufacturing Orders ──────────────────────────────────────────────

  @override
  Stream<List<ManufacturingOrderData>> watchManufacturingOrders({
    String? status,
  }) =>
      _db.watchManufacturingOrders(status: status);

  @override
  Future<int> createManufacturingOrder({
    required int bomId,
    required double orderedQty,
    required int warehouseId,
    required DateTime startDate,
    String? notes,
  }) =>
      _db.createManufacturingOrder(
        bomId: bomId,
        orderedQty: orderedQty,
        warehouseId: warehouseId,
        startDate: startDate,
        notes: notes,
      );

  @override
  Future<void> startProduction(int orderId) => _db.startProduction(orderId);

  @override
  Future<void> completeProduction(int orderId, {double? actualProducedQty}) =>
      _db.completeProduction(orderId, actualProducedQty: actualProducedQty);

  // ── Fixed Assets ──────────────────────────────────────────────────────

  @override
  Stream<List<AssetCategory>> watchAssetCategories() =>
      _db.watchAssetCategories();

  @override
  Future<int> createAssetCategory({
    required String name,
    double defaultUsefulLife = 5,
    String defaultDepreciationMethod = 'straight_line',
    int? accountId,
    int? depreciationAccountId,
  }) =>
      _db.createAssetCategory(
        name: name,
        defaultUsefulLife: defaultUsefulLife,
        defaultDepreciationMethod: defaultDepreciationMethod,
        accountId: accountId,
        depreciationAccountId: depreciationAccountId,
      );

  @override
  Stream<List<FixedAssetData>> watchFixedAssets({String? status}) =>
      _db.watchFixedAssets(status: status);

  @override
  Future<int> createFixedAsset({
    required String code,
    required String name,
    required int categoryId,
    String? location,
    required double purchasePrice,
    required DateTime purchaseDate,
    required double usefulLifeYears,
    double salvageValue = 0,
    String depreciationMethod = 'straight_line',
    String? notes,
  }) =>
      _db.createFixedAsset(
        code: code,
        name: name,
        categoryId: categoryId,
        location: location,
        purchasePrice: purchasePrice,
        purchaseDate: purchaseDate,
        usefulLifeYears: usefulLifeYears,
        salvageValue: salvageValue,
        depreciationMethod: depreciationMethod,
        notes: notes,
      );

  @override
  Future<int> runMonthlyDepreciation(DateTime periodDate) =>
      _db.runMonthlyDepreciation(periodDate);

  @override
  Future<void> disposeAsset(
    int assetId, {
    required double disposalValue,
    required DateTime disposalDate,
  }) =>
      _db.disposeAsset(
        assetId,
        disposalValue: disposalValue,
        disposalDate: disposalDate,
      );

  @override
  Future<List<AssetDepreciationData>> getAssetDepreciationSchedule(
    int assetId,
  ) =>
      _db.getAssetDepreciationSchedule(assetId);

  @override
  Future<Map<String, double>> getAssetsSummary() => _db.getAssetsSummary();

  // ── Stock Reconciliation ──────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>> reconcileStock(
    int warehouseId,
    Map<int, double> actualQuantities,
  ) =>
      _db.reconcileStock(warehouseId, actualQuantities);

  @override
  Future<void> applyStockAdjustment(
    int warehouseId,
    Map<int, double> actualQuantities, {
    String? auditNotes,
  }) =>
      _db.applyStockAdjustment(
        warehouseId,
        actualQuantities,
        auditNotes: auditNotes,
      );

  // ── Operational Expenses ──────────────────────────────────────────────

  @override
  Stream<List<OpExpenseCategoryData>> watchExpenseCategories() =>
      _db.watchExpenseCategories();

  // ── New methods for widget refactoring ───────────────────────────────

  @override
  Future<void> deleteBOM(int bomId) async {
    await (_db.delete(_db.bomComponents)
          ..where((c) => c.bomId.equals(bomId)))
        .go();
    await (_db.delete(_db.billOfMaterials)
          ..where((b) => b.id.equals(bomId)))
        .go();
  }

  @override
  Future<void> updateBOM({
    required int bomId,
    required int finishedProductId,
    required String bomCode,
    double expectedQuantity = 1,
    String? notes,
    required List<Map<String, dynamic>> components,
    bool? autoDepleteOnSale,
    String? depletionPolicy,
    bool? isActive,
     double? overheadPercent,
     double? profitPercent,
     String? profitBasis,
     double? pieceWeight,
     double? outputQuantityOverride,
     String? outputUnit,
  }) =>
      _db.updateBOM(
        bomId: bomId,
        finishedProductId: finishedProductId,
        bomCode: bomCode,
        expectedQuantity: expectedQuantity,
        notes: notes,
        components: components,
        autoDepleteOnSale: autoDepleteOnSale,
        depletionPolicy: depletionPolicy,
         overheadPercent: overheadPercent,
         profitPercent: profitPercent,
         profitBasis: profitBasis,
         pieceWeight: pieceWeight,
         outputQuantityOverride: outputQuantityOverride,
         outputUnit: outputUnit,
        isActive: isActive,
      );

  @override
  Future<void> updateManufacturingOrder({
    required int orderId,
    int? bomId,
    double? orderedQty,
    int? warehouseId,
    String? notes,
  }) =>
      _db.updateManufacturingOrder(
        orderId: orderId,
        bomId: bomId,
        orderedQty: orderedQty,
        warehouseId: warehouseId,
        notes: notes,
      );

  @override
  Future<void> cancelManufacturingOrder(int orderId) =>
      // Spec 146 (S-MFG-GL, US2): delegate to the atomic DAO reversal so an
      // in_progress cancel restores consumed raw + reverses the WIP entry
      // instead of the old status-only write (which left stock deducted and a
      // dangling WIP debit). draft still cancels with no stock/GL effect.
      _db.reverseManufacturingOrder(orderId);

  @override
  Future<void> reverseManufacturingOrder(int orderId) =>
      _db.reverseManufacturingOrder(orderId);

  @override
  Future<void> addMfgOrderCost({
    required int orderId,
    required String costType,
    required String description,
    required double amount,
    int? expenseCategoryId,
    int? expenseId,
  }) =>
      _db.addMfgOrderCost(
        orderId: orderId,
        costType: costType,
        description: description,
        amount: amount,
        expenseCategoryId: expenseCategoryId,
        expenseId: expenseId,
      );

  @override
  Stream<List<MfgOrderCostData>> watchAllMfgOrderCosts() =>
      _db.watchAllMfgOrderCosts();

  @override
  Future<void> updateManufacturingOrderCosts(int orderId, double additionalCosts) async {
    await (_db.update(_db.manufacturingOrders)
          ..where((o) => o.id.equals(orderId)))
        .write(ManufacturingOrdersCompanion(
      additionalCosts: Value(additionalCosts),
    ));
  }

  @override
  Future<void> allocateMonthlyExpenses({required DateTime month}) =>
      _db.allocateMonthlyExpenses(month: month);

  @override
  Future<BomCostPreview> getBomCostPreview(int bomId) =>
      _db.getBomCostPreview(bomId);

  @override
  Future<List<Map<String, dynamic>>> getButcheryTemplates() =>
      _db.getButcheryTemplates();

  @override
  Future<List<Map<String, dynamic>>> getButcheryTemplateLines(int templateId) =>
      _db.getButcheryTemplateLines(templateId);

  @override
  Future<List<Map<String, dynamic>>> getButcheryOrders() =>
      _db.getButcheryOrders();

  @override
  Future<List<Map<String, dynamic>>> getButcheryOrderLines(int orderId) =>
      _db.getButcheryOrderLines(orderId);

  @override
  Future<List<Map<String, dynamic>>> getButcheryYieldReport({
    required DateTime from,
    required DateTime to,
  }) =>
      _db.getButcheryYieldReport(from: from, to: to);

  @override
  Future<int> createButcheryTemplate({
    required int carcassProductId,
    required String name,
    String valuationMethod = 'sales_value',
    double varianceThresholdPercent = 2,
  }) =>
      _db.createButcheryTemplate(
        carcassProductId: carcassProductId,
        name: name,
        valuationMethod: valuationMethod,
        varianceThresholdPercent: varianceThresholdPercent,
      );

  @override
  Future<int> addButcheryTemplateLine({
    required int templateId,
    required int outputProductId,
    required double expectedYieldPercent,
    required bool isByProduct,
    double valuationPrice = 0,
    String unit = 'كجم',
  }) =>
      _db.addButcheryTemplateLine(
        templateId: templateId,
        outputProductId: outputProductId,
        expectedYieldPercent: expectedYieldPercent,
        isByProduct: isByProduct,
        valuationPrice: valuationPrice,
        unit: unit,
      );

  @override
  Future<int> createButcheryOrder({
    required int carcassProductId,
    required int warehouseId,
    required double carcassQuantity,
    required double carcassWeight,
    required double carcassTotalCost,
    required List<Map<String, dynamic>> outputs,
    int? templateId,
    String weightUnit = 'g',
    String? notes,
  }) =>
      _db.createButcheryOrder(
        carcassProductId: carcassProductId,
        warehouseId: warehouseId,
        carcassQuantity: carcassQuantity,
        carcassWeight: carcassWeight,
        carcassTotalCost: carcassTotalCost,
        outputs: outputs,
        templateId: templateId,
        weightUnit: weightUnit,
        notes: notes,
      );

  @override
  Future<Map<String, dynamic>> postButcheryOrder(int orderId) =>
      _db.postButcheryOrder(orderId);

  @override
  Future<void> reverseButcheryOrder(int orderId) =>
      _db.reverseButcheryOrder(orderId);

  @override
  Future<double?> getLastPurchasePrice(int productId) =>
      _db.getLastPurchasePrice(productId);

  @override
  Future<List<OpExpenseCategoryData>> getActiveExpenseCategories() =>
      _db.getActiveExpenseCategories();

  @override
  Future<int> createExpenseCategory({
    required String name,
    String type = 'indirect',
    bool isProductionRelated = true,
    String allocationMethod = 'fixed_monthly',
    double defaultRate = 0,
  }) =>
      _db.createExpenseCategory(
        name: name,
        type: type,
        isProductionRelated: isProductionRelated,
        allocationMethod: allocationMethod,
        defaultRate: defaultRate,
      );

  @override
  Future<bool> updateExpenseCategory(int id, OpExpenseCategoriesCompanion data) =>
      _db.updateExpenseCategory(id, data);

  @override
  Future<bool> updateExpenseStatus(int expenseId, String status) =>
      _db.updateExpenseStatus(expenseId, status);

  @override
  Future<List<Map<String, dynamic>>> getExpensesForReport({
    required DateTime from,
    required DateTime to,
  }) =>
      _db.getExpensesForReport(from: from, to: to);

  @override
  Future<bool> deleteExpenseCategory(int id) =>
      _db.deleteExpenseCategory(id);

  @override
  Future<int> recordExpense({
    required int categoryId,
    required double amount,
    required DateTime expenseDate,
    String period = 'monthly',
    int? manufacturingOrderId,
    String? reference,
    String? notes,
    required int userId,
    int? branchId,
  }) =>
      _db.recordExpense(
        categoryId: categoryId,
        amount: amount,
        expenseDate: expenseDate,
        period: period,
        manufacturingOrderId: manufacturingOrderId,
        reference: reference,
        notes: notes,
        userId: userId,
        branchId: branchId,
      );

  @override
  Future<List<Map<String, dynamic>>> getExpensesReport({
    required DateTime from,
    required DateTime to,
  }) =>
      _db.getExpensesReport(from: from, to: to);

  @override
  Future<int> deleteExpense(int expenseId) =>
      OperationalExpensesDao(_db).deleteExpense(expenseId);
}
