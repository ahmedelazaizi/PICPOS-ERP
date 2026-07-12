import '../../data/database/database.dart' as db;

/// ILandedCostRepository interface
abstract class ILandedCostRepository {
  /// Create a landed cost sheet for a purchase invoice
  Future<int> createLandedCostSheet({
    required int purchaseInvoiceId,
    required String sheetNumber,
    String allocationMethod = 'by_value',
    String? notes,
    int? createdBy,
  });

  /// Get sheets for a purchase invoice
  Future<List<db.LandedCostSheetData>> getLandedCostSheets({
    int? purchaseInvoiceId,
  });

  /// Add a cost item to a sheet
  Future<int> addLandedCostItem({
    required int sheetId,
    required String costType,
    required String description,
    required double amount,
    int? supplierPartyId,
  });

  /// Get cost items for a sheet
  Future<List<db.LandedCostItemData>> getLandedCostItems(int sheetId);

  /// Delete a cost item
  Future<void> deleteLandedCostItem(int itemId);

  /// Calculate allocations based on the chosen method
  Future<List<db.LandedCostAllocationData>> calculateAllocations(int sheetId);

  /// Apply allocations — update inventory average cost
  Future<void> applyLandedCost(int sheetId);

  /// Get allocations with product names
  Future<List<Map<String, dynamic>>> getAllocationsWithDetails(int sheetId);
}
