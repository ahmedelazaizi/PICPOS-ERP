part of '../client_write_interceptor.dart';
class ClientWriteInterceptor implements SyncInterceptor {
  ClientWriteInterceptor._();
  static void setup() => SyncInterceptor.instance = ClientWriteInterceptor._();
  @override
  bool get isClientModeImpl =>
      ServerProxy.isClientMode || WriteRouter.isMirrorActive;
  @override
  bool get isMirrorModeImpl => WriteRouter.isMirrorActive;
  static final _proxy = _CwiCoreSupport.proxy;
  static AppDatabase? get _db => _CwiCoreSupport.database;
  static void initialize(AppDatabase db) => _CwiCoreSupport.initialize(db);
  static Future<T?> _tryOrQueue<T>({
    required String tableName,
    required String operation,
    required Map<String, dynamic> payload,
    required Future<T?> Function(String idempotencyKey) serverCall,
  }) =>
      _CwiCoreSupport.tryOrQueue(
        tableName: tableName,
        operation: operation,
        payload: payload,
        serverCall: serverCall,
      );
  static ExchangeLegCollector? get activeExchangeCollector =>
      _CwiCoreSupport.activeExchangeCollector;
  static Future<T> runWithExchangeCollector<T>(
    ExchangeLegCollector collector,
    Future<T> Function() body,
  ) =>
      _CwiCoreSupport.runWithExchangeCollector(collector, body);
  static Future<void> dispatchWrite(
    Future<Object?> Function() submit, {
    required String tag,
  }) =>
      _CwiCoreSupport.dispatchWrite(submit, tag: tag);
  static Future<bool> _tryOrQueueVoid({
    required String tableName,
    required String operation,
    required Map<String, dynamic> payload,
    required Future<void> Function(String idempotencyKey) serverCall,
  }) =>
      _CwiCoreSupport.tryOrQueueVoid(
        tableName: tableName,
        operation: operation,
        payload: payload,
        serverCall: serverCall,
      );
  static Future<String?> _lookupPartyGlobalId(int? partyId) =>
      _CwiCoreSupport.lookupPartyGlobalId(partyId);
  static Future<String?> _lookupPartyName(int? partyId) =>
      _CwiCoreSupport.lookupPartyName(partyId);
  static Future<void> _enrichItemsWithProductGlobalId(
    Map<String, dynamic> payload, {
    String itemsKey = 'items',
  }) =>
      _CwiCoreSupport.enrichItemsWithProductGlobalId(
        payload,
        itemsKey: itemsKey,
      );
  static Future<int?> createExpense({required double amount, required String category, String? description, int? partyId, int? safeId, int? userId, int? costCenterId, int? branchId, String? globalId, String? paperType}) => _CwiCommerce.createExpense(amount: amount, category: category, description: description, partyId: partyId, safeId: safeId, userId: userId, costCenterId: costCenterId, branchId: branchId, globalId: globalId, paperType: paperType);
  static Future<bool> deleteExpense(int id) => _CwiCommerce.deleteExpense(id);
  static Future<int?> createReceipt({required double amount, required String category, String? description, int? partyId, int? safeId, int? userId, int? branchId, int? costCenterId, int? linkedAccountId, String? globalId, String? paperType}) => _CwiCommerce.createReceipt(amount: amount, category: category, description: description, partyId: partyId, safeId: safeId, userId: userId, branchId: branchId, costCenterId: costCenterId, linkedAccountId: linkedAccountId, globalId: globalId, paperType: paperType);
  static Future<int?> createParty({required String name, String? code, String? phone, String? address, bool isCustomer = true, bool isSupplier = false, bool isDeliveryCompany = false, String? taxId, double creditLimit = 0, int paymentTermsDays = 0, double balance = 0, double fixedDiscount = 0, String priceLevel = 'default', int? groupId, String? globalId, List<int> branchIds = const [], int? costCenterId}) => _CwiCommerce.createParty(name: name, code: code, phone: phone, address: address, isCustomer: isCustomer, isSupplier: isSupplier, isDeliveryCompany: isDeliveryCompany, taxId: taxId, creditLimit: creditLimit, paymentTermsDays: paymentTermsDays, balance: balance, fixedDiscount: fixedDiscount, priceLevel: priceLevel, groupId: groupId, globalId: globalId, branchIds: branchIds, costCenterId: costCenterId);
  static Future<bool> updateParty(int id, Map<String, dynamic> data) => _CwiCommerce.updateParty(id, data);
  static Future<int?> createUnitStatic(UnitsCompanion unit) async => SyncInterceptor.instance?.createUnit(unit);
  static Future<bool> updateUnitStatic(int id, Map<String, dynamic> data) async => SyncInterceptor.instance?.updateUnit(id, data) ?? Future.value(false);
  static Future<bool> deleteUnitStatic(int id) async => SyncInterceptor.instance?.deleteUnit(id) ?? Future.value(false);
  static Future<bool> deleteParty(int id, {String? idempotencyKey}) => _CwiCommerce.deleteParty(id, idempotencyKey: idempotencyKey);
  static Future<int?> createProduct({required String code, required String name, required double salePrice, required double costPrice, int? categoryId, int? supplierId, double currentStock = 0, String? barcode, double minStock = 0, double taxRate = 0, bool taxExempt = false, bool isSoldByWeight = false, bool allowNegativeSale = false, bool trackExpiry = false, int defaultShelfDays = 90, int alertDaysBefore = 30, double? pricePerUnit, double wholesalePrice = 0, double priceTalabat = 0, double priceCareem = 0, double priceAshyae = 0, String? scaleType, int? scalePluNumber, String productType = 'product', int? warehouseId, String? globalId, List<Map<String, dynamic>>? units, List<Map<String, dynamic>>? barcodes}) => _CwiCatalogProducts.createProduct(code: code, name: name, salePrice: salePrice, costPrice: costPrice, categoryId: categoryId, supplierId: supplierId, currentStock: currentStock, barcode: barcode, minStock: minStock, taxRate: taxRate, taxExempt: taxExempt, isSoldByWeight: isSoldByWeight, allowNegativeSale: allowNegativeSale, trackExpiry: trackExpiry, defaultShelfDays: defaultShelfDays, alertDaysBefore: alertDaysBefore, pricePerUnit: pricePerUnit, wholesalePrice: wholesalePrice, priceTalabat: priceTalabat, priceCareem: priceCareem, priceAshyae: priceAshyae, scaleType: scaleType, scalePluNumber: scalePluNumber, productType: productType, warehouseId: warehouseId, globalId: globalId, units: units, barcodes: barcodes);
  static Future<bool> updateProduct(int id, Map<String, dynamic> data) => _CwiCatalogProducts.updateProduct(id, data);
  static Future<int?> createProductUnitStatic(ProductUnitsCompanion unit) async => SyncInterceptor.instance?.createProductUnit(unit);
  static Future<bool> updateProductUnitStatic(int id, Map<String, dynamic> data) async => SyncInterceptor.instance?.updateProductUnit(id, data) ?? Future.value(false);
  static Future<bool> deleteProductUnitStatic(int id) async => SyncInterceptor.instance?.deleteProductUnit(id) ?? Future.value(false);
  static Future<bool> deleteProduct(int id, {String? idempotencyKey}) => _CwiCatalogProducts.deleteProduct(id, idempotencyKey: idempotencyKey);
  static Future<int?> createPurchase({required int supplierId, required List<Map<String, dynamic>> items, double paid = 0, String? notes, String? globalId, int? userId}) => _CwiCatalogOperations.createPurchase(supplierId: supplierId, items: items, paid: paid, notes: notes, globalId: globalId, userId: userId);
  static Future<bool> updatePurchase({required int invoiceId, required int supplierId, required List<Map<String, dynamic>> items, double paid = 0, String? notes, int? warehouseId, int? branchId, int? costCenterId, String? paymentMethod, String? supplierInvoiceNumber, int? userId}) => _CwiCatalogOperations.updatePurchase(invoiceId: invoiceId, supplierId: supplierId, items: items, paid: paid, notes: notes, warehouseId: warehouseId, branchId: branchId, costCenterId: costCenterId, paymentMethod: paymentMethod, supplierInvoiceNumber: supplierInvoiceNumber, userId: userId);
  static Future<bool> deletePurchase(int id) => _CwiCatalogOperations.deletePurchase(id);
  static Future<int?> openShift(int userId, double openingBalance,
          {int? localShiftId, int? branchId, String? globalId}) =>
      _CwiCatalogOperations.openShift(userId, openingBalance,
          localShiftId: localShiftId,
          branchId: branchId,
          globalId: globalId);
  static Future<bool> closeShift({required int userId, required double actualCash, double actualCard = 0}) => _CwiCatalogOperations.closeShift(userId: userId, actualCash: actualCash, actualCard: actualCard);
  static Future<bool> saveSettings(Map<String, String> settings) => _CwiCatalogOperations.saveSettings(settings);
  static Future<int?> createCategory({required String name, required String color, int? printerId, String? iconName, bool isGlobal = true, List<int> branchIds = const []}) => _CwiCatalogOperations.createCategory(name: name, color: color, printerId: printerId, iconName: iconName, isGlobal: isGlobal, branchIds: branchIds);
  static Future<bool> updateCategory({required int id, required String name, required String color, int? printerId, String? iconName, bool isGlobal = true, List<int> branchIds = const []}) => _CwiCatalogOperations.updateCategory(id: id, name: name, color: color, printerId: printerId, iconName: iconName, isGlobal: isGlobal, branchIds: branchIds);
  static Future<bool> deleteCategory(int id, {int? moveToCategoryId}) =>
      _CwiCatalogOperations.deleteCategory(id, moveToCategoryId: moveToCategoryId);
  static Future<bool> updateUser(int userId, Map<String, dynamic> fields) => _CwiCatalogOperations.updateUser(userId, fields);
  static Future<bool> updateUserPassword(int userId, String password) => _CwiCatalogOperations.updateUserPassword(userId, password);
  static Future<bool> resetUserPasswordOnline(int userId, String password) => _CwiCatalogOperations.resetUserPasswordOnline(userId, password);
  static Future<bool> updateUserPin(int userId, String? pin) => _CwiCatalogOperations.updateUserPin(userId, pin);
  static Future<int?> createWarehouse({required String name, int? branchId, String? globalId}) => _CwiCatalogOperations.createWarehouse(name: name, branchId: branchId, globalId: globalId);
  static Future<bool> updateWarehouse(int id, Map<String, dynamic> fields) => _CwiCatalogOperations.updateWarehouse(id, fields);
  static Future<bool> setDefaultWarehouse(int id) => _CwiCatalogOperations.setDefaultWarehouse(id);
  static Future<bool> unsetDefaultWarehouse(int id) => _CwiCatalogOperations.unsetDefaultWarehouse(id);
  static Future<bool> deleteWarehouse(int id) => _CwiCatalogOperations.deleteWarehouse(id);
  static Future<int?> submitSale(Map<String, dynamic> saleData) => _CwiTradingSales.submitSale(saleData);
  static Future<int?> submitHeldOrder(Map<String, dynamic> orderData) => _CwiTradingSales.submitHeldOrder(orderData);
  static Future<bool> deleteHeldOrder(int id) => _CwiTradingSales.deleteHeldOrder(id);
  static Future<int?> submitSalesReturn(Map<String, dynamic> returnData) => _CwiTradingSales.submitSalesReturn(returnData);
  static Future<int?> submitExchange(Map<String, dynamic> exchangeData) => _CwiTradingSales.submitExchange(exchangeData);
  static Future<bool> deleteSalesInvoice(int id) => _CwiTradingSales.deleteSalesInvoice(id);
  static Future<bool> updateSalesInvoice(int id, Map<String, dynamic> data) => _CwiTradingSales.updateSalesInvoice(id, data);
  static Future<bool> submitVoidSalesInvoice({required int salesId, String? salesGlobalId, String? invoiceNumber, String? reason, required String globalId, int? userId}) => _CwiTradingSales.submitVoidSalesInvoice(salesId: salesId, salesGlobalId: salesGlobalId, invoiceNumber: invoiceNumber, reason: reason, globalId: globalId, userId: userId);
  static Future<bool> submitSalesPayment({required int salesId, String? salesGlobalId, String? invoiceNumber, required double amount, required String globalId, int? userId}) => _CwiTradingSales.submitSalesPayment(salesId: salesId, salesGlobalId: salesGlobalId, invoiceNumber: invoiceNumber, amount: amount, globalId: globalId, userId: userId);
  static Future<bool> adjustStock({required int productId, required int warehouseId, required double quantity, String? type, String? notes, String? adjustmentEventGid}) => _CwiTradingInventory.adjustStock(productId: productId, warehouseId: warehouseId, quantity: quantity, type: type, notes: notes, adjustmentEventGid: adjustmentEventGid);
  static Future<int> reconcileOpeningStocks() => _CwiTradingInventory.reconcileOpeningStocks();
  static Future<int?> createCommercialPaper({required String paperNumber, required String type, required String direction, required int partyId, required double amount, required DateTime issueDate, required DateTime dueDate, String? bankName, int? safeId, String? accountNumber, String? notes, String? globalId, int? drawerAccountId, String? drawerName}) => _CwiTradingPapers.createCommercialPaper(paperNumber: paperNumber, type: type, direction: direction, partyId: partyId, amount: amount, issueDate: issueDate, dueDate: dueDate, bankName: bankName, safeId: safeId, accountNumber: accountNumber, notes: notes, globalId: globalId, drawerAccountId: drawerAccountId, drawerName: drawerName);
  static Future<bool> updateCommercialPaperStatus(int id, String status,
          {int? changedBy, String? notes, int? counterAccountId}) =>
      _CwiTradingPapers.updateCommercialPaperStatus(id, status,
          changedBy: changedBy,
          notes: notes,
          counterAccountId: counterAccountId);
  static Future<bool> renewCommercialPaper(int id, DateTime newDueDate, {int? changedBy, String? notes}) => _CwiTradingPapers.renewCommercialPaper(id, newDueDate, changedBy: changedBy, notes: notes);
  static Future<bool> partialCollectPaper(int id, double amount, {int? changedBy, String? notes}) => _CwiTradingPapers.partialCollectPaper(id, amount, changedBy: changedBy, notes: notes);
  static Future<bool> endorseCommercialPaper(int id, int toPartyId, {int? changedBy, String? notes}) => _CwiTradingPapers.endorseCommercialPaper(id, toPartyId, changedBy: changedBy, notes: notes);
  static Future<bool> depositPaperForCollection(int id, int bankSafeId, {int? changedBy, String? notes}) => _CwiTradingPapers.depositPaperForCollection(id, bankSafeId, changedBy: changedBy, notes: notes);
  static Future<bool> reissueCommercialPaper(int id, int newPartyId, {int? changedBy, String? notes}) => _CwiTradingPapers.reissueCommercialPaper(id, newPartyId, changedBy: changedBy, notes: notes);
  static Future<bool> submitSafeTransfer({required int fromSafeId, required int toSafeId, required double amount, int? userId, String? description}) => _CwiTradingPurchases.submitSafeTransfer(fromSafeId: fromSafeId, toSafeId: toSafeId, amount: amount, userId: userId, description: description);
  static Future<bool> submitSetDefaultSafe({required int safeId}) => _CwiTradingPurchases.submitSetDefaultSafe(safeId: safeId);
  static Future<bool> submitStockTransfer({required int fromWarehouseId, required int toWarehouseId, required List<Map<String, dynamic>> items, int? userId, String? notes, String? globalId}) => _CwiTradingPurchases.submitStockTransfer(fromWarehouseId: fromWarehouseId, toWarehouseId: toWarehouseId, items: items, userId: userId, notes: notes, globalId: globalId);
  static Future<bool> submitPurchase({required int supplierId, required int warehouseId, required List<Map<String, dynamic>> items, required double paid, String paymentMethod = 'cash', String? supplierInvoiceNumber, String? notes, int? costCenterId, int? branchId, int? safeId, String? globalId, int? userId, String? createdByUsername, double discount = 0, int? currencyId, double? exchangeRate, ImportDocumentFields? importDetails, int? purchaseAccountId}) => _CwiTradingPurchases.submitPurchase(supplierId: supplierId, warehouseId: warehouseId, items: items, paid: paid, paymentMethod: paymentMethod, supplierInvoiceNumber: supplierInvoiceNumber, notes: notes, costCenterId: costCenterId, branchId: branchId, safeId: safeId, globalId: globalId, userId: userId, createdByUsername: createdByUsername, discount: discount, currencyId: currencyId, exchangeRate: exchangeRate, importDetails: importDetails, purchaseAccountId: purchaseAccountId);
  static Future<bool> submitPurchaseReturn(Map<String, dynamic> returnData) => _CwiTradingPurchases.submitPurchaseReturn(returnData);
  static Future<bool> submitPurchaseReturnEdit(Map<String, dynamic> editData) => _CwiTradingPurchases.submitPurchaseReturnEdit(editData);
  static Future<bool> submitVoidPurchase({required int purchaseId, String? purchaseGlobalId, String? invoiceNumber, String? reason, required String globalId, int? userId}) => _CwiTradingPurchases.submitVoidPurchase(purchaseId: purchaseId, purchaseGlobalId: purchaseGlobalId, invoiceNumber: invoiceNumber, reason: reason, globalId: globalId, userId: userId);
  static Future<bool> submitPurchasePayment({required int purchaseId, String? purchaseGlobalId, String? invoiceNumber, required double amount, required String globalId, int? userId}) => _CwiTradingPurchases.submitPurchasePayment(purchaseId: purchaseId, purchaseGlobalId: purchaseGlobalId, invoiceNumber: invoiceNumber, amount: amount, globalId: globalId, userId: userId);
  static Future<bool> submitInventoryBond(Map<String, dynamic> bondData) => _CwiTradingPurchases.submitInventoryBond(bondData);
  static Future<bool> closeSafe(int safeId, {int? userId, double? cashAmount, double? bankAmount, String? notes, String? closeEventGid}) =>
      _CwiTradingPurchases.closeSafe(safeId, userId: userId, cashAmount: cashAmount, bankAmount: bankAmount, notes: notes, closeEventGid: closeEventGid);
  static Future<void> submitFloorPlan(Map<String, dynamic> document) =>
      _CwiSyncFoundation.submitFloorPlan(document);
  static Future<void> submitTableReservation(Map<String, dynamic> document) =>
      _CwiSyncFoundation.submitTableReservation(document);
  static Future<void> submitAttachment(Map<String, dynamic> document) =>
      _CwiSyncFoundation.submitAttachment(document);
  static Future<void> submitAttachmentDelete(Map<String, dynamic> document) =>
      _CwiSyncFoundation.submitAttachmentDelete(document);
  @override
  Future<void> submitLandedCostApply(Map<String, dynamic> document) =>
      _CwiSyncFoundation.submitLandedCostApply(document);
  @override
  Future<void> submitFixedAssetCreate(Map<String, dynamic> document) =>
      _CwiSyncFoundation.submitFixedAssetCreate(document);
  @override
  Future<void> submitAssetDepreciationRun(Map<String, dynamic> request) =>
      _CwiSyncFoundation.submitAssetDepreciationRun(request);
  @override
  Future<void> submitOperationalExpense(Map<String, dynamic> document) =>
      _CwiSyncFoundation.submitOperationalExpense(document);
  @override
  Future<void> submitManufacturingAction(Map<String, dynamic> request) =>
      _CwiSyncFoundation.submitManufacturingAction(request);
  @override
  Future<void> submitBookingDepositApplication(
          Map<String, dynamic> request) =>
      _CwiSyncFoundation.submitBookingDepositApplication(request);
  @override
  Future<void> submitJournalEntry({required String description, required DateTime date, required List<dynamic> lines, String? referenceType, int? referenceId, bool isAutoPosted = false, int? costCenterId, int? branchId, String? globalId}) => _CwiSyncFoundation.submitJournalEntry(description: description, date: date, lines: lines, referenceType: referenceType, referenceId: referenceId, isAutoPosted: isAutoPosted, costCenterId: costCenterId, branchId: branchId, globalId: globalId);
  @override
  Future<void> submitSafeTransaction({required int safeId, required String transactionType, required double amount, required String category, String? description, int? userId, String? referenceType, int? referenceId, String? globalId, String? safeGlobalId, int? costCenterId, int? partyId, String? partyGlobalId, int? currencyId, double? exchangeRate, double? foreignAmount}) => _CwiSyncFoundation.submitSafeTransaction(safeId: safeId, transactionType: transactionType, amount: amount, category: category, description: description, userId: userId, referenceType: referenceType, referenceId: referenceId, globalId: globalId, safeGlobalId: safeGlobalId, costCenterId: costCenterId, partyId: partyId, partyGlobalId: partyGlobalId, currencyId: currencyId, exchangeRate: exchangeRate, foreignAmount: foreignAmount);
  @override
  Future<int?> createUnit(covariant UnitsCompanion unit) => _CwiSyncCatalog.createUnit(unit);
  @override
  Future<bool> updateUnit(int id, Map<String, dynamic> data) => _CwiSyncCatalog.updateUnit(id, data);
  @override
  Future<bool> deleteUnit(int id) => _CwiSyncCatalog.deleteUnit(id);
  @override
  Future<int?> createProductUnit(covariant ProductUnitsCompanion productUnit) => _CwiSyncCatalog.createProductUnit(productUnit);
  @override
  Future<bool> updateProductUnit(int id, Map<String, dynamic> data) => _CwiSyncCatalog.updateProductUnit(id, data);
  @override
  Future<bool> deleteProductUnit(int id) => _CwiSyncCatalog.deleteProductUnit(id);
  @override
  Future<int?> createProductBarcode(covariant ProductBarcodesCompanion barcode) => _CwiSyncCatalog.createProductBarcode(barcode);
  @override
  Future<bool> deleteProductBarcode(int id) => _CwiSyncCatalog.deleteProductBarcode(id);
  @override
  Future<int?> createUser({required String username, required String password, required String displayName, int? roleId, List<int> branchIds = const [], String? globalId, String? cardCode}) => _CwiSyncCatalog.createUser(username: username, password: password, displayName: displayName, roleId: roleId, branchIds: branchIds, globalId: globalId, cardCode: cardCode);
  @override
  Future<int?> createRole({required String name, String? description, bool isSystemRole = false}) => _CwiSyncCatalog.createRole(name: name, description: description, isSystemRole: isSystemRole);
  @override
  Future<bool> setRolePermissions(int roleId, List<String> permissionCodes, {String? roleGlobalId, String? roleName}) => _CwiSyncCatalog.setRolePermissions(roleId, permissionCodes, roleGlobalId: roleGlobalId, roleName: roleName);
  @override
  Future<int?> createRegion({required String name, String? address, String? phone, int? costCenterId}) => _CwiSyncCatalog.createRegion(name: name, address: address, phone: phone, costCenterId: costCenterId);
  @override
  Future<bool> updateRegion({required int id, required String name, String? address, String? phone, int? costCenterId}) => _CwiSyncCatalog.updateRegion(id: id, name: name, address: address, phone: phone, costCenterId: costCenterId);
  @override
  Future<int?> createPartyGroup(covariant dynamic companion) => _CwiSyncCatalog.createPartyGroup(companion);
  @override
  Future<bool> updatePartyGroup(int id, Map<String, dynamic> data) => _CwiSyncCatalog.updatePartyGroup(id, data);
  @override
  Future<bool> deletePartyGroup(int id) => _CwiSyncCatalog.deletePartyGroup(id);
  @override
  Future<int?> createPurchaseOrder(Map<String, dynamic> data, List<Map<String, dynamic>> items) => _CwiSyncOrders.createPurchaseOrder(data, items);
  @override
  Future<bool> updatePurchaseOrderStatus(int id, String status) => _CwiSyncOrders.updatePurchaseOrderStatus(id, status);
  @override
  Future<bool> deletePurchaseOrder(int id) => _CwiSyncOrders.deletePurchaseOrder(id);
  @override
  Future<int?> createSalesOrder(Map<String, dynamic> data, List<Map<String, dynamic>> items) => _CwiSyncOrders.createSalesOrder(data, items);
  @override
  Future<bool> updateSalesOrderStatus(int id, String status) => _CwiSyncOrders.updateSalesOrderStatus(id, status);
  @override
  Future<bool> deleteSalesOrder(int id) => _CwiSyncOrders.deleteSalesOrder(id);
  @override
  Future<int?> createQuotation(Map<String, dynamic> data, List<Map<String, dynamic>> items) => _CwiSyncOrders.createQuotation(data, items);
  @override
  Future<bool> updateQuotationStatus(int id, String status, {int? convertedInvoiceId}) => _CwiSyncOrders.updateQuotationStatus(id, status, convertedInvoiceId: convertedInvoiceId);
  @override
  Future<bool> updateQuotation(int id, Map<String, dynamic> data, List<Map<String, dynamic>> items) => _CwiSyncOrders.updateQuotation(id, data, items);
  @override
  Future<bool> deleteQuotation(int id) => _CwiSyncOrders.deleteQuotation(id);
  @override
  Future<int?> createPriceList(Map<String, dynamic> data) => _CwiSyncOrders.createPriceList(data);
  @override
  Future<bool> updatePriceList(int id, Map<String, dynamic> data) => _CwiSyncOrders.updatePriceList(id, data);
  @override
  Future<bool> setPriceListItem(Map<String, dynamic> data) => _CwiSyncOrders.setPriceListItem(data);
  @override
  Future<int?> createPrinter(Map<String, dynamic> data) => _CwiSyncOrders.createPrinter(data);
  @override
  Future<bool> updatePrinter(int id, Map<String, dynamic> data) => _CwiSyncOrders.updatePrinter(id, data);
  @override
  Future<bool> deletePrinter(int id) => _CwiSyncOrders.deletePrinter(id);
  static Future<bool> pushActivityLog(Map<String, dynamic> logData) =>
      _CwiSyncOrders.pushActivityLog(logData);
  static Future<int?> createBranch({
    required String name,
    String? code,
    String? address,
    String? phone,
    int? costCenterId,
    int? regionId,
    String? globalId,
  }) =>
      _CwiAdmin.createBranch(
        name: name,
        code: code,
        address: address,
        phone: phone,
        costCenterId: costCenterId,
        regionId: regionId,
        globalId: globalId,
      );
  static Future<bool> updateBranch(int id, Map<String, dynamic> data) =>
      _CwiAdmin.updateBranch(id, data);
  static Future<bool> deleteBranch(int id, {int? reassignUsersToBranchId}) =>
      _CwiAdmin.deleteBranch(id,
          reassignUsersToBranchId: reassignUsersToBranchId);
  static Future<int?> createSafe({
    required String name,
    required String safeType,
    String? bankName,
    String? accountNumber,
    int? costCenterId,
    int? branchId,
    String? globalId,
  }) =>
      _CwiAdmin.createSafe(
        name: name,
        safeType: safeType,
        bankName: bankName,
        accountNumber: accountNumber,
        costCenterId: costCenterId,
        branchId: branchId,
        globalId: globalId,
      );
  static Future<bool> updateSafe(int id, Map<String, dynamic> data) =>
      _CwiAdmin.updateSafe(id, data);
  static Future<bool> deleteSafe(int id) => _CwiAdmin.deleteSafe(id);
  static Future<int?> createAccount({
    required String code,
    required String name,
    required String accountType,
    int? parentId,
    String? globalId,
  }) =>
      _CwiAdmin.createAccount(
        code: code,
        name: name,
        accountType: accountType,
        parentId: parentId,
        globalId: globalId,
      );
  static Future<bool> updateAccount(int id, Map<String, dynamic> data) =>
      _CwiAdmin.updateAccount(id, data);
  static Future<bool> deleteAccount(int id) => _CwiAdmin.deleteAccount(id);
  static Future<bool> setAccountMapping({
    required String purpose,
    required int accountId,
    int? costCenterId,
  }) =>
      _CwiAdmin.setAccountMapping(
        purpose: purpose,
        accountId: accountId,
        costCenterId: costCenterId,
      );
  static Future<bool> deleteAccountMapping({
    required String purpose,
    int? costCenterId,
  }) =>
      _CwiAdmin.deleteAccountMapping(
        purpose: purpose,
        costCenterId: costCenterId,
      );
  static Future<int?> createCostCenter({
    required String code,
    required String name,
    int? parentId,
    String? globalId,
  }) =>
      _CwiAdmin.createCostCenter(
        code: code,
        name: name,
        parentId: parentId,
        globalId: globalId,
      );
  static Future<bool> updateCostCenter(int id, Map<String, dynamic> data) =>
      _CwiAdmin.updateCostCenter(id, data);
  static Future<bool> deleteCostCenter(int id) => _CwiAdmin.deleteCostCenter(id);
  static Future<bool> setUserRegionAccess(int userId, List<int> regionIds) =>
      _CwiAdmin.setUserRegionAccess(userId, regionIds);
}
