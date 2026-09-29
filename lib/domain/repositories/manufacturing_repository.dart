import 'package:ural_erp/data/database/database.dart';

/// Repository interface for Manufacturing & Fixed Assets operations.
///
/// Abstracts the `ManufacturingAssetsDao` extension to follow Clean Architecture.
/// Covers: BOMs, Manufacturing Orders, Fixed Assets, Depreciation,
/// Stock Reconciliation, and Operational Expenses.
abstract class ManufacturingRepository {
  // ── Bill of Materials (BOM) ───────────────────────────────────────────

  /// Watch all BOMs.
  Stream<List<BillOfMaterialData>> watchBOMs();

  /// Get BOM by ID.
  Future<BillOfMaterialData?> getBOM(int id);

  /// Get BOM components.
  Future<List<BomComponentData>> getBOMComponents(int bomId);

  /// Create a BOM with components.
  Future<int> createBOM({
    required int finishedProductId,
    required String bomCode,
    double expectedQuantity = 1,
    String? notes,
    required List<Map<String, dynamic>> components,
    // Feature 009 — optional auto-deplete flags. Default `isActive = true`
    // matches the table default. The DAO enforces FR-004 (autoDepleteOnSale
    // requires isActive).
    bool autoDepleteOnSale = false,
    String depletionPolicy = 'prefer_finished_stock',
    bool isActive = true,
     double overheadPercent = 0,
     double profitPercent = 0,
     String profitBasis = 'after_overhead',
     double? pieceWeight,
     double? outputQuantityOverride,
     String outputUnit = 'g',
  });

  /// Delete a BOM and its components.
  Future<void> deleteBOM(int bomId);

  /// Update an existing BOM and its components.
  Future<void> updateBOM({
    required int bomId,
    required int finishedProductId,
    required String bomCode,
    double expectedQuantity = 1,
    String? notes,
    required List<Map<String, dynamic>> components,
    // Feature 009 — `null` means "leave unchanged" so legacy callers
    // (existing BOM-form widgets) preserve their behavior.
    bool? autoDepleteOnSale,
    String? depletionPolicy,
    bool? isActive,
     double? overheadPercent,
     double? profitPercent,
     String? profitBasis,
     double? pieceWeight,
     double? outputQuantityOverride,
     String? outputUnit,
  });

  /// Update a draft manufacturing order.
  Future<void> updateManufacturingOrder({
    required int orderId,
    int? bomId,
    double? orderedQty,
    int? warehouseId,
    String? notes,
  });

  // ── Manufacturing Orders ──────────────────────────────────────────────

  /// Watch manufacturing orders, optionally filtered by status.
  Stream<List<ManufacturingOrderData>> watchManufacturingOrders({String? status});

  /// Create a manufacturing order.
  Future<int> createManufacturingOrder({
    required int bomId,
    required double orderedQty,
    required int warehouseId,
    required DateTime startDate,
    String? notes,
  });

  /// Start production: deduct raw materials from inventory.
  Future<void> startProduction(int orderId);

  /// Complete production: add finished product to inventory.
  Future<void> completeProduction(int orderId, {double? actualProducedQty});

  /// Cancel a manufacturing order.
  Future<void> cancelManufacturingOrder(int orderId);

  /// Reverse a posted or in-progress manufacturing order.
  Future<void> reverseManufacturingOrder(int orderId);

  /// Add a cost entry to a manufacturing order.
  ///
  /// ⚠️ **و[expenseId] ليس زينة**: بدونه يصير سطرُ التكلفة يتيماً — يُعرَف
  /// مبلغُه ولا يُعرَف أيُّ مصروفٍ مُوّل منه، فلا يُقاس «كم بقي غيرَ محمَّل»
  /// ولا يُمنَع تحميلُ المصروف نفسِه مرّتَين.
  Future<void> addMfgOrderCost({
    required int orderId,
    required String costType,
    required String description,
    required double amount,
    int? expenseCategoryId,
    int? expenseId,
  });

  /// Watch **every** order's cost rows at once.
  ///
  /// ⚠️ لجدولٍ يعرض أوامرَ كثيرةً معاً — القراءةُ لأمرٍ واحدٍ تُنتج استعلاماً
  /// لكلّ صفّ (N+1).
  Stream<List<MfgOrderCostData>> watchAllMfgOrderCosts();

  /// Update the additionalCosts total on a manufacturing order.
  Future<void> updateManufacturingOrderCosts(int orderId, double additionalCosts);

