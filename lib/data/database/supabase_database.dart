import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'database.dart' if (dart.library.html) 'database_stub.dart';
import '../../services/security_service.dart';

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
    final data = await _client
        .from('products')
        .select()
        .eq('id', id)
        .maybeSingle();
    return data != null ? _mapToProduct(data) : null;
  }

  Future<Product?> getProductByCode(String code) async {
    final data = await _client
        .from('products')
        .select()
        .eq('barcode', code)
        .maybeSingle();
    return data != null ? _mapToProduct(data) : null;
  }

  Future<int> insertProduct(ProductsCompanion product) async {
    final data = await _client
        .from('products')
        .insert({
          'code': product.code.value,
          'name': product.name.value,
          'category_id': product.categoryId.present
              ? product.categoryId.value
              : null,
          'sale_price': product.salePrice.present ? product.salePrice.value : 0,
          'cost_price': product.costPrice.present ? product.costPrice.value : 0,
          'min_stock': product.minStock.present ? product.minStock.value : 0,
          'current_stock': product.currentStock.present
              ? product.currentStock.value
              : 0,
          'track_inventory': product.trackInventory.present
              ? product.trackInventory.value
              : true,
          'is_sold_by_weight': product.isSoldByWeight.present
              ? product.isSoldByWeight.value
              : false,
          'track_expiry': product.trackExpiry.present
              ? product.trackExpiry.value
              : false,
          'is_active': product.isActive.present ? product.isActive.value : true,
          'scale_plu_number': product.scalePluNumber.present
              ? product.scalePluNumber.value
              : null,
          'scale_type': product.scaleType.present
              ? product.scaleType.value
              : 'count',
        })
        .select('id')
        .single();
    return data['id'] as int;
  }

  Future<void> updateProduct(Product product) async {
    await _client
        .from('products')
        .update({
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
          'scale_plu_number': product.scalePluNumber,
          'scale_type': product.scaleType,
        })
        .eq('id', product.id);
  }

  Future<void> updateProductStock(int productId, double newStock) async {
    await _client
        .from('products')
        .update({'current_stock': newStock})
        .eq('id', productId);
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
      taxRate: (data['tax_rate'] as num?)?.toDouble() ?? 0,
      description: data['description'] as String?,
      imageData: data['image_data'] != null
          ? Uint8List.fromList(_decodeBytes(data['image_data'])!)
          : null,
      isActive: data['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(data['created_at'] as String),
      updatedAt: data['updated_at'] != null ? DateTime.parse(data['updated_at'] as String) : DateTime.parse(data['created_at'] as String),
      priceTalabat: (data['price_talabat'] as num?)?.toDouble() ?? 0,
      priceCareem: (data['price_careem'] as num?)?.toDouble() ?? 0,
      priceAshyae: (data['price_ashyae'] as num?)?.toDouble() ?? 0,
      wholesalePrice: (data['wholesale_price'] as num?)?.toDouble() ?? 0,
      isLocked: data['is_locked'] as bool? ?? false, // #9
      isKitchenSet: data['is_kitchen_set'] as bool? ?? false,
      sortOrder: data['sort_order'] as int? ?? 0,
      scalePluNumber: data['scale_plu_number'] as int?,
      scaleType: data['scale_type'] as String? ?? 'count',
      egsCode: data['egs_code'] as String?,
      gpcCode: data['gpc_code'] as String?,
      itemTaxType: data['item_tax_type'] as String? ?? 'T1',
      itemTaxSubtype: data['item_tax_subtype'] as String? ?? 'V009',
      productType: data['product_type'] as String? ?? 'general',
      globalId: data['global_id'] as String? ?? '',
      rowVersion: 0,
      createdOnServer: data['created_on_server'] as bool? ?? true,
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
    final data = await _client
        .from('categories')
        .insert({
          'name': category.name.value,
          'description': category.description.present
              ? category.description.value
              : null,
          'parent_id': category.parentId.present
              ? category.parentId.value
              : null,
          'is_active': category.isActive.present
              ? category.isActive.value
              : true,
          'is_global': category.isGlobal.present
              ? category.isGlobal.value
              : true,
          'branch_ids': category.branchIds.present
              ? category.branchIds.value
              : null,
        })
        .select('id')
        .single();
    return data['id'] as int;
  }

  Category _mapToCategory(Map<String, dynamic> data) {
    return Category(
      id: data['id'] as int,
      name: data['name'] as String,
      description: data['description'] as String?,
      color: data['color'] as String? ?? '#2563EB',
      parentId: data['parent_id'] as int?,
      sortOrder: data['sort_order'] as int? ?? 0,
      isExcluded: data['is_excluded'] as bool? ?? false,
      isActive: data['is_active'] as bool? ?? true,
      isLocked: data['is_locked'] as bool? ?? false,
      showInPos: data['show_in_pos'] as bool? ?? true,
      isGlobal: data['is_global'] as bool? ?? true,
      branchIds: data['branch_ids'] as String?,
      isSystemDefault: data['is_system_default'] as bool? ?? false,
      rowVersion: 0,
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
    final data = await _client
        .from('parties')
        .select()
        .eq('id', id)
        .maybeSingle();
    return data != null ? _mapToParty(data) : null;
  }

  Future<int> insertParty(PartiesCompanion party) async {
    final data = await _client
        .from('parties')
        .insert({
          'name': party.name.value,
          'phone': party.phone.present ? party.phone.value : null,
          'address': party.address.present ? party.address.value : null,
          'is_customer': party.isCustomer.present
              ? party.isCustomer.value
              : true,
          'is_supplier': party.isSupplier.present
              ? party.isSupplier.value
              : false,
          'is_delivery_company': party.isDeliveryCompany.present
              ? party.isDeliveryCompany.value
              : false,
          'balance': party.balance.present ? party.balance.value : 0,
          'credit_limit': party.creditLimit.present
              ? party.creditLimit.value
              : 0,
        })
        .select('id')
        .single();
    return data['id'] as int;
  }

  Future<void> updatePartyBalance(int partyId, double newBalance) async {
    await _client
        .from('parties')
        .update({'balance': newBalance})
        .eq('id', partyId);
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
      isDeliveryCompany: data['is_delivery_company'] as bool? ?? false,
      isFavorite: data['is_favorite'] as bool? ?? false,
      balance: (data['balance'] as num?)?.toDouble() ?? 0,
      creditLimit: (data['credit_limit'] as num?)?.toDouble() ?? 0,
      fixedDiscount: (data['fixed_discount'] as num?)?.toDouble() ?? 0,
      isActive: data['is_active'] as bool? ?? true,
      priceLevel: data['price_level'] as String? ?? 'default',
      isGlobal: data['is_global'] as bool? ?? true,
      createdAt: DateTime.parse(data['created_at'] as String),
      isSystemDefault: data['is_system_default'] as bool? ?? false,
      rowVersion: 0,
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
    final data = await _client
        .from('sales_invoices')
        .select()
        .eq('id', id)
        .maybeSingle();
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
    final data = await _client
        .from('sales_invoices')
        .insert({
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
        })
        .select('id')
        .single();
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
    final data = await _client
        .from('sales_invoice_items')
        .select()
        .eq('invoice_id', invoiceId);
    return data.map(_mapToSalesInvoiceItem).toList();
  }

  SalesInvoiceData _mapToSalesInvoice(Map<String, dynamic> data) {
    return SalesInvoiceData(
      id: data['id'] as int,
      globalId: data['global_id'] as String? ?? '',
      isDeleted: data['is_deleted'] as bool? ?? false,
      updatedAt: data['updated_at'] != null ? DateTime.parse(data['updated_at'] as String) : DateTime.parse(data['created_at'] as String),
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
      cashPaid: (data['cash_paid'] as num?)?.toDouble() ?? 0,
      bankPaid: (data['bank_paid'] as num?)?.toDouble() ?? 0,
      clickPaid: (data['click_paid'] as num?)?.toDouble() ?? 0,
      status: data['status'] as String? ?? 'completed',
      deliveryStatus: data['delivery_status'] as String?,
      deliveryFee: (data['delivery_fee'] as num?)?.toDouble() ?? 0,
      deliveryCompanyId: data['delivery_company_id'] as int?,
      deliveryCompanyPartyId: data['delivery_company_party_id'] as int?,
      courierId: data['courier_id'] as int?,
      notes: data['notes'] as String?,
      saleType: data['sale_type'] as String? ?? 'default',
      orderNumber: data['order_number'] as int?,
      isLocked: data['is_locked'] as bool? ?? false,
      createdAt: DateTime.parse(data['created_at'] as String),
      rowVersion: 0,
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
      sortOrder: data['sort_order'] as int? ?? 0,
      taxRate: (data['tax_rate'] as num?)?.toDouble() ?? 0,
      taxAmount: (data['tax_amount'] as num?)?.toDouble() ?? 0,
      unitName: data['unit_name'] as String?,
      quantityInBase: (data['quantity_in_base'] as num?)?.toDouble() ?? 1.0,
      rowVersion: 0,
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
    int? supplierId,
    required int warehouseId,
    required int userId,
    required DateTime invoiceDate,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    final data = await _client
        .from('purchase_invoices')
        .insert({
          'invoice_number': invoiceNumber,
          'supplier_id': supplierId,
          'warehouse_id': warehouseId,
          'invoice_date': invoiceDate.toIso8601String(),
          'subtotal': subtotal,
          'discount': discount,
          'tax': tax,
          'total': total,
          'paid': paid,
          'payment_method': paymentMethod,
          'notes': notes,
        })
        .select('id')
        .single();
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
      globalId: data['global_id'] as String? ?? '',
      isDeleted: data['is_deleted'] as bool? ?? false,
      updatedAt: data['updated_at'] != null ? DateTime.parse(data['updated_at'] as String) : DateTime.parse(data['created_at'] as String),
      invoiceNumber: data['invoice_number'] as String,
      supplierId: data['supplier_id'] as int,
      warehouseId: data['warehouse_id'] as int,
      invoiceDate: DateTime.parse(data['invoice_date'] as String),
      subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0,
      discount: (data['discount'] as num?)?.toDouble() ?? 0,
      tax: (data['tax'] as num?)?.toDouble() ?? 0,
      total: (data['total'] as num?)?.toDouble() ?? 0,
      paid: (data['paid'] as num?)?.toDouble() ?? 0,
      paymentMethod: data['payment_method'] as String? ?? 'cash',
      status: data['status'] as String? ?? 'pending',
      isLocked: data['is_locked'] as bool? ?? false,
      notes: data['notes'] as String?,
      createdAt: DateTime.parse(data['created_at'] as String),
      rowVersion: 0,
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
      idempotencyKey: data['idempotency_key'] as String?,
      rowVersion: 0,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WAREHOUSES
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Warehouse>> getAllWarehouses() async {
    final data = await _client.from('warehouses').select().order('name');
    return data.map(_mapToWarehouse).toList();
  }

  Stream<List<Offer>> watchActiveOffers() {
    return _client
        .from('offers')
        .stream(primaryKey: ['id'])
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .map(
          (data) => data.map(_mapToOffer).where((o) {
            if (o.startDate != null && o.startDate!.isAfter(DateTime.now())) {
              return false;
            }
            if (o.endDate != null && o.endDate!.isBefore(DateTime.now())) {
              return false;
            }
            return true;
          }).toList(),
        );
  }

  Future<List<OfferItem>> getOfferItems(int offerId) async {
    final data = await _client
        .from('offer_items')
        .select()
        .eq('offer_id', offerId);
    return data.map(_mapToOfferItem).toList();
  }

  Future<Warehouse?> getDefaultWarehouse() async {
    final data = await _client
        .from('warehouses')
        .select()
        .eq('is_default', true)
        .maybeSingle();
    return data != null ? _mapToWarehouse(data) : null;
  }

  Warehouse _mapToWarehouse(Map<String, dynamic> data) {
    return Warehouse(
      id: data['id'] as int,
      name: data['name'] as String,
      branchId: data['branch_id'] as int?,
      type: data['type'] as String? ?? 'general',
      isDefault: data['is_default'] as bool? ?? false,
      isActive: data['is_active'] as bool? ?? true,
      // Spec 129 F6 — read the flag from Supabase if present; defaults to
      // false so a Supabase row that pre-dates v148 doesn't crash the cast.
      isSystemDefault: data['is_system_default'] as bool? ?? false,
      rowVersion: 0,
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
    final data = await _client
        .from('safes')
        .select()
        .eq('is_default', true)
        .maybeSingle();
    return data != null ? _mapToSafe(data) : null;
  }

  Future<Safe?> getDefaultSafeByType(String type) async {
    final data = await _client
        .from('safes')
        .select()
        .eq('safe_type', type)
        .eq('is_default', true)
        .maybeSingle();

    if (data != null) return _mapToSafe(data);

    // Fallback
    final fallback = await _client
        .from('safes')
        .select()
        .eq('safe_type', type)
        .limit(1)
        .maybeSingle();

    return fallback != null ? _mapToSafe(fallback) : null;
  }

  Future<void> updateSafeBalance(int safeId, double newBalance) async {
    await _client
        .from('safes')
        .update({'balance': newBalance})
        .eq('id', safeId);
  }

  Future<int> createReceiptVoucher({
    required double amount,
    required String category,
    String? description,
    int? partyId,
    int? safeId,
    int? userId,
  }) async {
    // Basic implementation for web - in a real app, this would involve a transaction
    // and complex server-side logic in a Supabase Function or similar.
    // For this stub, we just insert the transaction and update the safe.

    final targetSafeId = safeId ?? (await getDefaultSafe())?.id;
    if (targetSafeId == null) throw Exception('No safe found');

    final safeData = await _client
        .from('safes')
        .select('balance')
        .eq('id', targetSafeId)
        .maybeSingle();
    if (safeData == null) throw Exception('Safe not found');
    final currentBalance = (safeData['balance'] as num).toDouble();
    final newBalance = currentBalance + amount;

    final voucherNumber = 'RV-${DateTime.now().millisecondsSinceEpoch}';

    final data = await _client
        .from('safe_transactions')
        .insert({
          'voucher_number': voucherNumber,
          'safe_id': targetSafeId,
          'transaction_type': 'receipt',
          'category': category,
          'amount': amount,
          'balance_after': newBalance,
          'party_id': partyId,
          'description': description,
          'user_id': userId,
        })
        .select('id')
        .maybeSingle();
    if (data == null) throw Exception('Failed to create receipt voucher');

    await updateSafeBalance(targetSafeId, newBalance);
    return data['id'] as int;
  }

  Future<int> createPaymentVoucher({
    required double amount,
    required String category,
    String? description,
    int? partyId,
    int? safeId,
    int? userId,
  }) async {
    final targetSafeId = safeId ?? (await getDefaultSafe())?.id;
    if (targetSafeId == null) throw Exception('No safe found');

    final safeData = await _client
        .from('safes')
        .select('balance')
        .eq('id', targetSafeId)
        .maybeSingle();
    if (safeData == null) throw Exception('Safe not found');
    final currentBalance = (safeData['balance'] as num).toDouble();
    if (currentBalance < amount) throw Exception('Insufficient balance');

    final newBalance = currentBalance - amount;
    final voucherNumber = 'PV-${DateTime.now().millisecondsSinceEpoch}';

    final data = await _client
        .from('safe_transactions')
        .insert({
          'voucher_number': voucherNumber,
          'safe_id': targetSafeId,
          'transaction_type': 'payment',
          'category': category,
          'amount': amount,
          'balance_after': newBalance,
          'party_id': partyId,
          'description': description,
          'user_id': userId,
        })
        .select('id')
        .maybeSingle();
    if (data == null) throw Exception('Failed to create payment voucher');

    await updateSafeBalance(targetSafeId, newBalance);
    return data['id'] as int;
  }

  Future<void> closeSafe(int safeId, {int? userId}) async {
    final safeData = await _client
        .from('safes')
        .select('balance')
        .eq('id', safeId)
        .single();
    final currentBalance = (safeData['balance'] as num).toDouble();
    if (currentBalance == 0) return;

    final voucherNumber = 'CLO-${DateTime.now().millisecondsSinceEpoch}';

    await _client.from('safe_transactions').insert({
      'voucher_number': voucherNumber,
      'safe_id': safeId,
      'transaction_type': 'payment',
      'category': 'daily_closing',
      'amount': currentBalance,
      'balance_after': 0,
      'description': 'Daily Treasury Closing - اقفال يومي',
      'user_id': userId,
    });

    await updateSafeBalance(safeId, 0);
  }

  Safe _mapToSafe(Map<String, dynamic> data) {
    return Safe(
      id: data['id'] as int,
      name: data['name'] as String,
      safeType: data['safe_type'] as String? ?? 'cash',
      bankName: data['bank_name'] as String?,
      accountNumber: data['account_number'] as String?,
      balance: (data['balance'] as num?)?.toDouble() ?? 0,
      branchId: data['branch_id'] as int?,
      isDefault: data['is_default'] as bool? ?? false,
      isActive: data['is_active'] as bool? ?? true,
      isSystemDefault: data['is_system_default'] as bool? ?? false,
      rowVersion: 0,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // USERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<UserWithRole?> getUserByUsername(String username) async {
    final data = await _client
        .from('users')
        .select('*, roles(*)')
        .eq('username', username)
        .eq('is_active', true)
        .maybeSingle();
    if (data == null) return null;
    return UserWithRole(
      user: _mapToUser(data),
      role: data['roles'] != null ? _mapToRole(data['roles']) : null,
    );
  }

  Future<UserWithRole?> getUserById(int id) async {
    final data = await _client
        .from('users')
        .select('*, roles(*)')
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return UserWithRole(
      user: _mapToUser(data),
      role: data['roles'] != null ? _mapToRole(data['roles']) : null,
    );
  }

  Future<UserWithRole?> authenticateUser(
    String username,
    String password,
  ) async {
    final userWithRole = await getUserByUsername(username);
    if (userWithRole == null) return null;

    if (SecurityService.verifyPassword(
      password,
      userWithRole.user.passwordSalt,
      userWithRole.user.passwordHash,
    )) {
      return userWithRole;
    }
    return null;
  }

  Role _mapToRole(Map<String, dynamic> data) {
    return Role(
      id: data['id'] as int,
      name: data['name'] as String,
      description: data['description'] as String?,
      isSystemRole: data['is_system_role'] as bool? ?? false,
      createdAt: DateTime.parse(data['created_at'] as String),
      rowVersion: 0,
    );
  }

  User _mapToUser(Map<String, dynamic> data) {
    return User(
      id: data['id'] as int,
      username: data['username'] as String,
      passwordHash: data['password_hash'] as String? ?? '',
      passwordSalt: data['password_salt'] as String? ?? '',
      displayName: data['display_name'] as String? ?? '',
      roleId: data['role_id'] as int?,
      pin: data['pin'] as String?,
      defaultScreen: data['default_screen'] as String? ?? 'pos',
      isLocked: data['is_locked'] as bool? ?? false,
      isActive: data['is_active'] as bool? ?? true,
      maxDiscountPercent: (data['max_discount_percent'] as num?)?.toDouble(),
      discountLimitIsPercent:
          data['discount_limit_is_percent'] as bool? ?? true,
      forcePasswordChange: data['force_password_change'] as bool? ?? false,
      createdAt: DateTime.parse(data['created_at'] as String),
      rowVersion: 0,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESTAURANT TABLES & SECTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<TableSection>> watchAllSections() {
    return _client
        .from('table_sections')
        .stream(primaryKey: ['id'])
        .eq('is_active', true)
        .order('name')
        .map((data) => data.map(_mapToTableSection).toList());
  }

  Stream<List<RestaurantTable>> watchTablesBySection(int sectionId) {
    return _client
        .from('restaurant_tables')
        .stream(primaryKey: ['id'])
        .eq('section_id', sectionId)
        .map(
          (data) => data
              .where((o) => o['is_active'] == true)
              .map(_mapToRestaurantTable)
              .toList(),
        );
  }

  Future<int> createSection(String name) async {
    final data = await _client
        .from('table_sections')
        .insert({'name': name})
        .select('id')
        .single();
    return data['id'] as int;
  }

  Future<int> createTable({
    required String name,
    int? sectionId,
    int capacity = 4,
  }) async {
    final data = await _client
        .from('restaurant_tables')
        .insert({
          'name': name,
          'section_id': sectionId,
          'capacity': capacity,
          'status': 'available',
        })
        .select('id')
        .single();
    return data['id'] as int;
  }

  Future<void> updateTableStatus(int tableId, String status) async {
    await _client
        .from('restaurant_tables')
        .update({'status': status})
        .eq('id', tableId);
  }

  Future<void> updateTableInfo(
    int tableId, {
    String? name,
    int? sectionId,
    int? capacity,
  }) async {
    final Map<String, dynamic> updates = {};
    if (name != null) updates['name'] = name;
    if (sectionId != null) updates['section_id'] = sectionId;
    if (capacity != null) updates['capacity'] = capacity;

    if (updates.isNotEmpty) {
      await _client.from('restaurant_tables').update(updates).eq('id', tableId);
    }
  }

  Future<void> deleteTable(int tableId) async {
    await _client
        .from('restaurant_tables')
        .update({'is_active': false})
        .eq('id', tableId);
  }

  Future<TableOrder?> getActiveOrderForTable(int tableId) async {
    final data = await _client
        .from('table_orders')
        .select()
        .eq('table_id', tableId)
        .inFilter('status', ['open', 'bill_requested'])
        .maybeSingle();
    return data != null ? _mapToTableOrder(data) : null;
  }

  Stream<TableOrder?> watchActiveOrderForTable(int tableId) {
    return _client
        .from('table_orders')
        .stream(primaryKey: ['id'])
        .eq('table_id', tableId)
        .map((data) {
          final activeOrders = data.where(
            (o) => o['status'] == 'open' || o['status'] == 'bill_requested',
          );
          return activeOrders.isNotEmpty
              ? _mapToTableOrder(activeOrders.first)
              : null;
        });
  }

  Future<int> createTableOrder(int tableId, {int? userId}) async {
    // In Supabase, we should ideally use a stored procedure or transaction
    // For now, we update the table and create the order
    await updateTableStatus(tableId, 'occupied');

    final data = await _client
        .from('table_orders')
        .insert({
          'table_id': tableId,
          'user_id': userId,
          'status': 'open',
          'opened_at': DateTime.now().toIso8601String(),
        })
        .select('id')
        .single();
    return data['id'] as int;
  }

  Future<void> addOrUpdateTableOrderItem({
    required int orderId,
    required int productId,
    required double quantity,
    required double unitPrice,
  }) async {
    final existing = await _client
        .from('table_order_items')
        .select()
        .eq('table_order_id', orderId)
        .eq('product_id', productId)
        .maybeSingle();

    if (existing != null) {
      final newQty = (existing['quantity'] as num).toDouble() + quantity;
      await _client
          .from('table_order_items')
          .update({'quantity': newQty, 'total': newQty * unitPrice})
          .eq('id', existing['id']);
    } else {
      await _client.from('table_order_items').insert({
        'table_order_id': orderId,
        'product_id': productId,
        'quantity': quantity,
        'unit_price': unitPrice,
        'total': quantity * unitPrice,
      });
    }

    await _updateTableOrderTotal(orderId);
  }

  Future<void> _updateTableOrderTotal(int orderId) async {
    final itemsData = await _client
        .from('table_order_items')
        .select('total')
        .eq('table_order_id', orderId);

    final total = itemsData.fold(
      0.0,
      (sum, item) => sum + (item['total'] as num).toDouble(),
    );

    await _client
        .from('table_orders')
        .update({'total': total})
        .eq('id', orderId);
  }

  Future<List<TableOrderItem>> getTableOrderItems(int orderId) async {
    final data = await _client
        .from('table_order_items')
        .select()
        .eq('table_order_id', orderId);
    return data.map(_mapToTableOrderItem).toList();
  }

  Future<void> removeTableOrderItem(int orderId, int productId) async {
    await _client
        .from('table_order_items')
        .delete()
        .eq('table_order_id', orderId)
        .eq('product_id', productId);

    await _updateTableOrderTotal(orderId);
  }

  Future<void> clearTableOrderItems(int orderId) async {
    await _client
        .from('table_order_items')
        .delete()
        .eq('table_order_id', orderId);
    await _updateTableOrderTotal(orderId);
  }

  Future<void> closeTableOrder(int orderId, int tableId) async {
    await _client
        .from('table_orders')
        .update({
          'status': 'closed',
          'closed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', orderId);

    await updateTableStatus(tableId, 'available');
  }

  Future<void> requestTableBill(int orderId, int tableId) async {
    await _client
        .from('table_orders')
        .update({'status': 'bill_requested'})
        .eq('id', orderId);

    await updateTableStatus(tableId, 'billing');
  }

  Future<void> finalizeTableOrder(
    int orderId,
    int tableId, {
    int? invoiceId,
  }) async {
    await _client
        .from('table_orders')
        .update({
          'status': 'closed',
          'closed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', orderId);

    await updateTableStatus(tableId, 'available');
  }

  TableSection _mapToTableSection(Map<String, dynamic> data) {
    return TableSection(
      id: data['id'] as int,
      name: data['name'] as String,
      isActive: data['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }

  RestaurantTable _mapToRestaurantTable(Map<String, dynamic> data) {
    return RestaurantTable(
      id: data['id'] as int,
      sectionId: data['section_id'] as int?,
      name: data['name'] as String? ?? '',
      capacity: data['capacity'] as int? ?? 4,
      status: data['status'] as String? ?? 'available',
      x: (data['x'] as num?)?.toDouble() ?? 0.0,
      y: (data['y'] as num?)?.toDouble() ?? 0.0,
      shape: data['shape'] as String? ?? 'rectangle',
      lastStatusAt: data['last_status_at'] != null
          ? DateTime.parse(data['last_status_at'] as String)
          : DateTime.now(),
      isActive: data['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }

  TableOrder _mapToTableOrder(Map<String, dynamic> data) {
    return TableOrder(
      id: data['id'] as int,
      tableId: data['table_id'] as int,
      status: data['status'] as String? ?? 'open',
      total: (data['total'] as num?)?.toDouble() ?? 0,
      userId: data['user_id'] as int?,
      guestCount: (data['guest_count'] as int?) ?? 1,
      notes: data['notes'] as String?,
      discountType: data['discount_type'] as String?,
      discountValue: (data['discount_value'] as num?)?.toDouble() ?? 0,
      paidAmount: (data['paid_amount'] as num?)?.toDouble() ?? 0,
      openedAt: DateTime.parse(data['opened_at'] as String),
      closedAt: data['closed_at'] != null
          ? DateTime.parse(data['closed_at'] as String)
          : null,
    );
  }

  TableOrderItem _mapToTableOrderItem(Map<String, dynamic> data) {
    return TableOrderItem(
      id: data['id'] as int,
      tableOrderId: data['table_order_id'] as int,
      productId: data['product_id'] as int,
      quantity: (data['quantity'] as num).toDouble(),
      unitPrice: (data['unit_price'] as num).toDouble(),
      total: (data['total'] as num).toDouble(),
      taxRate: (data['tax_rate'] as num?)?.toDouble() ?? 0,
      taxAmount: (data['tax_amount'] as num?)?.toDouble() ?? 0,
      addedAt: DateTime.parse(data['added_at'] as String),
    );
  }

  Offer _mapToOffer(Map<String, dynamic> data) {
    return Offer(
      id: data['id'] as int,
      name: data['name'] as String,
      offerPrice: (data['offer_price'] as num).toDouble(),
      isActive: data['is_active'] as bool? ?? true,
      startDate: data['start_date'] != null
          ? DateTime.parse(data['start_date'] as String)
          : null,
      endDate: data['end_date'] != null
          ? DateTime.parse(data['end_date'] as String)
          : null,
      createdAt: DateTime.parse(data['created_at'] as String),
      offerType: (data['offer_type'] as String?) ?? 'bundle',
      currentUses: (data['current_uses'] as int?) ?? 0,
      discountValue: (data['discount_value'] as num?)?.toDouble(),
      buyQuantity: data['buy_quantity'] as int?,
      getQuantity: data['get_quantity'] as int?,
      minQuantity: data['min_quantity'] as int?,
      maxUses: data['max_uses'] as int?,
      timeStart: data['time_start'] as String?,
      timeEnd: data['time_end'] as String?,
      categoryId: data['category_id'] as int?,
      isGlobal: data['is_global'] as bool? ?? true,
      branchIds: data['branch_ids'] as String?,
      barcode: data['barcode'] as String?,
    );
  }

  OfferItem _mapToOfferItem(Map<String, dynamic> data) {
    return OfferItem(
      id: data['id'] as int,
      offerId: data['offer_id'] as int,
      productId: data['product_id'] as int,
      quantity: (data['quantity'] as num).toDouble(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String?> getSetting(String key) async {
    final data = await _client
        .from('settings')
        .select('value')
        .eq('key', key)
        .maybeSingle();
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
