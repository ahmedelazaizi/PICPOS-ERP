import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

/// Supabase database service for web platform
/// Provides same interface as Drift database but uses Supabase
class SupabaseDatabase {
  final SupabaseClient _client;

  SupabaseDatabase(this._client);

  // ═══════════════════════════════════════════════════════════════════════════
  // PRODUCTS
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<Product>> watchAllProducts() {
    return _client
        .from('products')
        .stream(primaryKey: ['id'])
        .order('name')
        .map((data) => data.map(_mapToProduct).toList());
  }

  Future<List<Product>> getAllProducts() async {
    final data = await _client.from('products').select().order('name');
    return data.map(_mapToProduct).toList();
  }

  Future<Product?> getProductById(int id) async {
    final data = await _client.from('products').select().eq('id', id).maybeSingle();
    return data != null ? _mapToProduct(data) : null;
  }

  Future<Product?> getProductByCode(String code) async {
    final data = await _client.from('products').select().eq('code', code).maybeSingle();
    return data != null ? _mapToProduct(data) : null;
  }

  Future<int> insertProduct(ProductsCompanion product) async {
    final data = await _client.from('products').insert({
      'code': product.code.value,
      'name': product.name.value,
      'category_id': product.categoryId.present ? product.categoryId.value : null,
      'sale_price': product.salePrice.present ? product.salePrice.value : 0,
      'cost_price': product.costPrice.present ? product.costPrice.value : 0,
      'min_stock': product.minStock.present ? product.minStock.value : 0,
      'current_stock': product.currentStock.present ? product.currentStock.value : 0,
      'track_inventory': product.trackInventory.present ? product.trackInventory.value : true,
      'is_sold_by_weight': product.isSoldByWeight.present ? product.isSoldByWeight.value : false,
      'track_expiry': product.trackExpiry.present ? product.trackExpiry.value : false,
      'is_active': product.isActive.present ? product.isActive.value : true,
    }).select('id').single();
    return data['id'] as int;
  }

  Future<void> updateProduct(Product product) async {
    await _client.from('products').update({
      'code': product.code,
      'name': product.name,
      'category_id': product.categoryId,
      'sale_price': product.salePrice,
      'cost_price': product.costPrice,
      'min_stock': product.minStock,
      'current_stock': product.currentStock,
      'track_inventory': product.trackInventory,
      'is_sold_by_weight': product.isSoldByWeight,
      'track_expiry': product.trackExpiry,
      'is_active': product.isActive,
      'description': product.description,
      'image_data': product.imageData,
    }).eq('id', product.id);
  }

  Future<void> updateProductStock(int productId, double newStock) async {
    await _client.from('products').update({
      'current_stock': newStock,
    }).eq('id', productId);
  }

  Future<void> deleteProduct(int id) async {
    await _client.from('products').delete().eq('id', id);
  }

