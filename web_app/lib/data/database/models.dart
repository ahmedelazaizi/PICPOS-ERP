// Database stub for web platform
// This file provides type definitions without FFI dependencies

// ═══════════════════════════════════════════════════════════════════════════
// DATA CLASSES (matching Drift-generated classes)
// ═══════════════════════════════════════════════════════════════════════════

class AppUser {
  final int id;
  final String username;
  final String passwordHash;
  final String role;
  final String? fullName;
  final bool isActive;
  final DateTime createdAt;

  AppUser({
    required this.id,
    required this.username,
    required this.passwordHash,
    this.role = 'cashier',
    this.fullName,
    this.isActive = true,
    required this.createdAt,
  });
}

class Product {
  final int id;
  final String code;
  final String name;
  final int? categoryId;
  final double salePrice;
  final double costPrice;
  final double minStock;
  final double currentStock;
  final bool trackInventory;
  final bool isSoldByWeight;
  final bool trackExpiry;
  final int defaultShelfDays;
  final int alertDaysBefore;
  final bool allowNegativeSale;
  final double? pricePerUnit;
  final String weightUnit;
  final String? description;
  final List<int>? imageData;
  final bool isActive;
  final DateTime createdAt;

  Product({
    required this.id,
    required this.code,
    required this.name,
    this.categoryId,
    this.salePrice = 0,
    this.costPrice = 0,
    this.minStock = 0,
    this.currentStock = 0,
    this.trackInventory = true,
    this.isSoldByWeight = false,
    this.trackExpiry = false,
    this.defaultShelfDays = 90,
    this.alertDaysBefore = 30,
    this.allowNegativeSale = false,
    this.pricePerUnit,
    this.weightUnit = 'kg',
    this.description,
    this.imageData,
    this.isActive = true,
    required this.createdAt,
  });
}

class ProductsCompanion {
  final Value<String> code;
  final Value<String> name;
  final Value<int?> categoryId;
  final Value<double> salePrice;
  final Value<double> costPrice;
  final Value<double> minStock;
  final Value<double> currentStock;
  final Value<bool> trackInventory;
  final Value<bool> isSoldByWeight;
  final Value<bool> trackExpiry;
  final Value<bool> isActive;

  ProductsCompanion({
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.salePrice = const Value.absent(),
    this.costPrice = const Value.absent(),
    this.minStock = const Value.absent(),
    this.currentStock = const Value.absent(),
    this.trackInventory = const Value.absent(),
    this.isSoldByWeight = const Value.absent(),
    this.trackExpiry = const Value.absent(),
    this.isActive = const Value.absent(),
  });
}

class Category {
  final int id;
  final String name;
  final String? description;
  final int? parentId;
  final bool isActive;
  final DateTime createdAt;

  Category({
    required this.id,
    required this.name,
    this.description,
    this.parentId,
    this.isActive = true,
    required this.createdAt,
  });
}

class CategoriesCompanion {
  final Value<String> name;
  final Value<String?> description;
  final Value<int?> parentId;
  final Value<bool> isActive;

  CategoriesCompanion({
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.parentId = const Value.absent(),
    this.isActive = const Value.absent(),
  });
}

class Party {
  final int id;
  final String name;
  final String? phone;
  final String? address;
  final String? taxId;
  final bool isCustomer;
  final bool isSupplier;
  final double balance;
  final double creditLimit;
  final bool isActive;
  final DateTime createdAt;

  Party({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.taxId,
    this.isCustomer = true,
    this.isSupplier = false,
    this.balance = 0,
    this.creditLimit = 0,
    this.isActive = true,
    required this.createdAt,
  });
}

class PartiesCompanion {
  final Value<String> name;
  final Value<String?> phone;
  final Value<String?> address;
  final Value<bool> isCustomer;
  final Value<bool> isSupplier;
  final Value<double> balance;
  final Value<double> creditLimit;

  PartiesCompanion({
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.address = const Value.absent(),
    this.isCustomer = const Value.absent(),
    this.isSupplier = const Value.absent(),
    this.balance = const Value.absent(),
    this.creditLimit = const Value.absent(),
  });
}

class Warehouse {
  final int id;
  final String name;
  final String? address;
  final bool isDefault;
  final bool isActive;
  final DateTime createdAt;

  Warehouse({
    required this.id,
    required this.name,
    this.address,
    this.isDefault = false,
    this.isActive = true,
    required this.createdAt,
  });
}

class WarehousesCompanion {
  final Value<String> name;
  final Value<String?> address;
  final Value<bool> isDefault;
  final Value<bool> isActive;

  WarehousesCompanion({
    this.name = const Value.absent(),
    this.address = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.isActive = const Value.absent(),
  });
}

