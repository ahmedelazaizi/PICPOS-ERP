import 'database.dart' as db;
export 'database.dart' hide AppDatabase;

// Web stub for database - actual operations should go through Supabase
// This file providing the same interface as AppDatabase to satisfy the compiler

class AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // STREAMS & QUERIES
  // ═══════════════════════════════════════════════════════════════════════
  Stream<List<db.Product>> watchAllProducts() => Stream.value([]);
  Stream<List<db.Product>> searchProducts(String query) => Stream.value([]);
  Stream<List<db.Category>> watchAllCategories() => Stream.value([]);
  Stream<List<db.Product>> watchLowStockProducts() => Stream.value([]);
  Stream<List<db.Safe>> watchSafes() => Stream.value([]); // Return Stream
  Stream<List<db.Party>> watchCustomers() => Stream.value([]);
  Stream<List<db.Party>> watchSuppliers() => Stream.value([]);
  Stream<List<db.SalesInvoiceData>> watchTodaySales() => Stream.value([]);
  Future<List<db.SalesInvoiceData>> getTodaySales() async => [];
  Stream<List<db.SalesInvoiceData>> watchTodaySalesForUser(int userId) =>
      Stream.value([]);
  Stream<List<db.SalesInvoiceData>> watchSalesSince(DateTime from,
          {int? userId, List<int>? warehouseIds}) =>
      Stream.value([]);
  Future<List<db.SalesInvoiceData>> getTodaySalesForUser(int userId) async =>
      [];
  Stream<List<db.PurchaseInvoiceData>> watchPurchaseInvoices() =>
      Stream.value([]);
  Stream<List<db.PurchaseInvoiceWithSupplier>> watchPurchasesWithSupplier() =>
      Stream.value([]);
  Stream<List<db.StockMovement>> watchProductMovements(int productId) =>
      Stream.value([]);
  Stream<List<db.Safe>> watchAllSafes() => Stream.value([]);
  Stream<List<db.SafeTransactionData>> watchRecentTransactions() =>
      Stream.value([]);
  Future<List<db.ProductBatch>> getExpiredBatches() async => [];
  Future<List<db.ProductBatch>> getExpiringBatches(int days) async => [];
  Stream<List<db.StockMovement>> watchRecentStockMovements() =>
      Stream.value([]);
  Stream<List<db.UserWithRole>> watchAllUsers() => Stream.value([]);
  Stream<List<db.Role>> watchRoles() => Stream.value([]);
  Stream<List<db.Printer>> watchPrinters() => Stream.value([]);
  Stream<List<db.TableSection>> watchAllSections() => Stream.value([]);
  Stream<List<db.RestaurantTable>> watchTablesBySection(int sectionId) =>
      Stream.value([]);
  Stream<db.TableOrder?> watchActiveOrderForTable(int tableId) =>
      Stream.value(null);
  Stream<List<db.Offer>> watchActiveOffers() => Stream.value([]);
  Stream<List<db.HeldOrder>> watchHeldOrders() => Stream.value([]);

  // ═══════════════════════════════════════════════════════════════════════
  // DRIFT-LIKE SELECT STUBS
  // ═══════════════════════════════════════════════════════════════════════
  DriftStub get parties => DriftStub();
  DriftStub get products => DriftStub();
  DriftStub get safes => DriftStub();
  DriftStub get salesInvoices => DriftStub();
  DriftStub get purchaseInvoices => DriftStub();
  DriftStub get categories => DriftStub();
  DriftStub get warehouse => DriftStub();
  DriftStub get users => DriftStub();
  DriftStub get stockMovements => DriftStub();
  DriftStub get safeTransactions => DriftStub();
  DriftStub get tableSections => DriftStub();
  DriftStub get restaurantTables => DriftStub();
  DriftStub get tableOrders => DriftStub();
  DriftStub get tableOrderItems => DriftStub();
  DriftStub get offers => DriftStub();
  DriftStub get offerItems => DriftStub();
  DriftStub get productBarcodes => DriftStub();
  DriftStub get units => DriftStub();
  DriftStub get productUnits => DriftStub();
  DriftStub get productBatches => DriftStub();
  DriftStub get deliveryCompanies => DriftStub();
  DriftStub get couriers => DriftStub();
  DriftStub get roles => DriftStub();
  DriftStub get printers => DriftStub();
  DriftStub get heldOrders => DriftStub();
  DriftStub get heldOrderItems => DriftStub();

  DriftStub select(dynamic table) => DriftStub();
  dynamic into(dynamic table) => DriftStub();
  dynamic update(dynamic table) => DriftStub();
  dynamic delete(dynamic table) => DriftStub();
  Future<List<db.Product>> getLowStockProducts() async => [];
  Future<void> close() async {}

  // ═══════════════════════════════════════════════════════════════════════
  // CORE OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════
  Future<db.Product?> getProductById(int id) async => null;
  Future<Map<int, db.Product>> getProductsByIds(List<int> ids) async => const {};
  Future<db.Product?> getProductByCode(String code) async {
    return null;
  }

  Future<List<db.Party>> getPartiesWithBalance({bool? isCustomer}) async => [];
  Future<bool> updateParty(db.Party party) async => true;
  Future<void> updateProductStock(int productId, double newStock) async {}
  Future<int> createStockMovement(db.StockMovementsCompanion movement) async =>
      0;
  Future<int> insertProduct(db.ProductsCompanion companion) async => 0;
  Future<bool> updateProduct(db.Product product) async => true;
  Future<void> deleteProduct(int id) async {}
  Future<void> adjustStock({
    required int productId,
    int? warehouseId,
    required double quantity,
    String? type,
    String? notes,
  }) async {}
  Future<Map<int, DateTime>> getProductExpiryMap() async => {};

  // Treasury
  Future<void> updateSafeBalance(int safeId, double newBalance) async {}
  Future<int> createSafeTransaction(
    db.SafeTransactionsCompanion transaction,
  ) async => 0;
  Future<db.Safe?> getDefaultSafeByType(String type) async => null;
  Future<int> createReceiptVoucher({
    required double amount,
    required String category,
    int? partyId,
    String? description,
    int? safeId,
  }) async => 0;
  Future<int> createPaymentVoucher({
    required double amount,
    required String category,
    int? partyId,
    String? description,
    int? safeId,
  }) async => 0;
  Future<void> closeSafe(int safeId) async {}
  Future<double> getTotalCashBalance() async => 0;

  // Invoice Operations
  Future<int> createSalesInvoice({
    String? invoiceNumber,
    int? customerId,
    required int warehouseId,
    required int userId,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    required String paymentMethod,
    bool isBooking = false,
    String? deliveryStatus,
    double deliveryFee = 0,
    int? deliveryCompanyId,
    int? courierId,
    String? notes,
    String? adhocCustomerName,
    String? adhocCustomerPhone,
    String? adhocCustomerNote,
    required List<db.SalesInvoiceItemsCompanion> items,
    double? cashAmount,
    double? bankAmount,
  }) async => 0;

  Future<void> updateSalesInvoice({
    required int invoiceId,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    required String paymentMethod,
    String? notes,
    required List<db.SalesInvoiceItemsCompanion> items,
  }) async {}

  Future<void> updateSalesInvoiceStatus(int invoiceId, String status) async {}
  Future<void> updatePurchaseInvoiceStatus(int invoiceId, String status) async {}

  Future<int> createPurchaseInvoice({
    required int supplierId,
    required int warehouseId,
    required List<db.PurchaseInvoiceItemsCompanion> items,
    required double paid,
    String paymentMethod = 'cash',
    String? notes,
    DateTime? invoiceDate,
  }) async => 0;

  Future<void> updatePurchaseInvoice({
    required int invoiceId,
    required int supplierId,
    required List<db.PurchaseInvoiceItemsCompanion> items,
    required double paid,
    String paymentMethod = 'cash',
    String? notes,
  }) async {}

  Future<void> addPurchasePayment({
    required int invoiceId,
    required double amount,
  }) async {}
  Future<void> deletePurchaseInvoice(int invoiceId) async {}
  Future<List<db.PurchaseInvoiceItem>> getPurchaseInvoiceItems(
    int invoiceId,
  ) async => [];
  Future<List<db.PurchaseInvoiceItemWithProduct>>
  getPurchaseInvoiceItemsWithProduct(int invoiceId) async => [];

  // Restaurant & Tables
  Future<void> createSection(String name) async {}
  Future<void> createTable({
    required String name,
    int? sectionId,
    int capacity = 4,
  }) async {}
  Future<void> updateTableStatus(int tableId, String status) async {}
  Future<db.TableOrder?> getActiveOrderForTable(int tableId) async => null;
  Future<int> createTableOrder(int tableId,
          {int? userId, double taxRate = 0}) async =>
      0;
  Future<void> addOrUpdateTableOrderItem({
    required int orderId,
    required int productId,
    required double quantity,
    required double unitPrice,
    double taxRate = 0,
  }) async {}
  Future<List<db.TableOrderItem>> getTableOrderItems(int orderId) async => [];
  Future<void> removeTableOrderItem(int orderId, int productId) async {}
  Future<void> clearTableOrderItems(int orderId) async {}
  Future<void> closeTableOrder(int orderId) async {}
  Future<void> requestTableBill(int orderId, int tableId) async {}
  Future<void> updateTableInfo(
    int tableId, {
    required String name,
    int capacity = 4,
    int? sectionId,
  }) async {}
  Future<void> deleteTable(int tableId) async {}
  Future<void> transferTableOrder(int orderId, int targetTableId) async {}

  // User & RBAC
  Future<db.UserWithRole?> authenticateUser(
    String username,
    String password,
  ) async => null;
  Future<db.UserWithRole?> authenticateByCardCode(String cardCode) async =>
      null;
  Future<db.UserWithRole?> authenticateByPasswordOrCard(String input) async =>
      null;
  Future<db.UserWithRole?> getUserByUsername(String username) async => null;
  Future<db.UserWithRole?> getUserById(int id) async => null;
  Future<int> createUser({
    required String displayName,
    required String username,
    required String password,
    int? roleId,
  }) async => 0;
  Future<void> updateUserInfo({
    required int userId,
    required String displayName,
    int? roleId,
  }) async {}
  Future<void> updateUserPassword({
    required int userId,
    required String newPassword,
  }) async {}
  Future<void> toggleUserActive({
    required int userId,
    required bool isActive,
  }) async {}
  Future<void> assignRoleToUser(int userId, int roleId) async {}
  Future<void> setUserLocked(int userId, bool isLocked) async {}
  Future<void> updateUserPin(int userId, String? pin) async {}
  Future<List<String>> getUserPermissionCodes(int userId) async => [];
  Future<bool> userHasPermission(int userId, String permissionCode) async =>
      false;
  Future<db.Role?> getRoleById(int roleId) async => null;

  // Held Orders
  Future<int> createHeldOrder({
    required String holdNumber,
    required double subtotal,
    required double discount,
    required bool discountIsPercent,
    String? note,
    int? customerId,
    required List<Map<String, dynamic>> items,
  }) async => 0;
  Future<Map<String, dynamic>?> getHeldOrderWithItems(int orderId) async =>
      null;
  Future<void> deleteHeldOrder(int orderId) async {}

  // Category & Printers
  Future<bool> updateCategory(db.Category category) async => true;
  Future<int> insertCategoryWithPrinter({
    required String name,
    String? description,
    String color = '#2563EB',
    int? parentId,
    int sortOrder = 0,
    int? printerId,
    String? iconName,
  }) async => 0;
  Future<bool> updateCategoryWithPrinter({
    required int id,
    required String name,
    String? description,
    String color = '#2563EB',
    int? parentId,
    int sortOrder = 0,
    int? printerId,
    String? iconName,
    bool isActive = true,
  }) async => true;
  Future<void> deleteCategory(int id) async {}
  Future<bool> updatePrinter({
    required int id,
    required String name,
    String? port,
    String? ipAddress,
    int? portNumber,
    String printerType = 'thermal',
    String purpose = 'pos_receipt',
    String? description,
    bool isActive = true,
  }) async => true;
  Future<int> insertPrinter({
    required String name,
    String? port,
    String? ipAddress,
    int? portNumber,
    String printerType = 'thermal',
    String purpose = 'pos_receipt',
    String? description,
  }) async => 0;
  Future<void> deletePrinter(int id) async {}
  Future<List<db.OfferItem>> getOfferItems(int offerId) async => [];

  // ═══════════════════════════════════════════════════════════════════════
  // ANALYTICS & REPORTS
  // ═══════════════════════════════════════════════════════════════════════
  Future<List<db.SalesInvoiceData>> getSalesForDateRange(
    DateTime start,
    DateTime end,
  ) async => [];
  Future<List<db.PurchaseInvoiceData>> getPurchaseInvoicesByDateRange(
    DateTime start,
    DateTime end,
  ) async => [];
  Future<List<db.SafeTransactionData>> getTransactionsByDateRange(
    DateTime start,
    DateTime end, {
    int? userId,
  }) async => [];
  Future<db.TreasuryAnalytics> getTreasuryReportAnalytics(
    DateTime start,
    DateTime end,
  ) async => db.TreasuryAnalytics(
    cashBalance: 0,
    bankBalance: 0,
    totalBalance: 0,
    periodIncome: 0,
    periodExpense: 0,
    netFlow: 0,
    openingBalance: 0,
    totalIn: 0,
    totalOut: 0,
    closingBalance: 0,
    totalReceipts: 0,
    totalPayments: 0,
  );
  Future<db.InventoryAnalytics> getInventoryReportAnalytics() async =>
      db.InventoryAnalytics(
        totalCostValue: 0,
        totalSaleValue: 0,
        potentialProfit: 0,
        uniqueProducts: 0,
        lowStockCount: 0,
        outOfStockCount: 0,
        itemsCount: 0,
      );
  Future<db.SalesAnalytics> getSalesAnalytics(
    DateTime start,
    DateTime end, {
    int? userId,
    int? costCenterId,
    List<int>? warehouseIds,
    String? paymentMethod,
    String? saleType,
    Set<int>? allowedBranchIds,
  }) async => db.SalesAnalytics(
    totalSales: 0,
    totalGrossProfit: 0,
    totalNetProfit: 0,
    totalProfit: 0,
    salesCount: 0,
    invoiceCount: 0,
    averageSaleValue: 0,
    averageInvoiceValue: 0,
    totalDiscount: 0,
    totalTax: 0,
  );
  Future<db.PurchasesAnalytics> getPurchasesReportAnalytics(
    DateTime start,
    DateTime end, {
    Set<int>? allowedBranchIds,
  }) async => db.PurchasesAnalytics(
    totalPurchases: 0,
    totalOutstanding: 0,
    invoiceCount: 0,
    averagePurchaseValue: 0,
  );

  // Missing methods from build logs
  Future<List<db.SalesInvoiceData>> getSalesByDateRange(
    DateTime startDate,
    DateTime endDate, {
    int? userId,
  }) async => [];
  Future<List<db.SalesInvoiceData>> getSalesReturns(
    DateTime startDate,
    DateTime endDate,
  ) async => [];
  Future<List<db.SalesReturnHistoryEntry>> getSalesReturnHistoryEntries(
    DateTime startDate,
    DateTime endDate, {
    int limit = 500,
    Set<int>? allowedBranchIds,
  }) async => [];
  Future<List<db.SalesInvoiceItem>> getSalesInvoiceItems(int invoiceId) async =>
      [];
  Future<List<db.PurchaseInvoiceWithSupplier>>
  getPurchasesWithSupplierByDateRange(DateTime start, DateTime end) async => [];
  Future<List<db.Product>> getAllProducts() async => [];
  Future<int> insertParty(db.PartiesCompanion companion) async => 0;
  Future<List<db.ProductBarcode>> getProductBarcodes(int productId) async => [];

  // ═══════════════════════════════════════════════════════════════════════
  // MISCELLANEOUS
  // ═══════════════════════════════════════════════════════════════════════
  Future<db.Party?> getPartyById(int id) async => null;
  Future<db.PartySummary?> getPartySummary(int partyId) async => null;
  Future<List<db.PartyStatementEntry>> getPartyStatement(
    int partyId, {
    DateTime? fromDate,
    DateTime? toDate,
    int? branchId,
  }) async => [];
  Future<db.SalesInvoiceData?> getSalesInvoiceById(int id) async => null;
  Future<db.SalesInvoiceData?> getSalesInvoiceByNumber(String number) async =>
      null;
  Future<db.PurchaseInvoiceData?> getPurchaseInvoiceById(int id) async => null;
  Future<db.PurchaseInvoiceData?> getPurchaseInvoiceByNumber(
    String number,
  ) async => null;
  Future<db.Category?> getCategoryById(int id) async => null;
  Future<String?> getSetting(String key) async => null;
  Future<void> setSetting(String key, String value) async {}
  Future<bool> barcodeExists(String barcode, {int? excludeProductId}) async =>
      false;
  Future<bool> productCodeExists(String code, {int? excludeProductId}) async =>
      false;
  Future<void> insertProductBarcode(
    int productId,
    String barcode, {
    bool isPrimary = false,
  }) async {}
  Future<void> createDefaultProductUnits(
    int productId, {
    double piecePrice = 0,
    double pieceCost = 0,
    String? pieceBarcode,
  }) async {}

  Future<void> transaction(Future<void> Function() action) async {
    await action();
  }
}

class DriftStub {
  DriftStub where(dynamic Function(dynamic) filter) => this;
  DriftStub limit(int limit, {int? offset}) => this;
  DriftStub orderBy(List<dynamic> terms) => this;
  Future<List<T>> get<T>() async => [];
  Future<T?> getSingleOrNull<T>() async => null;
  Future<T> getSingle<T>() async => throw UnimplementedError();
  Stream<List<T>> watch<T>() => Stream.value([]);
  Stream<T?> watchSingleOrNull<T>() => Stream.value(null);
  Stream<T> watchSingle<T>() => Stream.empty();
  Future<int> insert(dynamic companion) async => 0;
  Future<void> write(dynamic companion) async {}
  Future<void> go() async {}
  dynamic join(List<dynamic> joins) => this;
}