  Product _mapToProduct(Map<String, dynamic> data) {
    return Product(
      id: data['id'] as int,
      code: data['code'] as String,
      name: data['name'] as String,
      categoryId: data['category_id'] as int?,
      salePrice: (data['sale_price'] as num?)?.toDouble() ?? 0,
      costPrice: (data['cost_price'] as num?)?.toDouble() ?? 0,
      minStock: (data['min_stock'] as num?)?.toDouble() ?? 0,
      currentStock: (data['current_stock'] as num?)?.toDouble() ?? 0,
      trackInventory: data['track_inventory'] as bool? ?? true,
      isSoldByWeight: data['is_sold_by_weight'] as bool? ?? false,
      trackExpiry: data['track_expiry'] as bool? ?? false,
      defaultShelfDays: data['default_shelf_days'] as int? ?? 90,
      alertDaysBefore: data['alert_days_before'] as int? ?? 30,
      allowNegativeSale: data['allow_negative_sale'] as bool? ?? false,
      pricePerUnit: (data['price_per_unit'] as num?)?.toDouble(),
      weightUnit: data['weight_unit'] as String? ?? 'kg',
      description: data['description'] as String?,
      imageData: data['image_data'] != null ? _decodeBytes(data['image_data']) : null,
      isActive: data['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CATEGORIES
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<Category>> watchCategories() {
    return _client
        .from('categories')
        .stream(primaryKey: ['id'])
        .order('name')
        .map((data) => data.map(_mapToCategory).toList());
  }

  Future<List<Category>> getAllCategories() async {
    final data = await _client.from('categories').select().order('name');
    return data.map(_mapToCategory).toList();
  }

  Future<int> insertCategory(CategoriesCompanion category) async {
    final data = await _client.from('categories').insert({
      'name': category.name.value,
      'description': category.description.present ? category.description.value : null,
      'parent_id': category.parentId.present ? category.parentId.value : null,
      'is_active': category.isActive.present ? category.isActive.value : true,
    }).select('id').single();
    return data['id'] as int;
  }

  Category _mapToCategory(Map<String, dynamic> data) {
    return Category(
      id: data['id'] as int,
      name: data['name'] as String,
      description: data['description'] as String?,
      parentId: data['parent_id'] as int?,
      isActive: data['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PARTIES (Customers & Suppliers)
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<Party>> watchCustomers() {
    return _client
        .from('parties')
        .stream(primaryKey: ['id'])
        .eq('is_customer', true)
        .order('name')
        .map((data) => data.map(_mapToParty).toList());
  }

  Stream<List<Party>> watchSuppliers() {
    return _client
        .from('parties')
        .stream(primaryKey: ['id'])
        .eq('is_supplier', true)
        .order('name')
        .map((data) => data.map(_mapToParty).toList());
  }

  Future<Party?> getPartyById(int id) async {
    final data = await _client.from('parties').select().eq('id', id).maybeSingle();
    return data != null ? _mapToParty(data) : null;
  }

  Future<int> insertParty(PartiesCompanion party) async {
    final data = await _client.from('parties').insert({
      'name': party.name.value,
      'phone': party.phone.present ? party.phone.value : null,
      'address': party.address.present ? party.address.value : null,
      'is_customer': party.isCustomer.present ? party.isCustomer.value : true,
      'is_supplier': party.isSupplier.present ? party.isSupplier.value : false,
      'balance': party.balance.present ? party.balance.value : 0,
      'credit_limit': party.creditLimit.present ? party.creditLimit.value : 0,
    }).select('id').single();
    return data['id'] as int;
  }

  Party _mapToParty(Map<String, dynamic> data) {
    return Party(
      id: data['id'] as int,
      name: data['name'] as String,
      phone: data['phone'] as String?,
      address: data['address'] as String?,
      taxId: data['tax_id'] as String?,
      isCustomer: data['is_customer'] as bool? ?? true,
      isSupplier: data['is_supplier'] as bool? ?? false,
      balance: (data['balance'] as num?)?.toDouble() ?? 0,
      creditLimit: (data['credit_limit'] as num?)?.toDouble() ?? 0,
      isActive: data['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SALES INVOICES
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<SalesInvoiceData>> watchSalesInvoices() {
    return _client
        .from('sales_invoices')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => data.map(_mapToSalesInvoice).toList());
  }

  Future<SalesInvoiceData?> getSalesInvoiceById(int id) async {
    final data = await _client.from('sales_invoices').select().eq('id', id).maybeSingle();
    return data != null ? _mapToSalesInvoice(data) : null;
  }

  Future<int> insertSalesInvoice({
    required String invoiceNumber,
    int? customerId,
    required int warehouseId,
    required int userId,
    required DateTime invoiceDate,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    required String paymentMethod,
    String? notes,
  }) async {
    final data = await _client.from('sales_invoices').insert({
      'invoice_number': invoiceNumber,
      'customer_id': customerId,
      'warehouse_id': warehouseId,
      'user_id': userId,
      'invoice_date': invoiceDate.toIso8601String(),
      'subtotal': subtotal,
      'discount': discount,
      'tax': tax,
      'total': total,
      'paid': paid,
      'payment_method': paymentMethod,
      'notes': notes,
    }).select('id').single();
    return data['id'] as int;
  }

  Future<void> insertSalesInvoiceItem({
    required int invoiceId,
    required int productId,
    required double quantity,
    required double unitPrice,
    required double discount,
    required double total,
    double costPrice = 0,
  }) async {
    await _client.from('sales_invoice_items').insert({
      'invoice_id': invoiceId,
      'product_id': productId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount': discount,
      'total': total,
      'cost_price': costPrice,
    });
  }

  Future<List<SalesInvoiceItem>> getSalesInvoiceItems(int invoiceId) async {
    final data = await _client.from('sales_invoice_items').select().eq('invoice_id', invoiceId);
    return data.map(_mapToSalesInvoiceItem).toList();
  }

  SalesInvoiceData _mapToSalesInvoice(Map<String, dynamic> data) {
    return SalesInvoiceData(
      id: data['id'] as int,
      invoiceNumber: data['invoice_number'] as String,
      customerId: data['customer_id'] as int?,
      warehouseId: data['warehouse_id'] as int,
      userId: data['user_id'] as int,
      invoiceDate: DateTime.parse(data['invoice_date'] as String),
      subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0,
      discount: (data['discount'] as num?)?.toDouble() ?? 0,
      tax: (data['tax'] as num?)?.toDouble() ?? 0,
      total: (data['total'] as num?)?.toDouble() ?? 0,
      paid: (data['paid'] as num?)?.toDouble() ?? 0,
      paymentMethod: data['payment_method'] as String? ?? 'cash',
      status: data['status'] as String? ?? 'completed',
      notes: data['notes'] as String?,
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }

  SalesInvoiceItem _mapToSalesInvoiceItem(Map<String, dynamic> data) {
    return SalesInvoiceItem(
      id: data['id'] as int,
      invoiceId: data['invoice_id'] as int,
      productId: data['product_id'] as int,
      quantity: (data['quantity'] as num).toDouble(),
      unitPrice: (data['unit_price'] as num).toDouble(),
      discount: (data['discount'] as num?)?.toDouble() ?? 0,
      total: (data['total'] as num).toDouble(),
      batchId: data['batch_id'] as int?,
      costPrice: (data['cost_price'] as num?)?.toDouble() ?? 0,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PURCHASE INVOICES
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<PurchaseInvoiceData>> watchPurchaseInvoices() {
    return _client
        .from('purchase_invoices')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => data.map(_mapToPurchaseInvoice).toList());
  }

  Future<int> insertPurchaseInvoice({
    required String invoiceNumber,
    required int supplierId,
    required int warehouseId,
    required DateTime invoiceDate,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    String? notes,
  }) async {
    final data = await _client.from('purchase_invoices').insert({
      'invoice_number': invoiceNumber,
      'supplier_id': supplierId,
      'warehouse_id': warehouseId,
      'invoice_date': invoiceDate.toIso8601String(),
      'subtotal': subtotal,
      'discount': discount,
      'tax': tax,
      'total': total,
      'paid': paid,
      'notes': notes,
    }).select('id').single();
    return data['id'] as int;
  }

  Future<void> insertPurchaseInvoiceItem({
    required int invoiceId,
    required int productId,
    required double quantity,
    required double unitCost,
    required double discount,
    required double total,
    String? batchNumber,
    DateTime? expiryDate,
  }) async {
    await _client.from('purchase_invoice_items').insert({
      'invoice_id': invoiceId,
      'product_id': productId,
      'quantity': quantity,
      'unit_cost': unitCost,
      'discount': discount,
      'total': total,
      'batch_number': batchNumber,
      'expiry_date': expiryDate?.toIso8601String(),
    });
  }

  PurchaseInvoiceData _mapToPurchaseInvoice(Map<String, dynamic> data) {
    return PurchaseInvoiceData(
      id: data['id'] as int,
      invoiceNumber: data['invoice_number'] as String,
      supplierId: data['supplier_id'] as int,
      warehouseId: data['warehouse_id'] as int,
      invoiceDate: DateTime.parse(data['invoice_date'] as String),
      subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0,
      discount: (data['discount'] as num?)?.toDouble() ?? 0,
      tax: (data['tax'] as num?)?.toDouble() ?? 0,
      total: (data['total'] as num?)?.toDouble() ?? 0,
      paid: (data['paid'] as num?)?.toDouble() ?? 0,
      status: data['status'] as String? ?? 'pending',
      notes: data['notes'] as String?,
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STOCK MOVEMENTS
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<StockMovement>> watchStockMovements() {
    return _client
        .from('stock_movements')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(100)
        .map((data) => data.map(_mapToStockMovement).toList());
  }

  Future<void> insertStockMovement({
    required int productId,
    required int warehouseId,
    required String movementType,
    required double quantity,
    required double unitCost,
    required double balanceAfter,
    String? referenceType,
    int? referenceId,
    String? notes,
  }) async {
    await _client.from('stock_movements').insert({
      'product_id': productId,
      'warehouse_id': warehouseId,
      'movement_type': movementType,
      'quantity': quantity,
      'unit_cost': unitCost,
      'balance_after': balanceAfter,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'notes': notes,
    });
  }

  StockMovement _mapToStockMovement(Map<String, dynamic> data) {
    return StockMovement(
      id: data['id'] as int,
      productId: data['product_id'] as int,
      warehouseId: data['warehouse_id'] as int,
      movementType: data['movement_type'] as String,
      quantity: (data['quantity'] as num).toDouble(),
      unitCost: (data['unit_cost'] as num?)?.toDouble() ?? 0,
      balanceAfter: (data['balance_after'] as num).toDouble(),
      referenceType: data['reference_type'] as String?,
      referenceId: data['reference_id'] as int?,
      notes: data['notes'] as String?,
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WAREHOUSES
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Warehouse>> getAllWarehouses() async {
    final data = await _client.from('warehouses').select().order('name');
    return data.map(_mapToWarehouse).toList();
  }

  Future<Warehouse?> getDefaultWarehouse() async {
    final data = await _client.from('warehouses').select().eq('is_default', true).maybeSingle();
    return data != null ? _mapToWarehouse(data) : null;
  }

  Warehouse _mapToWarehouse(Map<String, dynamic> data) {
    return Warehouse(
      id: data['id'] as int,
      name: data['name'] as String,
      address: data['address'] as String?,
      isDefault: data['is_default'] as bool? ?? false,
      isActive: data['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SAFES (Treasury)
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<Safe>> watchSafes() {
    return _client
        .from('safes')
        .stream(primaryKey: ['id'])
        .order('name')
        .map((data) => data.map(_mapToSafe).toList());
  }

  Future<Safe?> getDefaultSafe() async {
    final data = await _client.from('safes').select().eq('is_default', true).maybeSingle();
    return data != null ? _mapToSafe(data) : null;
  }

  Future<void> updateSafeBalance(int safeId, double newBalance) async {
    await _client.from('safes').update({
      'balance': newBalance,
    }).eq('id', safeId);
  }

  Safe _mapToSafe(Map<String, dynamic> data) {
    return Safe(
      id: data['id'] as int,
      name: data['name'] as String,
      safeType: data['safe_type'] as String? ?? 'cash',
      balance: (data['balance'] as num?)?.toDouble() ?? 0,
      isDefault: data['is_default'] as bool? ?? false,
      isActive: data['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }

  /// Get default safe by type (cash/bank)
  Future<Safe?> getDefaultSafeByType(String safeType) async {
    final data = await _client
        .from('safes')
        .select()
        .eq('safe_type', safeType)
        .eq('is_default', true)
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();
    
    if (data != null) return _mapToSafe(data);
    
    // Fallback to any safe of that type if no default is marked
    final fallback = await _client
        .from('safes')
        .select()
        .eq('safe_type', safeType)
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();
    return fallback != null ? _mapToSafe(fallback) : null;
  }

  /// Update party balance (customer/supplier)
  Future<void> updatePartyBalance(int partyId, double delta) async {
    final party = await getPartyById(partyId);
    if (party != null) {
      final newBalance = party.balance + delta;
      await _client.from('parties').update({
        'balance': newBalance,
      }).eq('id', partyId);
    }
  }

  /// Create a safe transaction with full accounting treatment
  Future<int> createSafeTransaction(SafeTransactionsCompanion transaction) async {
    // Insert the transaction record
    final data = await _client.from('safe_transactions').insert({
      'voucher_number': transaction.voucherNumber.value,
      'safe_id': transaction.safeId.value,
      'transaction_type': transaction.transactionType.value,
      'category': transaction.category.value,
      'amount': transaction.amount.value,
      'balance_after': transaction.balanceAfter.value,
      'party_id': transaction.partyId.present ? transaction.partyId.value : null,
      'reference_type': transaction.referenceType.present ? transaction.referenceType.value : null,
      'reference_id': transaction.referenceId.present ? transaction.referenceId.value : null,
      'description': transaction.description.present ? transaction.description.value : null,
      'user_id': transaction.userId.present ? transaction.userId.value : null,
    }).select('id').single();
    
    final transactionId = data['id'] as int;
    
    // Update the safe balance
    await updateSafeBalance(transaction.safeId.value, transaction.balanceAfter.value);
    
    // Update party balance if this is a party-related transaction
    if (transaction.partyId.present && transaction.partyId.value != null) {
      final partyId = transaction.partyId.value!;
      final amount = transaction.amount.value;
      final transType = transaction.transactionType.value;
      
      // Receipt from customer: reduce their outstanding balance
      // Payment to supplier: reduce our outstanding balance to them
      if (transType == 'receipt' || transType == 'payment') {
        await updatePartyBalance(partyId, -amount);
      }
    }
    
    return transactionId;
  }

  /// Generate invoice number
  Future<String> generateInvoiceNumber(String prefix) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    return '$prefix${timestamp.substring(timestamp.length - 8)}';
  }

  /// Watch safe transactions
  Stream<List<SafeTransaction>> watchSafeTransactions() {
    return _client
        .from('safe_transactions')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(100)
        .map((data) => data.map(_mapToSafeTransaction).toList());
  }

  SafeTransaction _mapToSafeTransaction(Map<String, dynamic> data) {
    return SafeTransaction(
      id: data['id'] as int,
      voucherNumber: data['voucher_number'] as String,
      safeId: data['safe_id'] as int,
      transactionType: data['transaction_type'] as String,
      category: data['category'] as String,
      amount: (data['amount'] as num).toDouble(),
      balanceAfter: (data['balance_after'] as num).toDouble(),
      partyId: data['party_id'] as int?,
      referenceType: data['reference_type'] as String?,
      referenceId: data['reference_id'] as int?,
      description: data['description'] as String?,
      userId: data['user_id'] as int?,
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // USERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<AppUser?> getUserByUsername(String username) async {
    final data = await _client.from('users').select().eq('username', username).maybeSingle();
    return data != null ? _mapToUser(data) : null;
  }

  AppUser _mapToUser(Map<String, dynamic> data) {
    return AppUser(
      id: data['id'] as int,
      username: data['username'] as String,
      passwordHash: data['password_hash'] as String,
      role: data['role'] as String? ?? 'cashier',
      fullName: data['full_name'] as String?,
      isActive: data['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String?> getSetting(String key) async {
    final data = await _client.from('settings').select('value').eq('key', key).maybeSingle();
    return data?['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await _client.from('settings').upsert({
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'key');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELD/SUSPENDED ORDERS - الفواتير المعلقة
  // ═══════════════════════════════════════════════════════════════════════════

  /// Watch all held orders
  Stream<List<HeldOrder>> watchHeldOrders() {
    return _client
        .from('held_orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => data.map(_mapToHeldOrder).toList());
  }

  /// Get all held orders
  Future<List<HeldOrder>> getAllHeldOrders() async {
    final data = await _client
        .from('held_orders')
        .select()
        .order('created_at', ascending: false);
    return data.map(_mapToHeldOrder).toList();
  }

  /// Get items for a held order
  Future<List<HeldOrderItem>> getHeldOrderItems(int heldOrderId) async {
    final data = await _client
        .from('held_order_items')
        .select()
        .eq('held_order_id', heldOrderId);
    return data.map(_mapToHeldOrderItem).toList();
  }

  /// Create a held order with items
  Future<int> createHeldOrder({
    required String holdNumber,
    required double subtotal,
    required double discount,
    required bool discountIsPercent,
    String? note,
    int? customerId,
    required List<Map<String, dynamic>> items,
  }) async {
    // Insert held order
    final orderData = await _client.from('held_orders').insert({
      'hold_number': holdNumber,
      'subtotal': subtotal,
      'discount': discount,
      'discount_is_percent': discountIsPercent,
      'note': note,
      'customer_id': customerId,
    }).select('id').single();
    
    final orderId = orderData['id'] as int;
    
    // Insert items
    for (final item in items) {
      await _client.from('held_order_items').insert({
        'held_order_id': orderId,
        'product_id': item['productId'],
        'quantity': item['quantity'],
        'unit_price': item['unitPrice'],
        'custom_price': item['customPrice'],
        'note': item['note'],
      });
    }
    
    return orderId;
  }

  /// Delete a held order (items deleted via CASCADE)
  Future<void> deleteHeldOrder(int orderId) async {
    await _client.from('held_orders').delete().eq('id', orderId);
  }

  /// Get held order with its items (for retrieval)
  Future<Map<String, dynamic>?> getHeldOrderWithItems(int orderId) async {
    final orderData = await _client
        .from('held_orders')
        .select()
        .eq('id', orderId)
        .maybeSingle();
    
    if (orderData == null) return null;
    
    final order = _mapToHeldOrder(orderData);
    final itemsData = await getHeldOrderItems(orderId);
    
    // Get products for items
    final itemsWithProducts = <Map<String, dynamic>>[];
    for (final item in itemsData) {
      final product = await getProductById(item.productId);
      if (product != null) {
        itemsWithProducts.add({
          'product': product,
          'quantity': item.quantity,
          'unitPrice': item.unitPrice,
          'customPrice': item.customPrice,
          'note': item.note,
        });
      }
    }
    
    return {
      'order': order,
      'items': itemsWithProducts,
    };
  }

  HeldOrder _mapToHeldOrder(Map<String, dynamic> data) {
    return HeldOrder(
      id: data['id'] as int,
      holdNumber: data['hold_number'] as String,
      subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0,
      discount: (data['discount'] as num?)?.toDouble() ?? 0,
      discountIsPercent: data['discount_is_percent'] as bool? ?? false,
      note: data['note'] as String?,
      userId: data['user_id'] as int?,
      customerId: data['customer_id'] as int?,
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }

  HeldOrderItem _mapToHeldOrderItem(Map<String, dynamic> data) {
    return HeldOrderItem(
      id: data['id'] as int,
      heldOrderId: data['held_order_id'] as int,
      productId: data['product_id'] as int,
      quantity: (data['quantity'] as num).toDouble(),
      unitPrice: (data['unit_price'] as num).toDouble(),
      customPrice: (data['custom_price'] as num?)?.toDouble(),
      note: data['note'] as String?,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<int>? _decodeBytes(dynamic data) {
    if (data == null) return null;
    if (data is List) return data.cast<int>();
    if (data is String) {
      // Base64 decode if string
      try {
        return List<int>.from(data.codeUnits);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