class Safe {
  final int id;
  final String name;
  final String safeType; // 'cash' or 'bank'
  final double balance;
  final bool isDefault;
  final bool isActive;
  final DateTime createdAt;

  Safe({
    required this.id,
    required this.name,
    this.safeType = 'cash',
    this.balance = 0,
    this.isDefault = false,
    this.isActive = true,
    required this.createdAt,
  });
}

class SafesCompanion {
  final Value<String> name;
  final Value<String> safeType;
  final Value<double> balance;
  final Value<bool> isDefault;
  final Value<bool> isActive;

  SafesCompanion({
    this.name = const Value.absent(),
    this.safeType = const Value.absent(),
    this.balance = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.isActive = const Value.absent(),
  });
}

class SafeTransaction {
  final int id;
  final String voucherNumber;
  final int safeId;
  final String transactionType; // 'receipt' or 'payment'
  final String category;
  final double amount;
  final double balanceAfter;
  final int? partyId;
  final String? referenceType;
  final int? referenceId;
  final String? description;
  final int? userId;
  final DateTime createdAt;

  SafeTransaction({
    required this.id,
    required this.voucherNumber,
    required this.safeId,
    required this.transactionType,
    required this.category,
    required this.amount,
    required this.balanceAfter,
    this.partyId,
    this.referenceType,
    this.referenceId,
    this.description,
    this.userId,
    required this.createdAt,
  });
}

class SafeTransactionsCompanion {
  final Value<String> voucherNumber;
  final Value<int> safeId;
  final Value<String> transactionType;
  final Value<String> category;
  final Value<double> amount;
  final Value<double> balanceAfter;
  final Value<int?> partyId;
  final Value<String?> referenceType;
  final Value<int?> referenceId;
  final Value<String?> description;
  final Value<int?> userId;

  SafeTransactionsCompanion({
    this.voucherNumber = const Value.absent(),
    this.safeId = const Value.absent(),
    this.transactionType = const Value.absent(),
    this.category = const Value.absent(),
    this.amount = const Value.absent(),
    this.balanceAfter = const Value.absent(),
    this.partyId = const Value.absent(),
    this.referenceType = const Value.absent(),
    this.referenceId = const Value.absent(),
    this.description = const Value.absent(),
    this.userId = const Value.absent(),
  });

  SafeTransactionsCompanion.insert({
    required String voucherNumber,
    required int safeId,
    required String transactionType,
    required String category,
    required double amount,
    required double balanceAfter,
    this.partyId = const Value.absent(),
    this.referenceType = const Value.absent(),
    this.referenceId = const Value.absent(),
    this.description = const Value.absent(),
    this.userId = const Value.absent(),
  }) : voucherNumber = Value(voucherNumber),
       safeId = Value(safeId),
       transactionType = Value(transactionType),
       category = Value(category),
       amount = Value(amount),
       balanceAfter = Value(balanceAfter);
}

// ═══════════════════════════════════════════════════════════════════════════
// HELD/SUSPENDED ORDERS - الفواتير المعلقة
// ═══════════════════════════════════════════════════════════════════════════

class HeldOrder {
  final int id;
  final String holdNumber;
  final double subtotal;
  final double discount;
  final bool discountIsPercent;
  final String? note;
  final int? userId;
  final int? customerId;
  final DateTime createdAt;

  HeldOrder({
    required this.id,
    required this.holdNumber,
    required this.subtotal,
    required this.discount,
    required this.discountIsPercent,
    this.note,
    this.userId,
    this.customerId,
    required this.createdAt,
  });
}

class HeldOrderItem {
  final int id;
  final int heldOrderId;
  final int productId;
  final double quantity;
  final double unitPrice;
  final double? customPrice;
  final String? note;

  HeldOrderItem({
    required this.id,
    required this.heldOrderId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.customPrice,
    this.note,
  });
}

class SalesInvoiceData {
  final int id;
  final String invoiceNumber;
  final int? customerId;
  final int warehouseId;
  final int userId;
  final DateTime invoiceDate;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double paid;
  final String paymentMethod;
  final String status;
  final String? notes;
  final DateTime createdAt;

  SalesInvoiceData({
    required this.id,
    required this.invoiceNumber,
    this.customerId,
    required this.warehouseId,
    required this.userId,
    required this.invoiceDate,
    this.subtotal = 0,
    this.discount = 0,
    this.tax = 0,
    this.total = 0,
    this.paid = 0,
    this.paymentMethod = 'cash',
    this.status = 'completed',
    this.notes,
    required this.createdAt,
  });
}

class SalesInvoiceItem {
  final int id;
  final int invoiceId;
  final int productId;
  final double quantity;
  final double unitPrice;
  final double discount;
  final double total;
  final int? batchId;
  final double costPrice;

  SalesInvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0,
    required this.total,
    this.batchId,
    this.costPrice = 0,
  });
}

class PurchaseInvoiceData {
  final int id;
  final String invoiceNumber;
  final int supplierId;
  final int warehouseId;
  final DateTime invoiceDate;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double paid;
  final String status;
  final String? notes;
  final DateTime createdAt;

  PurchaseInvoiceData({
    required this.id,
    required this.invoiceNumber,
    required this.supplierId,
    required this.warehouseId,
    required this.invoiceDate,
    this.subtotal = 0,
    this.discount = 0,
    this.tax = 0,
    this.total = 0,
    this.paid = 0,
    this.status = 'pending',
    this.notes,
    required this.createdAt,
  });
}

class PurchaseInvoiceItem {
  final int id;
  final int invoiceId;
  final int productId;
  final double quantity;
  final double unitCost;
  final double discount;
  final double total;
  final String? batchNumber;
  final DateTime? expiryDate;

  PurchaseInvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.productId,
    required this.quantity,
    required this.unitCost,
    this.discount = 0,
    required this.total,
    this.batchNumber,
    this.expiryDate,
  });
}

class StockMovement {
  final int id;
  final int productId;
  final int warehouseId;
  final String movementType;
  final double quantity;
  final double unitCost;
  final double balanceAfter;
  final String? referenceType;
  final int? referenceId;
  final String? notes;
  final DateTime createdAt;

  StockMovement({
    required this.id,
    required this.productId,
    required this.warehouseId,
    required this.movementType,
    required this.quantity,
    this.unitCost = 0,
    required this.balanceAfter,
    this.referenceType,
    this.referenceId,
    this.notes,
    required this.createdAt,
  });
}

class Offer {
  final int id;
  final String name;
  final String? description;
  final double offerPrice;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isActive;
  final DateTime createdAt;

  Offer({
    required this.id,
    required this.name,
    this.description,
    required this.offerPrice,
    this.startDate,
    this.endDate,
    this.isActive = true,
    required this.createdAt,
  });
}

class OfferItem {
  final int id;
  final int offerId;
  final int productId;
  final double quantity;

  OfferItem({
    required this.id,
    required this.offerId,
    required this.productId,
    required this.quantity,
  });
}

class RestaurantTable {
  final int id;
  final String tableNumber;
  final String? name;
  final int capacity;
  final String status;
  final DateTime createdAt;

  RestaurantTable({
    required this.id,
    required this.tableNumber,
    this.name,
    this.capacity = 4,
    this.status = 'available',
    required this.createdAt,
  });
}

class TableOrder {
  final int id;
  final int tableId;
  final int userId;
  final String status;
  final double total;
  final DateTime openedAt;
  final DateTime? closedAt;

  TableOrder({
    required this.id,
    required this.tableId,
    required this.userId,
    this.status = 'open',
    this.total = 0,
    required this.openedAt,
    this.closedAt,
  });
}

class TableOrderItem {
  final int id;
  final int orderId;
  final int productId;
  final double quantity;
  final double unitPrice;
  final String? notes;
  final DateTime createdAt;

  TableOrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.notes,
    required this.createdAt,
  });
}

class Setting {
  final int id;
  final String key;
  final String? value;
  final DateTime updatedAt;

  Setting({
    required this.id,
    required this.key,
    this.value,
    required this.updatedAt,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// VALUE WRAPPER (matching Drift's Value class)
// ═══════════════════════════════════════════════════════════════════════════

class Value<T> {
  final T? _value;
  final bool _present;

  const Value(this._value) : _present = true;
  const Value.absent() : _value = null, _present = false;

  T get value => _value as T;
  bool get present => _present;
}

// ═══════════════════════════════════════════════════════════════════════════
// STUB DATABASE (web platform)
// ═══════════════════════════════════════════════════════════════════════════

class AppDatabase {
  Future<void> close() async {}
  
  // All methods are stubs - use Supabase providers on web
  Stream<List<Product>> watchAllProducts() => Stream.value([]);
  Stream<List<Category>> watchAllCategories() => Stream.value([]);
  Stream<List<Party>> watchCustomers() => Stream.value([]);
  Stream<List<Party>> watchSuppliers() => Stream.value([]);
  Stream<List<SalesInvoiceData>> watchTodaySales() => Stream.value([]);
  Stream<List<Safe>> watchAllSafes() => Stream.value([]);
  Stream<List<AppUser>> watchAllUsers() => Stream.value([]);
  Stream<List<Product>> watchLowStockProducts() => Stream.value([]);
  Stream<List<Product>> searchProducts(String query) => Stream.value([]);
}
