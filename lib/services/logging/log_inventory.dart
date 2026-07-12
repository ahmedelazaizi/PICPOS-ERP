part of '../activity_logger.dart';

// ═══════════════════════════════════════════════════════════════════════════
// INVENTORY, PRODUCTS & STOCK
// ═══════════════════════════════════════════════════════════════════════════

extension ActivityLoggerInventory on ActivityLogger {
  Future<void> logProductEdit(int userId, String userName, String productName, {int? productId}) {
    return log(userId: userId, userName: userName, action: 'product_edit', entityType: 'product',
        entityId: productId, description: 'تعديل صنف: $productName');
  }

  Future<void> logProductDelete(int userId, String userName, String productName, {int? productId}) {
    return log(userId: userId, userName: userName, action: 'product_delete', entityType: 'product',
        entityId: productId, description: 'حذف صنف: $productName');
  }

  Future<void> logStockAdjust(int userId, String userName, String productName, double oldQty, double newQty) {
    return log(userId: userId, userName: userName, action: 'stock_adjust', entityType: 'inventory',
        description: 'تعديل مخزون يدوي: $productName', oldValue: oldQty.toString(), newValue: newQty.toString(),
        amount: newQty - oldQty);
  }

  Future<void> logInventoryBondCreate(int userId, String userName, String bondType,
      {int? bondId, double? totalValue}) {
    return log(userId: userId, userName: userName, action: 'inventory_bond_create', entityType: 'inventory_bond',
        entityId: bondId, description: 'إنشاء سند مخزني: $bondType', amount: totalValue);
  }

  Future<void> logStockTransfer(int userId, String userName, String fromLocation, String toLocation,
      {int? transferId, int? itemCount}) {
    return log(userId: userId, userName: userName, action: 'stock_transfer', entityType: 'inventory',
        entityId: transferId,
        description: 'تحويل مخزون من $fromLocation إلى $toLocation${itemCount != null ? " ($itemCount صنف)" : ""}');
  }

  Future<void> logStockAudit(int userId, String userName, String auditAction,
      {int? auditId, int? discrepancies}) {
    return log(userId: userId, userName: userName, action: 'stock_audit', entityType: 'inventory',
        entityId: auditId,
        description: 'جرد مخزون: $auditAction${discrepancies != null ? " ($discrepancies فرق)" : ""}');
  }

  Future<void> logCategoryAdd(int userId, String userName, String categoryName) {
    return log(userId: userId, userName: userName, action: 'category_add', entityType: 'category',
        description: 'إضافة تصنيف: $categoryName');
  }

  Future<void> logCategoryEdit(int userId, String userName, String categoryName, {String? oldName}) {
    return log(userId: userId, userName: userName, action: 'category_edit', entityType: 'category',
        description: 'تعديل تصنيف: ${oldName ?? categoryName}', oldValue: oldName, newValue: categoryName);
  }

  Future<void> logCategoryDelete(int userId, String userName, String categoryName) {
    return log(userId: userId, userName: userName, action: 'category_delete', entityType: 'category',
        description: 'حذف تصنيف: $categoryName');
  }

  Future<void> logPluOperation(int userId, String userName, String operation, String productName, {int? pluCode}) {
    return log(userId: userId, userName: userName, action: 'plu_$operation', entityType: 'plu',
        description: '$operation PLU: $productName${pluCode != null ? " (كود: $pluCode)" : ""}');
  }
}
