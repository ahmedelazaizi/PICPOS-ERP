import '../../data/database/database.dart' as db;
import '../../domain/repositories/landed_cost_repository.dart';

class LandedCostRepositoryImpl implements ILandedCostRepository {
  final db.AppDatabase _db;

  LandedCostRepositoryImpl(this._db);

  @override
  Future<int> createLandedCostSheet({
    required int purchaseInvoiceId,
    required String sheetNumber,
    String allocationMethod = 'by_value',
    String? notes,
    int? createdBy,
  }) {
    return _db.createLandedCostSheet(
      purchaseInvoiceId: purchaseInvoiceId,
      sheetNumber: sheetNumber,
      allocationMethod: allocationMethod,
      notes: notes,
      createdBy: createdBy,
    );
  }

  @override
  Future<List<db.LandedCostSheetData>> getLandedCostSheets({
    int? purchaseInvoiceId,
  }) {
    return _db.getLandedCostSheets(purchaseInvoiceId: purchaseInvoiceId);
  }

  @override
  Future<int> addLandedCostItem({
    required int sheetId,
    required String costType,
    required String description,
    required double amount,
    int? supplierPartyId,
  }) {
    return _db.addLandedCostItem(
      sheetId: sheetId,
      costType: costType,
      description: description,
      amount: amount,
      supplierPartyId: supplierPartyId,
    );
  }

  @override
  Future<List<db.LandedCostItemData>> getLandedCostItems(int sheetId) {
    return _db.getLandedCostItems(sheetId);
  }

  @override
  Future<void> deleteLandedCostItem(int itemId) {
    return _db.deleteLandedCostItem(itemId);
  }

  @override
  Future<void> updateAllocationMethod(int sheetId, String method) {
    return _db.updateAllocationMethod(sheetId, method);
  }

  @override
  Future<List<db.LandedCostAllocationData>> calculateAllocations(int sheetId) {
    return _db.calculateAllocations(sheetId);
  }

  @override
  Future<void> applyLandedCost(int sheetId) {
    return _db.applyLandedCost(sheetId);
  }

  @override
  Future<List<Map<String, dynamic>>> getAllocationsWithDetails(int sheetId) {
    return _db.getAllocationsWithDetails(sheetId);
  }
}