  /// Allocate indirect production expenses for a month.
  Future<void> allocateMonthlyExpenses({required DateTime month});

  /// Read cost figures for a BOM.
  Future<BomCostPreview> getBomCostPreview(int bomId);

  /// Read butchery lookup and report rows.
  Future<List<Map<String, dynamic>>> getButcheryTemplates();
  Future<List<Map<String, dynamic>>> getButcheryTemplateLines(int templateId);
  Future<List<Map<String, dynamic>>> getButcheryOrders();
  Future<List<Map<String, dynamic>>> getButcheryOrderLines(int orderId);
  Future<List<Map<String, dynamic>>> getButcheryYieldReport({
    required DateTime from,
    required DateTime to,
  });
  Future<int> createButcheryTemplate({
    required int carcassProductId,
    required String name,
    String valuationMethod = 'sales_value',
    double varianceThresholdPercent = 2,
  });
  Future<int> addButcheryTemplateLine({
    required int templateId,
    required int outputProductId,
    required double expectedYieldPercent,
    required bool isByProduct,
    double valuationPrice = 0,
    String unit = 'كجم',
  });
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
  });
  Future<Map<String, dynamic>> postButcheryOrder(int orderId);
  Future<void> reverseButcheryOrder(int orderId);

  /// Get the last purchase price for a product.
  Future<double?> getLastPurchasePrice(int productId);

  // ── Fixed Assets ──────────────────────────────────────────────────────

  /// Watch all asset categories.
  Stream<List<AssetCategory>> watchAssetCategories();

  /// Create asset category.
  Future<int> createAssetCategory({
    required String name,
    double defaultUsefulLife = 5,
    String defaultDepreciationMethod = 'straight_line',
    int? accountId,
    int? depreciationAccountId,
  });

  /// Watch all fixed assets, optionally filtered by status.
  Stream<List<FixedAssetData>> watchFixedAssets({String? status});

  /// Create a fixed asset with acquisition journal entry.
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
  });

  /// Calculate and post monthly depreciation for all active assets.
  Future<int> runMonthlyDepreciation(DateTime periodDate);

  /// Dispose of an asset (sell or write-off).
  Future<void> disposeAsset(
    int assetId, {
    required double disposalValue,
    required DateTime disposalDate,
  });

  /// Get depreciation schedule for an asset.
  Future<List<AssetDepreciationData>> getAssetDepreciationSchedule(int assetId);

  /// Get asset summary: total value, accumulated depreciation, book value.
  Future<Map<String, double>> getAssetsSummary();

  // ── Stock Reconciliation ──────────────────────────────────────────────

  /// Compare actual vs book quantity.
  Future<Map<String, dynamic>> reconcileStock(
    int warehouseId,
    Map<int, double> actualQuantities,
  );

  /// Apply stock adjustment after audit.
  Future<void> applyStockAdjustment(
    int warehouseId,
    Map<int, double> actualQuantities, {
    String? auditNotes,
  });

  // ── Operational Expenses ──────────────────────────────────────────────

  /// Watch all expense categories.
  Stream<List<OpExpenseCategoryData>> watchExpenseCategories();

  Future<List<OpExpenseCategoryData>> getActiveExpenseCategories();
  Future<int> createExpenseCategory({
    required String name,
    String type = 'indirect',
    bool isProductionRelated = true,
    String allocationMethod = 'fixed_monthly',
    double defaultRate = 0,
  });
  Future<bool> updateExpenseCategory(int id, OpExpenseCategoriesCompanion data);

  /// ينقل المصروفَ في دورته: `draft` ← `approved` ← `paid`.
  ///
  /// ⚠️ **أثرُ مراجعةٍ لا حدثٌ محاسبيّ** — القيدُ يُرحَّل عند التسجيل لا عند
  /// الاعتماد، وترحيلُ ثانٍ هنا يُقيّد المصروفَ مرّتَين. راجع تعليقَ الـDAO.
  Future<bool> updateExpenseStatus(int expenseId, String status);

  /// كلُّ المصروفات في نافذةٍ زمنيّةٍ بفئتها وفرعها وحالتها.
  ///
  /// مفاتيحُ الخريطة كما يعطيها `getExpensesForReport` — راجعه.
  Future<List<Map<String, dynamic>>> getExpensesForReport({
    required DateTime from,
    required DateTime to,
  });
  Future<bool> deleteExpenseCategory(int id);
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
  });
  Future<List<Map<String, dynamic>>> getExpensesReport({
    required DateTime from,
    required DateTime to,
  });
  Future<int> deleteExpense(int expenseId);
}
